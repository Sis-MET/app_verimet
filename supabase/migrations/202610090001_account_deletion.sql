begin;

-- Google Play exige que una app donde se crean cuentas permita eliminarlas,
-- desde la app y desde una página web. En IvMET la evidencia metrológica es
-- inmutable (verificaciones, pruebas y lecturas no se editan ni se borran), así
-- que eliminar significa:
--
-- - se borra el acceso: el alias de login, las licencias y las asignaciones,
--   y la cuenta Auth queda bloqueada con un correo interno (ivmet-account-delete);
-- - se borran o anonimizan los datos personales: nombre, usuario, correo y
--   teléfono de contacto, mensajes de las solicitudes de plan;
-- - se conservan, sin datos personales, los registros técnicos y la auditoría,
--   que siguen siendo la evidencia de lo que se hizo y cuándo.
--
-- Cada eliminación deja su constancia en private.eliminaciones_cuenta.

create table private.eliminaciones_cuenta (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  solicitado_por uuid not null references auth.users(id),
  alcance varchar(10) not null,
  origen varchar(10) not null,
  usuarios uuid[] not null,
  solicitado_at timestamptz not null default now(),
  auth_cerrado_at timestamptz,
  constraint eliminaciones_cuenta_alcance_ck check (alcance in ('ACCOUNT','COMPANY')),
  constraint eliminaciones_cuenta_origen_ck check (origen in ('APP','WEB'))
);
create index eliminaciones_cuenta_pendientes_idx on private.eliminaciones_cuenta(solicitado_at)
  where auth_cerrado_at is null;
revoke all on private.eliminaciones_cuenta from public,anon,authenticated,service_role;

-- El correo de contacto de la empresa es el de quien la registró: si esa
-- persona elimina su cuenta, el correo se va con ella.
alter table private.empresas_autoregistro alter column correo drop not null;

-- Deja una cuenta sin acceso y sin datos personales. Lo que hizo (capturas,
-- verificaciones, auditoría) sigue apuntando a su perfil, ahora anónimo.
create function private.anonymize_member(target uuid,actor uuid,reason text) returns void
language plpgsql security definer set search_path='' as $$
declare anonymous text:='eliminado.'||replace(target::text,'-','');
begin
  update public.licencias_usuario set estado='REVOKED',revocada_at=now(),revocada_por=actor,motivo_revocacion=reason
    where usuario_id=target and estado='ACTIVE';
  delete from private.login_aliases where auth_user_id=target;
  update public.usuario_plantas set activa=false where usuario_id=target and activa;
  delete from public.usuario_equipos where usuario_id=target;
  -- Una captura sin finalizar no es evidencia: se abandona.
  update public.verificacion_borradores set estado='ABANDONED' where usuario_id=target and estado='DRAFT';
  update public.solicitudes_plan set contacto_nombre='Usuario eliminado',contacto_correo=null,
      contacto_telefono=null,mensaje=''
    where solicitado_por=target;
  update public.perfiles set usuario=anonymous,usuario_normalizado=anonymous,nombre='Usuario eliminado',
      activo=false,debe_cambiar_password=true
    where id=target;
  insert into public.eventos_licencia(usuario_id,tipo_evento,actor_id,motivo)
    values(target,'ACCOUNT_DELETED',actor,reason);
end; $$;

-- Lo llama ivmet-account-delete después de autenticar a quien la pide (con su
-- contraseña o con un código a su correo). `ACCOUNT` elimina la propia cuenta;
-- `COMPANY` elimina la empresa autoregistrada completa y la pide su jefe de
-- calidad. Devuelve las cuentas Auth que la función debe bloquear.
create function public.ivmet_account_delete(target_user uuid,scope text,origin text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  member public.perfiles%rowtype; cid uuid; users uuid[]; deletion uuid; done private.eliminaciones_cuenta%rowtype;
  reason text:=case scope when 'COMPANY' then 'Empresa eliminada a pedido del cliente.'
    else 'Cuenta eliminada a pedido de su titular.' end;
  person uuid;
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform private.admin_assert(target_user is not null and scope in ('ACCOUNT','COMPANY')
    and origin in ('APP','WEB'),'INVALID_REQUEST');
  select p.cliente_id into cid from public.perfiles p where p.id=target_user;
  perform private.admin_assert(cid is not null,'ACCOUNT_NOT_FOUND');
  perform pg_advisory_xact_lock(hashtextextended(cid::text,10));
  select * into member from public.perfiles p where p.id=target_user for update;
  if not member.activo then
    -- Un doble envío de la misma eliminación devuelve la constancia anterior.
    select * into done from private.eliminaciones_cuenta e
      where e.solicitado_por=target_user and e.alcance=scope order by e.solicitado_at desc limit 1;
    perform private.admin_assert(found,'ACCOUNT_NOT_FOUND');
    return jsonb_build_object('deletionId',done.id,'scope',done.alcance,'users',to_jsonb(done.usuarios),'replayed',true);
  end if;

  if scope='ACCOUNT' then
    -- Una empresa autoregistrada no queda sin jefe de calidad: se elimina la
    -- empresa o se nombra antes a otro jefe.
    perform private.admin_assert(member.rol<>'cliente_jefe_calidad' or not private.self_service_client(cid)
      or exists(select 1 from public.perfiles p where p.cliente_id=cid and p.activo and p.id<>target_user
        and p.rol='cliente_jefe_calidad'),'LAST_QUALITY_MANAGER');
    perform private.anonymize_member(target_user,target_user,reason);
    update private.empresas_autoregistro set correo=null where cliente_id=cid and propietario_id=target_user;
    users:=array[target_user];
  else
    perform private.admin_assert(member.rol='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
    perform private.admin_assert(private.self_service_client(cid),'SELF_SERVICE_REQUIRED');
    users:=array(select p.id from public.perfiles p where p.cliente_id=cid order by p.id);
    -- También las cuentas que el jefe ya había desactivado: conservan su nombre.
    for person in select p.id from public.perfiles p where p.cliente_id=cid
        and p.usuario_normalizado not like 'eliminado.%' loop
      perform private.anonymize_member(person,target_user,reason);
    end loop;
    update public.suscripcion_cupos set estado='REVOKED' where estado in ('ACTIVE','PENDING')
      and suscripcion_id in (select s.id from public.suscripciones s join public.contratos c on c.id=s.contrato_id
        where c.cliente_id=cid);
    update public.suscripciones set estado='CANCELLED',motivo_suspension=reason where estado<>'CANCELLED'
      and contrato_id in (select c.id from public.contratos c where c.cliente_id=cid);
    update public.contratos set estado='CANCELLED' where cliente_id=cid and estado<>'CANCELLED';
    update public.solicitudes_plan set estado='CANCELLED' where cliente_id=cid and estado in ('PENDING','CONTACTED');
    update public.solicitudes_plan set contacto_nombre='Empresa eliminada',contacto_correo=null,
        contacto_telefono=null,mensaje='',nota_interna=null
      where cliente_id=cid;
    delete from private.empresas_autoregistro where cliente_id=cid;
    update public.equipos_ivmet set habilitado=false,estado_configuracion='SUSPENDED'
      where habilitado and equipo_id in (select e.id from public.equipos e where e.cliente_id=cid);
    update public.plantas set activo=false where cliente_id=cid and activo;
    update public.clientes set nombre='Empresa eliminada',razon_social='Empresa eliminada',activo=false where id=cid;
  end if;

  insert into private.eliminaciones_cuenta(cliente_id,solicitado_por,alcance,origen,usuarios)
    values(cid,target_user,scope,origin,users) returning id into deletion;
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(target_user,cid,case scope when 'COMPANY' then 'cliente' else 'perfil' end,
      case scope when 'COMPANY' then cid::text else target_user::text end,
      case scope when 'COMPANY' then 'COMPANY_DELETED' else 'ACCOUNT_DELETED' end,
      jsonb_build_object('deletionId',deletion,'origin',origin,'accounts',cardinality(users)));
  return jsonb_build_object('deletionId',deletion,'scope',scope,'users',to_jsonb(users),'replayed',false);
end; $$;

-- La función marca la constancia cuando bloqueó todas las cuentas Auth.
create function public.ivmet_account_deletion_done(deletion_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  update private.eliminaciones_cuenta set auth_cerrado_at=coalesce(auth_cerrado_at,now()) where id=deletion_id;
end; $$;

-- Constancias cuyas cuentas Auth no se pudieron bloquear. La función las
-- reintenta en cada eliminación, empezando por las más antiguas.
create function public.ivmet_account_deletions_pending(max_rows integer) returns table(id uuid,usuarios uuid[])
language sql stable security definer set search_path='' as $$
  select e.id,e.usuarios from private.eliminaciones_cuenta e
  where auth.role()='service_role' and e.auth_cerrado_at is null
  order by e.solicitado_at limit least(greatest(coalesce(max_rows,0),0),50);
$$;

revoke all on function private.anonymize_member(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_account_delete(uuid,text,text),public.ivmet_account_deletion_done(uuid),
  public.ivmet_account_deletions_pending(integer) from public,anon,authenticated;
grant execute on function public.ivmet_account_delete(uuid,text,text),public.ivmet_account_deletion_done(uuid),
  public.ivmet_account_deletions_pending(integer) to service_role;

commit;

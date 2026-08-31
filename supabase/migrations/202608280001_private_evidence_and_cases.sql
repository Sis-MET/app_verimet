begin;

-- No se elimina evidencia ni el historial del outbox. Se impide su exportación.
create function private.ivmet_export_allowed(aggregate_name text) returns boolean
language sql immutable set search_path='' as $$
  select aggregate_name = any(array[
    'public.clientes','public.plantas','public.equipos','public.equipo_rangos',
    'public.perfiles','public.usuario_plantas','public.planes_comerciales','public.precios_plan',
    'public.contratos','public.suscripciones','public.facturas','public.pagos','public.suscripcion_cupos',
    'public.licencias_usuario','public.eventos_licencia','public.areas','public.equipos_ivmet',
    'public.patrones','public.patron_plantas','public.patron_certificados','public.planes',
    'public.plan_versiones','public.plan_pruebas','public.plan_puntos','public.equipo_planes',
    'public.casos_compartidos']);
$$;

alter table private.sync_outbox add column privacy_blocked boolean not null default false;
update private.sync_outbox set privacy_blocked=true
where not private.ivmet_export_allowed(aggregate_type);

-- Los paneles anteriores tampoco muestran contadores de actividad privada histórica.
do $$ declare function_name text; definition text; begin
  foreach function_name in array array['public.ivmet_admin_read(text,uuid,jsonb)','private.ivmet_admin_read(text,uuid,jsonb)'] loop
    definition:=pg_get_functiondef(function_name::regprocedure);
    if strpos(definition,'from private.sync_outbox group by estado')=0 then raise exception 'ADMIN_READ_PRIVACY_PATCH_MISMATCH'; end if;
    definition:=replace(definition,'from private.sync_outbox group by estado',
      'from private.sync_outbox where not privacy_blocked and private.ivmet_export_allowed(aggregate_type) group by estado');
    definition:=replace(definition,'from private.sync_runs order by started_at',
      'from private.sync_runs where direccion=''DATAMET_TO_SUPABASE'' or metadata->>''privacyContract''=''3'' order by started_at');
    execute definition;
  end loop;
end $$;

create sequence private.case_code_seq;
create table public.casos_compartidos (
  id uuid primary key default extensions.gen_random_uuid(),
  codigo text not null unique default ('CASO-' || lpad(nextval('private.case_code_seq')::text,8,'0')),
  alerta_id uuid not null references public.alertas(id),
  verificacion_id uuid not null references public.verificaciones(id),
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  equipo_id uuid not null references public.equipos(id),
  autorizado_por uuid not null references public.perfiles(id),
  autorizado_at timestamptz not null default now(),
  consentimiento_version text not null default 'case-sharing-v1',
  snapshot_hash text not null check (snapshot_hash ~ '^[0-9a-f]{64}$'),
  snapshot jsonb not null,
  mensaje text not null,
  visibilidad text not null default 'SHARED' check (visibilidad in ('SHARED','WITHDRAWN')),
  retirado_at timestamptz,
  retirado_por uuid references public.perfiles(id),
  motivo_retiro text,
  estado text not null default 'NEW' check (estado in ('NEW','IN_REVIEW','WAITING_CLIENT','RESOLVED')),
  responsable text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint casos_scope_fk foreign key (verificacion_id,cliente_id,planta_id,equipo_id)
    references public.verificaciones(id,cliente_id,planta_id,equipo_id),
  constraint casos_retiro_ck check ((visibilidad='SHARED' and retirado_at is null and retirado_por is null and motivo_retiro is null)
    or (visibilidad='WITHDRAWN' and retirado_at is not null and retirado_por is not null and length(btrim(motivo_retiro))>0))
);
create unique index casos_alerta_compartida_uq on public.casos_compartidos(alerta_id) where visibilidad='SHARED';
create index casos_inbox_idx on public.casos_compartidos(visibilidad,estado,created_at desc,id);
create index casos_cliente_idx on public.casos_compartidos(cliente_id,planta_id,created_at desc,id);

create table public.caso_eventos (
  id uuid primary key default extensions.gen_random_uuid(),
  caso_id uuid not null references public.casos_compartidos(id),
  actor_id uuid references public.perfiles(id),
  actor_externo text,
  accion text not null,
  comentario text not null,
  created_at timestamptz not null default now(),
  constraint caso_eventos_actor_ck check (num_nonnulls(actor_id,actor_externo)=1)
);
create index caso_eventos_caso_idx on public.caso_eventos(caso_id,created_at,id);
create trigger caso_eventos_inmutables before update or delete on public.caso_eventos
for each row execute function private.prevent_evidence_mutation();
create trigger casos_updated before update on public.casos_compartidos
for each row execute function private.set_updated_at();

create function private.protect_case_consent() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then raise exception 'CASE_EVIDENCE_IMMUTABLE'; end if;
  if (to_jsonb(new)-array['visibilidad','retirado_at','retirado_por','motivo_retiro','estado','responsable','updated_at','row_version'])
     is distinct from (to_jsonb(old)-array['visibilidad','retirado_at','retirado_por','motivo_retiro','estado','responsable','updated_at','row_version'])
     or old.visibilidad='WITHDRAWN' then raise exception 'CASE_EVIDENCE_IMMUTABLE'; end if;
  return new;
end; $$;
create trigger casos_consentimiento before update or delete on public.casos_compartidos
for each row execute function private.protect_case_consent();

-- Un expediente es autónomo: no requiere copiar el resto del historial privado.
create function private.case_export(target_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select private.stringify_ivmet_outbox_numbers('public.casos_compartidos',to_jsonb(c))
    || jsonb_build_object('snapshot',case when c.visibilidad='SHARED' then c.snapshot else null end,
      'eventos',case when c.visibilidad='SHARED' then coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id)
        from public.caso_eventos e where e.caso_id=c.id),'[]') else '[]'::jsonb end)
  from public.casos_compartidos c where c.id=target_id;
$$;

create or replace function private.capture_sync_outbox() returns trigger
language plpgsql security definer set search_path='' as $$
declare row_data jsonb; key_data jsonb:='{}'; key_name text; aggregate_name text:=tg_table_schema||'.'||tg_table_name;
begin
  if not private.ivmet_export_allowed(aggregate_name) then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  row_data:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  foreach key_name in array tg_argv loop
    if not(row_data ? key_name) or row_data->key_name='null'::jsonb then raise exception 'OUTBOX_KEY_REQUIRED'; end if;
    key_data:=key_data||jsonb_build_object(key_name,row_data->key_name);
  end loop;
  if aggregate_name='public.casos_compartidos' then row_data:=private.case_export(new.id); end if;
  if row_data ? 'draft_revision' then row_data:=jsonb_set(row_data,'{draft_revision}',to_jsonb(row_data->>'draft_revision')); end if;
  insert into private.sync_outbox(aggregate_type,aggregate_key,operation,payload)
  values(aggregate_name,key_data,case tg_op when 'INSERT' then 'I' when 'UPDATE' then 'U' else 'D' end,
    private.stringify_ivmet_outbox_numbers(aggregate_name,row_data));
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create trigger casos_sync_outbox after insert or update on public.casos_compartidos
for each row execute function private.capture_sync_outbox('id');

create function private.case_event_changed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  update public.casos_compartidos set updated_at=now() where id=new.caso_id and visibilidad='SHARED';
  return new;
end; $$;
create trigger caso_evento_sync after insert on public.caso_eventos
for each row execute function private.case_event_changed();

create function public.ivmet_case_delivery(target_case_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$ select private.case_export(target_case_id) $$;
revoke all on function public.ivmet_case_delivery(uuid) from public,anon,authenticated;
grant execute on function public.ivmet_case_delivery(uuid) to service_role;

create or replace function public.claim_ivmet_sync_outbox(worker_id text,batch_size integer default 100)
returns table(event_id uuid,sequence bigint,aggregate_type varchar,aggregate_key jsonb,operation char,payload jsonb,attempts integer,created_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
  if worker_id is null or btrim(worker_id)='' then raise exception 'WORKER_ID_REQUIRED'; end if;
  return query with candidates as (
    select o.event_id from private.sync_outbox o
    where not o.privacy_blocked and private.ivmet_export_allowed(o.aggregate_type)
      and ((o.estado='PENDING' and o.available_at<=now()) or (o.estado='CLAIMED' and o.claimed_at<now()-interval '5 minutes'))
      and not exists(select 1 from private.sync_outbox b where b.estado='DEAD' and not b.privacy_blocked
        and private.ivmet_export_allowed(b.aggregate_type) and b.sequence<o.sequence)
    order by o.sequence for update skip locked limit least(greatest(batch_size,1),500)
  ), claimed as (
    update private.sync_outbox o set estado='CLAIMED',claimed_at=now(),claimed_by=worker_id,attempts=o.attempts+1,last_error=null
    from candidates c where o.event_id=c.event_id returning o.*
  ) select c.event_id,c.sequence,c.aggregate_type,c.aggregate_key,c.operation,
    -- Un consentimiento retirado invalida también eventos que todavía estaban en cola.
    case when c.aggregate_type='public.casos_compartidos' then private.case_export((c.aggregate_key->>'id')::uuid)
      || jsonb_build_object('_event_payload_hash',encode(sha256(convert_to(c.payload::text,'UTF8')),'hex')) else c.payload end,
    c.attempts,c.created_at from claimed c order by c.sequence;
end; $$;

-- Las políticas normales no bastan para service_role: se retiran los permisos directos.
revoke all on public.verificacion_borradores,public.verificaciones,public.verificacion_patrones,
  public.pruebas,public.lecturas,public.alertas,public.auditoria,public.casos_compartidos,public.caso_eventos
  from service_role;
revoke all on private.sync_outbox,private.sync_quarantine,private.sync_runs from service_role;

create or replace function private.can_read_verification(target_verification_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.verificaciones v where v.id=target_verification_id
    and private.current_profile_role() in ('cliente_operador','cliente_jefe_calidad')
    and private.can_access_client(v.cliente_id) and private.can_access_plant(v.planta_id));
$$;

create function private.alert_share_snapshot(target_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('version','case-sharing-v1','alerta',jsonb_build_object('id',a.id,'tipo',a.tipo,'resumen',a.resumen),
    'verificacion',private.stringify_ivmet_outbox_numbers('public.verificaciones',to_jsonb(v)-array['payload_hash','request_uuid','dispositivo_id']),
    'usuarios',jsonb_build_object('captura',(select p.nombre from public.perfiles p where p.id=v.capturado_por),
      'finalizacion',(select p.nombre from public.perfiles p where p.id=v.finalizado_por)),
    'patrones',coalesce((select jsonb_agg(to_jsonb(vp) order by vp.patron_id,vp.rol) from public.verificacion_patrones vp where vp.verificacion_id=v.id),'[]'),
    'pruebas',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.pruebas',to_jsonb(p))||jsonb_build_object('lecturas',
      coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.lecturas',to_jsonb(l)) order by l.orden,l.id)
        from public.lecturas l where l.prueba_id=p.id),'[]')) order by p.tipo)
      from public.pruebas p where p.verificacion_id=v.id),'[]'))
  from public.alertas a join public.verificaciones v on v.id=a.verificacion_id where a.id=target_id;
$$;

create function public.preview_ivmet_alert_share(target_alert_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.alertas%rowtype; data jsonb;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  select * into a from public.alertas where id=target_alert_id;
  perform private.admin_assert(found and private.can_access_client(a.cliente_id) and private.can_access_plant(a.planta_id),'ALERT_NOT_ACCESSIBLE');
  data:=private.alert_share_snapshot(a.id);
  return jsonb_build_object('snapshot',data,'snapshotHash',encode(sha256(convert_to(data::text,'UTF8')),'hex'),
    'alertVersion',a.row_version::text,'consentVersion','case-sharing-v1',
    'notice','Se enviará únicamente este expediente a Métrica. No incluye otras verificaciones. Retirar el acceso no elimina copias previamente entregadas.');
end; $$;

create function public.confirm_ivmet_alert_share(target_alert_id uuid,expected_row_version bigint,
  expected_snapshot_hash text,share_message text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.alertas%rowtype; data jsonb; digest text; case_id uuid; existing public.casos_compartidos%rowtype;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  select * into a from public.alertas where id=target_alert_id for update;
  perform private.admin_assert(found and private.can_access_client(a.cliente_id) and private.can_access_plant(a.planta_id),'ALERT_NOT_ACCESSIBLE');
  perform private.admin_assert(length(btrim(share_message)) between 1 and 2000,'SHARE_MESSAGE_REQUIRED');
  select * into existing from public.casos_compartidos c where c.alerta_id=a.id and c.visibilidad='SHARED';
  if found then
    perform private.admin_assert(existing.autorizado_por=auth.uid() and existing.snapshot_hash=expected_snapshot_hash
      and existing.mensaje=btrim(share_message),'IDEMPOTENCY_CONFLICT');
    return jsonb_build_object('id',existing.id,'codigo',existing.codigo);
  end if;
  perform private.admin_assert(a.row_version=expected_row_version,'ROW_VERSION_CONFLICT');
  -- Bloquea la verificación durante la vista/confirmación para no compartir una anulación no vista.
  perform 1 from public.verificaciones where id=a.verificacion_id for share;
  data:=private.alert_share_snapshot(a.id); digest:=encode(sha256(convert_to(data::text,'UTF8')),'hex');
  perform private.admin_assert(digest=expected_snapshot_hash,'SHARE_PREVIEW_CHANGED');
  insert into public.casos_compartidos(alerta_id,verificacion_id,cliente_id,planta_id,equipo_id,autorizado_por,snapshot_hash,snapshot,mensaje)
  values(a.id,a.verificacion_id,a.cliente_id,a.planta_id,a.equipo_id,auth.uid(),digest,data,btrim(share_message)) returning id into case_id;
  update public.alertas set visibilidad_metrica='SHARED',compartida_at=now(),compartida_por=auth.uid(),mensaje_compartido=btrim(share_message) where id=a.id;
  insert into public.caso_eventos(caso_id,actor_id,accion,comentario) values(case_id,auth.uid(),'SHARED',btrim(share_message));
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(auth.uid(),a.cliente_id,'caso_compartido',case_id::text,'SHARED_WITH_METRICA',jsonb_build_object('snapshot_hash',digest));
  return (select jsonb_build_object('id',id,'codigo',codigo) from public.casos_compartidos where id=case_id);
end; $$;

create function public.withdraw_ivmet_case(target_case_id uuid,expected_row_version bigint,reason text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.casos_compartidos%rowtype;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  select * into c from public.casos_compartidos where id=target_case_id for update;
  perform private.admin_assert(found and private.can_access_client(c.cliente_id) and private.can_access_plant(c.planta_id),'CASE_NOT_ACCESSIBLE');
  perform private.admin_assert(length(btrim(reason)) between 1 and 2000,'REASON_REQUIRED');
  if c.visibilidad='WITHDRAWN' then return; end if;
  perform private.admin_assert(c.row_version=expected_row_version,'ROW_VERSION_CONFLICT');
  update public.casos_compartidos set visibilidad='WITHDRAWN',retirado_at=now(),retirado_por=auth.uid(),motivo_retiro=btrim(reason) where id=c.id;
  update public.alertas set visibilidad_metrica='PRIVATE',compartida_at=null,compartida_por=null,mensaje_compartido=null where id=c.alerta_id;
  insert into public.caso_eventos(caso_id,actor_id,accion,comentario) values(c.id,auth.uid(),'WITHDRAWN',btrim(reason));
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion)
    values(auth.uid(),c.cliente_id,'caso_compartido',c.id::text,'SHARING_WITHDRAWN');
end; $$;

-- El endpoint antiguo no puede eludir la vista previa y la confirmación explícita.
create or replace function public.share_ivmet_alert(target_alert_id uuid,expected_row_version bigint,share_message text default null)
returns public.alertas language plpgsql set search_path='' as $$
begin raise exception 'SHARE_PREVIEW_CONFIRMATION_REQUIRED'; end; $$;
-- El seguimiento de Métrica se centraliza en los casos y permisos internos de RimMET.
revoke all on function public.acknowledge_ivmet_alert(uuid,bigint),public.attend_ivmet_alert(uuid,bigint,text)
  from public,anon,authenticated,service_role;

alter table public.casos_compartidos enable row level security;
alter table public.caso_eventos enable row level security;
revoke all on public.casos_compartidos,public.caso_eventos from public,anon,authenticated;
grant select on public.casos_compartidos,public.caso_eventos to authenticated;
create policy casos_customer_read on public.casos_compartidos for select to authenticated
using(private.can_access_client(cliente_id) and private.can_access_plant(planta_id));
create policy caso_eventos_customer_read on public.caso_eventos for select to authenticated
using(exists(select 1 from public.casos_compartidos c where c.id=caso_id
  and private.can_access_client(c.cliente_id) and private.can_access_plant(c.planta_id)));
revoke all on function private.ivmet_export_allowed(text),private.case_export(uuid),private.alert_share_snapshot(uuid),
  private.case_event_changed(),private.protect_case_consent() from public,anon,authenticated,service_role;
revoke all on sequence private.case_code_seq from public,anon,authenticated,service_role;
revoke all on function public.preview_ivmet_alert_share(uuid),public.confirm_ivmet_alert_share(uuid,bigint,text,text),
  public.withdraw_ivmet_case(uuid,bigint,text) from public,anon,service_role;
grant execute on function public.preview_ivmet_alert_share(uuid),public.confirm_ivmet_alert_share(uuid,bigint,text,text),
  public.withdraw_ivmet_case(uuid,bigint,text) to authenticated;
commit;

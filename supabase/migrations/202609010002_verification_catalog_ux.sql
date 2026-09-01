begin;

-- Una validación puede confirmar el maestro sin corregirlo. Compartir solo
-- tiene sentido cuando algún dato privado difiere realmente del catálogo.
create function private.equipment_has_corrections(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((select
    coalesce(ec.datos->>'ubicacion',e.ubicacion,'') is distinct from coalesce(e.ubicacion,'')
    or coalesce(ec.datos->>'cod_interno',e.cod_interno,'') is distinct from coalesce(e.cod_interno,'')
    or coalesce(ec.datos->>'marca',e.marca,'') is distinct from coalesce(e.marca,'')
    or coalesce(ec.datos->>'modelo',e.modelo,'') is distinct from coalesce(e.modelo,'')
    or coalesce(ec.datos->>'serie',e.serie,'') is distinct from coalesce(e.serie,'')
    from public.equipos e join public.equipos_cliente ec on ec.equipo_id=e.id
    where e.id=target),false);
$$;

-- La misma corrección no vuelve a ofrecerse mientras conserve una autorización
-- activa. Si cambia la ficha o se retira el acceso, vuelve a quedar pendiente.
create function private.equipment_has_pending_update(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((select private.equipment_has_corrections(target) and not exists(
      select 1
      from public.actualizaciones_compartidas a
      where a.equipo_id=target and a.visibilidad='SHARED'
        and a.snapshot->'customer'=current_snapshot.value->'customer'
        and coalesce(a.snapshot->>'area','')=coalesce(current_snapshot.value->>'area','')
        and coalesce(a.snapshot->>'catalogHash','')=coalesce(current_snapshot.value->>'catalogHash','')
    )
    from (select private.equipment_update_snapshot(target) value) current_snapshot
    where current_snapshot.value is not null),false);
$$;

-- Enriquece el contrato móvil sin exponer información nueva fuera del alcance
-- ya autorizado: conteos por planta, código del cliente y estado de corrección.
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_verification_catalog_ux;
alter function public.mobile_read_before_verification_catalog_ux(text,jsonb) set schema private;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  result jsonb;
  cid uuid;
  pid uuid:=nullif(filters->>'plantId','')::uuid;
  page_no int:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
  page_size int:=greatest(1,least(coalesce((filters->>'pageSize')::int,25),100));
begin
  if section<>'instruments' then
    result:=private.mobile_read_before_verification_catalog_ux(section,filters);
    if section='bootstrap' then
      result:=jsonb_set(result,'{plants}',coalesce((
        select jsonb_agg(plant||jsonb_build_object('equipmentCount',(
          select count(*)
          from public.equipos e
          join public.equipos_ivmet i on i.equipo_id=e.id
          join public.plantas p on p.id=e.planta_id
          where e.planta_id=(plant->>'id')::uuid and e.activo and p.activo
            and e.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY'
            and private.can_access_plant(e.planta_id)
        )) order by ord)
        from jsonb_array_elements(result->'plants') with ordinality plants(plant,ord)
      ),'[]'::jsonb));
    elsif section='equipment' then
      result:=result||jsonb_build_object(
        'customerHasCorrections',private.equipment_has_corrections((filters->>'equipmentId')::uuid),
        'customerUpdatePending',private.equipment_has_pending_update((filters->>'equipmentId')::uuid)
      );
    end if;
    return result;
  end if;

  cid:=private.mobile_require();
  with matching as (
    select e.id,e.cod_metrica,
      coalesce(ec.datos->>'cod_interno',e.cod_interno) cod_interno,
      coalesce(ec.datos->>'marca',e.marca) marca,
      coalesce(ec.datos->>'modelo',e.modelo) modelo,
      coalesce(ec.datos->>'serie',e.serie) serie,
      e.planta_id,i.area_id,coalesce(p.nombre,p.legacy_codigo_planta) planta,
      coalesce(a.nombre,'Sin área') area,
      coalesce(a.nombre,ec.datos->>'ubicacion',e.ubicacion,'Sin departamento') departamento
    from public.equipos e
    join public.equipos_ivmet i on i.equipo_id=e.id
    join public.plantas p on p.id=e.planta_id
    left join public.areas a on a.id=i.area_id
    left join public.equipos_cliente ec on ec.equipo_id=e.id
    where e.cliente_id=cid and e.activo and p.activo and e.estado_catalogo='READY'
      and i.habilitado and i.estado_configuracion='READY' and private.can_access_plant(e.planta_id)
      and (pid is null or e.planta_id=pid)
      and (nullif(filters->>'areaId','') is null or i.area_id=(filters->>'areaId')::uuid)
      and (nullif(filters->>'search','') is null
        or e.cod_metrica ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(ec.datos->>'cod_interno',e.cod_interno,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(ec.datos->>'marca',e.marca,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(ec.datos->>'modelo',e.modelo,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(a.nombre,ec.datos->>'ubicacion',e.ubicacion,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(p.nombre,p.legacy_codigo_planta,'') ilike '%'||left(filters->>'search',100)||'%')
  ), rows as (
    select * from matching
    order by coalesce(nullif(cod_interno,''),cod_metrica),lower(departamento),cod_metrica
    limit page_size offset (page_no-1)*page_size
  )
  select jsonb_build_object(
    'total',(select count(*) from matching),
    'items',coalesce((select jsonb_agg(to_jsonb(r)
      order by coalesce(nullif(r.cod_interno,''),r.cod_metrica),lower(r.departamento),r.cod_metrica) from rows r),'[]')
  ) into result;
  return result;
end;
$$;

-- La vista previa deja de existir cuando no hay una corrección pendiente.
alter function public.ivmet_customer_read(text,jsonb) rename to customer_read_before_verification_catalog_ux;
alter function public.customer_read_before_verification_catalog_ux(text,jsonb) set schema private;

create function public.ivmet_customer_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.customer_read_before_verification_catalog_ux(section,filters);
  if section='share-preview' then
    perform private.admin_assert(
      private.equipment_has_pending_update((filters->>'id')::uuid),
      'NO_EQUIPMENT_CORRECTIONS'
    );
  end if;
  return result;
end;
$$;

-- El control también se aplica al guardar. Los reintentos idempotentes de un
-- envío ya aceptado siguen llegando a la función anterior para recuperar recibo.
alter function public.ivmet_customer_mutate(text,jsonb,uuid) rename to customer_mutate_before_verification_catalog_ux;
alter function public.customer_mutate_before_verification_catalog_ux(text,jsonb,uuid) set schema private;

create function public.ivmet_customer_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if action='update.share' and not exists(
    select 1 from private.admin_requests r
    where r.request_id=ivmet_customer_mutate.request_id
      and r.action='customer.update.share'
      and r.actor='MOBILE:'||auth.uid()::text
  ) then
    perform private.admin_assert(
      private.equipment_has_pending_update((payload->>'id')::uuid),
      'NO_EQUIPMENT_CORRECTIONS'
    );
  end if;
  return private.customer_mutate_before_verification_catalog_ux(action,payload,request_id);
end;
$$;

revoke all on function private.equipment_has_corrections(uuid),
  private.equipment_has_pending_update(uuid),
  private.mobile_read_before_verification_catalog_ux(text,jsonb),
  private.customer_read_before_verification_catalog_ux(text,jsonb),
  private.customer_mutate_before_verification_catalog_ux(text,jsonb,uuid)
from public,anon,authenticated,service_role;

revoke all on function public.ivmet_mobile_read(text,jsonb),
  public.ivmet_customer_read(text,jsonb),
  public.ivmet_customer_mutate(text,jsonb,uuid)
from public,anon,service_role;
grant execute on function public.ivmet_mobile_read(text,jsonb),
  public.ivmet_customer_read(text,jsonb),
  public.ivmet_customer_mutate(text,jsonb,uuid)
to authenticated;

commit;

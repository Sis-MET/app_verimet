begin;

-- Guía de inicio de la app: cuánto de la puesta en marcha ya está hecho.
--
-- La app muestra la guía por rol y marca cada paso con lo que ya existe:
-- plantas y áreas, pesas patrón con certificado vigente, balanzas validadas y
-- configuradas, operadores y balanzas asignadas, verificaciones. Son conteos
-- del mismo alcance que el resto de `bootstrap`: el jefe de calidad cuenta
-- sus plantas; el operador, lo que tiene asignado y lo que capturó él.
--
-- Solo lectura y aditivo: una app anterior ignora `setup`, y una app nueva
-- contra un servidor anterior no lo recibe y deja la guía sin marcas.
create function private.mobile_setup_summary() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  quality boolean:=private.current_profile_role()='cliente_jefe_calidad';
  result jsonb;
begin
  with equipment as (
    select
      exists(select 1 from public.equipos_cliente ec
        where ec.equipo_id=e.id and ec.catalog_hash=e.source_hash) validated,
      exists(select 1 from public.equipo_planes ep
        join public.plan_versiones v on v.id=ep.plan_version_id
        where ep.equipo_id=e.id and ep.vigente_desde<=now()
          and (ep.vigente_hasta is null or ep.vigente_hasta>now()) and v.estado='PUBLISHED') configured,
      private.equipment_assignees(e.id)<>'[]'::jsonb assigned
    from public.equipos e
      join public.equipos_ivmet i on i.equipo_id=e.id
      join public.plantas p on p.id=e.planta_id
    where e.cliente_id=cid and e.activo and p.activo and e.estado_catalogo='READY'
      and i.habilitado and i.estado_configuracion='READY'
      and private.can_access_plant(e.planta_id) and private.equipment_in_scope(e.id)
  ), patterns as (
    select exists(select 1 from public.patron_certificados c
        where c.patron_id=pa.id and c.estado='ACTIVE' and c.vence_el>=current_date) traced
    from public.patrones pa
    where pa.cliente_id=cid and pa.activo and exists(select 1 from public.patron_plantas pp
      join public.plantas p on p.id=pp.planta_id
      where pp.patron_id=pa.id and p.activo and private.can_access_plant(pp.planta_id))
  )
  select jsonb_build_object(
    'plants',(select count(*) from public.plantas p
      where p.cliente_id=cid and p.activo and private.can_access_plant(p.id)),
    'areas',(select count(*) from public.areas a join public.plantas p on p.id=a.planta_id
      where a.cliente_id=cid and a.activa and p.activo and private.can_access_plant(a.planta_id)),
    'patterns',(select count(*) from patterns),
    'tracedPatterns',(select count(*) from patterns where traced),
    'equipment',(select count(*) from equipment),
    'validated',(select count(*) from equipment where validated),
    'configured',(select count(*) from equipment where configured),
    'assigned',(select count(*) from equipment where assigned),
    -- Operadores que trabajan en alguna planta del jefe. El operador no ve
    -- al resto del equipo.
    'operators',case when quality then (select count(distinct pr.id) from public.perfiles pr
      join public.usuario_plantas up on up.usuario_id=pr.id and up.activa
      where pr.cliente_id=cid and pr.activo and pr.rol='cliente_operador'
        and private.can_access_plant(up.planta_id)) end,
    -- Anuladas incluidas: la guía pregunta si ya se verificó alguna vez.
    'verifications',(select count(*) from public.verificaciones v
      where v.cliente_id=cid and private.can_access_plant(v.planta_id)
        and (quality or v.capturado_por=auth.uid()))
  ) into result;
  return result;
end; $$;

-- Se envuelve la lectura como en entregas anteriores.
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_setup_guide;
alter function public.mobile_read_before_setup_guide(text,jsonb) set schema private;
do $migration$
begin
  execute replace(pg_get_functiondef('private.mobile_read_before_setup_guide(text,jsonb)'::regprocedure),
    'ivmet_mobile_read.','mobile_read_before_setup_guide.');
end;
$migration$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb:=private.mobile_read_before_setup_guide(section,filters);
begin
  if section='bootstrap' then
    result:=result||jsonb_build_object('setup',private.mobile_setup_summary());
  end if;
  return result;
end; $$;

revoke all on function private.mobile_setup_summary(),private.mobile_read_before_setup_guide(text,jsonb)
from public,anon,authenticated,service_role;

revoke all on function public.ivmet_mobile_read(text,jsonb) from public,anon,service_role;
grant execute on function public.ivmet_mobile_read(text,jsonb) to authenticated;

commit;

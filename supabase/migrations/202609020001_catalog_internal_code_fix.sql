begin;

-- Las fichas privadas antiguas pueden conservar cod_interno como cadena vacía.
-- En el catálogo ese vacío no debe ocultar el código maestro de la empresa.
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_internal_code_fix;
alter function public.mobile_read_before_internal_code_fix(text,jsonb) set schema private;

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
    return private.mobile_read_before_internal_code_fix(section,filters);
  end if;

  cid:=private.mobile_require();
  with matching as (
    select e.id,e.cod_metrica,
      coalesce(
        nullif(btrim(ec.datos->>'cod_interno'),''),
        nullif(btrim(e.cod_interno),'')
      ) cod_interno,
      coalesce(nullif(btrim(ec.datos->>'marca'),''),e.marca) marca,
      coalesce(nullif(btrim(ec.datos->>'modelo'),''),e.modelo) modelo,
      coalesce(nullif(btrim(ec.datos->>'serie'),''),e.serie) serie,
      e.planta_id,i.area_id,coalesce(p.nombre,p.legacy_codigo_planta) planta,
      coalesce(a.nombre,'Sin área') area,
      coalesce(
        a.nombre,
        nullif(btrim(ec.datos->>'ubicacion'),''),
        nullif(btrim(e.ubicacion),''),
        'Sin departamento'
      ) departamento
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
        or coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),e.cod_interno,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(nullif(btrim(ec.datos->>'marca'),''),e.marca,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(nullif(btrim(ec.datos->>'modelo'),''),e.modelo,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(a.nombre,nullif(btrim(ec.datos->>'ubicacion'),''),e.ubicacion,'') ilike '%'||left(filters->>'search',100)||'%'
        or coalesce(p.nombre,p.legacy_codigo_planta,'') ilike '%'||left(filters->>'search',100)||'%')
  ), rows as (
    select * from matching
    order by coalesce(cod_interno,cod_metrica),lower(departamento),cod_metrica
    limit page_size offset (page_no-1)*page_size
  )
  select jsonb_build_object(
    'total',(select count(*) from matching),
    'items',coalesce((select jsonb_agg(to_jsonb(r)
      order by coalesce(r.cod_interno,r.cod_metrica),lower(r.departamento),r.cod_metrica) from rows r),'[]')
  ) into result;
  return result;
end;
$$;

revoke all on function private.mobile_read_before_internal_code_fix(text,jsonb)
from public,anon,authenticated,service_role;
revoke all on function public.ivmet_mobile_read(text,jsonb)
from public,anon,service_role;
grant execute on function public.ivmet_mobile_read(text,jsonb) to authenticated;

commit;

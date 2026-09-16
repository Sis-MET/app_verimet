begin;

-- RimMET atiende lo que comparte cada cliente dentro de su ficha. El directorio
-- indica qué empresas tienen casos o actualizaciones sin revisar, y las balanzas
-- contratadas se eligen en una lista y se habilitan juntas, no una por una.
create index casos_nuevos_cliente_idx on public.casos_compartidos(cliente_id)
  where visibilidad='SHARED' and estado='NEW';
create index actualizaciones_nuevas_cliente_idx on public.actualizaciones_compartidas(cliente_id)
  where visibilidad='SHARED' and estado='NEW';

create function private.client_attention(target uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object(
    'newCases',(select count(*) from public.casos_compartidos c
      where c.cliente_id=target and c.visibilidad='SHARED' and c.estado='NEW'),
    'pendingUpdates',(select count(*) from public.actualizaciones_compartidas a
      where a.cliente_id=target and a.visibilidad='SHARED' and a.estado='NEW'))
$$;

-- Balanzas de DataMET validadas que nadie habilitó ni suspendió: el aviso de
-- pendientes de RimMET. Una suspensión es una decisión explícita y no cuenta.
create function private.equipment_pending_enable(target_client uuid,target_plant uuid default null)
returns setof uuid language sql stable set search_path='' as $$
  select e.id from public.equipos e left join public.equipos_ivmet ei on ei.equipo_id=e.id
  where e.cliente_id=target_client and e.origen='DATAMET' and e.activo and e.estado_catalogo='READY'
    and (target_plant is null or e.planta_id=target_plant)
    and (ei.equipo_id is null or (not ei.habilitado and ei.estado_configuracion='PENDING'))
$$;

alter function public.ivmet_admin_read(text,uuid,jsonb) rename to admin_read_before_bulk;
alter function public.admin_read_before_bulk(text,uuid,jsonb) set schema private;
alter function public.ivmet_admin_mutate(text,text,jsonb,uuid) rename to admin_mutate_before_bulk;
alter function public.admin_mutate_before_bulk(text,text,jsonb,uuid) set schema private;
do $migration$
declare item record;
begin
  -- PL/pgSQL conserva el nombre anterior en las referencias calificadas.
  for item in select * from (values
    ('private.admin_read_before_bulk(text,uuid,jsonb)','ivmet_admin_read.','admin_read_before_bulk.'),
    ('private.admin_mutate_before_bulk(text,text,jsonb,uuid)','ivmet_admin_mutate.','admin_mutate_before_bulk.')
  ) v(signature,previous_name,next_name) loop
    execute replace(pg_get_functiondef(item.signature::regprocedure),item.previous_name,item.next_name);
  end loop;
end;
$migration$;

create function public.ivmet_admin_read(section text,client_id uuid default null,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.admin_read_before_bulk(section,client_id,filters);
  if section='clients' then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(x.item||private.client_attention(nullif(x.item->>'id','')::uuid)
        order by x.ord)
      from jsonb_array_elements(result->'items') with ordinality x(item,ord)),'[]'::jsonb));
  elsif section='client' then
    result:=result||jsonb_build_object('attention',private.client_attention(client_id));
  elsif section='equipment' then
    result:=result||jsonb_build_object('pendingEnable',(select count(*)
      from private.equipment_pending_enable(client_id,nullif(filters->>'plantId','')::uuid)));
  end if;
  return result;
end; $$;

create function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare customer uuid; enabled boolean; targets uuid[]; changed uuid[];
  digest text; saved private.admin_requests%rowtype; result jsonb;
begin
  if action<>'equipment.bulk-configure' then
    return private.admin_mutate_before_bulk(actor,action,payload,request_id);
  end if;
  perform private.staff_require(actor,'commercial');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object'
    and octet_length(payload::text)<=65536,'INVALID_REQUEST');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r
    where r.request_id=ivmet_admin_mutate.request_id and r.action=ivmet_admin_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;
  perform private.admin_assert(coalesce(payload->>'clientId','') ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$','INVALID_REQUEST');
  customer:=(payload->>'clientId')::uuid;
  perform private.admin_assert(exists(select 1 from public.clientes c where c.id=customer),'CLIENT_NOT_FOUND');
  -- Un lote por cliente a la vez; cada balanza se bloquea igual que en equipment.configure.
  perform pg_advisory_xact_lock(hashtextextended(customer::text,5));
  perform private.admin_assert(jsonb_typeof(payload->'enabled')='boolean' and jsonb_typeof(payload->'ids')='array'
    and jsonb_array_length(payload->'ids') between 1 and 500
    and not exists(select 1 from jsonb_array_elements(payload->'ids') x where jsonb_typeof(x.value)<>'string'
      or x.value#>>'{}' !~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'),'INVALID_REQUEST');
  enabled:=(payload->>'enabled')::boolean;
  targets:=array(select distinct x.value::uuid from jsonb_array_elements_text(payload->'ids') x(value) order by 1);
  perform private.admin_assert(cardinality(targets)=jsonb_array_length(payload->'ids'),'DUPLICATE_EQUIPMENT');
  perform 1 from public.equipos e where e.id=any(targets) for update;
  perform private.admin_assert((select count(*) from public.equipos e
    where e.id=any(targets) and e.cliente_id=customer)=cardinality(targets),'EQUIPMENT_NOT_FOUND');
  perform private.admin_assert(not exists(select 1 from public.equipos e
    where e.id=any(targets) and e.origen='CLIENTE'),'CUSTOMER_REGISTERED_EQUIPMENT');
  perform private.admin_assert(not enabled or not exists(select 1 from public.equipos e
    where e.id=any(targets) and not (e.activo and e.estado_catalogo='READY')),'EQUIPMENT_REQUIRES_REVIEW');
  perform 1 from public.equipos_ivmet ei where ei.equipo_id=any(targets) for update;
  -- Solo cambian las balanzas que no estaban ya en el estado pedido: sin versiones ni eventos de más.
  with applied as (
    insert into public.equipos_ivmet as ei(equipo_id,habilitado,estado_configuracion)
    select t.id,enabled,case when enabled then 'READY' else 'SUSPENDED' end from unnest(targets) t(id)
    on conflict(equipo_id) do update set habilitado=excluded.habilitado,estado_configuracion=excluded.estado_configuracion
      where ei.habilitado is distinct from excluded.habilitado
        or ei.estado_configuracion is distinct from excluded.estado_configuracion
    returning ei.equipo_id)
  select coalesce(array_agg(a.equipo_id order by a.equipo_id),'{}') into changed from applied a;
  insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion,despues)
    select actor,customer,'equipment',t.id::text,action,jsonb_build_object('enabled',enabled)
    from unnest(changed) t(id);
  result:=jsonb_build_object('requested',cardinality(targets),'changed',cardinality(changed),'enabled',enabled);
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,action,actor,digest,result);
  return result;
end; $$;

revoke all on function private.client_attention(uuid),private.equipment_pending_enable(uuid,uuid),
  private.admin_read_before_bulk(text,uuid,jsonb),private.admin_mutate_before_bulk(text,text,jsonb,uuid)
from public,anon,authenticated,service_role;
revoke all on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid)
  from public,anon,authenticated;
grant execute on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid)
  to service_role;

commit;

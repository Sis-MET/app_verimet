begin;

-- El catálogo importado es de solo lectura. Las correcciones del cliente viven
-- aparte y nunca se pierden con la siguiente importación de DataMET.
create table public.equipos_cliente (
  equipo_id uuid primary key,
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  datos jsonb not null default '{}' check (jsonb_typeof(datos)='object'),
  catalog_hash text not null,
  validado_por uuid not null references public.perfiles(id),
  validado_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  foreign key (equipo_id,cliente_id,planta_id) references public.equipos(id,cliente_id,planta_id)
);
create index equipos_cliente_scope_idx on public.equipos_cliente(cliente_id,planta_id);
create trigger equipos_cliente_updated before update on public.equipos_cliente
for each row execute function private.set_updated_at();
alter table public.equipos_cliente enable row level security;
revoke all on public.equipos_cliente from public,anon,authenticated,service_role;

-- Recibos de consentimiento específicos, no una autorización permanente.
create table public.actualizaciones_compartidas (
  id uuid primary key default extensions.gen_random_uuid(),
  equipo_id uuid not null,
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  autorizado_por uuid not null references public.perfiles(id),
  autorizado_at timestamptz not null default now(),
  consentimiento_version text not null default 'equipment-sharing-v1',
  snapshot jsonb not null,
  snapshot_hash text not null check(snapshot_hash ~ '^[0-9a-f]{64}$'),
  mensaje text not null check(length(btrim(mensaje)) between 1 and 2000),
  visibilidad text not null default 'SHARED' check(visibilidad in ('SHARED','WITHDRAWN')),
  retirado_at timestamptz,
  estado text not null default 'NEW' check(estado in ('NEW','REVIEWED')),
  comentario text,
  revisado_por text,
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  foreign key(equipo_id,cliente_id,planta_id) references public.equipos(id,cliente_id,planta_id),
  check((visibilidad='SHARED' and retirado_at is null) or (visibilidad='WITHDRAWN' and retirado_at is not null)),
  check(estado='NEW' or (revisado_por is not null and length(btrim(comentario)) between 1 and 2000))
);
create index actualizaciones_inbox_idx on public.actualizaciones_compartidas(visibilidad,autorizado_at desc,id);
create index actualizaciones_equipo_idx on public.actualizaciones_compartidas(cliente_id,planta_id,equipo_id);
create trigger actualizaciones_updated before update on public.actualizaciones_compartidas
for each row execute function private.set_updated_at();
alter table public.actualizaciones_compartidas enable row level security;
revoke all on public.actualizaciones_compartidas from public,anon,authenticated,service_role;

create function private.protect_equipment_consent() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' or (to_jsonb(new)-array['estado','comentario','revisado_por','visibilidad','retirado_at','updated_at','row_version'])
    is distinct from (to_jsonb(old)-array['estado','comentario','revisado_por','visibilidad','retirado_at','updated_at','row_version'])
    or (old.visibilidad='WITHDRAWN' and new.visibilidad<>'WITHDRAWN') then
    raise exception 'CONSENT_IS_IMMUTABLE';
  end if;
  return new;
end; $$;
create trigger actualizaciones_consent before update or delete on public.actualizaciones_compartidas
for each row execute function private.protect_equipment_consent();

create or replace function private.ivmet_export_allowed(aggregate_name text) returns boolean
language sql immutable set search_path='' as $$
  select aggregate_name=any(array['public.clientes','public.plantas','public.equipos','public.equipo_rangos',
    'public.perfiles','public.usuario_plantas','public.planes_comerciales','public.precios_plan',
    'public.contratos','public.suscripciones','public.facturas','public.pagos','public.suscripcion_cupos',
    'public.licencias_usuario','public.eventos_licencia','public.casos_compartidos','public.actualizaciones_compartidas']);
$$;
update private.sync_outbox set privacy_blocked=true where not private.ivmet_export_allowed(aggregate_type);
revoke all on public.areas,public.equipos_ivmet,public.patrones,public.patron_plantas,public.patron_certificados,
  public.planes,public.plan_versiones,public.plan_pruebas,public.plan_puntos,public.equipo_planes from service_role;

create function private.area_key(value text) returns text
language sql immutable set search_path='' as $$
  select lower(translate(regexp_replace(btrim(value),'\s+',' ','g'),'ÁÉÍÓÚÜáéíóúü','AEIOUUaeiouu'));
$$;
create index areas_match_idx on public.areas(cliente_id,planta_id,private.area_key(nombre));

create function private.customer_equipment(target uuid) returns public.equipos
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); e public.equipos%rowtype;
begin
  select eq.* into e from public.equipos eq join public.plantas p on p.id=eq.planta_id
    join public.equipos_ivmet i on i.equipo_id=eq.id where eq.id=target and eq.cliente_id=cid
    and eq.activo and p.activo and eq.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY'
    and private.can_access_plant(eq.planta_id);
  perform private.admin_assert(found,'EQUIPMENT_NOT_ACCESSIBLE');
  return e;
end; $$;

create function private.customer_pattern(target uuid,editing boolean default false) returns void
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require();
begin
  if editing then perform 1 from public.patrones where id=target and cliente_id=cid for update; end if;
  perform private.admin_assert(exists(select 1 from public.patrones p join public.patron_plantas pp on pp.patron_id=p.id
    where p.id=target and p.cliente_id=cid and private.can_access_plant(pp.planta_id)),'PATTERN_NOT_ACCESSIBLE');
  if editing then
    perform private.admin_assert(not exists(select 1 from public.patron_plantas pp where pp.patron_id=target
      and not private.can_access_plant(pp.planta_id)),'PATTERN_ALL_PLANTS_REQUIRED');
  end if;
end; $$;
-- Se usa también en escrituras; no puede ser STABLE al adquirir FOR UPDATE.
alter function private.customer_pattern(uuid,boolean) volatile;

create function private.equipment_update_snapshot(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('equipmentId',e.id,'code',e.cod_metrica,'clientCode',c.codigo,'plantCode',p.legacy_codigo_planta,
    'catalog',jsonb_build_object('ubicacion',e.ubicacion,'cod_interno',e.cod_interno,'marca',e.marca,'modelo',e.modelo,'serie',e.serie),
    'customer',ec.datos,'area',a.nombre,'validatedAt',ec.validado_at,'version',ec.row_version::text,
    'catalogHash',e.source_hash,'validatedCatalogHash',ec.catalog_hash)
  from public.equipos e join public.equipos_cliente ec on ec.equipo_id=e.id
    join public.clientes c on c.id=e.cliente_id join public.plantas p on p.id=e.planta_id
    join public.equipos_ivmet i on i.equipo_id=e.id left join public.areas a on a.id=i.area_id where e.id=target;
$$;

create function public.ivmet_customer_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); target uuid:=nullif(filters->>'id','')::uuid;
  pid uuid:=nullif(filters->>'plantId','')::uuid; e public.equipos%rowtype; result jsonb;
  pg int:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
  sz int:=greatest(1,least(coalesce((filters->>'pageSize')::int,25),100));
begin
  if section='equipment' then
    e:=private.customer_equipment(target);
    return jsonb_build_object('master',to_jsonb(e)-array['last_seen_run_id'],
      'customer',(select to_jsonb(ec)||jsonb_build_object('row_version',ec.row_version::text) from public.equipos_cliente ec where equipo_id=e.id),
      'areaId',(select area_id from public.equipos_ivmet where equipo_id=e.id),
      'suggestedAreaId',(select id from public.areas where planta_id=e.planta_id and activa and private.area_key(nombre)=private.area_key(e.ubicacion) order by created_at,id limit 1),
      'areas',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.nombre) order by a.nombre) from public.areas a where a.planta_id=e.planta_id and a.activa),'[]'),
      'suggestedArea',nullif(btrim(regexp_replace(e.ubicacion,'\s+',' ','g')),''));
  elsif section='areas' then
    perform private.admin_assert(pid is not null and private.can_access_plant(pid),'PLANT_SCOPE_INVALID');
    with matches as(select a.id,a.nombre name,a.activa active,a.row_version::text version from public.areas a
      where a.cliente_id=cid and a.planta_id=pid), rows as(select * from matches order by name,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(r) order by name,id) from rows r),'[]'),
      'total',(select count(*) from matches)) into result;
    return result;
  elsif section='area-suggestions' then
    perform private.admin_assert(pid is not null and private.can_access_plant(pid),'PLANT_SCOPE_INVALID');
    with candidates as(select private.area_key(eq.ubicacion) key,min(btrim(regexp_replace(eq.ubicacion,'\s+',' ','g'))) name,count(*) equipment_count
      from public.equipos eq join public.equipos_ivmet i on i.equipo_id=eq.id where eq.cliente_id=cid and eq.planta_id=pid
      and eq.activo and eq.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY'
      and length(btrim(eq.ubicacion)) between 1 and 150 and private.area_key(eq.ubicacion) not in ('sin ubicacion','s/n','n/a','-')
      and not exists(select 1 from public.areas a where a.planta_id=pid and private.area_key(a.nombre)=private.area_key(eq.ubicacion))
      group by private.area_key(eq.ubicacion)), rows as(select * from candidates order by name,key limit sz offset(pg-1)*sz)
    select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(r) order by name,key) from rows r),'[]'),
      'total',(select count(*) from candidates)) into result;
    return result;
  elsif section='patterns' then
    with matches as(select p.* from public.patrones p where p.cliente_id=cid and exists(select 1 from public.patron_plantas pp
      where pp.patron_id=p.id and (pid is null or pp.planta_id=pid) and private.can_access_plant(pp.planta_id))),
    rows as(select * from matches order by codigo,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('total',(select count(*) from matches),'items',coalesce((select jsonb_agg(
      private.stringify_ivmet_outbox_numbers('public.patrones',to_jsonb(p))||jsonb_build_object('row_version',p.row_version::text,
        'canEdit',not exists(select 1 from public.patron_plantas pp where pp.patron_id=p.id and not private.can_access_plant(pp.planta_id)),
        'plantIds',coalesce((select jsonb_agg(pp.planta_id) from public.patron_plantas pp where pp.patron_id=p.id and private.can_access_plant(pp.planta_id)),'[]'),
        'certificates',coalesce((select jsonb_agg(to_jsonb(pc)||jsonb_build_object('row_version',pc.row_version::text) order by pc.calibrado_el desc) from public.patron_certificados pc where pc.patron_id=p.id),'[]')) order by p.codigo,p.id) from rows p),'[]')) into result;
    return result;
  elsif section in ('plans','plan') then
    if section='plan' then
      perform private.admin_assert(exists(select 1 from public.plan_versiones v join public.planes p on p.id=v.plan_id
        where v.id=target and p.cliente_id=cid),'PLAN_NOT_ACCESSIBLE');
      return private.metrology_version_json(target);
    end if;
    with matches as(select v.* from public.plan_versiones v join public.planes p on p.id=v.plan_id
      where p.cliente_id=cid and p.activo and (coalesce(filters->>'state','')='' or v.estado=filters->>'state')),
    rows as(select * from matches order by created_at desc,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('total',(select count(*) from matches),'items',coalesce((select jsonb_agg(private.metrology_version_json(v.id) order by v.created_at desc,v.id) from rows v),'[]'),
      'finalizationEnabled',false) into result;
    return result;
  elsif section='share-preview' then
    perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
    e:=private.customer_equipment(target);
    result:=private.equipment_update_snapshot(e.id);
    perform private.admin_assert(result is not null,'EQUIPMENT_VALIDATION_REQUIRED');
    return jsonb_build_object('snapshot',result,'hash',encode(sha256(convert_to(result::text,'UTF8')),'hex'),
      'consentVersion','equipment-sharing-v1','notice','Solo se enviarán estos datos y el área de esta balanza. No se comparten planes, patrones ni pruebas. Retirar el acceso no elimina copias ya entregadas a Métrica.');
  elsif section='updates' then
    with matches as(select a.* from public.actualizaciones_compartidas a where a.cliente_id=cid and private.can_access_plant(a.planta_id)
      and (target is null or a.equipo_id=target)), rows as(select * from matches order by autorizado_at desc,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('total',(select count(*) from matches),'items',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('row_version',r.row_version::text) order by autorizado_at desc,id) from rows r),'[]')) into result;
    return result;
  end if;
  raise exception 'UNKNOWN_CUSTOMER_SECTION';
end; $$;

create function private.customer_plan_save(payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); target uuid:=nullif(payload->>'id','')::uuid;
  plan_id_value uuid:=nullif(payload->>'planId','')::uuid; v public.plan_versiones%rowtype;
  t jsonb; pt jsonb; trial uuid; seq int; current_name text;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(length(btrim(payload->>'name')) between 1 and 200
    and jsonb_typeof(payload->'tests')='array' and jsonb_array_length(payload->'tests') between 1 and 3,'PLAN_TESTS_REQUIRED');
  if target is null then
    if plan_id_value is null then
      insert into public.planes(cliente_id,nombre,created_by) values(cid,btrim(payload->>'name'),auth.uid()) returning id into plan_id_value;
    else
      select p.nombre into current_name from public.planes p
        where p.id=plan_id_value and p.cliente_id=cid and p.activo for update;
      perform private.admin_assert(found,'PLAN_NOT_ACCESSIBLE');
      perform private.admin_assert(btrim(payload->>'name')=current_name,'PLAN_NAME_IS_IMMUTABLE');
    end if;
    insert into public.plan_versiones(plan_id,version,procedimiento_referencia,notas,created_by)
      select plan_id_value,coalesce(max(pv.version),0)+1,nullif(btrim(payload->>'procedureReference'),''),payload->>'notes',auth.uid()
      from public.plan_versiones pv where pv.plan_id=plan_id_value returning id into target;
  else
    select pv.* into v from public.plan_versiones pv join public.planes p on p.id=pv.plan_id
      where pv.id=target and p.cliente_id=cid for update of pv,p;
    perform private.admin_assert(found,'PLAN_NOT_ACCESSIBLE');
    select p.nombre into current_name from public.planes p where p.id=v.plan_id;
    perform private.admin_assert(v.estado='DRAFT','PUBLISHED_PLAN_IS_IMMUTABLE');
    perform private.admin_assert(v.draft_revision=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert(btrim(payload->>'name')=current_name,'PLAN_NAME_IS_IMMUTABLE');
    delete from public.plan_puntos where plan_prueba_id in(select id from public.plan_pruebas where plan_version_id=target);
    delete from public.plan_pruebas where plan_version_id=target;
    update public.plan_versiones set procedimiento_referencia=nullif(btrim(payload->>'procedureReference'),''),
      notas=payload->>'notes',draft_revision=draft_revision+1 where id=target;
  end if;
  for t in select value from jsonb_array_elements(payload->'tests') loop
    perform private.admin_assert(jsonb_typeof(t->'points')='array' and jsonb_array_length(t->'points') between 1 and 200
      and (t->>'frequencyDays') ~ '^[0-9]{1,4}$' and (t->>'warningDays') ~ '^[0-9]{1,4}$'
      and (t->>'frequencyDays')::int between 1 and 3650 and (t->>'warningDays')::int<(t->>'frequencyDays')::int
      and length(btrim(t->>'unit')) between 1 and 20,'INVALID_PLAN_TEST');
    insert into public.plan_pruebas(plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,aviso_dias)
      values(target,t->>'type',t->>'method',btrim(t->>'unit'),(t->>'frequencyDays')::int,(t->>'warningDays')::int) returning id into trial;
    seq:=0;
    for pt in select value from jsonb_array_elements(t->'points') loop
      seq:=seq+1;
      perform private.admin_assert(jsonb_typeof(pt->'load')='string' and (pt->>'load') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
        and jsonb_typeof(pt->'tolerance')='string' and (pt->>'tolerance') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$','EXACT_DECIMAL_REQUIRED');
      perform private.admin_assert((pt->>'group') ~ '^[0-9]{1,4}$' and (pt->>'group')::int>0
        and length(btrim(pt->>'label')) between 1 and 200 and length(btrim(pt->>'code')) between 1 and 100
        and jsonb_typeof(coalesce(pt->'metadata','{}'))='object','INVALID_PLAN_POINT');
      insert into public.plan_puntos(plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,tolerancia,posicion,direccion,metadata)
        values(trial,(pt->>'group')::int,seq,pt->>'code',pt->>'label',(pt->>'load')::numeric,(pt->>'tolerance')::numeric,
          pt->>'position',pt->>'direction',coalesce(pt->'metadata','{}'));
    end loop;
  end loop;
  return target;
end; $$;

create function public.ivmet_customer_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); actor_value text:='MOBILE:'||auth.uid()::text;
  target uuid:=nullif(payload->>'id','')::uuid; pid uuid:=nullif(payload->>'plantId','')::uuid;
  saved private.admin_requests%rowtype; result jsonb; digest text; e public.equipos%rowtype;
  ec public.equipos_cliente%rowtype; a public.areas%rowtype; pattern public.patrones%rowtype;
  cert public.patron_certificados%rowtype; v public.plan_versiones%rowtype; shared public.actualizaciones_compartidas%rowtype;
  area_value uuid; plants uuid[]; field text; data jsonb; assignment_time timestamptz;
begin
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object' and octet_length(payload::text)<=262144,'INVALID_REQUEST');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  -- Revalidar rol y alcance antes incluso de devolver un recibo idempotente.
  if action like 'plan.%' or action like 'update.%' then
    perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  end if;
  if action='area.save' then
    perform private.admin_assert(pid is not null and private.can_access_plant(pid),'PLANT_SCOPE_INVALID');
  elsif action like 'pattern.%' or action like 'certificate.%' then
    if action='pattern.save' then
      plants:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
      perform private.admin_assert(cardinality(plants) between 1 and 100
        and not exists(select 1 from unnest(plants) plant where not private.can_access_plant(plant)),'PLANT_SCOPE_INVALID');
    end if;
    if action='pattern.save' and target is not null then perform private.customer_pattern(target,true);
    elsif action='certificate.create' then perform private.customer_pattern((payload->>'patternId')::uuid,true);
    elsif action='certificate.annul' then
      select * into cert from public.patron_certificados where id=target;
      perform private.admin_assert(found,'CERTIFICATE_NOT_ACCESSIBLE'); perform private.customer_pattern(cert.patron_id,true);
    end if;
  elsif action in ('equipment.validate','update.share') then e:=private.customer_equipment(target);
  elsif action='plan.assign' then e:=private.customer_equipment((payload->>'equipmentId')::uuid);
  elsif action='update.withdraw' then
    select * into shared from public.actualizaciones_compartidas where id=target and cliente_id=cid and private.can_access_plant(planta_id) for update;
    perform private.admin_assert(found,'UPDATE_NOT_ACCESSIBLE');
  end if;
  select * into saved from private.admin_requests r where r.request_id=ivmet_customer_mutate.request_id and r.action='customer.'||ivmet_customer_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor_value and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT'); return saved.result;
  end if;
  if action='area.save' then
    perform private.admin_assert(length(btrim(payload->>'name')) between 1 and 150 and jsonb_typeof(payload->'active')='boolean','INVALID_AREA');
    perform pg_advisory_xact_lock(hashtextextended(pid::text,2));
    if target is null then
      select * into a from public.areas where planta_id=pid and private.area_key(nombre)=private.area_key(payload->>'name') order by created_at,id limit 1;
      if found then
        perform private.admin_assert(a.activa,'AREA_INACTIVE'); target:=a.id;
      else
        insert into public.areas(cliente_id,planta_id,nombre,activa,created_by)
          values(cid,pid,btrim(regexp_replace(payload->>'name','\s+',' ','g')),(payload->>'active')::boolean,auth.uid()) returning id into target;
      end if;
    else
      select * into a from public.areas where id=target and cliente_id=cid and planta_id=pid for update;
      perform private.admin_assert(found and a.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      perform private.admin_assert(not exists(select 1 from public.areas where planta_id=pid and id<>target
        and private.area_key(nombre)=private.area_key(payload->>'name')),'AREA_ALREADY_EXISTS');
      perform private.admin_assert((payload->>'active')::boolean or not exists(select 1 from public.equipos_ivmet where area_id=target),'AREA_IN_USE');
      update public.areas set nombre=btrim(regexp_replace(payload->>'name','\s+',' ','g')),activa=(payload->>'active')::boolean where id=target;
    end if;
    result:=jsonb_build_object('id',target);
  elsif action='equipment.validate' then
    perform 1 from public.equipos where id=e.id for share;
    perform 1 from public.equipos_ivmet where equipo_id=e.id for update;
    e:=private.customer_equipment(e.id);
    perform private.admin_assert(payload->>'catalogHash'=e.source_hash,'CATALOG_CHANGED');
    select * into ec from public.equipos_cliente where equipo_id=e.id for update;
    perform private.admin_assert(coalesce(ec.row_version,0)=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    data:=payload->'data';
    perform private.admin_assert(jsonb_typeof(data)='object' and (data-array['ubicacion','cod_interno','marca','modelo','serie'])='{}','INVALID_EQUIPMENT_DATA');
    foreach field in array array['ubicacion','cod_interno','marca','modelo','serie'] loop
      perform private.admin_assert(jsonb_typeof(data->field)='string' and length(data->>field)<=150,'INVALID_EQUIPMENT_DATA');
    end loop;
    area_value:=nullif(payload->>'areaId','')::uuid;
    if length(btrim(coalesce(payload->>'areaName','')))>0 then
      perform private.admin_assert(area_value is null and length(btrim(payload->>'areaName'))<=150,'INVALID_AREA');
      perform pg_advisory_xact_lock(hashtextextended(e.planta_id::text,2));
      select * into a from public.areas where planta_id=e.planta_id and private.area_key(nombre)=private.area_key(payload->>'areaName') order by created_at,id limit 1 for update;
      if found then
        perform private.admin_assert(a.activa,'AREA_INACTIVE'); area_value:=a.id;
      else
        insert into public.areas(cliente_id,planta_id,nombre,created_by) values(cid,e.planta_id,btrim(regexp_replace(payload->>'areaName','\s+',' ','g')),auth.uid()) returning id into area_value;
      end if;
    end if;
    if area_value is not null then
      perform 1 from public.areas where id=area_value and planta_id=e.planta_id and cliente_id=cid and activa for share;
      perform private.admin_assert(found,'AREA_SCOPE_INVALID');
    end if;
    insert into public.equipos_cliente(equipo_id,cliente_id,planta_id,datos,catalog_hash,validado_por)
      values(e.id,cid,e.planta_id,data,e.source_hash,auth.uid())
      on conflict(equipo_id) do update set datos=excluded.datos,catalog_hash=excluded.catalog_hash,validado_por=auth.uid(),validado_at=now();
    update public.equipos_ivmet set area_id=area_value where equipo_id=e.id;
    result:=jsonb_build_object('id',e.id,'shared',false);
  elsif action='pattern.save' then
    plants:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
    perform private.admin_assert(cardinality(plants) between 1 and 100 and (select count(distinct p) from unnest(plants) p)=cardinality(plants)
      and not exists(select 1 from unnest(plants) p where not private.can_access_plant(p)),'PLANT_SCOPE_INVALID');
    perform private.admin_assert(length(btrim(payload->>'code')) between 1 and 100 and length(btrim(payload->>'description')) between 1 and 300
      and length(btrim(payload->>'type')) between 1 and 50 and jsonb_typeof(payload->'active')='boolean','INVALID_PATTERN');
    perform private.admin_assert(jsonb_typeof(payload->'capacity')='string' and ((payload->>'capacity')='' or
      (payload->>'capacity') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'),'EXACT_DECIMAL_REQUIRED');
    if target is null then
      insert into public.patrones(cliente_id,codigo,descripcion,tipo,clase,unidad,capacidad,activo,created_by)
        values(cid,btrim(payload->>'code'),btrim(payload->>'description'),payload->>'type',payload->>'class',payload->>'unit',
          nullif(payload->>'capacity','')::numeric,(payload->>'active')::boolean,auth.uid()) returning id into target;
    else
      select * into pattern from public.patrones where id=target for update;
      perform private.admin_assert(pattern.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      update public.patrones set codigo=btrim(payload->>'code'),descripcion=btrim(payload->>'description'),tipo=payload->>'type',
        clase=payload->>'class',unidad=payload->>'unit',capacidad=nullif(payload->>'capacity','')::numeric,activo=(payload->>'active')::boolean where id=target;
    end if;
    delete from public.patron_plantas where patron_id=target and planta_id<>all(plants);
    insert into public.patron_plantas(patron_id,planta_id) select target,unnest(plants) on conflict do nothing;
    result:=jsonb_build_object('id',target);
  elsif action='certificate.create' then
    perform private.admin_assert(length(btrim(payload->>'number')) between 1 and 150 and length(btrim(payload->>'lab')) between 1 and 250
      and payload->>'calibratedOn' ~ '^\d{4}-\d{2}-\d{2}$' and payload->>'expiresOn' ~ '^\d{4}-\d{2}-\d{2}$','INVALID_CERTIFICATE');
    insert into public.patron_certificados(patron_id,numero,laboratorio,calibrado_el,vence_el,created_by)
      values((payload->>'patternId')::uuid,payload->>'number',payload->>'lab',(payload->>'calibratedOn')::date,(payload->>'expiresOn')::date,auth.uid()) returning id into target;
    result:=jsonb_build_object('id',target);
  elsif action='certificate.annul' then
    perform private.admin_assert(length(btrim(payload->>'reason')) between 1 and 2000,'REASON_REQUIRED');
    perform private.admin_assert(cert.row_version=(payload->>'version')::bigint and cert.estado='ACTIVE','ROW_VERSION_CONFLICT');
    update public.patron_certificados set estado='ANNULLED',row_version=row_version+1 where id=target;
    result:=jsonb_build_object('id',target);
  elsif action='plan.save' then
    target:=private.customer_plan_save(payload); result:=jsonb_build_object('id',target);
  elsif action in ('plan.publish','plan.retire','plan.assign') then
    if action='plan.assign' then target:=(payload->>'planVersionId')::uuid; end if;
    select pv.* into v from public.plan_versiones pv join public.planes p on p.id=pv.plan_id
      where pv.id=target and p.cliente_id=cid and p.activo for update of pv;
    perform private.admin_assert(found,'PLAN_NOT_ACCESSIBLE');
    if action<>'plan.assign' then perform private.admin_assert(v.draft_revision=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT'); end if;
    if action='plan.retire' then
      perform private.admin_assert(v.estado='PUBLISHED','PUBLISHED_PLAN_REQUIRED');
      update public.plan_versiones set estado='RETIRED',retired_at=now(),retired_by=auth.uid() where id=v.id;
    else
      perform private.admin_assert(v.estado=case when action='plan.publish' then 'DRAFT' else 'PUBLISHED' end,'PUBLISHED_PLAN_REQUIRED');
      perform private.admin_assert(v.procedimiento_referencia is not null and exists(select 1 from public.plan_pruebas where plan_version_id=v.id)
        and not exists(select 1 from public.plan_pruebas t where t.plan_version_id=v.id and (
          not exists(select 1 from public.plan_puntos pp where pp.plan_prueba_id=t.id) or not exists(
            select 1 from private.approved_metrology_methods m where m.method=t.metodo_evaluacion and m.procedure_reference=v.procedimiento_referencia))),
        'OFFICIAL_PROCEDURE_REQUIRED');
      if action='plan.publish' then
        update public.plan_versiones set estado='PUBLISHED',published_at=now(),published_by=auth.uid() where id=v.id;
      else
        perform 1 from public.equipos where id=e.id for share;
        perform 1 from public.equipos_ivmet where equipo_id=e.id for update;
        e:=private.customer_equipment(e.id);
        perform private.admin_assert(exists(select 1 from public.equipos_cliente where equipo_id=e.id and catalog_hash=e.source_hash),'EQUIPMENT_VALIDATION_REQUIRED');
        assignment_time:=clock_timestamp();
        update public.equipo_planes set vigente_hasta=assignment_time where equipo_id=e.id and vigente_hasta is null;
        insert into public.equipo_planes(equipo_id,plan_version_id,vigente_desde,created_by) values(e.id,v.id,assignment_time,auth.uid());
      end if;
    end if;
    result:=jsonb_build_object('id',target);
  elsif action='update.share' then
    perform 1 from public.equipos where id=e.id for share;
    perform 1 from public.equipos_ivmet where equipo_id=e.id for share;
    perform 1 from public.equipos_cliente where equipo_id=e.id for share;
    perform 1 from public.areas where id=(select area_id from public.equipos_ivmet where equipo_id=e.id) for share;
    data:=private.equipment_update_snapshot(e.id);
    perform private.admin_assert(data is not null,'EQUIPMENT_VALIDATION_REQUIRED');
    perform private.admin_assert(jsonb_typeof(payload->'consent')='boolean' and (payload->>'consent')::boolean
      and payload->>'consentVersion'='equipment-sharing-v1','EXPLICIT_CONSENT_REQUIRED');
    perform private.admin_assert(payload->>'hash'=encode(sha256(convert_to(data::text,'UTF8')),'hex'),'SHARE_PREVIEW_CHANGED');
    insert into public.actualizaciones_compartidas(equipo_id,cliente_id,planta_id,autorizado_por,snapshot,snapshot_hash,mensaje)
      values(e.id,cid,e.planta_id,auth.uid(),data,payload->>'hash',btrim(payload->>'message')) returning id into target;
    result:=jsonb_build_object('id',target);
  elsif action='update.withdraw' then
    perform private.admin_assert(shared.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert(length(btrim(payload->>'reason')) between 1 and 2000,'REASON_REQUIRED');
    update public.actualizaciones_compartidas set visibilidad='WITHDRAWN',retirado_at=coalesce(retirado_at,now()) where id=target;
    result:=jsonb_build_object('id',target);
  else raise exception 'UNKNOWN_CUSTOMER_ACTION'; end if;
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(auth.uid(),cid,'customer_configuration',coalesce(target,e.id)::text,action,
      jsonb_build_object('result',result,'reason',payload->>'reason'));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,'customer.'||action,actor_value,digest,result);
  return result;
end; $$;

-- Una entrega retirada conserva el recibo, no el contenido visible al receptor.
create function public.ivmet_equipment_update_delivery(target_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(a)||jsonb_build_object('snapshot',case when a.visibilidad='SHARED' then a.snapshot else null end,
    'row_version',a.row_version::text) from public.actualizaciones_compartidas a where a.id=target_id;
$$;
create function private.capture_equipment_update() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into private.sync_outbox(aggregate_type,aggregate_key,operation,payload)
    values('public.actualizaciones_compartidas',jsonb_build_object('id',new.id),case when tg_op='INSERT' then 'I' else 'U' end,
      public.ivmet_equipment_update_delivery(new.id));
  return new;
end; $$;
create trigger actualizaciones_outbox after insert or update on public.actualizaciones_compartidas
for each row execute function private.capture_equipment_update();

create function private.authorized_export(aggregate_name text,target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select case when aggregate_name='public.casos_compartidos' then private.case_export(target)
    when aggregate_name='public.actualizaciones_compartidas' then public.ivmet_equipment_update_delivery(target) else null end;
$$;
do $$ declare definition text;
begin
  definition:=pg_get_functiondef('public.claim_ivmet_sync_outbox(text,integer)'::regprocedure);
  perform private.admin_assert(position('private.case_export((c.aggregate_key' in definition)>0,'OUTBOX_CONTRACT_MISMATCH');
  definition:=replace(definition,'c.aggregate_type=''public.casos_compartidos''',
    'c.aggregate_type in (''public.casos_compartidos'',''public.actualizaciones_compartidas'')');
  definition:=replace(definition,'private.case_export((c.aggregate_key','private.authorized_export(c.aggregate_type,(c.aggregate_key');
  execute definition;
end $$;

-- Conservamos las interfaces móviles y sus controles anteriores.
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_customer;
alter function public.mobile_read_before_customer(text,jsonb) set schema private;
create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; ec public.equipos_cliente%rowtype; e public.equipos%rowtype;
begin
  result:=private.mobile_read_before_customer(section,filters);
  if section='equipment' then
    e:=private.customer_equipment((filters->>'equipmentId')::uuid);
    select * into ec from public.equipos_cliente where equipo_id=e.id;
    result:=jsonb_set(result,'{equipment}',result->'equipment'||coalesce(ec.datos,'{}'));
    result:=result||jsonb_build_object('customerValidated',ec.equipo_id is not null and ec.catalog_hash=e.source_hash);
  elsif section='instruments' then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(r||jsonb_build_object('marca',coalesce(overlay.datos->>'marca',r->>'marca'),
      'modelo',coalesce(overlay.datos->>'modelo',r->>'modelo')) order by ord)
      from jsonb_array_elements(result->'items') with ordinality item(r,ord)
      left join public.equipos_cliente overlay on overlay.equipo_id=(r->>'id')::uuid),'[]'));
  end if;
  return result;
end; $$;

-- RimMET no define ni consulta la configuración privada del cliente.
alter function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) rename to mobile_save_before_validation;
alter function public.mobile_save_before_validation(uuid,uuid,uuid,bigint,jsonb,uuid) set schema private;
create function public.ivmet_mobile_save_draft(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require();
begin
  if not exists(select 1 from public.verificacion_borradores where request_uuid=request_id) then
    perform private.admin_assert(exists(select 1 from public.equipos_cliente ec join public.equipos e on e.id=ec.equipo_id
      where e.id=equipment_id and e.cliente_id=cid and private.can_access_plant(e.planta_id) and ec.catalog_hash=e.source_hash),
      'EQUIPMENT_VALIDATION_REQUIRED');
  end if;
  return private.mobile_save_before_validation(request_id,equipment_id,version_id,expected_version,content,save_id);
end; $$;
revoke all on function private.mobile_save_before_validation(uuid,uuid,uuid,bigint,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) from public,anon,service_role;
grant execute on function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) to authenticated;

alter function public.ivmet_admin_read(text,uuid,jsonb) rename to admin_read_before_customer;
alter function public.admin_read_before_customer(text,uuid,jsonb) set schema private;
create function public.ivmet_admin_read(section text,client_id uuid default null,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.admin_read_before_customer(section,client_id,filters);
  if section='client' then
    return (result-array['areas','patterns','metrologyPlans'])||jsonb_build_object('areas','[]'::jsonb,'patterns','[]'::jsonb,'metrologyPlans','[]'::jsonb,'customerManaged',true);
  elsif section='equipment' then
    return jsonb_set(result,'{items}',coalesce((select jsonb_agg(r-array['area_id','plan_version_id']) from jsonb_array_elements(result->'items') r),'[]'));
  end if;
  return result;
end; $$;

create or replace function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e public.equipos%rowtype; current_version bigint; saved private.admin_requests%rowtype; digest text; result jsonb;
begin
  perform private.staff_require(actor,case when action in ('scope.request','scope.extend','scope.retry') then 'integration' else 'commercial' end);
  if action in ('area.save','pattern.save','certificate.create','certificate.annul') then raise exception 'CUSTOMER_MANAGED_CONFIGURATION'; end if;
  if action<>'equipment.configure' then return private.ivmet_admin_mutate_before_permissions(actor,action,payload,request_id); end if;
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload->'enabled')='boolean','INVALID_REQUEST');
  perform private.admin_assert(nullif(payload->>'areaId','') is null and nullif(payload->>'planVersionId','') is null,'CUSTOMER_MANAGED_CONFIGURATION');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r where r.request_id=ivmet_admin_mutate.request_id and r.action=ivmet_admin_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT'); return saved.result;
  end if;
  select * into e from public.equipos where id=(payload->>'id')::uuid and cliente_id=(payload->>'clientId')::uuid for update;
  perform private.admin_assert(found,'EQUIPMENT_NOT_FOUND');
  select row_version into current_version from public.equipos_ivmet where equipo_id=e.id for update;
  perform private.admin_assert(coalesce(current_version,0)=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
  perform private.admin_assert(not (payload->>'enabled')::boolean or (e.activo and e.estado_catalogo='READY'),'EQUIPMENT_REQUIRES_REVIEW');
  insert into public.equipos_ivmet(equipo_id,habilitado,estado_configuracion)
    values(e.id,(payload->>'enabled')::boolean,case when (payload->>'enabled')::boolean then 'READY' else 'SUSPENDED' end)
    on conflict(equipo_id) do update set habilitado=excluded.habilitado,estado_configuracion=excluded.estado_configuracion;
  result:=jsonb_build_object('id',e.id);
  insert into private.admin_requests(request_id,action,actor,payload_hash,result) values(request_id,action,actor,digest,result);
  insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion) values(actor,e.cliente_id,'equipment',e.id::text,action);
  return result;
end; $$;

alter function public.ivmet_ops_read(text,text,jsonb) rename to ops_read_before_customer;
alter function public.ops_read_before_customer(text,text,jsonb) set schema private;
create function public.ivmet_ops_read(actor text,section text,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; pg int:=greatest(1,coalesce((filters->>'page')::int,1)); sz int:=least(100,greatest(1,coalesce((filters->>'pageSize')::int,20)));
begin
  if section in ('metrology','metrology-catalog') then raise exception 'CUSTOMER_MANAGED_CONFIGURATION'; end if;
  if section='equipment-updates' then
    perform private.staff_require(actor,'support');
    with matches as(select a.* from public.actualizaciones_compartidas a where a.visibilidad='SHARED'
      and (nullif(filters->>'clientId','') is null or a.cliente_id=(filters->>'clientId')::uuid)
      and (nullif(filters->>'search','') is null or a.snapshot->>'code' ilike '%'||left(filters->>'search',100)||'%')),
    rows as(select * from matches order by autorizado_at desc,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('total',(select count(*) from matches),'page',pg,'pageSize',sz,'items',coalesce((select jsonb_agg(
      to_jsonb(r)||jsonb_build_object('row_version',r.row_version::text) order by autorizado_at desc,id) from rows r),'[]')) into result;
    return result;
  end if;
  result:=private.ops_read_before_customer(actor,section,filters);
  if section='session' then
    result:=jsonb_set(result,'{capabilities}',coalesce((select jsonb_agg(c) from jsonb_array_elements(result->'capabilities') c where c<>'"metrology"'::jsonb),'[]'));
  elsif section='readiness' then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(r-array['standards','plans']) from jsonb_array_elements(result->'items') r),'[]'));
  elsif section='privacy' then result:=result||jsonb_build_object('customerConfigurationExport',false,'consentedEquipmentUpdates',true);
  end if;
  return result;
end; $$;

alter function public.ivmet_ops_mutate(text,text,jsonb,uuid) rename to ops_mutate_before_customer;
alter function public.ops_mutate_before_customer(text,text,jsonb,uuid) set schema private;
do $$ begin
  execute replace(pg_get_functiondef('private.ops_mutate_before_customer(text,text,jsonb,uuid)'::regprocedure),'ivmet_ops_mutate.','ops_mutate_before_customer.');
end $$;
create function public.ivmet_ops_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.actualizaciones_compartidas%rowtype; digest text; saved private.admin_requests%rowtype; result jsonb;
begin
  if action like 'metrology.%' then raise exception 'CUSTOMER_MANAGED_CONFIGURATION'; end if;
  if action<>'equipment-update.review' then return private.ops_mutate_before_customer(actor,action,payload,request_id); end if;
  perform private.staff_require(actor,'support');
  perform private.admin_assert(request_id is not null and length(btrim(payload->>'comment')) between 1 and 2000,'COMMENT_REQUIRED');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into a from public.actualizaciones_compartidas where id=(payload->>'id')::uuid and visibilidad='SHARED' for update;
  perform private.admin_assert(found,'UPDATE_NOT_ACCESSIBLE');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  select * into saved from private.admin_requests r where r.request_id=ivmet_ops_mutate.request_id and r.action=ivmet_ops_mutate.action;
  if found then perform private.admin_assert(saved.actor=actor and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT'); return saved.result; end if;
  perform private.admin_assert(a.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
  update public.actualizaciones_compartidas set estado='REVIEWED',comentario=btrim(payload->>'comment'),revisado_por=actor where id=a.id;
  result:=jsonb_build_object('id',a.id);
  insert into private.admin_requests(request_id,action,actor,payload_hash,result) values(request_id,action,actor,digest,result);
  insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion) values(actor,a.cliente_id,'equipment_update',a.id::text,action);
  return result;
end; $$;

revoke all on function private.area_key(text),private.customer_equipment(uuid),private.customer_pattern(uuid,boolean),
  private.equipment_update_snapshot(uuid),private.customer_plan_save(jsonb),private.protect_equipment_consent(),
  private.capture_equipment_update(),private.authorized_export(text,uuid),private.mobile_read_before_customer(text,jsonb),
  private.admin_read_before_customer(text,uuid,jsonb),private.ops_read_before_customer(text,text,jsonb),
  private.ops_mutate_before_customer(text,text,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_customer_read(text,jsonb),public.ivmet_customer_mutate(text,jsonb,uuid),
  public.ivmet_mobile_read(text,jsonb) from public,anon,service_role;
grant execute on function public.ivmet_customer_read(text,jsonb),public.ivmet_customer_mutate(text,jsonb,uuid),public.ivmet_mobile_read(text,jsonb) to authenticated;
revoke all on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_ops_read(text,text,jsonb),public.ivmet_ops_mutate(text,text,jsonb,uuid),
  public.ivmet_equipment_update_delivery(uuid) from public,anon,authenticated;
grant execute on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_ops_read(text,text,jsonb),public.ivmet_ops_mutate(text,text,jsonb,uuid),
  public.ivmet_equipment_update_delivery(uuid) to service_role;
create or replace function public.ivmet_worker_contract() returns integer
language sql stable security definer set search_path='' as $$ select 4 $$;
commit;

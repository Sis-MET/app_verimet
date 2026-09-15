begin;

-- Balanzas que la empresa compra o incorpora sin que Métrica tenga acceso. Viven
-- en public.equipos para reutilizar áreas, configuración guiada, borradores y
-- evidencia, pero no pertenecen al catálogo de DataMET: no tienen código de
-- Métrica, son privadas del cliente y solo el jefe de calidad las registra.
alter table public.equipos
  add column origen varchar(10) not null default 'DATAMET',
  add column registrado_por uuid references public.perfiles(id),
  add column registrado_at timestamptz;
alter table public.equipos
  alter column legacy_equipo_id drop not null,
  alter column cod_metrica drop not null;
alter table public.equipos add constraint equipos_origen_ck check (
  (origen='DATAMET' and legacy_equipo_id is not null and cod_metrica is not null
    and registrado_por is null and registrado_at is null)
  or (origen='CLIENTE' and legacy_equipo_id is null and cod_metrica is null
    and registrado_por is not null and registrado_at is not null
    and length(btrim(coalesce(cod_interno,''))) between 1 and 50)
);

-- El espejo SQL Server exige código de Métrica y enlaza expedientes y fichas
-- compartidas con mirror.equipos. Una balanza registrada no existe allí: sus
-- eventos quedan retenidos en Supabase en vez de morir en el worker y detener
-- toda la cola. Lo que la empresa comparte llega a Métrica por RimMET.
create function private.registered_equipment_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
  target:=case new.aggregate_type
    when 'public.equipos' then nullif(new.payload->>'id','')::uuid
    when 'public.equipo_rangos' then nullif(new.payload->>'equipo_id','')::uuid
    when 'public.actualizaciones_compartidas' then nullif(new.payload->>'equipo_id','')::uuid
    when 'public.casos_compartidos' then nullif(new.payload->>'equipo_id','')::uuid
  end;
  if target is not null and exists(select 1 from public.equipos e where e.id=target and e.origen='CLIENTE') then
    new.privacy_blocked:=true;
  end if;
  return new;
end; $$;
create trigger sync_outbox_registered_equipment before insert on private.sync_outbox
for each row execute function private.registered_equipment_event();

-- Valida y normaliza el alta o la corrección. Las cargas viajan como cadenas
-- exactas; el resultado es la forma canónica que se guarda y se compara.
create function private.registration_payload(payload jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare
  data jsonb:=payload->'data'; normalized jsonb:='{}'; field text; cleaned text; item jsonb; ranges jsonb:='[]';
  limits jsonb:='{"cod_interno":50,"marca":50,"modelo":50,"serie":70,"ubicacion":150}';
  capacity numeric; division numeric; verification numeric; previous numeric:=0; seq integer:=0;
  exact text:='^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$';
begin
  perform private.admin_assert(jsonb_typeof(data)='object'
    and (data-array['cod_interno','marca','modelo','serie','ubicacion','tipo','clase','unidad'])='{}'::jsonb
    and (select bool_and(jsonb_typeof(data->k)='string')
      from unnest(array['cod_interno','marca','modelo','serie','ubicacion','tipo','clase','unidad']) k),'INVALID_EQUIPMENT_DATA');
  for field in select jsonb_object_keys(limits) loop
    cleaned:=btrim(regexp_replace(data->>field,'\s+',' ','g'));
    perform private.admin_assert(length(cleaned)<=(limits->>field)::integer,'INVALID_EQUIPMENT_DATA');
    normalized:=normalized||jsonb_build_object(field,cleaned);
  end loop;
  perform private.admin_assert(normalized->>'cod_interno'<>'','EQUIPMENT_CODE_REQUIRED');
  perform private.admin_assert(data->>'tipo' in ('PLATFORM','TRUCK') and data->>'clase' in ('','I','II','III','IIII')
    and data->>'unidad' in ('kg','g','t','mg'),'INVALID_EQUIPMENT_DATA');
  -- La configuración guiada elige el perfil camionero por este texto.
  normalized:=normalized||jsonb_build_object('tipo_balanza',
    case data->>'tipo' when 'TRUCK' then 'Báscula camionera' else 'Balanza o plataforma' end,
    'clase',data->>'clase','unidad',data->>'unidad');
  perform private.admin_assert(jsonb_typeof(payload->'ranges')='array'
    and jsonb_array_length(payload->'ranges') between 1 and 3,'INVALID_EQUIPMENT_RANGES');
  for item in select r.item from jsonb_array_elements(payload->'ranges') r(item) loop
    seq:=seq+1;
    perform private.admin_assert(jsonb_typeof(item)='object' and (item-array['capacity','division','interval'])='{}'::jsonb
      and jsonb_typeof(item->'capacity')='string' and jsonb_typeof(item->'division')='string'
      and jsonb_typeof(item->'interval')='string' and item->>'capacity' ~ exact and item->>'division' ~ exact
      and (item->>'interval'='' or item->>'interval' ~ exact),'EXACT_DECIMAL_REQUIRED');
    capacity:=trim_scale((item->>'capacity')::numeric);
    division:=trim_scale((item->>'division')::numeric);
    verification:=trim_scale(nullif(item->>'interval','')::numeric);
    -- Cada rango supera al anterior; d>0, d<Max y, si se declara, d<=e<Max.
    perform private.admin_assert(capacity>previous and division>0 and division<capacity
      and (verification is null or (verification>=division and verification<capacity)),'INVALID_EQUIPMENT_RANGES');
    previous:=capacity;
    ranges:=ranges||jsonb_build_array(jsonb_build_object('number',seq,'capacity',capacity::text,
      'division',division::text,'interval',coalesce(verification::text,''),'decimals',scale(division)));
  end loop;
  return normalized||jsonb_build_object('ranges',ranges);
end; $$;

create function private.registration_hash(data jsonb) returns text
language sql immutable set search_path='' as $$
  select encode(sha256(convert_to(data::text,'UTF8')),'hex');
$$;

create function private.registration_customer_data(data jsonb) returns jsonb
language sql immutable set search_path='' as $$
  select jsonb_build_object('ubicacion',data->>'ubicacion','cod_interno',data->>'cod_interno',
    'marca',data->>'marca','modelo',data->>'modelo','serie',data->>'serie');
$$;

-- La misma forma canónica, reconstruida desde lo guardado.
create function private.registration_data(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('cod_interno',coalesce(e.cod_interno,''),'marca',coalesce(e.marca,''),
    'modelo',coalesce(e.modelo,''),'serie',coalesce(e.serie,''),'ubicacion',coalesce(e.ubicacion,''),
    'tipo_balanza',e.tipo_balanza,'clase',coalesce(e.clase,''),'unidad',e.unidad,
    'ranges',coalesce((select jsonb_agg(jsonb_build_object('number',r.numero_rango,
      'capacity',trim_scale(r.capacidad_max)::text,'division',trim_scale(r.division_escala)::text,
      'interval',coalesce(trim_scale(r.intervalo_verificacion)::text,''),'decimals',r.cantidad_decimales)
      order by r.numero_rango) from public.equipo_rangos r where r.equipo_id=e.id),'[]'))
  from public.equipos e where e.id=target;
$$;

create function private.registered_equipment(target uuid) returns public.equipos
language plpgsql stable security definer set search_path='' as $$
declare e public.equipos%rowtype;
begin
  e:=private.customer_equipment(target);
  perform private.admin_assert(e.origen='CLIENTE','REGISTERED_EQUIPMENT_REQUIRED');
  return e;
end; $$;

-- Los datos técnicos sostienen la evidencia: con capturas en curso o
-- verificaciones finalizadas ya no se corrigen.
create function private.registered_equipment_in_use(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.verificaciones v where v.equipo_id=target)
    or exists(select 1 from public.verificacion_borradores d where d.equipo_id=target
      and d.estado in ('DRAFT','FINALIZING') and d.expires_at>now());
$$;

-- Solo compara balanzas que la empresa ve. Una balanza del catálogo que no está
-- habilitada en IvMET no bloquea el alta ni se revela.
create function private.registration_conflict(cid uuid,plant uuid,data jsonb,excluded uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.admin_assert(not exists(select 1 from public.equipos e
      join public.equipos_ivmet i on i.equipo_id=e.id left join public.equipos_cliente ec on ec.equipo_id=e.id
    where e.planta_id=plant and e.activo and e.estado_catalogo='READY' and i.habilitado and e.id is distinct from excluded
      and private.area_key(coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),e.cod_interno,''))=private.area_key(data->>'cod_interno')),
    'EQUIPMENT_CODE_EXISTS');
  if data->>'serie'<>'' then
    perform private.admin_assert(not exists(select 1 from public.equipos e
        join public.equipos_ivmet i on i.equipo_id=e.id left join public.equipos_cliente ec on ec.equipo_id=e.id
      where e.cliente_id=cid and e.activo and e.estado_catalogo='READY' and i.habilitado and e.id is distinct from excluded
        and private.area_key(coalesce(nullif(btrim(ec.datos->>'serie'),''),e.serie,''))=private.area_key(data->>'serie')
        and private.area_key(coalesce(nullif(btrim(ec.datos->>'marca'),''),e.marca,''))=private.area_key(data->>'marca')),
      'EQUIPMENT_SERIAL_EXISTS');
  end if;
end; $$;

-- Igual que al validar una ficha: un área existente o un nombre nuevo que se
-- crea si no hay otra equivalente en la planta. Aquí el área es obligatoria.
create function private.registration_area(cid uuid,plant uuid,payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare area_value uuid:=nullif(payload->>'areaId','')::uuid; a public.areas%rowtype;
  area_name text:=btrim(regexp_replace(coalesce(payload->>'areaName',''),'\s+',' ','g'));
begin
  if area_name<>'' then
    perform private.admin_assert(area_value is null and length(area_name)<=150,'INVALID_AREA');
    perform pg_advisory_xact_lock(hashtextextended(plant::text,2));
    select * into a from public.areas where planta_id=plant and private.area_key(nombre)=private.area_key(area_name)
      order by created_at,id limit 1 for update;
    if found then
      perform private.admin_assert(a.activa,'AREA_INACTIVE'); area_value:=a.id;
    else
      insert into public.areas(cliente_id,planta_id,nombre,created_by)
        values(cid,plant,area_name,auth.uid()) returning id into area_value;
    end if;
  end if;
  perform private.admin_assert(area_value is not null,'AREA_REQUIRED');
  perform 1 from public.areas where id=area_value and planta_id=plant and cliente_id=cid and activa for share;
  perform private.admin_assert(found,'AREA_SCOPE_INVALID');
  return area_value;
end; $$;

create function private.registration_ranges(target uuid,data jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item jsonb;
begin
  delete from public.equipo_rangos where equipo_id=target and numero_rango>jsonb_array_length(data->'ranges');
  for item in select r.item from jsonb_array_elements(data->'ranges') r(item) loop
    insert into public.equipo_rangos as current_range(equipo_id,numero_rango,unidad,capacidad_max,division_escala,
      intervalo_verificacion,cantidad_decimales,source_hash)
    values(target,(item->>'number')::smallint,data->>'unidad',(item->>'capacity')::numeric,(item->>'division')::numeric,
      nullif(item->>'interval','')::numeric,(item->>'decimals')::smallint,
      private.registration_hash(item||jsonb_build_object('unit',data->>'unidad')))
    on conflict(equipo_id,numero_rango) do update set unidad=excluded.unidad,capacidad_max=excluded.capacidad_max,
      division_escala=excluded.division_escala,intervalo_verificacion=excluded.intervalo_verificacion,
      cantidad_decimales=excluded.cantidad_decimales,source_hash=excluded.source_hash
    where current_range.source_hash is distinct from excluded.source_hash;
  end loop;
end; $$;

-- Lo único que la empresa autoriza a entregar: identificación, área y datos
-- técnicos. Conserva las claves que RimMET ya muestra para una actualización.
create function private.registration_snapshot(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('kind','registration','equipmentId',e.id,'code',e.cod_interno,
    'clientCode',c.codigo,'plantCode',p.legacy_codigo_planta,'plantName',p.nombre,'catalog','{}'::jsonb,
    'customer',private.registration_customer_data(x.data),'area',a.nombre,
    'technical',jsonb_build_object('type',e.tipo_balanza,'class',nullif(e.clase,''),'unit',e.unidad,'ranges',x.data->'ranges'),
    'registeredAt',e.registrado_at,'version',e.source_version::text)
  from public.equipos e cross join lateral (select private.registration_data(e.id) as data) x
    join public.clientes c on c.id=e.cliente_id join public.plantas p on p.id=e.planta_id
    join public.equipos_ivmet i on i.equipo_id=e.id left join public.areas a on a.id=i.area_id
  where e.id=target and e.origen='CLIENTE';
$$;

-- El mismo contenido no vuelve a ofrecerse mientras siga autorizado.
create function private.registration_share_pending(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select not exists(select 1 from public.actualizaciones_compartidas a
    where a.equipo_id=target and a.visibilidad='SHARED' and a.consentimiento_version='equipment-registration-v1'
      and a.snapshot-'version'=private.registration_snapshot(target)-'version');
$$;

-- La configuración guiada nombraba el plan con el código de Métrica.
do $migration$
declare definition text;
begin
  select pg_get_functiondef('private.customer_configure_checks_before_load_free(uuid,jsonb,uuid)'::regprocedure) into definition;
  perform private.admin_assert(position('''Configuración ''||equipment.cod_metrica' in definition)>0,'CHECKS_CONTRACT_MISMATCH');
  execute replace(definition,'''Configuración ''||equipment.cod_metrica',
    '''Configuración ''||coalesce(equipment.cod_metrica,equipment.cod_interno)');
end;
$migration$;

-- Las funciones públicas se renombran y envuelven como en entregas anteriores.
-- PL/pgSQL no actualiza los parámetros calificados con el nombre anterior, así
-- que cada cuerpo se recompila con su nombre nuevo antes de envolverlo.
alter function public.ivmet_customer_mutate(text,jsonb,uuid) rename to customer_mutate_before_registration;
alter function public.customer_mutate_before_registration(text,jsonb,uuid) set schema private;
alter function public.ivmet_customer_read(text,jsonb) rename to customer_read_before_registration;
alter function public.customer_read_before_registration(text,jsonb) set schema private;
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_registration;
alter function public.mobile_read_before_registration(text,jsonb) set schema private;
alter function public.ivmet_admin_read(text,uuid,jsonb) rename to admin_read_before_registration;
alter function public.admin_read_before_registration(text,uuid,jsonb) set schema private;
alter function public.ivmet_admin_mutate(text,text,jsonb,uuid) rename to admin_mutate_before_registration;
alter function public.admin_mutate_before_registration(text,text,jsonb,uuid) set schema private;
alter function public.ivmet_ops_read(text,text,jsonb) rename to ops_read_before_registration;
alter function public.ops_read_before_registration(text,text,jsonb) set schema private;
do $migration$
declare item record;
begin
  for item in select * from (values
    ('private.customer_mutate_before_registration(text,jsonb,uuid)','ivmet_customer_mutate.','customer_mutate_before_registration.'),
    ('private.customer_read_before_registration(text,jsonb)','ivmet_customer_read.','customer_read_before_registration.'),
    ('private.mobile_read_before_registration(text,jsonb)','ivmet_mobile_read.','mobile_read_before_registration.'),
    ('private.admin_read_before_registration(text,uuid,jsonb)','ivmet_admin_read.','admin_read_before_registration.'),
    ('private.admin_mutate_before_registration(text,text,jsonb,uuid)','ivmet_admin_mutate.','admin_mutate_before_registration.'),
    ('private.ops_read_before_registration(text,text,jsonb)','ivmet_ops_read.','ops_read_before_registration.')
  ) v(signature,previous_name,next_name) loop
    execute replace(pg_get_functiondef(item.signature::regprocedure),item.previous_name,item.next_name);
  end loop;
end;
$migration$;

create function public.ivmet_customer_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; actor_value text; digest text; saved private.admin_requests%rowtype; result jsonb;
  e public.equipos%rowtype; data jsonb; plant uuid; area_value uuid; target uuid; technical_changed boolean; snapshot jsonb;
begin
  if action not in ('equipment.register','equipment.edit','equipment.retire','registration.share') then
    -- Una balanza registrada no se valida contra un catálogo que no existe ni se
    -- comparte como corrección de DataMET.
    if action in ('equipment.validate','update.share') and exists(select 1 from public.equipos
        where id=nullif(payload->>'id','')::uuid and origen='CLIENTE') then
      raise exception using errcode='P0001',message='REGISTERED_EQUIPMENT_USES_EDIT';
    end if;
    return private.customer_mutate_before_registration(action,payload,request_id);
  end if;
  cid:=private.mobile_require();
  actor_value:='MOBILE:'||auth.uid()::text;
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object'
    and octet_length(payload::text)<=65536,'INVALID_REQUEST');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  -- Revalidar rol y alcance antes incluso de devolver un recibo idempotente.
  if action='equipment.register' then
    plant:=nullif(payload->>'plantId','')::uuid;
    perform private.admin_assert(plant is not null and private.can_access_plant(plant) and exists(
      select 1 from public.plantas p where p.id=plant and p.cliente_id=cid and p.activo),'PLANT_SCOPE_INVALID');
  elsif action='equipment.retire' then
    -- Tras la baja la balanza ya no es accesible; el reintento debe recuperar su recibo.
    select * into e from public.equipos where id=nullif(payload->>'id','')::uuid and cliente_id=cid
      and origen='CLIENTE' and private.can_access_plant(planta_id);
    perform private.admin_assert(found,'EQUIPMENT_NOT_ACCESSIBLE');
  else
    e:=private.registered_equipment(nullif(payload->>'id','')::uuid);
  end if;
  select * into saved from private.admin_requests r
    where r.request_id=ivmet_customer_mutate.request_id and r.action='customer.'||ivmet_customer_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor_value and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;

  if action='equipment.register' then
    data:=private.registration_payload(payload);
    area_value:=private.registration_area(cid,plant,payload);
    perform pg_advisory_xact_lock(hashtextextended(plant::text,4));
    perform private.registration_conflict(cid,plant,data,null);
    insert into public.equipos(cliente_id,planta_id,origen,cod_interno,instrumento,tipo_balanza,marca,modelo,serie,
      unidad,ubicacion,clase,estado_catalogo,activo,source_hash,registrado_por,registrado_at)
    values(cid,plant,'CLIENTE',data->>'cod_interno','Balanza',data->>'tipo_balanza',nullif(data->>'marca',''),
      nullif(data->>'modelo',''),nullif(data->>'serie',''),data->>'unidad',nullif(data->>'ubicacion',''),
      nullif(data->>'clase',''),'READY',true,private.registration_hash(data),auth.uid(),now())
    returning * into e;
    perform private.registration_ranges(e.id,data);
    insert into public.equipos_ivmet(equipo_id,area_id,habilitado,estado_configuracion,created_by)
      values(e.id,area_value,true,'READY',auth.uid());
    -- La empresa es la fuente: la ficha nace validada.
    insert into public.equipos_cliente(equipo_id,cliente_id,planta_id,datos,catalog_hash,validado_por)
      values(e.id,cid,plant,private.registration_customer_data(data),e.source_hash,auth.uid());
    result:=jsonb_build_object('id',e.id);
  elsif action='equipment.edit' then
    perform 1 from public.equipos where id=e.id for update;
    perform 1 from public.equipos_ivmet where equipo_id=e.id for update;
    e:=private.registered_equipment(e.id);
    perform private.admin_assert(e.source_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    data:=private.registration_payload(payload);
    area_value:=private.registration_area(cid,e.planta_id,payload);
    perform pg_advisory_xact_lock(hashtextextended(e.planta_id::text,4));
    perform private.registration_conflict(cid,e.planta_id,data,e.id);
    technical_changed:=(data-array['cod_interno','marca','modelo','serie','ubicacion'])
      is distinct from (private.registration_data(e.id)-array['cod_interno','marca','modelo','serie','ubicacion']);
    perform private.admin_assert(not technical_changed or not private.registered_equipment_in_use(e.id),'EQUIPMENT_IN_USE');
    update public.equipos set cod_interno=data->>'cod_interno',tipo_balanza=data->>'tipo_balanza',
      marca=nullif(data->>'marca',''),modelo=nullif(data->>'modelo',''),serie=nullif(data->>'serie',''),
      unidad=data->>'unidad',ubicacion=nullif(data->>'ubicacion',''),clase=nullif(data->>'clase',''),
      source_hash=private.registration_hash(data),source_version=source_version+1
    where id=e.id returning * into e;
    if technical_changed then
      -- Los puntos de referencia salían de la capacidad anterior: se reconfigura.
      perform private.registration_ranges(e.id,data);
      update public.equipo_planes set vigente_hasta=clock_timestamp() where equipo_id=e.id and vigente_hasta is null;
    end if;
    update public.equipos_ivmet set area_id=area_value where equipo_id=e.id;
    update public.equipos_cliente set datos=private.registration_customer_data(data),catalog_hash=e.source_hash,
      validado_por=auth.uid(),validado_at=now() where equipo_id=e.id;
    result:=jsonb_build_object('id',e.id,'version',e.source_version::text,'configurationReset',technical_changed);
  elsif action='equipment.retire' then
    select * into e from public.equipos where id=e.id for update;
    perform private.admin_assert(e.activo,'EQUIPMENT_NOT_ACCESSIBLE');
    perform private.admin_assert(e.source_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert(length(btrim(coalesce(payload->>'reason',''))) between 1 and 2000,'REASON_REQUIRED');
    perform private.admin_assert(not exists(select 1 from public.verificacion_borradores d where d.equipo_id=e.id
      and d.estado in ('DRAFT','FINALIZING') and d.expires_at>now()),'EQUIPMENT_HAS_OPEN_DRAFTS');
    update public.equipos set activo=false,source_version=source_version+1 where id=e.id;
    update public.equipos_ivmet set habilitado=false,estado_configuracion='SUSPENDED' where equipo_id=e.id;
    update public.equipo_planes set vigente_hasta=clock_timestamp() where equipo_id=e.id and vigente_hasta is null;
    result:=jsonb_build_object('id',e.id);
  else
    perform 1 from public.equipos where id=e.id for share;
    perform 1 from public.equipos_ivmet where equipo_id=e.id for share;
    perform 1 from public.areas where id=(select area_id from public.equipos_ivmet where equipo_id=e.id) for share;
    snapshot:=private.registration_snapshot(e.id);
    perform private.admin_assert(jsonb_typeof(payload->'consent')='boolean' and (payload->>'consent')::boolean
      and payload->>'consentVersion'='equipment-registration-v1','EXPLICIT_CONSENT_REQUIRED');
    perform private.admin_assert(payload->>'hash'=encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'),'SHARE_PREVIEW_CHANGED');
    perform private.admin_assert(private.registration_share_pending(e.id),'REGISTRATION_ALREADY_SHARED');
    perform private.admin_assert(length(btrim(coalesce(payload->>'message',''))) between 1 and 2000,'MESSAGE_REQUIRED');
    insert into public.actualizaciones_compartidas(equipo_id,cliente_id,planta_id,autorizado_por,consentimiento_version,
      snapshot,snapshot_hash,mensaje)
    values(e.id,cid,e.planta_id,auth.uid(),'equipment-registration-v1',snapshot,payload->>'hash',btrim(payload->>'message'))
    returning id into target;
    result:=jsonb_build_object('id',target);
  end if;
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(auth.uid(),cid,'customer_configuration',coalesce(target,e.id)::text,action,
      jsonb_build_object('result',result,'reason',payload->>'reason'));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,'customer.'||action,actor_value,digest,result);
  return result;
end; $$;

create function public.ivmet_customer_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare e public.equipos%rowtype; snapshot jsonb; data jsonb;
begin
  if section='registration' then
    perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
    e:=private.registered_equipment(nullif(filters->>'id','')::uuid);
    data:=private.registration_data(e.id);
    return jsonb_build_object('id',e.id,'plantId',e.planta_id,'version',e.source_version::text,
      'data',private.registration_customer_data(data)||jsonb_build_object(
        'tipo',case when e.tipo_balanza='Báscula camionera' then 'TRUCK' else 'PLATFORM' end,
        'clase',data->>'clase','unidad',data->>'unidad'),
      'ranges',coalesce((select jsonb_agg(jsonb_build_object('capacity',r.item->>'capacity','division',r.item->>'division',
        'interval',r.item->>'interval') order by r.ord) from jsonb_array_elements(data->'ranges') with ordinality r(item,ord)),'[]'),
      'areaId',(select i.area_id from public.equipos_ivmet i where i.equipo_id=e.id),
      'areas',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.nombre) order by a.nombre)
        from public.areas a where a.planta_id=e.planta_id and a.activa),'[]'),
      'inUse',private.registered_equipment_in_use(e.id));
  elsif section='registration-preview' then
    perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
    e:=private.registered_equipment(nullif(filters->>'id','')::uuid);
    perform private.admin_assert(private.registration_share_pending(e.id),'REGISTRATION_ALREADY_SHARED');
    snapshot:=private.registration_snapshot(e.id);
    return jsonb_build_object('snapshot',snapshot,'hash',encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'),
      'consentVersion','equipment-registration-v1',
      'notice','Métrica recibirá solo la identificación, el área y los datos técnicos de esta balanza, para conocerla y preparar futuras calibraciones. No se comparten pruebas, planes, patrones ni resultados. Retirar el acceso no elimina copias ya entregadas.');
  end if;
  return private.customer_read_before_registration(section,filters);
end; $$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; target uuid; registered boolean;
begin
  result:=private.mobile_read_before_registration(section,filters);
  if section in ('instruments','history','drafts') then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item||jsonb_build_object('origen',e.origen,
        'cod_interno',coalesce(nullif(btrim(item->>'cod_interno'),''),nullif(btrim(ec.datos->>'cod_interno'),''),e.cod_interno))
        order by x.ord)
      from jsonb_array_elements(result->'items') with ordinality x(item,ord)
        join public.equipos e on e.id=coalesce(item->>'equipo_id',item->>'id')::uuid
        left join public.equipos_cliente ec on ec.equipo_id=e.id),'[]'::jsonb));
  elsif section='equipment' then
    target:=(filters->>'equipmentId')::uuid;
    registered:=result->'equipment'->>'origen'='CLIENTE';
    result:=result||jsonb_build_object('registeredByCustomer',registered,
      'registrationInUse',registered and private.registered_equipment_in_use(target),
      'registrationSharePending',registered and private.registration_share_pending(target),
      'registrationShared',registered and exists(select 1 from public.actualizaciones_compartidas a
        where a.equipo_id=target and a.visibilidad='SHARED' and a.consentimiento_version='equipment-registration-v1'));
  end if;
  return result;
end; $$;

-- RimMET no ve el inventario privado que registra la empresa: ni en el listado
-- de balanzas ni en los conteos del directorio.
create function public.ivmet_admin_read(section text,client_id uuid default null,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
  page_number integer:=greatest(coalesce((filters->>'page')::integer,1),1);
  page_size integer:=least(greatest(coalesce((filters->>'pageSize')::integer,20),1),100);
  search_text text:='%'||coalesce(filters->>'search','')||'%';
  plant_filter uuid:=nullif(filters->>'plantId','')::uuid;
begin
  if section<>'equipment' then
    result:=private.admin_read_before_registration(section,client_id,filters);
    if section='overview' then
      result:=result||jsonb_build_object('equipment',(result->>'equipment')::bigint
        -(select count(*) from public.equipos where activo and origen='CLIENTE'));
    elsif section='clients' then
      result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item||jsonb_build_object('equipment',
          (item->>'equipment')::bigint-(select count(*) from public.equipos e
            where e.cliente_id=(item->>'id')::uuid and e.activo and e.origen='CLIENTE')) order by x.ord)
        from jsonb_array_elements(result->'items') with ordinality x(item,ord)),'[]'::jsonb));
    end if;
    return result;
  end if;
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform private.admin_assert(client_id is not null,'CLIENT_REQUIRED');
  with matching as (
    select e.*,ei.area_id,coalesce(ei.habilitado,false) as habilitado,coalesce(ei.estado_configuracion,'PENDING') as estado_configuracion,
      coalesce(ei.row_version,0)::text as config_version,
      (select ep.plan_version_id from public.equipo_planes ep where ep.equipo_id=e.id and ep.vigente_hasta is null) as plan_version_id
    from public.equipos e left join public.equipos_ivmet ei on ei.equipo_id=e.id
    where e.cliente_id=client_id and e.origen='DATAMET' and (plant_filter is null or e.planta_id=plant_filter)
      and (coalesce(filters->>'status','')='' or e.estado_catalogo=filters->>'status')
      and (e.cod_metrica ilike search_text or e.instrumento ilike search_text or e.marca ilike search_text
        or e.serie ilike search_text or e.cod_interno ilike search_text)
  ), page_rows as (select * from matching order by cod_metrica,id limit page_size offset (page_number-1)*page_size)
  select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,
    'items',coalesce((select jsonb_agg((to_jsonb(e)-array['area_id','plan_version_id'])||jsonb_build_object('ranges',
      coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.equipo_rangos',to_jsonb(r)) order by r.numero_rango)
        from public.equipo_rangos r where r.equipo_id=e.id),'[]')) order by e.cod_metrica) from page_rows e),'[]')) into result;
  return result;
end; $$;

create function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if action='equipment.configure' and exists(select 1 from public.equipos
      where id=nullif(payload->>'id','')::uuid and origen='CLIENTE') then
    raise exception using errcode='P0001',message='CUSTOMER_REGISTERED_EQUIPMENT';
  end if;
  return private.admin_mutate_before_registration(actor,action,payload,request_id);
end; $$;

-- Un expediente compartido puede ser de una balanza sin código de Métrica.
create function public.ivmet_ops_read(actor text,section text,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.ops_read_before_registration(actor,section,filters);
  if section='cases' then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item||jsonb_build_object('origen',e.origen,
        'cod_interno',e.cod_interno) order by x.ord)
      from jsonb_array_elements(result->'items') with ordinality x(item,ord)
        join public.equipos e on e.id=(item->>'equipo_id')::uuid),'[]'::jsonb));
  end if;
  return result;
end; $$;

revoke all on function private.registered_equipment_event(),private.registration_payload(jsonb),
  private.registration_hash(jsonb),private.registration_customer_data(jsonb),private.registration_data(uuid),
  private.registered_equipment(uuid),private.registered_equipment_in_use(uuid),
  private.registration_conflict(uuid,uuid,jsonb,uuid),private.registration_area(uuid,uuid,jsonb),
  private.registration_ranges(uuid,jsonb),private.registration_snapshot(uuid),private.registration_share_pending(uuid),
  private.customer_mutate_before_registration(text,jsonb,uuid),private.customer_read_before_registration(text,jsonb),
  private.mobile_read_before_registration(text,jsonb),private.admin_read_before_registration(text,uuid,jsonb),
  private.admin_mutate_before_registration(text,text,jsonb,uuid),private.ops_read_before_registration(text,text,jsonb)
from public,anon,authenticated,service_role;
revoke all on function public.ivmet_customer_mutate(text,jsonb,uuid),public.ivmet_customer_read(text,jsonb),
  public.ivmet_mobile_read(text,jsonb) from public,anon,service_role;
grant execute on function public.ivmet_customer_mutate(text,jsonb,uuid),public.ivmet_customer_read(text,jsonb),
  public.ivmet_mobile_read(text,jsonb) to authenticated;
revoke all on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid),
  public.ivmet_ops_read(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid),
  public.ivmet_ops_read(text,text,jsonb) to service_role;

commit;

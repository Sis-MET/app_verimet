begin;

-- El móvil escribe exclusivamente mediante RPC: nunca puede finalizar evidencia
-- alterando el estado de un borrador ni ampliar su vencimiento por REST.
revoke insert (request_uuid,cliente_id,planta_id,area_id,equipo_id,plan_version_id,
  usuario_id,estado,paso_actual,payload,expires_at),
  update (paso_actual,payload,estado,expires_at)
  on public.verificacion_borradores from authenticated;
alter table public.verificacion_borradores
  add column context_snapshot jsonb,
  add column last_save_uuid uuid,
  add column last_save_hash text check(last_save_hash is null or last_save_hash ~ '^[0-9a-f]{64}$');

create function private.mobile_require() returns uuid
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'authenticated' or auth.uid() is null
    or private.current_profile_role() not in ('cliente_operador','cliente_jefe_calidad')
    or private.current_profile_role() is null
    or not private.user_has_active_license(auth.uid()) then
    raise exception using errcode='42501',message='MOBILE_ACCESS_DENIED';
  end if;
  return private.current_cliente_id();
end; $$;

create function private.mobile_plan(version_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',v.id,'name',p.nombre,'version',v.version,'state',v.estado,
    'procedure',v.procedimiento_referencia,'finalizationEnabled',false,
    'blockReason','OFFICIAL_ENGINE_NOT_RELEASED','tests',coalesce((select jsonb_agg(
      jsonb_build_object('id',t.id,'type',t.tipo,'method',t.metodo_evaluacion,'unit',t.unidad,
        'frequencyDays',t.frecuencia_dias,'warningDays',t.aviso_dias,'metadata',t.metadata,
        'points',coalesce((select jsonb_agg(jsonb_build_object('id',pt.id,'code',pt.codigo,
          'label',pt.etiqueta,'group',pt.grupo,'order',pt.orden,'load',pt.carga_nominal::text,
          'tolerance',pt.tolerancia::text,'position',pt.posicion,'direction',pt.direccion,
          'metadata',pt.metadata) order by pt.orden) from public.plan_puntos pt where pt.plan_prueba_id=t.id),'[]'))
      order by t.tipo) from public.plan_pruebas t where t.plan_version_id=v.id),'[]'))
  from public.plan_versiones v join public.planes p on p.id=v.plan_id where v.id=version_id;
$$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; eid uuid:=nullif(filters->>'equipmentId','')::uuid;
  pid uuid:=nullif(filters->>'plantId','')::uuid; target uuid:=nullif(filters->>'id','')::uuid;
  page_no int:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
  page_size int:=greatest(1,least(coalesce((filters->>'pageSize')::int,25),100));
  result jsonb; selected_equipment public.equipos%rowtype; selected_draft public.verificacion_borradores%rowtype;
begin
  if auth.role() is distinct from 'authenticated' or auth.uid() is null then
    raise exception using errcode='42501',message='AUTH_REQUIRED';
  end if;
  if section='session' then
    return jsonb_build_object('contractVersion',1,'serverTime',now(),
      'user',(select jsonb_build_object('id',p.id,'username',p.usuario,'name',p.nombre,
        'role',p.rol,'clientId',p.cliente_id,'mustChangePassword',p.debe_cambiar_password)
        from public.perfiles p where p.id=auth.uid() and p.activo),
      'access',public.ivmet_access_status());
  end if;
  cid:=private.mobile_require();
  if section='bootstrap' then
    return jsonb_build_object('serverTime',now(),'finalizationEnabled',false,
      'client',(select jsonb_build_object('id',id,'code',codigo,'name',coalesce(nombre,razon_social,codigo)) from public.clientes where id=cid),
      'plants',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.legacy_codigo_planta,
        'name',coalesce(p.nombre,p.legacy_codigo_planta)) order by p.legacy_codigo_planta)
        from public.plantas p where p.cliente_id=cid and p.activo and private.can_access_plant(p.id)),'[]'),
      'areas',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'plantId',a.planta_id,'name',a.nombre) order by a.nombre)
        from public.areas a where a.cliente_id=cid and a.activa and private.can_access_plant(a.planta_id)),'[]'),
      'equipmentCount',(select count(*) from public.equipos e join public.equipos_ivmet i on i.equipo_id=e.id
        join public.plantas p on p.id=e.planta_id where e.cliente_id=cid and e.activo and p.activo and i.habilitado
        and e.estado_catalogo='READY' and i.estado_configuracion='READY' and private.can_access_plant(e.planta_id)),
      'openAlerts',(select count(*) from public.alertas a where a.cliente_id=cid and a.estado_cliente='OPEN' and private.can_access_plant(a.planta_id)));
  elsif section='instruments' then
    with matching as (
      select e.id,e.cod_metrica,e.marca,e.modelo,e.serie,e.planta_id,i.area_id,
        coalesce(p.nombre,p.legacy_codigo_planta) planta,coalesce(a.nombre,'Sin área') area
      from public.equipos e join public.equipos_ivmet i on i.equipo_id=e.id
      join public.plantas p on p.id=e.planta_id left join public.areas a on a.id=i.area_id
      where e.cliente_id=cid and e.activo and p.activo and e.estado_catalogo='READY'
        and i.habilitado and i.estado_configuracion='READY' and private.can_access_plant(e.planta_id)
        and (pid is null or e.planta_id=pid)
        and (nullif(filters->>'areaId','') is null or i.area_id=(filters->>'areaId')::uuid)
        and (nullif(filters->>'search','') is null or e.cod_metrica ilike '%'||left(filters->>'search',100)||'%'
          or e.marca ilike '%'||left(filters->>'search',100)||'%')
    ), rows as (select * from matching order by cod_metrica limit page_size offset (page_no-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(r) order by r.cod_metrica) from rows r),'[]')) into result;
    return result;
  elsif section='equipment' then
    select eq.* into selected_equipment from public.equipos eq join public.equipos_ivmet i on i.equipo_id=eq.id
      join public.plantas pl on pl.id=eq.planta_id
      where eq.id=eid and eq.cliente_id=cid and private.can_access_plant(eq.planta_id)
        and eq.activo and pl.activo and eq.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY';
    perform private.admin_assert(found,'EQUIPMENT_NOT_ACCESSIBLE');
    return jsonb_build_object('equipment',to_jsonb(selected_equipment)-array['source_hash','last_seen_run_id'],
      'ranges',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.equipo_rangos',to_jsonb(r)) order by r.numero_rango) from public.equipo_rangos r where r.equipo_id=selected_equipment.id),'[]'),
      'plan',(select private.mobile_plan(ep.plan_version_id) from public.equipo_planes ep
        join public.plan_versiones v on v.id=ep.plan_version_id where ep.equipo_id=selected_equipment.id
        and ep.vigente_desde<=now() and (ep.vigente_hasta is null or ep.vigente_hasta>now()) and v.estado='PUBLISHED'
        order by ep.vigente_desde desc limit 1),
      'patterns',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.codigo,'description',p.descripcion,
        'certificates',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'number',c.numero,'laboratory',c.laboratorio,
          'calibratedOn',c.calibrado_el,'expiresOn',c.vence_el,'expired',c.vence_el<current_date) order by c.vence_el desc)
          from public.patron_certificados c where c.patron_id=p.id and c.estado='ACTIVE' and c.calibrado_el<=current_date),'[]')) order by p.codigo)
        from public.patrones p join public.patron_plantas pp on pp.patron_id=p.id
        where p.cliente_id=cid and p.activo and pp.planta_id=selected_equipment.planta_id),'[]'));
  elsif section='history' then
    with matching as (select v.id,v.equipo_id,v.realizado_at,v.alcance,v.veredicto_global,v.trazabilidad,v.estado,
        coalesce(v.equipo_snapshot->>'cod_metrica',e.cod_metrica) cod_metrica,a.id alerta_id
      from public.verificaciones v join public.equipos e on e.id=v.equipo_id left join public.alertas a on a.verificacion_id=v.id
      where v.cliente_id=cid and private.can_access_plant(v.planta_id) and (eid is null or v.equipo_id=eid)
    ), rows as (select * from matching order by realizado_at desc,id limit page_size offset (page_no-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(r) order by r.realizado_at desc,r.id) from rows r),'[]')) into result;
    return result;
  elsif section='verification' then
    perform private.admin_assert(private.can_read_verification(target),'VERIFICATION_NOT_ACCESSIBLE');
    return jsonb_build_object('verification',(select private.stringify_ivmet_outbox_numbers('public.verificaciones',to_jsonb(v)-array['payload_hash','request_uuid','dispositivo_id']) from public.verificaciones v where v.id=target),
      'users',(select jsonb_build_object('capture',capture.nombre,'finalization',finalization.nombre)
        from public.verificaciones v join public.perfiles capture on capture.id=v.capturado_por
        join public.perfiles finalization on finalization.id=v.finalizado_por where v.id=target),
      'tests',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.pruebas',to_jsonb(t))||jsonb_build_object('readings',
        coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.lecturas',to_jsonb(l)) order by l.orden) from public.lecturas l where l.prueba_id=t.id),'[]')) order by t.tipo) from public.pruebas t where t.verificacion_id=target),'[]'),
      'patterns',coalesce((select jsonb_agg(to_jsonb(p)) from public.verificacion_patrones p where p.verificacion_id=target),'[]'),
      'alert',(select to_jsonb(a)||jsonb_build_object('row_version',a.row_version::text) from public.alertas a where a.verificacion_id=target),
      'cases',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'code',c.codigo,'visibility',c.visibilidad,'state',c.estado,
        'version',c.row_version::text,'message',c.mensaje,'events',coalesce((select jsonb_agg(to_jsonb(ev) order by ev.created_at) from public.caso_eventos ev where ev.caso_id=c.id),'[]')) order by c.created_at desc)
        from public.casos_compartidos c where c.verificacion_id=target),'[]'));
  elsif section='drafts' then
    with matching as (select d.id,d.request_uuid,d.equipo_id,d.updated_at,d.version::text,d.estado,e.cod_metrica
      from public.verificacion_borradores d join public.equipos e on e.id=d.equipo_id
      where d.usuario_id=auth.uid() and d.cliente_id=cid and private.can_access_plant(d.planta_id)
        and d.estado='DRAFT' and d.expires_at>now() and (eid is null or d.equipo_id=eid)
    ), rows as (select * from matching order by updated_at desc,id limit page_size offset (page_no-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(r) order by r.updated_at desc,r.id) from rows r),'[]')) into result;
    return result;
  elsif section='draft' then
    select * into selected_draft from public.verificacion_borradores where id=target and usuario_id=auth.uid() and cliente_id=cid
      and private.can_access_plant(planta_id) and estado='DRAFT' and expires_at>now();
    perform private.admin_assert(found,'DRAFT_NOT_ACCESSIBLE');
    return to_jsonb(selected_draft)||jsonb_build_object('version',selected_draft.version::text,'context_snapshot',coalesce(selected_draft.context_snapshot,
      jsonb_build_object('plan',private.mobile_plan(selected_draft.plan_version_id),'equipment',(select to_jsonb(eq)-array['source_hash','last_seen_run_id'] from public.equipos eq where eq.id=selected_draft.equipo_id))));
  end if;
  raise exception 'UNKNOWN_MOBILE_SECTION';
end; $$;

create function public.ivmet_mobile_save_draft(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); e public.equipos%rowtype; d public.verificacion_borradores%rowtype;
  digest text; item jsonb; reading jsonb; cert jsonb; bundle jsonb; seen text[]:='{}';
begin
  perform private.admin_assert(request_id is not null and save_id is not null and version_id is not null
    and equipment_id is not null and expected_version>=0,'INVALID_DRAFT');
  perform private.admin_assert(jsonb_typeof(content)='object' and octet_length(content::text)<=262144
    and (content-array['tests','certificates','temperature','humidity','observations'])='{}'::jsonb,'INVALID_DRAFT_CONTENT');
  digest:=encode(sha256(convert_to(jsonb_build_array(equipment_id,version_id,content)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into d from public.verificacion_borradores where request_uuid=request_id for update;
  if found then
    perform private.admin_assert(d.usuario_id=auth.uid() and d.cliente_id=cid and private.can_access_plant(d.planta_id),'DRAFT_NOT_ACCESSIBLE');
    perform private.admin_assert(d.equipo_id=equipment_id and d.plan_version_id=version_id,'IDEMPOTENCY_CONFLICT');
    perform private.admin_assert(d.estado='DRAFT' and d.expires_at>now(),'DRAFT_EXPIRED');
    if d.last_save_uuid=save_id then
      perform private.admin_assert(d.last_save_hash=digest,'IDEMPOTENCY_CONFLICT');
      return jsonb_build_object('id',d.id,'requestId',d.request_uuid,'version',d.version::text,'savedAt',d.updated_at);
    end if;
    perform private.admin_assert(d.version=expected_version,'ROW_VERSION_CONFLICT');
  else
    perform private.admin_assert(expected_version=0,'ROW_VERSION_CONFLICT');
  end if;
  select eq.* into e from public.equipos eq join public.equipos_ivmet i on i.equipo_id=eq.id
    join public.plantas p on p.id=eq.planta_id where eq.id=equipment_id and eq.cliente_id=cid
    and eq.activo and p.activo and eq.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY'
    and private.can_access_plant(eq.planta_id) for share of eq,i,p;
  perform private.admin_assert(found,'EQUIPMENT_NOT_ACCESSIBLE');
  perform 1 from public.equipo_planes ep join public.plan_versiones v on v.id=ep.plan_version_id
    where ep.equipo_id=e.id and ep.plan_version_id=version_id and ep.vigente_desde<=coalesce(d.created_at,now())
      and (ep.vigente_hasta is null or ep.vigente_hasta>coalesce(d.created_at,now()))
      and (v.estado='PUBLISHED' or (d.id is not null and v.estado='RETIRED')) for share of ep,v;
  perform private.admin_assert(found,'PLAN_NOT_ASSIGNED');
  perform private.admin_assert(jsonb_typeof(content->'tests')='array' and jsonb_array_length(content->'tests') between 1 and 3
    and jsonb_typeof(content->'certificates')='array' and jsonb_array_length(content->'certificates')<=50
    and jsonb_typeof(content->'observations')='string' and length(content->>'observations')<=4000,'INVALID_DRAFT_CONTENT');
  foreach digest in array array['temperature','humidity'] loop
    perform private.admin_assert(jsonb_typeof(content->digest)='string' and ((content->>digest)='' or
      (content->>digest) ~ '^-?[0-9]{1,6}(\.[0-9]{1,3})?$'),'INVALID_ENVIRONMENT');
  end loop;
  if content->>'humidity'<>'' then
    perform private.admin_assert((content->>'humidity')::numeric between 0 and 100,'INVALID_HUMIDITY');
  end if;
  for item in select value from jsonb_array_elements(content->'tests') loop
    perform private.admin_assert((item-array['id','omitted','reason','readings'])='{}'::jsonb
      and jsonb_typeof(item->'omitted')='boolean' and jsonb_typeof(item->'reason')='string'
      and jsonb_typeof(item->'readings')='array','INVALID_TEST');
    perform private.admin_assert(exists(select 1 from public.plan_pruebas t where t.id=(item->>'id')::uuid
      and t.plan_version_id=version_id) and not (item->>'id'=any(seen)),'INVALID_TEST');
    seen:=array_append(seen,item->>'id');
    if (item->>'omitted')::boolean then
      perform private.admin_assert(length(btrim(item->>'reason')) between 1 and 2000 and jsonb_array_length(item->'readings')=0,'OMISSION_REASON_REQUIRED');
    else
      perform private.admin_assert(item->>'reason'='' and jsonb_array_length(item->'readings')<=500,'INVALID_TEST');
    end if;
    perform private.admin_assert((select count(*)=count(distinct v->>'pointId') from jsonb_array_elements(item->'readings') v),'DUPLICATE_POINT');
    for reading in select value from jsonb_array_elements(item->'readings') loop
      perform private.admin_assert((reading-array['pointId','indication','zero'])='{}'::jsonb and exists(
        select 1 from public.plan_puntos p where p.id=(reading->>'pointId')::uuid and p.plan_prueba_id=(item->>'id')::uuid),'INVALID_POINT');
      foreach digest in array array['indication','zero'] loop
        perform private.admin_assert(jsonb_typeof(reading->digest)='string' and ((reading->>digest)='' or
          (reading->>digest) ~ '^-?[0-9]{1,10}(\.[0-9]{1,9})?$'),'INVALID_DECIMAL_STRING');
      end loop;
    end loop;
  end loop;
  perform private.admin_assert(cardinality(seen)=(select count(*) from public.plan_pruebas where plan_version_id=version_id),'MISSING_TESTS');
  for cert in select value from jsonb_array_elements(content->'certificates') loop
    perform private.admin_assert(jsonb_typeof(cert)='string' and exists(select 1 from public.patron_certificados c
      join public.patrones p on p.id=c.patron_id join public.patron_plantas pp on pp.patron_id=p.id
      where c.id=(cert#>>'{}')::uuid and c.estado='ACTIVE' and c.calibrado_el<=current_date
        and p.activo and p.cliente_id=cid and pp.planta_id=e.planta_id),'CERTIFICATE_NOT_ACCESSIBLE');
  end loop;
  perform private.admin_assert((select count(*)=count(distinct c.patron_id) from jsonb_array_elements_text(content->'certificates') x
    join public.patron_certificados c on c.id=x::uuid),'DUPLICATE_PATTERN');
  digest:=encode(sha256(convert_to(jsonb_build_array(equipment_id,version_id,content)::text,'UTF8')),'hex');
  if d.id is null then
    bundle:=public.ivmet_mobile_read('equipment',jsonb_build_object('equipmentId',e.id));
    bundle:=jsonb_set(bundle,'{plan}',private.mobile_plan(version_id));
    insert into public.verificacion_borradores(request_uuid,cliente_id,planta_id,area_id,equipo_id,plan_version_id,usuario_id,
      payload,context_snapshot,last_save_uuid,last_save_hash)
    values(request_id,cid,e.planta_id,(select area_id from public.equipos_ivmet where equipo_id=e.id),e.id,version_id,auth.uid(),
      content,bundle,save_id,digest) returning * into d;
  else
    update public.verificacion_borradores set payload=content,last_save_uuid=save_id,last_save_hash=digest
      where id=d.id returning * into d;
  end if;
  -- No outbox: contenido privado; auditoría sin lecturas ni payload.
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion)
    values(auth.uid(),cid,'verificacion_borrador',d.id::text,'DRAFT_SAVED');
  return jsonb_build_object('id',d.id,'requestId',d.request_uuid,'version',d.version::text,'savedAt',d.updated_at);
end; $$;

revoke all on function private.mobile_require(),private.mobile_plan(uuid) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_mobile_read(text,jsonb),public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid)
  from public,anon,service_role;
grant execute on function public.ivmet_mobile_read(text,jsonb),public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) to authenticated;
commit;

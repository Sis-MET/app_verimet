-- Flexible internal checks: suggested plan loads remain immutable; actual loads
-- and the origin of working loads are captured separately, with engine v2.
alter function private.mobile_plan(uuid) rename to mobile_plan_before_flexible_capture;
create function private.mobile_plan(version_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select private.mobile_plan_before_flexible_capture(version_id) ||
    jsonb_build_object('captureVersion',2,'captureEngineVersion','ivmet-internal-2.0.0');
$$;

create function private.flexible_load_tolerance(equipment_id uuid,test_id uuid,point_id uuid,actual_load numeric)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare trial public.plan_pruebas%rowtype; equipment_value public.equipos%rowtype;
  range_value public.equipo_rangos%rowtype; load_kg numeric; e_kg numeric; tolerance_value numeric;
begin
  select * into trial from public.plan_pruebas where id=test_id;
  if trial.fuente_tolerancia<>'OIML_IN_SERVICE_REFERENCE' then
    select tolerancia into tolerance_value from public.plan_puntos where id=point_id and plan_prueba_id=test_id;
    if tolerance_value is null then
      select min(tolerancia) into tolerance_value from public.plan_puntos where plan_prueba_id=test_id;
    end if;
    return tolerance_value;
  end if;
  select * into equipment_value from public.equipos where id=equipment_id;
  load_kg:=private.mass_convert(actual_load,trial.unidad,'kg');
  select r.* into range_value from public.equipo_rangos r where r.equipo_id=equipment_id
    and r.intervalo_verificacion is not null and private.mass_convert(r.capacidad_max,r.unidad,'kg')>=load_kg
    order by private.mass_convert(r.capacidad_max,r.unidad,'kg'),r.numero_rango limit 1;
  if trial.tipo<>'linearity' or range_value.id is null then return null; end if;
  e_kg:=private.mass_convert(range_value.intervalo_verificacion,range_value.unidad,'kg');
  return private.mass_convert(private.oiml_r76_mpe(load_kg,e_kg,equipment_value.clase,true),'kg',trial.unidad);
end; $$;

create function private.validate_flexible_trial(version_id uuid,equipment_id uuid,item jsonb,complete boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare trial public.plan_pruebas%rowtype; setup jsonb:=item->'setup'; reading jsonb; substitution jsonb;
  active jsonb:='[]'; base jsonb; reference jsonb; field text; actual_load numeric; capacity numeric;
  group_count integer; reading_count integer; index_value integer:=0; omitted boolean;
begin
  perform private.admin_assert(jsonb_typeof(item)='object' and
    (item-array['id','omitted','reason','setup','readings','retainedReadings','substitutionDraft'])='{}'::jsonb
    and jsonb_typeof(item->'omitted')='boolean' and jsonb_typeof(item->'reason')='string'
    and jsonb_typeof(item->'readings')='array' and jsonb_typeof(item->'retainedReadings')='array','INVALID_TEST');
  select * into trial from public.plan_pruebas where id=(item->>'id')::uuid and plan_version_id=version_id;
  perform private.admin_assert(found,'INVALID_TEST');
  omitted:=(item->>'omitted')::boolean;
  perform private.admin_assert(not complete or omitted or not (item ? 'substitutionDraft'),'SUBSTITUTION_PENDING');
  perform private.admin_assert(length(item->>'reason')<=500 and
    (not omitted or length(btrim(item->>'reason'))>0),'OMISSION_REASON_REQUIRED');
  perform private.admin_assert(jsonb_typeof(setup)='object' and
    (setup-array['source','description','notes','platform','indicatorPosition','groupCount','measurementCount','pointCount','loadingMethod','substitutionMethod'])='{}'::jsonb
    and setup->>'source' in ('standard','process','mixed')
    and jsonb_typeof(setup->'description')='string' and length(setup->>'description')<=1000
    and jsonb_typeof(setup->'notes')='string' and length(setup->>'notes')<=2000
    and setup->>'platform' in ('square','rectangular','circular','triangular')
    and setup->>'indicatorPosition' in ('front','back','left','right')
    and setup->>'loadingMethod' in ('none','return_zero','continuous')
    and setup->>'substitutionMethod' in ('none','method_1','method_2')
    and jsonb_typeof(setup->'groupCount')='number' and jsonb_typeof(setup->'measurementCount')='number'
    and jsonb_typeof(setup->'pointCount')='number'
    and (setup->>'groupCount') ~ '^[1-3]$' and (setup->>'measurementCount') in ('3','5','10')
    and (setup->>'pointCount') ~ '^[0-9]{1,2}$','INVALID_TEST_SETUP');
  group_count:=case when trial.tipo='repeatability' then (setup->>'groupCount')::int else 1 end;
  reading_count:=case when trial.tipo='repeatability' then (setup->>'measurementCount')::int else (setup->>'pointCount')::int end;
  perform private.admin_assert(reading_count between 2 and 60
    and jsonb_array_length(item->'readings')=group_count*reading_count
    and jsonb_array_length(item->'retainedReadings')<=60,'INVALID_READING_COUNT');
  if trial.tipo='eccentricity' then
    perform private.admin_assert(case setup->>'platform' when 'square' then reading_count=5
      when 'rectangular' then reading_count in (3,5) when 'circular' then reading_count in (4,5)
      when 'triangular' then reading_count=4 else false end,'INVALID_PLATFORM_POSITIONS');
  end if;
  -- Inactive/omitted rows may contain unfinished text. They are retained verbatim
  -- but never parsed or included in the evaluation.
  for reading in select value from jsonb_array_elements((item->'readings')||(item->'retainedReadings')) loop
    perform private.admin_assert(jsonb_typeof(reading)='object' and
      (reading-array['pointId','group','slot','load','indication','zero','substitution'])='{}'::jsonb
      and jsonb_typeof(reading->'group')='number' and jsonb_typeof(reading->'slot')='number'
      and (reading->>'group') ~ '^[1-3]$' and (reading->>'slot') ~ '^[0-9]{1,2}$'
      and (reading->>'slot')::int between 1 and 60 and (reading->>'pointId')::uuid is not null
      and not exists(select 1 from public.plan_puntos p where p.id=(reading->>'pointId')::uuid and p.plan_prueba_id<>trial.id),'INVALID_POINT');
    foreach field in array array['load','indication','zero'] loop
      perform private.admin_assert(jsonb_typeof(reading->field)='string' and length(reading->>field)<=100,'INVALID_DECIMAL_STRING');
    end loop;
    if reading ? 'substitution' then
      substitution:=reading->'substitution';
      perform private.admin_assert(trial.tipo='linearity' and jsonb_typeof(substitution)='object'
        and (substitution-array['basePointId','referencePointId','indication'])='{}'::jsonb
        and (substitution->>'basePointId')::uuid is not null and (substitution->>'referencePointId')::uuid is not null
        and jsonb_typeof(substitution->'indication')='string' and length(substitution->>'indication')<=100,'INVALID_SUBSTITUTION');
    end if;
  end loop;
  if item ? 'substitutionDraft' then
    substitution:=item->'substitutionDraft';
    perform private.admin_assert(trial.tipo='linearity' and jsonb_typeof(substitution)='object'
      and (substitution-array['basePointId','referencePointId','indication'])='{}'::jsonb
      and (substitution->>'basePointId')::uuid is not null and (substitution->>'referencePointId')::uuid is not null
      and jsonb_typeof(substitution->'indication')='string' and length(substitution->>'indication')<=100,'INVALID_SUBSTITUTION');
  end if;
  perform private.admin_assert((select count(*)=count(distinct r->>'pointId')
    and count(*)=count(distinct jsonb_build_array(r->>'group',r->>'slot'))
    from jsonb_array_elements((item->'readings')||(item->'retainedReadings')) r),'DUPLICATE_POINT');
  select max(private.mass_convert(r.capacidad_max,r.unidad,trial.unidad)) into capacity
    from public.equipo_rangos r where r.equipo_id=equipment_id;
  for reading in select value from jsonb_array_elements(item->'readings') loop
    perform private.admin_assert((reading->>'group')::int=index_value/reading_count+1
      and (reading->>'slot')::int=index_value%reading_count+1,'INVALID_READING_ORDER');
    index_value:=index_value+1;
    if omitted then continue; end if;
    foreach field in array array['load','indication','zero'] loop
      perform private.admin_assert(reading->>field='' or (reading->>field) ~ '^-?[0-9]{1,10}(\.[0-9]{1,9})?$','INVALID_DECIMAL_STRING');
    end loop;
    if reading ? 'substitution' then
      substitution:=reading->'substitution';
      perform private.admin_assert((substitution->>'indication') ~ '^-?[0-9]{1,10}(\.[0-9]{1,9})?$','INVALID_SUBSTITUTION');
      select r into base from jsonb_array_elements(active) r where r->>'pointId'=substitution->>'basePointId';
      select r into reference from jsonb_array_elements(active) r where r->>'pointId'=substitution->>'referencePointId';
      perform private.admin_assert(base is not null and reference is not null,'SUBSTITUTION_REFERENCE_REQUIRED');
      actual_load:=nullif(base->>'load','')::numeric+(substitution->>'indication')::numeric
        -(nullif(reference->>'indication','')::numeric-nullif(reference->>'load','')::numeric);
      reading:=jsonb_set(reading,'{load}',to_jsonb(coalesce(actual_load::text,'')));
    end if;
    if complete then
      perform private.admin_assert(reading->>'load'<>'' and reading->>'indication'<>'','INCOMPLETE_TEST');
      actual_load:=(reading->>'load')::numeric;
      perform private.admin_assert(actual_load>=0 and actual_load<10000000000 and capacity is not null and actual_load<=capacity,'LOAD_OUT_OF_CAPACITY');
      if trial.tipo in ('eccentricity','repeatability') then
        perform private.admin_assert(actual_load>0,'POSITIVE_LOAD_REQUIRED');
      end if;
    end if;
    active:=active||jsonb_build_array(reading);
  end loop;
  if omitted then return item; end if;
  if trial.tipo in ('eccentricity','repeatability') then
    perform private.admin_assert(not exists(select 1 from jsonb_array_elements(active) r group by r->>'group'
      having count(distinct nullif(r->>'load','')::numeric)>1),'GROUP_LOAD_MISMATCH');
  elsif complete then
    perform private.admin_assert((select count(distinct (r->>'load')::numeric)>=2 from jsonb_array_elements(active) r),'DISTINCT_LOADS_REQUIRED');
  end if;
  return jsonb_set(item,'{readings}',active);
end; $$;

create function private.evaluate_flexible_payload(target_equipment_id uuid,target_plan_version_id uuid,payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare trial record; item jsonb; reading jsonb; readings_value jsonb; groups_value jsonb; group_value record;
  group_readings jsonb; mean_value numeric; deviation_value numeric; range_value numeric; group_tolerance numeric;
  min_tolerance numeric; tolerance_value numeric; error_value numeric; max_error numeric; max_deviation numeric; max_range numeric;
  reference_indication numeric; group_verdict text; test_verdict text; reading_verdict text; group_error numeric;
  global_verdict text:='pass'; executed_count integer:=0; omitted_count integer:=0; tests_value jsonb:='[]';
  plan_point uuid; suggested_load numeric; order_value integer; metric_value numeric;
begin
  perform private.admin_assert(payload->'captureVersion'='2'::jsonb,'INVALID_CAPTURE_VERSION');
  for trial in select * from public.plan_pruebas where plan_version_id=target_plan_version_id order by tipo loop
    select value into item from jsonb_array_elements(payload->'tests') where value->>'id'=trial.id::text;
    perform private.admin_assert(item is not null,'MISSING_TESTS');
    item:=private.validate_flexible_trial(target_plan_version_id,target_equipment_id,item,true);
    if (item->>'omitted')::boolean then
      omitted_count:=omitted_count+1;
      tests_value:=tests_value||jsonb_build_array(jsonb_build_object('planTestId',trial.id,'type',trial.tipo,
        'omitted',true,'reason',item->>'reason','method',trial.metodo_evaluacion,'methodCode',trial.metodo_codigo,
        'unit',trial.unidad,'decisionRule',trial.regla_decision,'toleranceSource',trial.fuente_tolerancia,
        'expandedUncertainty',trial.incertidumbre_expandida::text,'setup',item->'setup','readings','[]'::jsonb));
      continue;
    end if;
    executed_count:=executed_count+1; readings_value:='[]'; groups_value:='[]'; order_value:=0;
    test_verdict:='pass'; min_tolerance:=null; max_error:=0; max_deviation:=0; max_range:=0;
    reference_indication:=(item->'readings'->0->>'indication')::numeric;
    for group_value in select distinct (r->>'group')::int n from jsonb_array_elements(item->'readings') r order by n loop
      select jsonb_agg(r order by (r->>'slot')::int),avg((r->>'indication')::numeric),
        stddev_samp((r->>'indication')::numeric),max((r->>'indication')::numeric)-min((r->>'indication')::numeric),
        min(private.flexible_load_tolerance(target_equipment_id,trial.id,(r->>'pointId')::uuid,(r->>'load')::numeric))
        into group_readings,mean_value,deviation_value,range_value,group_tolerance
        from jsonb_array_elements(item->'readings') r where (r->>'group')::int=group_value.n;
      perform private.admin_assert(group_tolerance is not null,'OIML_EQUIPMENT_DATA_REQUIRED');
      group_verdict:=case when trial.tipo='repeatability' then
        private.decision_verdict(deviation_value,group_tolerance,trial.regla_decision,trial.incertidumbre_expandida) else 'pass' end;
      min_tolerance:=least(min_tolerance,group_tolerance); group_error:=0;
      max_deviation:=greatest(max_deviation,deviation_value); max_range:=greatest(max_range,range_value);
      for reading in select value from jsonb_array_elements(group_readings) loop
        order_value:=order_value+1; plan_point:=null; suggested_load:=null;
        select id,carga_nominal into plan_point,suggested_load from public.plan_puntos
          where id=(reading->>'pointId')::uuid and plan_prueba_id=trial.id;
        tolerance_value:=private.flexible_load_tolerance(target_equipment_id,trial.id,plan_point,(reading->>'load')::numeric);
        perform private.admin_assert(tolerance_value is not null,'OIML_EQUIPMENT_DATA_REQUIRED');
        error_value:=(reading->>'indication')::numeric-case trial.tipo when 'repeatability' then mean_value
          when 'eccentricity' then reference_indication else (reading->>'load')::numeric end;
        perform private.admin_assert(abs(error_value)<10000000000,'MEASUREMENT_OUT_OF_RANGE');
        max_error:=greatest(max_error,abs(error_value)); group_error:=greatest(group_error,abs(error_value));
        reading_verdict:=case when trial.tipo='repeatability' then group_verdict else
          private.decision_verdict(abs(error_value),tolerance_value,trial.regla_decision,trial.incertidumbre_expandida) end;
        perform private.admin_assert(reading_verdict is not null,'DECISION_RULE_INVALID');
        group_verdict:=private.worst_verdict(group_verdict,reading_verdict);
        readings_value:=readings_value||jsonb_build_array(jsonb_build_object('pointId',plan_point,
          'capturePointId',reading->>'pointId','group',group_value.n,'order',order_value,'code','P'||order_value,
          'label',case trial.tipo when 'eccentricity' then 'Posición ' else 'Medición ' end||(reading->>'slot'),
          'load',reading->>'load','suggestedLoad',suggested_load::text,'indication',reading->>'indication',
          'zero',nullif(reading->>'zero',''),'error',error_value::text,'tolerance',tolerance_value::text,
          'verdict',reading_verdict,'reference',trial.tipo='eccentricity' and order_value=1,
          'substitution',reading->'substitution','loadSource',item->'setup'->>'source'));
      end loop;
      test_verdict:=private.worst_verdict(test_verdict,group_verdict);
      groups_value:=groups_value||jsonb_build_array(jsonb_build_object('group',group_value.n,
        'load',case when trial.tipo='repeatability' then group_readings->0->>'load' end,'mean',mean_value::text,
        'standardDeviation',deviation_value::text,'range',range_value::text,'tolerance',group_tolerance::text,
        'metric',case when trial.tipo='repeatability' then deviation_value else group_error end::text,'verdict',group_verdict));
    end loop;
    global_verdict:=private.worst_verdict(global_verdict,test_verdict);
    metric_value:=case when trial.tipo='repeatability' then max_deviation else max_error end;
    tests_value:=tests_value||jsonb_build_array(jsonb_build_object('planTestId',trial.id,'type',trial.tipo,
      'omitted',false,'method',trial.metodo_evaluacion,'methodCode',trial.metodo_codigo,'unit',trial.unidad,
      'tolerance',min_tolerance::text,'verdict',test_verdict,'maxAbsoluteError',max_error::text,
      'mean',case when jsonb_array_length(groups_value)=1 then mean_value::text end,
      'standardDeviation',case when trial.tipo='repeatability' then max_deviation::text end,
      'range',max_range::text,'metric',metric_value::text,'decisionRule',trial.regla_decision,
      'toleranceSource',trial.fuente_tolerancia,'expandedUncertainty',trial.incertidumbre_expandida::text,
      'setup',item->'setup','groups',groups_value,'readings',readings_value));
  end loop;
  perform private.admin_assert(executed_count>0,'ALL_TESTS_OMITTED');
  return jsonb_build_object('scope',case when omitted_count>0 then 'partial' else 'complete' end,'verdict',global_verdict,
    'executedCount',executed_count,'omittedCount',omitted_count,'tests',tests_value);
end; $$;

-- Keep the existing authenticated save, concurrency and finalization contract.
create or replace function private.mobile_save_before_validation(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); e public.equipos%rowtype; d public.verificacion_borradores%rowtype;
  digest text; item jsonb; reading jsonb; cert jsonb; bundle jsonb; seen text[]:='{}';
begin
  perform private.admin_assert(request_id is not null and save_id is not null and version_id is not null
    and equipment_id is not null and expected_version>=0,'INVALID_DRAFT');
  perform private.admin_assert(jsonb_typeof(content)='object' and octet_length(content::text)<=262144
    and (content-array['tests','certificates','temperature','humidity','observations','captureVersion'])='{}'::jsonb,'INVALID_DRAFT_CONTENT');
  perform private.admin_assert(not (content ? 'captureVersion') or content->'captureVersion'='2'::jsonb,'INVALID_CAPTURE_VERSION');
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
    perform private.admin_assert(coalesce(d.payload->'captureVersion','1'::jsonb)=coalesce(content->'captureVersion','1'::jsonb),'CAPTURE_VERSION_MISMATCH');
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
    if content->'captureVersion'='2'::jsonb then
      perform private.validate_flexible_trial(version_id,equipment_id,item,false);
      perform private.admin_assert(not (item->>'id'=any(seen)),'INVALID_TEST');
      seen:=array_append(seen,item->>'id');
      continue;
    end if;
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

create or replace function public.ivmet_mobile_finalize_draft(draft_id uuid,expected_version bigint,
  finalize_id uuid,app_version_value text default null,device_id_value text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); d public.verificacion_borradores%rowtype; verification_id uuid;
  verification_time timestamptz:=clock_timestamp(); payload_digest text; finalize_digest text;
  engine_value text; traceability_value text; global_verdict text; scope_value text; selected_certificates integer;
  evaluation jsonb; item jsonb; reading_value jsonb; test_id uuid; updated_version bigint; alert_type text;
begin
  perform private.admin_assert(draft_id is not null and finalize_id is not null and expected_version>0,'INVALID_FINALIZATION');
  perform private.admin_assert(length(coalesce(app_version_value,''))<=50 and length(coalesce(device_id_value,''))<=200,'INVALID_FINALIZATION');
  select * into d from public.verificacion_borradores where id=draft_id for update;
  perform private.admin_assert(found and d.usuario_id=auth.uid() and d.cliente_id=cid and private.can_access_plant(d.planta_id),
    'DRAFT_NOT_ACCESSIBLE');
  finalize_digest:=encode(sha256(convert_to(jsonb_build_array(draft_id,expected_version,app_version_value,device_id_value)::text,'UTF8')),'hex');
  if d.estado='FINALIZED' then
    perform private.admin_assert(d.finalization_uuid=finalize_id and d.finalization_hash=finalize_digest,'FINALIZATION_CONFLICT');
    return jsonb_build_object('id',d.verificacion_id,'draftId',d.id,'version',d.version::text,
      'verdict',(select veredicto_global from public.verificaciones where id=d.verificacion_id),
      'traceability',(select trazabilidad from public.verificaciones where id=d.verificacion_id),
      'scope',(select alcance from public.verificaciones where id=d.verificacion_id),'idempotent',true);
  end if;
  perform private.admin_assert(d.estado='DRAFT' and d.expires_at>verification_time,'DRAFT_EXPIRED');
  perform private.admin_assert(d.version=expected_version,'ROW_VERSION_CONFLICT');
  engine_value:=case when d.payload->'captureVersion'='2'::jsonb then 'ivmet-internal-2.0.0' else 'ivmet-internal-1.0.0' end;
  if engine_value='ivmet-internal-2.0.0' then
    perform private.admin_assert(d.context_snapshot->'plan'->>'captureEngineVersion'=engine_value,'OFFICIAL_ENGINE_NOT_RELEASED');
  end if;
  perform private.admin_assert(coalesce((d.context_snapshot->'plan'->>'finalizationEnabled')::boolean,false)
    and d.context_snapshot->'plan'->>'engineVersion'='ivmet-internal-1.0.0','OFFICIAL_ENGINE_NOT_RELEASED');
  perform private.admin_assert(not exists(select 1 from public.verificacion_borradores x
    where x.finalization_uuid=finalize_id and x.id<>d.id),'FINALIZATION_CONFLICT');
  perform private.admin_assert(exists(select 1 from public.equipos_cliente ec join public.equipos e on e.id=ec.equipo_id
    where e.id=d.equipo_id and ec.catalog_hash=e.source_hash),'EQUIPMENT_VALIDATION_REQUIRED');

  select count(*) into selected_certificates from jsonb_array_elements_text(d.payload->'certificates');
  perform private.admin_assert(not exists(
    select 1 from jsonb_array_elements_text(d.payload->'certificates') selected(id)
      left join public.patron_certificados c on c.id=selected.id::uuid
      left join public.patrones p on p.id=c.patron_id and p.cliente_id=d.cliente_id
      left join public.patron_plantas pp on pp.patron_id=p.id and pp.planta_id=d.planta_id
    where c.id is null or p.id is null or pp.patron_id is null
  ),'CERTIFICATE_NOT_ACCESSIBLE');
  traceability_value:=case when selected_certificates>0 and not exists(
    select 1 from jsonb_array_elements_text(d.payload->'certificates') selected(id)
      left join public.patron_certificados c on c.id=selected.id::uuid
      left join public.patrones p on p.id=c.patron_id
    where c.id is null or p.id is null or not p.activo or c.estado<>'ACTIVE'
      or c.calibrado_el>verification_time::date or c.vence_el<verification_time::date
  ) then 'traceable' else 'non_traceable' end;
  if engine_value='ivmet-internal-2.0.0' then
    evaluation:=private.evaluate_flexible_payload(d.equipo_id,d.plan_version_id,d.payload);
    if exists(select 1 from jsonb_array_elements(d.payload->'tests') t where not (t->>'omitted')::boolean
      and (t->'setup'->>'source'<>'standard' or exists(select 1 from jsonb_array_elements(t->'readings') r where r ? 'substitution'))) then
      traceability_value:='non_traceable';
    end if;
  else
    evaluation:=private.evaluate_draft_payload(d.equipo_id,d.plan_version_id,d.payload);
  end if;
  global_verdict:=evaluation->>'verdict';
  scope_value:=evaluation->>'scope';
  payload_digest:=encode(sha256(convert_to(d.payload::text,'UTF8')),'hex');
  verification_id:=extensions.gen_random_uuid();

  -- El resultado se calcula antes de insertar. La evidencia nace definitiva e inmutable.
  insert into public.verificaciones(id,request_uuid,payload_hash,cliente_id,planta_id,area_id,equipo_id,plan_version_id,
    capturado_por,finalizado_por,realizado_at,alcance,veredicto_global,trazabilidad,temperatura_c,humedad_relativa_pct,
    observaciones,equipo_snapshot,plan_snapshot,app_version,dispositivo_id,motor_version,regla_decision_resumen)
  values(verification_id,d.request_uuid,payload_digest,d.cliente_id,d.planta_id,d.area_id,d.equipo_id,d.plan_version_id,
    d.usuario_id,auth.uid(),verification_time,scope_value,global_verdict,traceability_value,
    nullif(d.payload->>'temperature','')::numeric,nullif(d.payload->>'humidity','')::numeric,d.payload->>'observations',
    jsonb_build_object('equipment',d.context_snapshot->'equipment','ranges',d.context_snapshot->'ranges'),
    d.context_snapshot->'plan',nullif(app_version_value,''),nullif(device_id_value,''),engine_value,'mixed');

  insert into public.verificacion_patrones(verificacion_id,patron_id,certificado_id,rol,snapshot)
  select verification_id,p.id,c.id,'standard',jsonb_build_object('pattern',to_jsonb(p),'certificate',to_jsonb(c),
    'validAtMeasurement',c.estado='ACTIVE' and c.calibrado_el<=verification_time::date and c.vence_el>=verification_time::date)
  from jsonb_array_elements_text(d.payload->'certificates') selected(id)
    join public.patron_certificados c on c.id=selected.id::uuid join public.patrones p on p.id=c.patron_id;

  for item in select value from jsonb_array_elements(evaluation->'tests') loop
    if (item->>'omitted')::boolean then
      insert into public.pruebas(verificacion_id,plan_prueba_id,tipo,estado_ejecucion,motivo_omision,metodo_evaluacion,
        metodo_codigo,unidad,regla_decision,fuente_tolerancia,incertidumbre_expandida,evaluacion_snapshot)
      values(verification_id,(item->>'planTestId')::uuid,item->>'type','omitted',item->>'reason',item->>'method',
        item->>'methodCode',item->>'unit',item->>'decisionRule',item->>'toleranceSource',
        nullif(item->>'expandedUncertainty','')::numeric,
        jsonb_build_object('claimScope','INTERNAL_CHECK_ONLY','engineVersion',engine_value,'setup',item->'setup'));
      continue;
    end if;
    test_id:=extensions.gen_random_uuid();
    insert into public.pruebas(id,verificacion_id,plan_prueba_id,tipo,estado_ejecucion,metodo_evaluacion,metodo_codigo,unidad,
      tolerancia,veredicto,error_max_abs,media,desviacion_estandar,rango,regla_decision,fuente_tolerancia,
      incertidumbre_expandida,valor_metrica,evaluacion_snapshot)
    values(test_id,verification_id,(item->>'planTestId')::uuid,item->>'type','executed',item->>'method',item->>'methodCode',
      item->>'unit',nullif(item->>'tolerance','')::numeric,item->>'verdict',nullif(item->>'maxAbsoluteError','')::numeric,
      nullif(item->>'mean','')::numeric,nullif(item->>'standardDeviation','')::numeric,nullif(item->>'range','')::numeric,
      item->>'decisionRule',item->>'toleranceSource',nullif(item->>'expandedUncertainty','')::numeric,
      nullif(item->>'metric','')::numeric,jsonb_build_object('claimScope','INTERNAL_CHECK_ONLY',
        'engineVersion',engine_value,'setup',item->'setup','groups',item->'groups','procedureReference',d.context_snapshot->'plan'->>'procedure'));
    for reading_value in select value from jsonb_array_elements(item->'readings') loop
      insert into public.lecturas(prueba_id,plan_punto_id,grupo,orden,punto_codigo,etiqueta,carga_nominal,indicacion,
        retorno_cero,error,tolerancia,veredicto,metadata)
      values(test_id,(reading_value->>'pointId')::uuid,(reading_value->>'group')::int,(reading_value->>'order')::int,
        reading_value->>'code',reading_value->>'label',(reading_value->>'load')::numeric,
        (reading_value->>'indication')::numeric,nullif(reading_value->>'zero','')::numeric,
        (reading_value->>'error')::numeric,(reading_value->>'tolerance')::numeric,reading_value->>'verdict',
        jsonb_build_object('reference',(reading_value->>'reference')::boolean,'decisionRule',item->>'decisionRule',
          'limitSource',item->>'toleranceSource','capturePointId',reading_value->>'capturePointId',
          'suggestedLoad',reading_value->>'suggestedLoad','loadSource',reading_value->>'loadSource','substitution',reading_value->'substitution'));
    end loop;
  end loop;

  if global_verdict<>'pass' or traceability_value='non_traceable' then
    alert_type:=case when global_verdict='fail' and traceability_value='non_traceable' then 'FAILED_NON_TRACEABLE'
      when global_verdict='fail' then 'FAILED' when global_verdict='inconclusive' then 'INCONCLUSIVE' else 'NON_TRACEABLE' end;
    insert into public.alertas(verificacion_id,cliente_id,planta_id,equipo_id,tipo,resumen)
    values(verification_id,d.cliente_id,d.planta_id,d.equipo_id,alert_type,
      case alert_type when 'FAILED_NON_TRACEABLE' then 'Resultado no conforme y sin trazabilidad vigente.'
        when 'FAILED' then 'Una o más comprobaciones resultaron no conformes.'
        when 'INCONCLUSIVE' then 'La regla de decisión no permite concluir conformidad.'
        else 'La comprobación no cuenta con trazabilidad vigente.' end);
  end if;
  update public.verificacion_borradores set estado='FINALIZED',finalized_at=verification_time,verificacion_id=verification_id,
    finalization_uuid=finalize_id,finalization_hash=finalize_digest where id=d.id returning version into updated_version;
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues,dispositivo_id)
  values(auth.uid(),d.cliente_id,'verificacion',verification_id::text,'INTERNAL_CHECK_FINALIZED',
    jsonb_build_object('verdict',global_verdict,'traceability',traceability_value,'scope',scope_value,
      'engineVersion',engine_value),nullif(device_id_value,''));
  return jsonb_build_object('id',verification_id,'draftId',d.id,'version',updated_version::text,
    'verdict',global_verdict,'traceability',traceability_value,'scope',scope_value,
    'alertCreated',global_verdict<>'pass' or traceability_value='non_traceable','idempotent',false);
end; $$;

revoke all on function private.mobile_plan_before_flexible_capture(uuid),private.mobile_plan(uuid),
  private.flexible_load_tolerance(uuid,uuid,uuid,numeric),private.validate_flexible_trial(uuid,uuid,jsonb,boolean),
  private.evaluate_flexible_payload(uuid,uuid,jsonb),private.mobile_save_before_validation(uuid,uuid,uuid,bigint,jsonb,uuid)
  from public,anon,authenticated,service_role;

begin;

-- Los planes siguen siendo el mecanismo interno de versionado, pero la app
-- configura una única rutina activa por equipo. Esta relación privada evita
-- exponer al cliente el ciclo técnico de borrador/publicación/asignación.
create table private.equipment_configuration_plans (
  equipo_id uuid primary key references public.equipos(id),
  plan_id uuid not null unique references public.planes(id),
  created_at timestamptz not null default now()
);

revoke all on private.equipment_configuration_plans
  from public, anon, authenticated, service_role;

create function public.ivmet_customer_configure_checks(
  equipment_id uuid,
  configuration jsonb,
  request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  actor_value text:='MOBILE:'||auth.uid()::text;
  saved private.admin_requests%rowtype;
  equipment public.equipos%rowtype;
  plan_id_value uuid;
  version_id uuid;
  previous_version_id uuid;
  test_id uuid;
  definition private.metrology_method_definitions%rowtype;
  test jsonb;
  load_value jsonb;
  result jsonb;
  digest text;
  profile text;
  unit_value text;
  maximum_capacity numeric;
  tolerance_value numeric;
  load_numeric numeric;
  frequency_value integer;
  warning_value integer;
  repetitions_value integer;
  positions_value integer;
  point_sequence integer;
  version_value integer;
  assignment_time timestamptz;
begin
  perform private.admin_assert(
    private.current_profile_role()='cliente_jefe_calidad',
    'QUALITY_MANAGER_REQUIRED'
  );
  perform private.admin_assert(
    request_id is not null
      and equipment_id is not null
      and jsonb_typeof(configuration)='object'
      and configuration-array['tests']='{}'::jsonb
      and jsonb_typeof(configuration->'tests')='array'
      and jsonb_array_length(configuration->'tests') between 1 and 3
      and octet_length(configuration::text)<=65536,
    'INVALID_CHECK_CONFIGURATION'
  );
  perform private.admin_assert(
    (select count(*)=count(distinct value->>'type')
       from jsonb_array_elements(configuration->'tests')),
    'DUPLICATE_CHECK_TYPE'
  );

  digest:=encode(sha256(convert_to(
    'checks.configure'||equipment_id::text||configuration::text,
    'UTF8'
  )),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r
    where r.request_id=ivmet_customer_configure_checks.request_id
      and r.action='customer.checks.configure';
  if found then
    perform private.admin_assert(
      saved.actor=actor_value and saved.payload_hash=digest,
      'IDEMPOTENCY_CONFLICT'
    );
    return saved.result;
  end if;

  equipment:=private.customer_equipment(equipment_id);
  perform 1 from public.equipos e where e.id=equipment.id for share;
  perform 1 from public.equipos_ivmet i where i.equipo_id=equipment.id for update;
  perform private.admin_assert(
    exists(select 1 from public.equipos_cliente ec
      where ec.equipo_id=equipment.id and ec.catalog_hash=equipment.source_hash),
    'EQUIPMENT_VALIDATION_REQUIRED'
  );

  select r.unidad,r.capacidad_max into unit_value,maximum_capacity
    from public.equipo_rangos r where r.equipo_id=equipment.id
    order by r.capacidad_max desc,r.numero_rango desc limit 1;
  perform private.admin_assert(
    unit_value is not null and maximum_capacity>0,
    'EQUIPMENT_RANGES_REQUIRED'
  );

  profile:=case when lower(concat_ws(' ',equipment.instrumento,
      equipment.tipo_instrumento,equipment.tipo_balanza,equipment.plataforma))
      ~ '(camión|camion|vehicular|truck)'
    then 'IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1'
    else 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1' end;

  perform pg_advisory_xact_lock(hashtextextended(equipment.id::text,3));
  select link.plan_id into plan_id_value
    from private.equipment_configuration_plans link
    where link.equipo_id=equipment.id for update;
  if plan_id_value is null then
    insert into public.planes(cliente_id,nombre,created_by)
      values(cid,'Configuración '||equipment.cod_metrica,auth.uid())
      returning id into plan_id_value;
    insert into private.equipment_configuration_plans(equipo_id,plan_id)
      values(equipment.id,plan_id_value);
  end if;

  select coalesce(max(v.version),0)+1 into version_value
    from public.plan_versiones v where v.plan_id=plan_id_value;
  insert into public.plan_versiones(
    plan_id,version,procedimiento_referencia,notas,created_by
  ) values(
    plan_id_value,version_value,profile,
    'Configuración guiada por equipo. Publicación y asignación automáticas.',
    auth.uid()
  ) returning id into version_id;

  for test in select value from jsonb_array_elements(configuration->'tests') loop
    perform private.admin_assert(
      test-array['type','frequencyDays','tolerance','loads','load',
        'repetitions','positions']='{}'::jsonb
        and test->>'type' in ('linearity','repeatability','eccentricity')
        and (test->>'frequencyDays') ~ '^[0-9]{1,4}$'
        and (test->>'tolerance') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
        and (test->>'frequencyDays')::integer between 1 and 3650,
      'INVALID_CHECK_CONFIGURATION'
    );
    tolerance_value:=(test->>'tolerance')::numeric;
    frequency_value:=(test->>'frequencyDays')::integer;
    warning_value:=least(30,greatest(0,frequency_value/4));
    perform private.admin_assert(tolerance_value>0,'INVALID_CHECK_TOLERANCE');

    select * into definition from private.metrology_method_definitions d
      where d.procedure_reference=profile
        and d.test_type=test->>'type' and d.active;
    perform private.admin_assert(found,'NORMATIVE_METHOD_REQUIRED');

    insert into public.plan_pruebas(
      plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,
      aviso_dias,metodo_codigo,regla_decision,fuente_tolerancia,metadata
    ) values(
      version_id,test->>'type',definition.evaluation_method,unit_value,
      frequency_value,warning_value,definition.method_code,'direct',
      'CLIENT_PROCESS',jsonb_build_object(
        'normativeProfile',profile,
        'sourceReference',definition.source_reference,
        'configurationMode','equipment-guided-v1'
      )
    ) returning id into test_id;

    point_sequence:=0;
    if test->>'type'='linearity' then
      perform private.admin_assert(
        jsonb_typeof(test->'loads')='array'
          and jsonb_array_length(test->'loads') between definition.min_points
            and least(definition.max_points,60)
          and (select count(*)=count(distinct value#>>'{}')
            from jsonb_array_elements(test->'loads')),
        'INVALID_CHECK_LOADS'
      );
      for load_value in select value from jsonb_array_elements(test->'loads') loop
        perform private.admin_assert(
          jsonb_typeof(load_value)='string'
            and (load_value#>>'{}') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$',
          'EXACT_DECIMAL_REQUIRED'
        );
        load_numeric:=(load_value#>>'{}')::numeric;
        perform private.admin_assert(
          load_numeric between 0 and maximum_capacity,
          'CHECK_LOAD_OUT_OF_RANGE'
        );
        point_sequence:=point_sequence+1;
        insert into public.plan_puntos(
          plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,
          tolerancia,metadata
        ) values(
          test_id,1,point_sequence,'L'||lpad(point_sequence::text,2,'0'),
          'Carga '||(load_value#>>'{}')||' '||unit_value,load_numeric,
          tolerance_value,'{"generated":true}'::jsonb
        );
      end loop;
    elsif test->>'type'='repeatability' then
      perform private.admin_assert(
        (test->>'load') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
          and (test->>'repetitions') ~ '^[0-9]{1,3}$',
        'INVALID_CHECK_LOADS'
      );
      load_numeric:=(test->>'load')::numeric;
      repetitions_value:=(test->>'repetitions')::integer;
      perform private.admin_assert(
        load_numeric>0 and load_numeric<=maximum_capacity
          and repetitions_value between definition.min_points
            and least(definition.max_points,10),
        'INVALID_CHECK_LOADS'
      );
      for sequence_value in 1..repetitions_value loop
        insert into public.plan_puntos(
          plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,
          tolerancia,metadata
        ) values(
          test_id,1,sequence_value,'R'||lpad(sequence_value::text,2,'0'),
          'Repetición '||sequence_value,load_numeric,tolerance_value,
          '{"generated":true}'::jsonb
        );
      end loop;
    else
      perform private.admin_assert(
        (test->>'load') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
          and (test->>'positions') ~ '^[0-9]{1,2}$',
        'INVALID_CHECK_LOADS'
      );
      load_numeric:=(test->>'load')::numeric;
      positions_value:=(test->>'positions')::integer;
      perform private.admin_assert(
        load_numeric>0 and load_numeric<=maximum_capacity
          and positions_value=case when profile='IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1'
            then 3 else 5 end,
        'INVALID_CHECK_LOADS'
      );
      for sequence_value in 1..positions_value loop
        insert into public.plan_puntos(
          plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,
          tolerancia,posicion,metadata,es_referencia
        ) values(
          test_id,1,sequence_value,'E'||lpad(sequence_value::text,2,'0'),
          case when sequence_value=1 then 'Lectura de referencia'
            else 'Posición '||sequence_value end,
          load_numeric,tolerance_value,
          case when profile='IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1'
            then (array['Inicio','Centro','Final'])[sequence_value]
            else case when sequence_value=1 then 'Centro'
              else 'Posición '||sequence_value end end,
          '{"generated":true}'::jsonb,sequence_value=1
        );
      end loop;
    end if;
  end loop;

  update public.plan_versiones set
    estado='PUBLISHED',published_at=clock_timestamp(),published_by=auth.uid()
    where id=version_id;

  assignment_time:=clock_timestamp();
  select ep.plan_version_id into previous_version_id
    from public.equipo_planes ep where ep.equipo_id=equipment.id
      and ep.vigente_hasta is null order by ep.vigente_desde desc limit 1;
  update public.equipo_planes set vigente_hasta=assignment_time
    where equipo_id=equipment.id and vigente_hasta is null;
  insert into public.equipo_planes(
    equipo_id,plan_version_id,vigente_desde,created_by
  ) values(equipment.id,version_id,assignment_time,auth.uid());
  update public.plan_versiones set
    estado='RETIRED',retired_at=assignment_time,retired_by=auth.uid()
    where plan_id=plan_id_value and id<>version_id and estado='PUBLISHED';

  result:=jsonb_build_object(
    'equipmentId',equipment.id,
    'configurationId',version_id,
    'version',version_value,
    'state','PUBLISHED',
    'replacedConfigurationId',previous_version_id
  );
  insert into public.auditoria(
    actor_id,cliente_id,entidad,entidad_id,accion,despues
  ) values(
    auth.uid(),cid,'equipment_check_configuration',equipment.id::text,
    'checks.configure',result||jsonb_build_object('tests',configuration->'tests')
  );
  insert into private.admin_requests(
    request_id,action,actor,payload_hash,result
  ) values(
    request_id,'customer.checks.configure',actor_value,digest,result
  );
  return result;
end; $$;

-- Se conserva el contrato anterior únicamente para áreas, patrones, ficha y
-- consentimiento. La creación/publicación/asignación manual de planes deja de
-- ser una capacidad pública del cliente.
alter function public.ivmet_customer_mutate(text,jsonb,uuid)
  rename to customer_mutate_before_guided_configuration;
alter function public.customer_mutate_before_guided_configuration(text,jsonb,uuid)
  set schema private;
-- La implementación heredada calificaba dos parámetros con el nombre de la
-- función pública. PostgreSQL no actualiza esas referencias dentro de PL/pgSQL
-- al renombrarla, por lo que se recompila con su nuevo nombre antes de envolverla.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'private.customer_mutate_before_guided_configuration(text,jsonb,uuid)'::regprocedure
  ) into definition;
  execute replace(
    definition,
    'ivmet_customer_mutate.',
    'customer_mutate_before_guided_configuration.'
  );
end;
$migration$;
create function public.ivmet_customer_mutate(
  action text,
  payload jsonb,
  request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if action like 'plan.%' then
    raise exception using errcode='42501',message='LEGACY_PLAN_MANAGEMENT_DISABLED';
  end if;
  return private.customer_mutate_before_guided_configuration(
    action,payload,request_id
  );
end; $$;

alter function public.ivmet_customer_read(text,jsonb)
  rename to customer_read_before_guided_configuration;
alter function public.customer_read_before_guided_configuration(text,jsonb)
  set schema private;
create function public.ivmet_customer_read(
  section text,
  filters jsonb default '{}'
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if section in ('plans','plan','method-catalog') then
    raise exception using errcode='42501',message='LEGACY_PLAN_MANAGEMENT_DISABLED';
  end if;
  return private.customer_read_before_guided_configuration(section,filters);
end; $$;

revoke all on function
  private.customer_mutate_before_guided_configuration(text,jsonb,uuid),
  private.customer_read_before_guided_configuration(text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function
  public.ivmet_customer_mutate(text,jsonb,uuid),
  public.ivmet_customer_read(text,jsonb)
  from public, anon, service_role;
grant execute on function
  public.ivmet_customer_mutate(text,jsonb,uuid),
  public.ivmet_customer_read(text,jsonb)
  to authenticated;

revoke all on function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  from public, anon, service_role;
grant execute on function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  to authenticated;

commit;

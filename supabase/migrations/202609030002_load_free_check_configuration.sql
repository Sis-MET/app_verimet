begin;

-- La configuración del jefe de calidad define pruebas, periodicidad y error
-- permisible. Las cargas se declaran al ejecutar; los puntos del plan son solo
-- referencias internas generadas a partir de la capacidad del equipo.
alter function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  rename to customer_configure_checks_before_load_free;
alter function public.customer_configure_checks_before_load_free(uuid,jsonb,uuid)
  set schema private;

-- La función original califica el parámetro request_id con el nombre público.
-- Después de renombrarla se recompila esa referencia para conservar el contrato
-- transaccional y la idempotencia que ya fueron probados.
do $migration$
declare definition text;
begin
  select pg_get_functiondef(
    'private.customer_configure_checks_before_load_free(uuid,jsonb,uuid)'::regprocedure
  ) into definition;
  execute replace(
    definition,
    'ivmet_customer_configure_checks.',
    'customer_configure_checks_before_load_free.'
  );
end;
$migration$;

create function public.ivmet_customer_configure_checks(
  equipment_id uuid,
  configuration jsonb,
  request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  equipment_value public.equipos%rowtype;
  maximum_capacity numeric;
  profile_value text;
  test_value jsonb;
  generated_test jsonb;
  generated_tests jsonb:='[]'::jsonb;
begin
  perform private.admin_assert(
    private.current_profile_role()='cliente_jefe_calidad',
    'QUALITY_MANAGER_REQUIRED'
  );
  perform private.admin_assert(
    equipment_id is not null and request_id is not null
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

  equipment_value:=private.customer_equipment(equipment_id);
  select r.capacidad_max into maximum_capacity
    from public.equipo_rangos r where r.equipo_id=equipment_value.id
    order by r.capacidad_max desc,r.numero_rango desc limit 1;
  perform private.admin_assert(maximum_capacity>0,'EQUIPMENT_RANGES_REQUIRED');
  profile_value:=case when lower(concat_ws(' ',equipment_value.instrumento,
      equipment_value.tipo_instrumento,equipment_value.tipo_balanza,equipment_value.plataforma))
      ~ '(camión|camion|vehicular|truck)'
    then 'IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1'
    else 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1' end;

  for test_value in select value from jsonb_array_elements(configuration->'tests') loop
    -- Campos de clientes anteriores se admiten para una transición segura, pero
    -- se eliminan antes de calcular el hash y nunca determinan los puntos.
    perform private.admin_assert(
      jsonb_typeof(test_value)='object'
        and test_value-array['type','frequencyDays','tolerance','loads','load','repetitions','positions']='{}'::jsonb
        and test_value->>'type' in ('linearity','repeatability','eccentricity')
        and jsonb_typeof(test_value->'frequencyDays')='string'
        and jsonb_typeof(test_value->'tolerance')='string',
      'INVALID_CHECK_CONFIGURATION'
    );
    generated_test:=jsonb_build_object(
      'type',test_value->>'type',
      'frequencyDays',test_value->>'frequencyDays',
      'tolerance',test_value->>'tolerance'
    );
    if test_value->>'type'='linearity' then
      generated_test:=generated_test||jsonb_build_object('loads',jsonb_build_array(
        '0',round(maximum_capacity*.25,9)::text,
        round(maximum_capacity*.5,9)::text,
        round(maximum_capacity*.75,9)::text,
        round(maximum_capacity,9)::text
      ));
    elsif test_value->>'type'='repeatability' then
      generated_test:=generated_test||jsonb_build_object(
        'load',round(maximum_capacity*.5,9)::text,
        'repetitions',case when profile_value='IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1' then '3' else '5' end
      );
    else
      generated_test:=generated_test||jsonb_build_object(
        'load',round(maximum_capacity/3,9)::text,
        'positions',case when profile_value='IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1' then '3' else '5' end
      );
    end if;
    generated_tests:=generated_tests||jsonb_build_array(generated_test);
  end loop;

  return private.customer_configure_checks_before_load_free(
    equipment_id,jsonb_build_object('tests',generated_tests),request_id
  );
end; $$;

revoke all on function
  private.customer_configure_checks_before_load_free(uuid,jsonb,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  from public,anon,service_role;
grant execute on function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  to authenticated;

commit;

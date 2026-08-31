begin;

-- IvMET es un sistema de comprobaciones metrológicas internas. Estos métodos no
-- emiten certificados de calibración ni sustituyen la verificación legal de IBMETRO.
create table private.metrology_method_definitions (
  procedure_reference text not null,
  test_type text not null,
  evaluation_method text not null,
  method_code text not null unique,
  name_es text not null,
  source_reference text not null,
  source_url text not null,
  engine_version text not null,
  min_points integer not null check (min_points > 0),
  max_points integer not null check (max_points between min_points and 500),
  requirements jsonb not null default '{}'::jsonb,
  claim_scope text not null default 'INTERNAL_CHECK_ONLY'
    check (claim_scope = 'INTERNAL_CHECK_ONLY'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (procedure_reference, test_type),
  check (test_type in ('linearity','repeatability','eccentricity')),
  check (evaluation_method in ('absolute_error','sample_standard_deviation','range'))
);

revoke all on private.metrology_method_definitions from public,anon,authenticated,service_role;

insert into private.metrology_method_definitions
  (procedure_reference,test_type,evaluation_method,method_code,name_es,source_reference,source_url,
   engine_version,min_points,max_points,requirements)
values
  ('IVMET-CONTROL-INTERNO-PLATAFORMA-V1','linearity','absolute_error',
   'EURAMET-CG18-V4-ERROR-INDICATION','Error de indicación',
   'EURAMET Calibration Guide No. 18, version 4.0 (11/2015), sections 5.2 and 6.2',
   'https://www.euramet.org/Media/docs/Publications/calguides/I-CAL-GUI-018_Calibration_Guide_No._18_web.pdf',
   'ivmet-internal-1.0.0',5,200,'{"loads":"distributed_working_range","officialName":"error de indicación"}'),
  ('IVMET-CONTROL-INTERNO-PLATAFORMA-V1','repeatability','sample_standard_deviation',
   'EURAMET-CG18-V4-REPEATABILITY','Repetibilidad',
   'EURAMET Calibration Guide No. 18, version 4.0 (11/2015), sections 5.1 and 6.1',
   'https://www.euramet.org/Media/docs/Publications/calguides/I-CAL-GUI-018_Calibration_Guide_No._18_web.pdf',
   'ivmet-internal-1.0.0',5,200,'{"oneLoadGroup":true,"statistic":"sample_standard_deviation"}'),
  ('IVMET-CONTROL-INTERNO-PLATAFORMA-V1','eccentricity','range',
   'EURAMET-CG18-V4-ECCENTRICITY','Excentricidad',
   'EURAMET Calibration Guide No. 18, version 4.0 (11/2015), sections 5.3 and 6.3',
   'https://www.euramet.org/Media/docs/Publications/calguides/I-CAL-GUI-018_Calibration_Guide_No._18_web.pdf',
   'ivmet-internal-1.0.0',5,50,'{"firstPointIsReference":true,"suggestedLoad":"Max/3"}'),
  ('IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1','linearity','absolute_error',
   'EURAMET-CG18-V4-ERROR-INDICATION-TRUCK','Error de indicación de báscula estática',
   'EURAMET Calibration Guide No. 18 v4.0; OIML R 76-1:2006 A.4.4',
   'https://www.oiml.org/en/files/pdf_r/r076-1-e06.pdf',
   'ivmet-internal-1.0.0',5,200,'{"loads":"distributed_working_range","staticOnly":true}'),
  ('IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1','repeatability','sample_standard_deviation',
   'EURAMET-CG18-V4-REPEATABILITY-TRUCK','Repetibilidad de báscula estática',
   'EURAMET Calibration Guide No. 18 v4.0, section 5.1',
   'https://www.euramet.org/Media/docs/Publications/calguides/I-CAL-GUI-018_Calibration_Guide_No._18_web.pdf',
   'ivmet-internal-1.0.0',3,100,'{"oneLoadGroup":true,"highCapacity":true,"staticOnly":true}'),
  ('IVMET-CONTROL-INTERNO-BASCULA-CAMIONERA-V1','eccentricity','range',
   'OIML-R76-2006-STATIC-TRUCK-SHIFT','Desplazamiento de carga en báscula estática',
   'OIML R 76-1:2006, 3.6.2.4 and A.4.7.4',
   'https://www.oiml.org/en/files/pdf_r/r076-1-e06.pdf',
   'ivmet-internal-1.0.0',3,100,'{"positions":["inicio","centro","final"],"reverseWhenApplicable":true,"staticOnly":true}');

-- Compatibilidad con la barrera de publicación creada en la migración de operaciones.
insert into private.approved_metrology_methods
  (method,procedure_reference,procedure_hash,golden_tests_reference,engine_version,approved_by,approved_at)
select distinct d.evaluation_method,d.procedure_reference,
  encode(sha256(convert_to(d.procedure_reference||':'||d.engine_version,'UTF8')),'hex'),
  'scripts/test-mobile-db.mjs#normative-metrology',d.engine_version,
  'IvMET normative baseline - internal checks only',now()
from private.metrology_method_definitions d
on conflict (method,procedure_reference) do nothing;

alter table public.plan_pruebas
  add column metodo_codigo varchar(100),
  add column regla_decision varchar(30) not null default 'direct',
  add column incertidumbre_expandida numeric(19,9),
  add column fuente_tolerancia varchar(40) not null default 'CLIENT_PROCESS',
  add column alcance_declaracion varchar(40) not null default 'INTERNAL_CHECK_ONLY',
  add constraint plan_pruebas_regla_ck check (regla_decision in ('direct','guard_band')),
  add constraint plan_pruebas_incertidumbre_ck check (
    incertidumbre_expandida is null or incertidumbre_expandida >= 0
  ),
  add constraint plan_pruebas_fuente_tolerancia_ck check (
    fuente_tolerancia in ('CLIENT_PROCESS','MANUFACTURER','CALIBRATION_REPORT','OIML_IN_SERVICE_REFERENCE')
  ),
  add constraint plan_pruebas_alcance_ck check (alcance_declaracion='INTERNAL_CHECK_ONLY'),
  add constraint plan_pruebas_guard_band_ck check (
    regla_decision<>'guard_band' or incertidumbre_expandida>0
  );

alter table public.plan_puntos add column es_referencia boolean not null default false;

alter table public.verificaciones
  drop constraint verificaciones_veredicto_ck,
  add constraint verificaciones_veredicto_ck check (
    veredicto_global is null or veredicto_global in ('pass','fail','inconclusive')
  ),
  add column alcance_declaracion varchar(40) not null default 'INTERNAL_CHECK_ONLY'
    check (alcance_declaracion='INTERNAL_CHECK_ONLY'),
  add column motor_version varchar(50),
  add column regla_decision_resumen varchar(30);

alter table public.pruebas
  drop constraint pruebas_veredicto_ck,
  add constraint pruebas_veredicto_ck check (
    veredicto is null or veredicto in ('pass','fail','inconclusive')
  ),
  add column metodo_codigo varchar(100),
  add column regla_decision varchar(30),
  add column fuente_tolerancia varchar(40),
  add column incertidumbre_expandida numeric(19,9),
  add column valor_metrica numeric(19,9),
  add column evaluacion_snapshot jsonb not null default '{}'::jsonb;

alter table public.lecturas
  drop constraint lecturas_veredicto_ck,
  add constraint lecturas_veredicto_ck check (veredicto in ('pass','fail','inconclusive'));

alter table public.verificacion_borradores
  add column finalization_uuid uuid,
  add column finalization_hash text,
  add constraint verificacion_borradores_finalization_uuid_uq unique(finalization_uuid),
  add constraint verificacion_borradores_finalization_hash_ck check (
    finalization_hash is null or finalization_hash ~ '^[0-9a-f]{64}$'
  );

create or replace function private.mass_convert(value numeric,source_unit text,target_unit text)
returns numeric language plpgsql immutable set search_path='' as $$
declare kilograms numeric; source text:=lower(btrim(source_unit)); target text:=lower(btrim(target_unit));
begin
  kilograms:=case source when 't' then value*1000 when 'kg' then value when 'g' then value/1000
    when 'mg' then value/1000000 else null end;
  if kilograms is null then return null; end if;
  return case target when 't' then kilograms/1000 when 'kg' then kilograms when 'g' then kilograms*1000
    when 'mg' then kilograms*1000000 else null end;
end; $$;

create or replace function private.oiml_accuracy_class(raw_value text)
returns text language plpgsql immutable set search_path='' as $$
declare value text:=upper(coalesce(raw_value,''));
begin
  if value ~ '(^|[^I])IIII([^I]|$)' or value ~ '(^|[^0-9])4([^0-9]|$)' then return 'IIII'; end if;
  if value ~ '(^|[^I])III([^I]|$)' or value ~ '(^|[^0-9])3([^0-9]|$)' then return 'III'; end if;
  if value ~ '(^|[^I])II([^I]|$)' or value ~ '(^|[^0-9])2([^0-9]|$)' then return 'II'; end if;
  if value ~ '(^|[^I])I([^I]|$)' or value ~ '(^|[^0-9])1([^0-9]|$)' then return 'I'; end if;
  return null;
end; $$;

create or replace function private.oiml_r76_mpe(load_value numeric,verification_interval numeric,
  accuracy_class text,in_service boolean default true) returns numeric
language plpgsql immutable set search_path='' as $$
declare intervals numeric; factor numeric; class_value text:=private.oiml_accuracy_class(accuracy_class);
begin
  if load_value<0 or verification_interval<=0 or class_value is null then return null; end if;
  intervals:=load_value/verification_interval;
  factor:=case class_value
    when 'I' then case when intervals<=50000 then 0.5 when intervals<=200000 then 1.0 else 1.5 end
    when 'II' then case when intervals<=5000 then 0.5 when intervals<=20000 then 1.0 when intervals<=100000 then 1.5 else null end
    when 'III' then case when intervals<=500 then 0.5 when intervals<=2000 then 1.0 when intervals<=10000 then 1.5 else null end
    when 'IIII' then case when intervals<=50 then 0.5 when intervals<=200 then 1.0 when intervals<=1000 then 1.5 else null end
  end;
  if factor is null then return null; end if;
  return verification_interval*factor*(case when in_service then 2 else 1 end);
end; $$;

create or replace function private.decision_verdict(metric numeric,tolerance numeric,decision_rule text,
  expanded_uncertainty numeric default null) returns text
language plpgsql immutable set search_path='' as $$
begin
  if metric is null or tolerance is null or metric<0 or tolerance<0 then return null; end if;
  if decision_rule='direct' then return case when metric<=tolerance then 'pass' else 'fail' end; end if;
  if decision_rule='guard_band' and expanded_uncertainty>0 then
    if metric+expanded_uncertainty<=tolerance then return 'pass'; end if;
    if greatest(metric-expanded_uncertainty,0)>tolerance then return 'fail'; end if;
    return 'inconclusive';
  end if;
  return null;
end; $$;

create or replace function private.worst_verdict(current_value text,next_value text) returns text
language sql immutable set search_path='' as $$
  select case when 'fail'=any(array[current_value,next_value]) then 'fail'
    when 'inconclusive'=any(array[current_value,next_value]) then 'inconclusive'
    when 'pass'=any(array[current_value,next_value]) then 'pass' else null end;
$$;

create or replace function private.effective_point_tolerance(equipment_id uuid,test_id uuid,point_id uuid)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare trial public.plan_pruebas%rowtype; point_value public.plan_puntos%rowtype;
  equipment_value public.equipos%rowtype; range_value public.equipo_rangos%rowtype;
  load_kg numeric; e_kg numeric; mpe_kg numeric;
begin
  select * into trial from public.plan_pruebas where id=test_id;
  select * into point_value from public.plan_puntos where id=point_id and plan_prueba_id=test_id;
  if trial.id is null or point_value.id is null then return null; end if;
  if trial.fuente_tolerancia<>'OIML_IN_SERVICE_REFERENCE' then return point_value.tolerancia; end if;
  if trial.tipo<>'linearity' then return null; end if;
  select * into equipment_value from public.equipos where id=equipment_id;
  load_kg:=private.mass_convert(point_value.carga_nominal,trial.unidad,'kg');
  if load_kg is null then return null; end if;
  select r.* into range_value from public.equipo_rangos r where r.equipo_id=equipment_id
    and r.intervalo_verificacion is not null
    and private.mass_convert(r.capacidad_max,r.unidad,'kg')>=load_kg
    order by private.mass_convert(r.capacidad_max,r.unidad,'kg'),r.numero_rango limit 1;
  if range_value.id is null then return null; end if;
  e_kg:=private.mass_convert(range_value.intervalo_verificacion,range_value.unidad,'kg');
  mpe_kg:=private.oiml_r76_mpe(load_kg,e_kg,equipment_value.clase,true);
  return private.mass_convert(mpe_kg,'kg',trial.unidad);
end; $$;

create or replace function private.validate_normative_plan_content() returns trigger
language plpgsql security definer set search_path='' as $$
declare trial record; definition private.metrology_method_definitions%rowtype; points_count integer;
begin
  if old.estado='DRAFT' and new.estado='PUBLISHED' and exists(
    select 1 from private.metrology_method_definitions d where d.procedure_reference=new.procedimiento_referencia and d.active
  ) then
    for trial in select * from public.plan_pruebas where plan_version_id=new.id loop
      select * into definition from private.metrology_method_definitions d
        where d.procedure_reference=new.procedimiento_referencia and d.test_type=trial.tipo and d.active;
      perform private.admin_assert(found and trial.metodo_evaluacion=definition.evaluation_method
        and trial.metodo_codigo=definition.method_code,'NORMATIVE_METHOD_MISMATCH');
      select count(*) into points_count from public.plan_puntos p where p.plan_prueba_id=trial.id;
      perform private.admin_assert(points_count between definition.min_points and definition.max_points,'NORMATIVE_POINTS_REQUIRED');
      perform private.admin_assert(trial.regla_decision<>'guard_band' or trial.incertidumbre_expandida>0,'DECISION_RULE_INVALID');
      perform private.admin_assert(trial.fuente_tolerancia<>'OIML_IN_SERVICE_REFERENCE' or trial.tipo='linearity','OIML_REFERENCE_NOT_APPLICABLE');
      if trial.tipo='repeatability' then
        perform private.admin_assert((select count(distinct grupo)=1 and count(distinct carga_nominal)=1
          from public.plan_puntos where plan_prueba_id=trial.id),'REPEATABILITY_ONE_LOAD_REQUIRED');
      elsif trial.tipo='eccentricity' then
        perform private.admin_assert((select count(*)=1 from public.plan_puntos where plan_prueba_id=trial.id and es_referencia),
          'ECCENTRICITY_REFERENCE_REQUIRED');
      end if;
    end loop;
  end if;
  return new;
end; $$;

create trigger plan_versiones_00_normative_validation
before update on public.plan_versiones
for each row execute function private.validate_normative_plan_content();

-- El cliente elige perfil, pruebas, frecuencia, cargas y límites. El método y
-- la fórmula se resuelven desde el catálogo controlado y no desde el payload.
create or replace function private.customer_plan_save(payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); target uuid:=nullif(payload->>'id','')::uuid;
  plan_id_value uuid:=nullif(payload->>'planId','')::uuid; v public.plan_versiones%rowtype;
  t jsonb; pt jsonb; trial uuid; seq int; current_name text; profile text:=payload->>'procedureReference';
  definition private.metrology_method_definitions%rowtype; rule_value text; source_value text; uncertainty_value numeric;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(length(btrim(payload->>'name')) between 1 and 200
    and jsonb_typeof(payload->'tests')='array' and jsonb_array_length(payload->'tests') between 1 and 3,'PLAN_TESTS_REQUIRED');
  perform private.admin_assert(exists(select 1 from private.metrology_method_definitions d
    where d.procedure_reference=profile and d.active),'NORMATIVE_PROFILE_REQUIRED');
  if target is null then
    if plan_id_value is null then
      insert into public.planes(cliente_id,nombre,created_by) values(cid,btrim(payload->>'name'),auth.uid()) returning id into plan_id_value;
    else
      select p.nombre into current_name from public.planes p where p.id=plan_id_value and p.cliente_id=cid and p.activo for update;
      perform private.admin_assert(found,'PLAN_NOT_ACCESSIBLE');
      perform private.admin_assert(btrim(payload->>'name')=current_name,'PLAN_NAME_IS_IMMUTABLE');
    end if;
    insert into public.plan_versiones(plan_id,version,procedimiento_referencia,notas,created_by)
      select plan_id_value,coalesce(max(pv.version),0)+1,profile,payload->>'notes',auth.uid()
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
    update public.plan_versiones set procedimiento_referencia=profile,notas=payload->>'notes',draft_revision=draft_revision+1 where id=target;
  end if;
  for t in select value from jsonb_array_elements(payload->'tests') loop
    select * into definition from private.metrology_method_definitions d
      where d.procedure_reference=profile and d.test_type=t->>'type' and d.active;
    perform private.admin_assert(found,'NORMATIVE_METHOD_REQUIRED');
    perform private.admin_assert(coalesce(t->>'method',definition.evaluation_method)=definition.evaluation_method,'NORMATIVE_METHOD_MISMATCH');
    perform private.admin_assert(jsonb_typeof(t->'points')='array'
      and jsonb_array_length(t->'points') between definition.min_points and definition.max_points
      and (t->>'frequencyDays') ~ '^[0-9]{1,4}$' and (t->>'warningDays') ~ '^[0-9]{1,4}$'
      and (t->>'frequencyDays')::int between 1 and 3650 and (t->>'warningDays')::int<(t->>'frequencyDays')::int
      and length(btrim(t->>'unit')) between 1 and 20,'INVALID_PLAN_TEST');
    rule_value:=coalesce(nullif(t->>'decisionRule',''),'direct');
    source_value:=coalesce(nullif(t->>'toleranceSource',''),'CLIENT_PROCESS');
    perform private.admin_assert(rule_value in ('direct','guard_band')
      and source_value in ('CLIENT_PROCESS','MANUFACTURER','CALIBRATION_REPORT','OIML_IN_SERVICE_REFERENCE')
      and (source_value<>'OIML_IN_SERVICE_REFERENCE' or t->>'type'='linearity'),'DECISION_RULE_INVALID');
    perform private.admin_assert(jsonb_typeof(coalesce(t->'uncertainty','""'::jsonb))='string'
      and (coalesce(t->>'uncertainty','')='' or (t->>'uncertainty') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'),
      'EXACT_DECIMAL_REQUIRED');
    uncertainty_value:=nullif(t->>'uncertainty','')::numeric;
    perform private.admin_assert(rule_value<>'guard_band' or uncertainty_value>0,'DECISION_RULE_INVALID');
    insert into public.plan_pruebas(plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,aviso_dias,
      metodo_codigo,regla_decision,incertidumbre_expandida,fuente_tolerancia,metadata)
    values(target,t->>'type',definition.evaluation_method,btrim(t->>'unit'),(t->>'frequencyDays')::int,
      (t->>'warningDays')::int,definition.method_code,rule_value,uncertainty_value,source_value,
      jsonb_build_object('normativeProfile',profile,'sourceReference',definition.source_reference)) returning id into trial;
    seq:=0;
    for pt in select value from jsonb_array_elements(t->'points') loop
      seq:=seq+1;
      perform private.admin_assert(jsonb_typeof(pt->'load')='string' and (pt->>'load') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
        and jsonb_typeof(pt->'tolerance')='string' and (pt->>'tolerance') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$','EXACT_DECIMAL_REQUIRED');
      perform private.admin_assert((pt->>'group') ~ '^[0-9]{1,4}$' and (pt->>'group')::int>0
        and length(btrim(pt->>'label')) between 1 and 200 and length(btrim(pt->>'code')) between 1 and 100
        and jsonb_typeof(coalesce(pt->'metadata','{}'))='object','INVALID_PLAN_POINT');
      insert into public.plan_puntos(plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,tolerancia,posicion,direccion,metadata,es_referencia)
      values(trial,(pt->>'group')::int,seq,pt->>'code',pt->>'label',(pt->>'load')::numeric,(pt->>'tolerance')::numeric,
        nullif(btrim(pt->>'position'),''),nullif(btrim(pt->>'direction'),''),coalesce(pt->'metadata','{}'),
        case when t->>'type'='eccentricity' then seq=1 else false end);
    end loop;
  end loop;
  return target;
end; $$;

create or replace function private.mobile_plan(version_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',v.id,'name',p.nombre,'version',v.version,'state',v.estado,
    'procedure',v.procedimiento_referencia,'engineVersion','ivmet-internal-1.0.0',
    'claimScope','INTERNAL_CHECK_ONLY',
    'notice','Comprobación interna. No constituye calibración acreditada ni verificación legal.',
    'finalizationEnabled',v.estado in ('PUBLISHED','RETIRED') and exists(select 1 from public.plan_pruebas x where x.plan_version_id=v.id)
      and not exists(select 1 from public.plan_pruebas x where x.plan_version_id=v.id and not exists(
        select 1 from private.metrology_method_definitions d where d.procedure_reference=v.procedimiento_referencia
          and d.test_type=x.tipo and d.evaluation_method=x.metodo_evaluacion and d.method_code=x.metodo_codigo and d.active)),
    'blockReason',case when not exists(select 1 from public.plan_pruebas x where x.plan_version_id=v.id) or exists(
      select 1 from public.plan_pruebas x where x.plan_version_id=v.id and not exists(select 1 from private.metrology_method_definitions d
        where d.procedure_reference=v.procedimiento_referencia and d.test_type=x.tipo and d.method_code=x.metodo_codigo and d.active))
      then 'OFFICIAL_ENGINE_NOT_RELEASED' end,
    'tests',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'type',t.tipo,'method',t.metodo_evaluacion,
      'methodCode',t.metodo_codigo,'decisionRule',t.regla_decision,'expandedUncertainty',t.incertidumbre_expandida::text,
      'toleranceSource',t.fuente_tolerancia,'unit',t.unidad,'frequencyDays',t.frecuencia_dias,'warningDays',t.aviso_dias,
      'metadata',t.metadata,'points',coalesce((select jsonb_agg(jsonb_build_object('id',pt.id,'code',pt.codigo,
        'label',pt.etiqueta,'group',pt.grupo,'order',pt.orden,'load',pt.carga_nominal::text,'tolerance',pt.tolerancia::text,
        'position',pt.posicion,'direction',pt.direccion,'reference',pt.es_referencia,'metadata',pt.metadata) order by pt.orden)
        from public.plan_puntos pt where pt.plan_prueba_id=t.id),'[]')) order by case t.tipo when 'linearity' then 1 when 'repeatability' then 2 else 3 end)
      from public.plan_pruebas t where t.plan_version_id=v.id),'[]'))
  from public.plan_versiones v join public.planes p on p.id=v.plan_id where v.id=version_id;
$$;

create or replace function private.metrology_catalog_json() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('engineVersion','ivmet-internal-1.0.0','claimScope','INTERNAL_CHECK_ONLY',
    'notice','Los métodos están destinados al control interno. La frecuencia y los límites pertenecen al cliente.',
    'profiles',coalesce((select jsonb_agg(profile order by profile->>'code') from (
      select jsonb_build_object('code',d.procedure_reference,
        'name',case d.procedure_reference when 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1' then 'Balanzas y plataformas estáticas'
          else 'Básculas camioneras estáticas' end,
        'tests',jsonb_agg(jsonb_build_object('type',d.test_type,'method',d.evaluation_method,'methodCode',d.method_code,
          'name',d.name_es,'source',d.source_reference,'minPoints',d.min_points,'maxPoints',d.max_points,
          'requirements',d.requirements) order by d.test_type)) profile
      from private.metrology_method_definitions d where d.active group by d.procedure_reference) catalog),'[]'));
$$;

-- Catálogo autenticado para el constructor de planes del jefe de calidad.
alter function public.ivmet_customer_read(text,jsonb) rename to customer_read_before_normative;
alter function public.customer_read_before_normative(text,jsonb) set schema private;
create function public.ivmet_customer_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if section='method-catalog' then
    perform private.mobile_require();
    return private.metrology_catalog_json();
  end if;
  result:=private.customer_read_before_normative(section,filters);
  if section='plans' then result:=jsonb_set(result,'{finalizationEnabled}','true'::jsonb); end if;
  return result;
end; $$;

create or replace function private.equipment_test_schedule(target_equipment uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  with assigned as (
    select t.id,t.tipo,t.frecuencia_dias,t.aviso_dias from public.equipo_planes ep
      join public.plan_versiones v on v.id=ep.plan_version_id
      join public.plan_pruebas t on t.plan_version_id=v.id
    where ep.equipo_id=target_equipment and ep.vigente_hasta is null and v.estado='PUBLISHED'
  ), status as (
    select a.*,last_run.realizado_at last_traceable_at,
      coalesce(last_run.realizado_at,(select vigente_desde from public.equipo_planes where equipo_id=target_equipment and vigente_hasta is null))
        + make_interval(days=>a.frecuencia_dias) due_at
    from assigned a left join lateral (
      select max(v.realizado_at) realizado_at from public.verificaciones v join public.pruebas p on p.verificacion_id=v.id
      where v.equipo_id=target_equipment and v.estado='ACTIVE' and v.trazabilidad='traceable'
        and p.tipo=a.tipo and p.estado_ejecucion='executed'
    ) last_run on true
  ) select coalesce(jsonb_agg(jsonb_build_object('type',tipo,'lastTraceableAt',last_traceable_at,'dueAt',due_at,
      'warningAt',due_at-make_interval(days=>aviso_dias),'state',case when due_at<now() then 'OVERDUE'
        when due_at-make_interval(days=>aviso_dias)<=now() then 'DUE_SOON' else 'CURRENT' end) order by tipo),'[]') from status;
$$;

-- Conserva el contrato anterior y añade capacidad del motor y vencimientos derivados.
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_normative;
alter function public.mobile_read_before_normative(text,jsonb) set schema private;
create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  result:=private.mobile_read_before_normative(section,filters);
  if section='bootstrap' then
    result:=result||jsonb_build_object('finalizationEnabled',true,'metrologyContractVersion',1,
      'engineVersion','ivmet-internal-1.0.0');
  elsif section='equipment' then
    result:=result||jsonb_build_object('schedule',private.equipment_test_schedule((filters->>'equipmentId')::uuid));
  end if;
  return result;
end; $$;

create or replace function private.evaluate_draft_payload(target_equipment_id uuid,target_plan_version_id uuid,payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare trial record; point_record record; item jsonb; reading_value jsonb; readings_value jsonb;
  indication_value numeric; zero_value numeric; error_value numeric; metric_value numeric; tolerance_value numeric;
  min_tolerance numeric; max_error numeric; mean_value numeric; deviation_value numeric; range_value numeric;
  reference_point uuid; reference_indication numeric; reading_verdict text; test_verdict text;
  global_verdict text:='pass'; executed_count integer:=0; omitted_count integer:=0; tests_value jsonb:='[]'::jsonb;
begin
  for trial in select t.* from public.plan_pruebas t where t.plan_version_id=target_plan_version_id
    order by case t.tipo when 'linearity' then 1 when 'repeatability' then 2 else 3 end loop
    item:=null;
    select value into item from jsonb_array_elements(payload->'tests') where value->>'id'=trial.id::text;
    perform private.admin_assert(item is not null,'MISSING_TESTS');
    if (item->>'omitted')::boolean then
      perform private.admin_assert(length(btrim(coalesce(item->>'reason',''))) between 1 and 500,'OMISSION_REASON_REQUIRED');
      omitted_count:=omitted_count+1;
      tests_value:=tests_value||jsonb_build_array(jsonb_build_object(
        'planTestId',trial.id,'type',trial.tipo,'omitted',true,'reason',btrim(item->>'reason'),
        'method',trial.metodo_evaluacion,'methodCode',trial.metodo_codigo,'unit',trial.unidad,
        'decisionRule',trial.regla_decision,'toleranceSource',trial.fuente_tolerancia,
        'expandedUncertainty',trial.incertidumbre_expandida::text,'readings','[]'::jsonb));
      continue;
    end if;

    executed_count:=executed_count+1;
    perform private.admin_assert(jsonb_typeof(item->'readings')='array'
      and jsonb_array_length(item->'readings')=(select count(*) from public.plan_puntos where plan_prueba_id=trial.id)
      and not exists(select 1 from jsonb_array_elements(item->'readings') x
        where coalesce(x->>'indication','')='' or jsonb_typeof(x->'indication')<>'string'),
      'INCOMPLETE_TEST');
    select avg((r->>'indication')::numeric),stddev_samp((r->>'indication')::numeric),
      max((r->>'indication')::numeric)-min((r->>'indication')::numeric)
      into mean_value,deviation_value,range_value from jsonb_array_elements(item->'readings') r;
    test_verdict:='pass'; min_tolerance:=null; max_error:=0; metric_value:=null;
    reference_point:=null; reference_indication:=null; readings_value:='[]'::jsonb;
    if trial.tipo='eccentricity' then
      select id into reference_point from public.plan_puntos where plan_prueba_id=trial.id and es_referencia limit 1;
      select (r->>'indication')::numeric into reference_indication from jsonb_array_elements(item->'readings') r
        where r->>'pointId'=reference_point::text;
      perform private.admin_assert(reference_indication is not null,'ECCENTRICITY_REFERENCE_REQUIRED');
    end if;
    for point_record in select * from public.plan_puntos where plan_prueba_id=trial.id order by orden loop
      reading_value:=null;
      select value into reading_value from jsonb_array_elements(item->'readings') where value->>'pointId'=point_record.id::text;
      perform private.admin_assert(reading_value is not null,'INCOMPLETE_TEST');
      indication_value:=(reading_value->>'indication')::numeric;
      tolerance_value:=private.effective_point_tolerance(target_equipment_id,trial.id,point_record.id);
      perform private.admin_assert(tolerance_value is not null,'OIML_EQUIPMENT_DATA_REQUIRED');
      min_tolerance:=case when min_tolerance is null then tolerance_value else least(min_tolerance,tolerance_value) end;
      error_value:=case when trial.tipo='eccentricity' then indication_value-reference_indication
        when trial.tipo='repeatability' then indication_value-mean_value else indication_value-point_record.carga_nominal end;
      perform private.admin_assert(abs(error_value)<10000000000,'MEASUREMENT_OUT_OF_RANGE');
      max_error:=greatest(max_error,abs(error_value));
      if trial.tipo in ('linearity','eccentricity') then
        reading_verdict:=private.decision_verdict(abs(error_value),tolerance_value,trial.regla_decision,trial.incertidumbre_expandida);
        perform private.admin_assert(reading_verdict is not null,'DECISION_RULE_INVALID');
        test_verdict:=private.worst_verdict(test_verdict,reading_verdict);
      end if;
    end loop;
    if trial.tipo='repeatability' then
      metric_value:=deviation_value;
      test_verdict:=private.decision_verdict(metric_value,min_tolerance,trial.regla_decision,trial.incertidumbre_expandida);
    else metric_value:=max_error; end if;
    perform private.admin_assert(test_verdict is not null,'DECISION_RULE_INVALID');
    global_verdict:=private.worst_verdict(global_verdict,test_verdict);

    for point_record in select * from public.plan_puntos where plan_prueba_id=trial.id order by orden loop
      select value into reading_value from jsonb_array_elements(item->'readings') where value->>'pointId'=point_record.id::text;
      indication_value:=(reading_value->>'indication')::numeric;
      zero_value:=nullif(reading_value->>'zero','')::numeric;
      tolerance_value:=private.effective_point_tolerance(target_equipment_id,trial.id,point_record.id);
      error_value:=case when trial.tipo='eccentricity' then indication_value-reference_indication
        when trial.tipo='repeatability' then indication_value-mean_value else indication_value-point_record.carga_nominal end;
      reading_verdict:=case when trial.tipo='repeatability' then test_verdict else
        private.decision_verdict(abs(error_value),tolerance_value,trial.regla_decision,trial.incertidumbre_expandida) end;
      readings_value:=readings_value||jsonb_build_array(jsonb_build_object(
        'pointId',point_record.id,'group',point_record.grupo,'order',point_record.orden,'code',point_record.codigo,
        'label',point_record.etiqueta,'load',point_record.carga_nominal::text,'indication',indication_value::text,
        'zero',zero_value::text,'error',error_value::text,'tolerance',tolerance_value::text,
        'verdict',reading_verdict,'reference',point_record.es_referencia));
    end loop;
    tests_value:=tests_value||jsonb_build_array(jsonb_build_object(
      'planTestId',trial.id,'type',trial.tipo,'omitted',false,'method',trial.metodo_evaluacion,
      'methodCode',trial.metodo_codigo,'unit',trial.unidad,'tolerance',min_tolerance::text,
      'verdict',test_verdict,'maxAbsoluteError',max_error::text,'mean',mean_value::text,
      'standardDeviation',deviation_value::text,'range',range_value::text,'metric',metric_value::text,
      'decisionRule',trial.regla_decision,'toleranceSource',trial.fuente_tolerancia,
      'expandedUncertainty',trial.incertidumbre_expandida::text,'readings',readings_value));
  end loop;
  perform private.admin_assert(executed_count>0,'ALL_TESTS_OMITTED');
  return jsonb_build_object('scope',case when omitted_count>0 then 'partial' else 'complete' end,
    'verdict',global_verdict,'executedCount',executed_count,'omittedCount',omitted_count,'tests',tests_value);
end; $$;

create or replace function public.ivmet_mobile_finalize_draft(draft_id uuid,expected_version bigint,
  finalize_id uuid,app_version_value text default null,device_id_value text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); d public.verificacion_borradores%rowtype; verification_id uuid;
  verification_time timestamptz:=clock_timestamp(); payload_digest text; finalize_digest text;
  traceability_value text; global_verdict text; scope_value text; selected_certificates integer;
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
  evaluation:=private.evaluate_draft_payload(d.equipo_id,d.plan_version_id,d.payload);
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
    d.context_snapshot->'plan',nullif(app_version_value,''),nullif(device_id_value,''),'ivmet-internal-1.0.0','mixed');

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
        jsonb_build_object('claimScope','INTERNAL_CHECK_ONLY','engineVersion','ivmet-internal-1.0.0'));
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
        'engineVersion','ivmet-internal-1.0.0','procedureReference',d.context_snapshot->'plan'->>'procedure'));
    for reading_value in select value from jsonb_array_elements(item->'readings') loop
      insert into public.lecturas(prueba_id,plan_punto_id,grupo,orden,punto_codigo,etiqueta,carga_nominal,indicacion,
        retorno_cero,error,tolerancia,veredicto,metadata)
      values(test_id,(reading_value->>'pointId')::uuid,(reading_value->>'group')::int,(reading_value->>'order')::int,
        reading_value->>'code',reading_value->>'label',(reading_value->>'load')::numeric,
        (reading_value->>'indication')::numeric,nullif(reading_value->>'zero','')::numeric,
        (reading_value->>'error')::numeric,(reading_value->>'tolerance')::numeric,reading_value->>'verdict',
        jsonb_build_object('reference',(reading_value->>'reference')::boolean,'decisionRule',item->>'decisionRule',
          'limitSource',item->>'toleranceSource'));
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
      'engineVersion','ivmet-internal-1.0.0'),nullif(device_id_value,''));
  return jsonb_build_object('id',verification_id,'draftId',d.id,'version',updated_version::text,
    'verdict',global_verdict,'traceability',traceability_value,'scope',scope_value,
    'alertCreated',global_verdict<>'pass' or traceability_value='non_traceable','idempotent',false);
end; $$;

revoke all on function private.mass_convert(numeric,text,text),private.oiml_accuracy_class(text),
  private.oiml_r76_mpe(numeric,numeric,text,boolean),private.decision_verdict(numeric,numeric,text,numeric),
  private.worst_verdict(text,text),private.effective_point_tolerance(uuid,uuid,uuid),
  private.validate_normative_plan_content(),private.customer_plan_save(jsonb),private.mobile_plan(uuid),
  private.metrology_catalog_json(),private.customer_read_before_normative(text,jsonb),
  private.equipment_test_schedule(uuid),private.mobile_read_before_normative(text,jsonb),
  private.evaluate_draft_payload(uuid,uuid,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.ivmet_customer_read(text,jsonb),public.ivmet_mobile_read(text,jsonb),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text) from public,anon,service_role;
grant execute on function public.ivmet_customer_read(text,jsonb),public.ivmet_mobile_read(text,jsonb),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text) to authenticated;

commit;

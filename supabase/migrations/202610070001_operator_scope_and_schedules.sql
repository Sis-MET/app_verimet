begin;

-- ============================================================================
-- 1. Balanzas asignadas a cada operador
-- ============================================================================
--
-- La planta sigue siendo el primer filtro (`usuario_plantas`). Dentro de ella,
-- el jefe de calidad decide qué balanzas verifica cada operador. Un operador
-- sin asignaciones no ve ninguna: la restricción es explícita, no un "todas"
-- implícito que desaparece al asignar la primera.
create table public.usuario_equipos (
  usuario_id uuid not null references public.perfiles(id) on delete restrict,
  equipo_id uuid not null references public.equipos(id) on delete restrict,
  asignado_por uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (usuario_id, equipo_id)
);

create index usuario_equipos_equipo_idx on public.usuario_equipos (equipo_id, usuario_id);

alter table public.usuario_equipos enable row level security;
revoke all on public.usuario_equipos from public, anon, authenticated;
grant select on public.usuario_equipos to authenticated;
create policy usuario_equipos_select_self
on public.usuario_equipos for select to authenticated
using (usuario_id = auth.uid());

-- El jefe de calidad ve todas las balanzas de sus plantas; el operador, solo
-- las asignadas. El alcance de planta y licencia se comprueba aparte.
create function private.equipment_in_scope(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.current_profile_role()='cliente_jefe_calidad'
    or exists(select 1 from public.usuario_equipos ue
      where ue.usuario_id=auth.uid() and ue.equipo_id=target);
$$;

-- Punto único por el que pasan la ficha, la validación, la configuración y la
-- lectura de una balanza concreta.
create or replace function private.customer_equipment(target uuid) returns public.equipos
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); e public.equipos%rowtype;
begin
  select eq.* into e from public.equipos eq join public.plantas p on p.id=eq.planta_id
    join public.equipos_ivmet i on i.equipo_id=eq.id where eq.id=target and eq.cliente_id=cid
    and eq.activo and p.activo and eq.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY'
    and private.can_access_plant(eq.planta_id) and private.equipment_in_scope(eq.id);
  perform private.admin_assert(found,'EQUIPMENT_NOT_ACCESSIBLE');
  return e;
end; $$;

-- El operador conserva acceso a lo que él mismo capturó aunque después se le
-- retire la balanza.
create or replace function private.can_read_verification(target_verification_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.verificaciones v where v.id=target_verification_id
    and private.current_profile_role() in ('cliente_operador','cliente_jefe_calidad')
    and private.can_access_client(v.cliente_id) and private.can_access_plant(v.planta_id)
    and (private.equipment_in_scope(v.equipo_id) or v.capturado_por=auth.uid()));
$$;

-- Defensa en profundidad: las lecturas REST directas respetan el mismo alcance.
drop policy equipos_select_assigned on public.equipos;
create policy equipos_select_assigned
on public.equipos for select to authenticated
using (
  activo
  and estado_catalogo = 'READY'
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
  and private.equipment_in_scope(id)
);

drop policy equipo_rangos_select_assigned on public.equipo_rangos;
create policy equipo_rangos_select_assigned
on public.equipo_rangos for select to authenticated
using (
  exists (
    select 1 from public.equipos e
    where e.id = equipo_rangos.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
      and private.equipment_in_scope(e.id)
  )
);

drop policy equipos_ivmet_select_assigned on public.equipos_ivmet;
create policy equipos_ivmet_select_assigned
on public.equipos_ivmet for select to authenticated
using (
  habilitado
  and estado_configuracion = 'READY'
  and exists (
    select 1 from public.equipos e
    where e.id = equipos_ivmet.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
      and private.equipment_in_scope(e.id)
  )
);

drop policy equipo_planes_select_assigned on public.equipo_planes;
create policy equipo_planes_select_assigned
on public.equipo_planes for select to authenticated
using (
  exists (
    select 1 from public.equipos e
    where e.id = equipo_planes.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
      and private.equipment_in_scope(e.id)
  )
);

-- ============================================================================
-- 2. Periodicidad configurable de cada prueba
-- ============================================================================
--
-- Una regla describe cuándo toca la verificación intermedia:
--
--   fixed    fechas fijas de calendario desde `startsOn`:
--            day   cada N días
--            week  cada N semanas, los días ISO de `weekdays` (1 = lunes)
--            month cada N meses, el día `monthDay` (se recorta al último día
--                  del mes) o el `weekOfMonth`-ésimo `weekday` (5 = último)
--            year  cada N años, en el mes de `startsOn`, igual que month
--   rolling  N días/semanas/meses/años después de la última verificación
--            realizada (o de la asignación de la configuración).
--
-- `warningDays` abre la ventana de cada fecha: una verificación hecha desde
-- `fecha - warningDays` y antes de que abra la ventana siguiente cuenta para
-- esa fecha. Las ventanas son contiguas y no se solapan, así que una misma
-- verificación nunca cumple dos fechas.
--
-- La app replica estas reglas en `check_schedule.dart` solo para la vista
-- previa del editor; el calendario y la vigencia se calculan aquí.
create table private.plan_test_schedules (
  plan_prueba_id uuid primary key references public.plan_pruebas(id),
  rule jsonb not null,
  created_at timestamptz not null default now()
);

revoke all on private.plan_test_schedules from public, anon, authenticated, service_role;

create function private.schedule_normalize(rule jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare
  mode_value text; unit_value text; every_value integer; warning_value integer;
  start_value date; result jsonb; weekdays_value jsonb;
begin
  perform private.admin_assert(
    jsonb_typeof(rule)='object'
      and rule-array['mode','unit','every','weekdays','monthMode','monthDay',
        'weekOfMonth','weekday','startsOn','warningDays']='{}'::jsonb
      and rule->>'mode' in ('fixed','rolling')
      and rule->>'unit' in ('day','week','month','year')
      and jsonb_typeof(rule->'every')='number' and (rule->>'every') ~ '^[0-9]{1,3}$'
      and jsonb_typeof(rule->'warningDays')='number' and (rule->>'warningDays') ~ '^[0-9]{1,2}$',
    'INVALID_CHECK_SCHEDULE'
  );
  mode_value:=rule->>'mode';
  unit_value:=rule->>'unit';
  every_value:=(rule->>'every')::integer;
  warning_value:=(rule->>'warningDays')::integer;
  perform private.admin_assert(
    every_value between 1 and case unit_value
      when 'day' then 365 when 'week' then 52 when 'month' then 24 else 5 end
      and warning_value between 0 and 90,
    'INVALID_CHECK_SCHEDULE'
  );
  result:=jsonb_build_object('mode',mode_value,'unit',unit_value,
    'every',every_value,'warningDays',warning_value);
  if mode_value='rolling' then
    perform private.admin_assert(
      rule-array['mode','unit','every','warningDays']='{}'::jsonb,
      'INVALID_CHECK_SCHEDULE'
    );
    return result;
  end if;

  perform private.admin_assert(
    jsonb_typeof(rule->'startsOn')='string'
      and (rule->>'startsOn') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
    'INVALID_CHECK_SCHEDULE'
  );
  begin
    start_value:=(rule->>'startsOn')::date;
  exception when others then
    perform private.admin_assert(false,'INVALID_CHECK_SCHEDULE');
  end;
  perform private.admin_assert(
    start_value between date '2020-01-01' and date '2100-12-31',
    'INVALID_CHECK_SCHEDULE'
  );
  result:=result||jsonb_build_object('startsOn',to_char(start_value,'YYYY-MM-DD'));

  if unit_value='day' then
    perform private.admin_assert(
      rule-array['mode','unit','every','warningDays','startsOn']='{}'::jsonb,
      'INVALID_CHECK_SCHEDULE'
    );
  elsif unit_value='week' then
    perform private.admin_assert(
      rule-array['mode','unit','every','warningDays','startsOn','weekdays']='{}'::jsonb
        and jsonb_typeof(rule->'weekdays')='array'
        and jsonb_array_length(rule->'weekdays') between 1 and 7
        and not exists(select 1 from jsonb_array_elements(rule->'weekdays') item
          where jsonb_typeof(item.value)<>'number' or (item.value#>>'{}') !~ '^[1-7]$')
        and (select count(distinct item.value) from jsonb_array_elements(rule->'weekdays') item)
          =jsonb_array_length(rule->'weekdays'),
      'INVALID_CHECK_SCHEDULE'
    );
    select jsonb_agg(day_value order by day_value) into weekdays_value
      from (select (item.value#>>'{}')::integer day_value
        from jsonb_array_elements(rule->'weekdays') item) days;
    result:=result||jsonb_build_object('weekdays',weekdays_value);
  else
    perform private.admin_assert(rule->>'monthMode' in ('day','weekday'),'INVALID_CHECK_SCHEDULE');
    if rule->>'monthMode'='day' then
      perform private.admin_assert(
        rule-array['mode','unit','every','warningDays','startsOn','monthMode','monthDay']='{}'::jsonb
          and jsonb_typeof(rule->'monthDay')='number'
          and (rule->>'monthDay') ~ '^[0-9]{1,2}$'
          and (rule->>'monthDay')::integer between 1 and 31,
        'INVALID_CHECK_SCHEDULE'
      );
      result:=result||jsonb_build_object('monthMode','day',
        'monthDay',(rule->>'monthDay')::integer);
    else
      perform private.admin_assert(
        rule-array['mode','unit','every','warningDays','startsOn','monthMode',
          'weekOfMonth','weekday']='{}'::jsonb
          and jsonb_typeof(rule->'weekOfMonth')='number'
          and (rule->>'weekOfMonth') ~ '^[1-5]$'
          and jsonb_typeof(rule->'weekday')='number'
          and (rule->>'weekday') ~ '^[1-7]$',
        'INVALID_CHECK_SCHEDULE'
      );
      result:=result||jsonb_build_object('monthMode','weekday',
        'weekOfMonth',(rule->>'weekOfMonth')::integer,
        'weekday',(rule->>'weekday')::integer);
    end if;
  end if;
  return result;
end; $$;

-- Días aproximados entre fechas. Solo alimenta `frecuencia_dias`, que sigue
-- siendo obligatoria en `plan_pruebas` para los consumidores anteriores.
create function private.schedule_frequency_days(rule jsonb) returns integer
language sql immutable set search_path='' as $$
  select least(3650,greatest(1,case rule->>'unit'
    when 'day' then (rule->>'every')::integer
    when 'week' then case when rule->>'mode'='fixed'
      then round(7.0*(rule->>'every')::integer/jsonb_array_length(rule->'weekdays'))::integer
      else 7*(rule->>'every')::integer end
    when 'month' then 30*(rule->>'every')::integer
    else 365*(rule->>'every')::integer end));
$$;

-- Las configuraciones anteriores a esta migración solo tienen `frecuencia_dias`:
-- equivalen a "N días después de la última verificación".
create function private.plan_test_rule(test_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(
    (select s.rule from private.plan_test_schedules s where s.plan_prueba_id=t.id),
    jsonb_build_object('mode','rolling','unit','day','every',t.frecuencia_dias,
      'warningDays',t.aviso_dias))
  from public.plan_pruebas t where t.id=test_id;
$$;

create function private.schedule_add(base date, unit text, amount integer) returns date
language sql immutable set search_path='' as $$
  -- PostgreSQL recorta al último día del mes: 31/01 + 1 mes = 28/02.
  select case unit
    when 'day' then base+amount
    when 'week' then base+7*amount
    when 'month' then (base+make_interval(months=>amount))::date
    else (base+make_interval(years=>amount))::date end;
$$;

create function private.schedule_month_index(value date) returns integer
language sql immutable set search_path='' as $$
  select extract(year from value)::integer*12+extract(month from value)::integer-1;
$$;

create function private.schedule_month_date(rule jsonb, month_index integer) returns date
language plpgsql immutable set search_path='' as $$
declare
  first_day date:=make_date(month_index/12,month_index%12+1,1);
  last_day date:=(first_day+interval '1 month')::date-1;
  target integer;
begin
  if rule->>'monthMode'='weekday' then
    target:=(rule->>'weekday')::integer;
    if (rule->>'weekOfMonth')::integer=5 then
      return last_day-((extract(isodow from last_day)::integer-target+7)%7);
    end if;
    return first_day+((target-extract(isodow from first_day)::integer+7)%7)
      +7*((rule->>'weekOfMonth')::integer-1);
  end if;
  return make_date(month_index/12,month_index%12+1,
    least((rule->>'monthDay')::integer,extract(day from last_day)::integer));
end; $$;

-- Primera fecha fija igual o posterior a `on_or_after`.
create function private.schedule_next(rule jsonb, on_or_after date) returns date
language plpgsql immutable set search_path='' as $$
declare
  start_date date:=(rule->>'startsOn')::date;
  every_value integer:=(rule->>'every')::integer;
  lower_bound date:=greatest(on_or_after,start_date);
  week_start date; week_index integer; candidate date;
  month_zero integer; month_offset integer; step integer;
begin
  if rule->>'mode'<>'fixed' then return null; end if;
  if rule->>'unit'='day' then
    return start_date+ceil((lower_bound-start_date)::numeric/every_value)::integer*every_value;
  elsif rule->>'unit'='week' then
    week_start:=start_date-(extract(isodow from start_date)::integer-1);
    week_index:=(lower_bound-week_start)/7;
    if week_index%every_value<>0 then
      week_index:=(week_index/every_value+1)*every_value;
      lower_bound:=week_start+7*week_index;
    end if;
    for attempt in 1..2 loop
      select min(week_start+7*week_index+(item.value#>>'{}')::integer-1) into candidate
        from jsonb_array_elements(rule->'weekdays') item
        where week_start+7*week_index+(item.value#>>'{}')::integer-1>=lower_bound;
      if candidate is not null then return candidate; end if;
      week_index:=week_index+every_value;
      lower_bound:=week_start+7*week_index;
    end loop;
    return null;
  end if;
  step:=case when rule->>'unit'='year' then every_value*12 else every_value end;
  month_zero:=private.schedule_month_index(start_date);
  month_offset:=ceil((private.schedule_month_index(lower_bound)-month_zero)::numeric/step)::integer*step;
  candidate:=private.schedule_month_date(rule,month_zero+month_offset);
  if candidate<lower_bound then
    candidate:=private.schedule_month_date(rule,month_zero+month_offset+step);
  end if;
  return candidate;
end; $$;

-- Última fecha fija igual o anterior a `on_or_before`; null antes de empezar.
create function private.schedule_previous(rule jsonb, on_or_before date) returns date
language plpgsql immutable set search_path='' as $$
declare
  start_date date:=(rule->>'startsOn')::date;
  every_value integer:=(rule->>'every')::integer;
  upper_bound date:=on_or_before;
  week_start date; week_index integer; candidate date;
  month_zero integer; month_offset integer; step integer;
begin
  if rule->>'mode'<>'fixed' or on_or_before<start_date then return null; end if;
  if rule->>'unit'='day' then
    return start_date+((upper_bound-start_date)/every_value)*every_value;
  elsif rule->>'unit'='week' then
    week_start:=start_date-(extract(isodow from start_date)::integer-1);
    week_index:=(upper_bound-week_start)/7;
    if week_index%every_value<>0 then
      week_index:=week_index-week_index%every_value;
      upper_bound:=week_start+7*week_index+6;
    end if;
    for attempt in 1..2 loop
      select max(week_start+7*week_index+(item.value#>>'{}')::integer-1) into candidate
        from jsonb_array_elements(rule->'weekdays') item
        where week_start+7*week_index+(item.value#>>'{}')::integer-1<=upper_bound
          and week_start+7*week_index+(item.value#>>'{}')::integer-1>=start_date;
      if candidate is not null then return candidate; end if;
      week_index:=week_index-every_value;
      if week_index<0 then return null; end if;
      upper_bound:=week_start+7*week_index+6;
    end loop;
    return null;
  end if;
  step:=case when rule->>'unit'='year' then every_value*12 else every_value end;
  month_zero:=private.schedule_month_index(start_date);
  month_offset:=((private.schedule_month_index(upper_bound)-month_zero)/step)*step;
  candidate:=private.schedule_month_date(rule,month_zero+month_offset);
  if candidate>upper_bound then
    month_offset:=month_offset-step;
    if month_offset<0 then return null; end if;
    candidate:=private.schedule_month_date(rule,month_zero+month_offset);
  end if;
  if candidate<start_date then return null; end if;
  return candidate;
end; $$;

-- El día en planta lo marca el teléfono: la app envía su desfase horario.
-- Bolivia (UTC-4) cuando no llega.
create function private.agenda_offset(filters jsonb) returns integer
language sql immutable set search_path='' as $$
  select case when coalesce(filters->>'utcOffsetMinutes','') ~ '^-?[0-9]{1,3}$'
      and (filters->>'utcOffsetMinutes')::integer between -720 and 840
    then (filters->>'utcOffsetMinutes')::integer else -240 end;
$$;

create function private.local_date(value timestamptz, offset_minutes integer) returns date
language sql immutable set search_path='' as $$
  select ((value at time zone 'UTC')+make_interval(mins=>offset_minutes))::date;
$$;

-- Cualquier prueba ejecutada en una verificación vigente cuenta como
-- realizada, con o sin trazabilidad: el calendario refleja que la verificación
-- intermedia se hizo; la trazabilidad sigue en el resultado.
create function private.equipment_run_dates(target uuid, test_type text, offset_minutes integer)
returns table(run_date date)
language sql stable security definer set search_path='' as $$
  select distinct private.local_date(v.realizado_at,offset_minutes)
  from public.verificaciones v join public.pruebas p on p.verificacion_id=v.id
  where v.equipo_id=target and v.estado='ACTIVE'
    and p.tipo=test_type and p.estado_ejecucion='executed';
$$;

-- Vigencia de cada prueba de la configuración activa: la fecha que toca y su
-- urgencia (CURRENT, DUE_SOON, OVERDUE).
create function private.equipment_schedule_status(target uuid, offset_minutes integer default -240)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  today date:=private.local_date(now(),offset_minutes);
  anchor date; trial record; rule jsonb; warning_days integer; runs date[];
  current_due date; next_due date; due date; state_value text;
  last_run timestamptz; last_traceable timestamptz; result jsonb:='[]'::jsonb;
begin
  select private.local_date(ep.vigente_desde,offset_minutes) into anchor
    from public.equipo_planes ep where ep.equipo_id=target and ep.vigente_hasta is null
    order by ep.vigente_desde desc limit 1;
  for trial in
    select t.id,t.tipo from public.equipo_planes ep
      join public.plan_versiones pv on pv.id=ep.plan_version_id
      join public.plan_pruebas t on t.plan_version_id=pv.id
    where ep.equipo_id=target and ep.vigente_hasta is null and pv.estado='PUBLISHED'
    order by t.tipo
  loop
    rule:=private.plan_test_rule(trial.id);
    warning_days:=(rule->>'warningDays')::integer;
    runs:=array(select r.run_date from private.equipment_run_dates(target,trial.tipo,offset_minutes) r);
    select max(v.realizado_at),
        max(v.realizado_at) filter (where v.trazabilidad='traceable')
      into last_run,last_traceable
      from public.verificaciones v join public.pruebas p on p.verificacion_id=v.id
      where v.equipo_id=target and v.estado='ACTIVE'
        and p.tipo=trial.tipo and p.estado_ejecucion='executed';
    if rule->>'mode'='fixed' then
      current_due:=private.schedule_previous(rule,today+warning_days);
      if current_due is null then
        due:=private.schedule_next(rule,today);
        state_value:='CURRENT';
      else
        next_due:=private.schedule_next(rule,current_due+1);
        if exists(select 1 from unnest(runs) run_date
            where run_date>=current_due-warning_days and run_date<next_due-warning_days) then
          due:=next_due;
          state_value:='CURRENT';
        else
          due:=current_due;
          state_value:=case when today>due then 'OVERDUE' else 'DUE_SOON' end;
        end if;
      end if;
    else
      due:=private.schedule_add(
        coalesce(private.local_date(last_run,offset_minutes),anchor,today),
        rule->>'unit',(rule->>'every')::integer);
      state_value:=case when today>due then 'OVERDUE'
        when today>=due-warning_days then 'DUE_SOON' else 'CURRENT' end;
    end if;
    result:=result||jsonb_build_array(jsonb_build_object(
      'type',trial.tipo,'rule',rule,'lastRunAt',last_run,'lastTraceableAt',last_traceable,
      'dueAt',to_char(due,'YYYY-MM-DD'),'warningAt',to_char(due-warning_days,'YYYY-MM-DD'),
      'state',state_value));
  end loop;
  return result;
end; $$;

-- Firma anterior, para cualquier consumidor que no envíe desfase horario.
create or replace function private.equipment_test_schedule(target_equipment uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select private.equipment_schedule_status(target_equipment,-240);
$$;

-- Fechas de una balanza dentro de un rango, una fila por prueba y fecha.
-- Estados: DONE, SCHEDULED, DUE_SOON, DUE_TODAY, OVERDUE y MISSED (ventana
-- cerrada sin verificación).
create function private.equipment_agenda(target uuid, range_start date, range_end date, offset_minutes integer)
returns table(occurrence_date date, occurrence_type text, occurrence_state text, occurrence_done_on date)
language plpgsql stable security definer set search_path='' as $$
declare
  today date:=private.local_date(now(),offset_minutes);
  anchor date; trial record; rule jsonb; warning_days integer; every_value integer; runs date[];
  scheduled date; next_scheduled date; base date; step integer;
begin
  select private.local_date(ep.vigente_desde,offset_minutes) into anchor
    from public.equipo_planes ep where ep.equipo_id=target and ep.vigente_hasta is null
    order by ep.vigente_desde desc limit 1;
  for trial in
    select t.id,t.tipo from public.equipo_planes ep
      join public.plan_versiones pv on pv.id=ep.plan_version_id
      join public.plan_pruebas t on t.plan_version_id=pv.id
    where ep.equipo_id=target and ep.vigente_hasta is null and pv.estado='PUBLISHED'
    order by t.tipo
  loop
    rule:=private.plan_test_rule(trial.id);
    warning_days:=(rule->>'warningDays')::integer;
    every_value:=(rule->>'every')::integer;
    runs:=array(select r.run_date from private.equipment_run_dates(target,trial.tipo,offset_minutes) r);
    occurrence_type:=trial.tipo;
    if rule->>'mode'='fixed' then
      scheduled:=private.schedule_next(rule,range_start);
      while scheduled is not null and scheduled<=range_end loop
        next_scheduled:=private.schedule_next(rule,scheduled+1);
        -- Fechas cuya ventana se cerró antes de activar esta configuración no
        -- le pertenecen.
        if anchor is null or next_scheduled-warning_days>anchor then
          select max(run_date) into occurrence_done_on from unnest(runs) run_date
            where run_date>=scheduled-warning_days and run_date<next_scheduled-warning_days;
          occurrence_date:=scheduled;
          occurrence_state:=case
            when occurrence_done_on is not null then 'DONE'
            when today<scheduled-warning_days then 'SCHEDULED'
            when today<scheduled then 'DUE_SOON'
            when today=scheduled then 'DUE_TODAY'
            when today<next_scheduled-warning_days then 'OVERDUE'
            else 'MISSED' end;
          return next;
        end if;
        scheduled:=next_scheduled;
      end loop;
    else
      occurrence_state:='DONE';
      for occurrence_date in
        select run_date from unnest(runs) run_date where run_date between range_start and range_end
      loop
        occurrence_done_on:=occurrence_date;
        return next;
      end loop;
      base:=coalesce((select max(run_date) from unnest(runs) run_date),anchor,today);
      occurrence_done_on:=null;
      step:=1;
      loop
        scheduled:=private.schedule_add(base,rule->>'unit',every_value*step);
        exit when scheduled>range_end or step>4000;
        if scheduled>=range_start then
          occurrence_date:=scheduled;
          occurrence_state:=case
            when today<scheduled-warning_days then 'SCHEDULED'
            when today<scheduled then 'DUE_SOON'
            when today=scheduled then 'DUE_TODAY'
            else 'OVERDUE' end;
          return next;
        end if;
        -- Vencida: las siguientes dependen de cuándo se haga, no se proyectan.
        exit when step=1 and scheduled<today;
        step:=step+1;
      end loop;
    end if;
  end loop;
end; $$;

-- ============================================================================
-- 3. Configuración con periodicidad
-- ============================================================================
alter function public.ivmet_customer_configure_checks(uuid,jsonb,uuid)
  rename to customer_configure_checks_before_schedules;
alter function public.customer_configure_checks_before_schedules(uuid,jsonb,uuid)
  set schema private;

-- Los clientes anteriores siguen enviando `frequencyDays`; los nuevos envían
-- `schedule`. Las dos formas terminan en una regla guardada por prueba.
create function public.ivmet_customer_configure_checks(
  equipment_id uuid,
  configuration jsonb,
  request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  test_value jsonb; rule_value jsonb; frequency integer;
  legacy_tests jsonb:='[]'::jsonb; rules jsonb:='{}'::jsonb;
  result jsonb; trial record; stored jsonb;
begin
  perform private.admin_assert(
    private.current_profile_role()='cliente_jefe_calidad',
    'QUALITY_MANAGER_REQUIRED'
  );
  perform private.admin_assert(
    jsonb_typeof(configuration)='object'
      and jsonb_typeof(configuration->'tests')='array',
    'INVALID_CHECK_CONFIGURATION'
  );
  for test_value in select value from jsonb_array_elements(configuration->'tests') loop
    perform private.admin_assert(
      jsonb_typeof(test_value)='object'
        and test_value->>'type' in ('linearity','repeatability','eccentricity'),
      'INVALID_CHECK_CONFIGURATION'
    );
    if test_value ? 'schedule' then
      rule_value:=private.schedule_normalize(test_value->'schedule');
      frequency:=private.schedule_frequency_days(rule_value);
    else
      perform private.admin_assert(
        jsonb_typeof(test_value->'frequencyDays')='string'
          and (test_value->>'frequencyDays') ~ '^[0-9]{1,4}$'
          and (test_value->>'frequencyDays')::integer between 1 and 3650,
        'INVALID_CHECK_CONFIGURATION'
      );
      frequency:=(test_value->>'frequencyDays')::integer;
      rule_value:=jsonb_build_object('mode','rolling','unit','day','every',frequency,
        'warningDays',least(30,greatest(0,frequency/4)));
    end if;
    rules:=rules||jsonb_build_object(test_value->>'type',rule_value);
    legacy_tests:=legacy_tests||jsonb_build_array(
      (test_value-'schedule')||jsonb_build_object('frequencyDays',frequency::text));
  end loop;

  result:=private.customer_configure_checks_before_schedules(
    equipment_id,jsonb_build_object('tests',legacy_tests),request_id);

  -- Un reintento con el mismo request_id devuelve el recibo anterior: su regla
  -- tiene que ser la misma que la que ya quedó guardada.
  for trial in select t.id,t.tipo from public.plan_pruebas t
    where t.plan_version_id=(result->>'configurationId')::uuid
  loop
    select s.rule into stored from private.plan_test_schedules s where s.plan_prueba_id=trial.id;
    if found then
      perform private.admin_assert(stored=rules->trial.tipo,'IDEMPOTENCY_CONFLICT');
    else
      insert into private.plan_test_schedules(plan_prueba_id,rule)
        values(trial.id,rules->trial.tipo);
    end if;
  end loop;
  return result||jsonb_build_object('schedules',rules);
end; $$;

-- ============================================================================
-- 4. Lecturas del móvil con alcance por operador
-- ============================================================================
create function private.equipment_assignees(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.nombre) order by p.nombre,p.id),'[]'::jsonb)
  from public.usuario_equipos ue
  join public.perfiles p on p.id=ue.usuario_id
  join public.equipos e on e.id=ue.equipo_id
  join public.usuario_plantas up on up.usuario_id=p.id and up.planta_id=e.planta_id and up.activa
  where ue.equipo_id=target and p.activo and p.rol='cliente_operador';
$$;

create function private.mobile_instruments(filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  result jsonb;
  cid uuid:=private.mobile_require();
  pid uuid:=nullif(filters->>'plantId','')::uuid;
  page_no int:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
  page_size int:=greatest(1,least(coalesce((filters->>'pageSize')::int,25),100));
begin
  with matching as (
    select e.id,e.cod_metrica,e.origen,
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
      and private.equipment_in_scope(e.id)
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
end; $$;

create function private.mobile_history(filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  result jsonb;
  cid uuid:=private.mobile_require();
  eid uuid:=nullif(filters->>'equipmentId','')::uuid;
  page_no int:=greatest(1,least(coalesce((filters->>'page')::int,1),100000));
  page_size int:=greatest(1,least(coalesce((filters->>'pageSize')::int,25),100));
begin
  with matching as (
    select v.id,v.equipo_id,v.realizado_at,v.alcance,v.veredicto_global,v.trazabilidad,v.estado,
      coalesce(v.equipo_snapshot->>'cod_metrica',e.cod_metrica) cod_metrica,a.id alerta_id,
      e.origen,coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),e.cod_interno) cod_interno
    from public.verificaciones v
    join public.equipos e on e.id=v.equipo_id
    left join public.alertas a on a.verificacion_id=v.id
    left join public.equipos_cliente ec on ec.equipo_id=e.id
    where v.cliente_id=cid and private.can_access_plant(v.planta_id)
      and (eid is null or v.equipo_id=eid)
      and (private.equipment_in_scope(v.equipo_id) or v.capturado_por=auth.uid())
  ), rows as (
    select * from matching order by realizado_at desc,id
    limit page_size offset (page_no-1)*page_size
  )
  select jsonb_build_object(
    'total',(select count(*) from matching),
    'items',coalesce((select jsonb_agg(to_jsonb(r) order by r.realizado_at desc,r.id) from rows r),'[]')
  ) into result;
  return result;
end; $$;

-- Balanzas que el usuario puede ver hoy, con lo que la agenda necesita.
create function private.agenda_equipment(cid uuid, plant_filter uuid, operator_filter text)
returns table(id uuid, data jsonb)
language sql stable security definer set search_path='' as $$
  select e.id,jsonb_build_object(
      'id',e.id,'cod_metrica',e.cod_metrica,'origen',e.origen,
      'cod_interno',coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),nullif(btrim(e.cod_interno),'')),
      'plantId',e.planta_id,'planta',coalesce(p.nombre,p.legacy_codigo_planta),
      'departamento',coalesce(a.nombre,nullif(btrim(ec.datos->>'ubicacion'),''),
        nullif(btrim(e.ubicacion),''),'Sin departamento'))
    ||case when private.current_profile_role()='cliente_jefe_calidad'
      then jsonb_build_object('assignees',private.equipment_assignees(e.id))
      else '{}'::jsonb end
  from public.equipos e
  join public.equipos_ivmet i on i.equipo_id=e.id
  join public.plantas p on p.id=e.planta_id
  left join public.areas a on a.id=i.area_id
  left join public.equipos_cliente ec on ec.equipo_id=e.id
  where e.cliente_id=cid and e.activo and p.activo and e.estado_catalogo='READY'
    and i.habilitado and i.estado_configuracion='READY'
    and private.can_access_plant(e.planta_id) and private.equipment_in_scope(e.id)
    and (plant_filter is null or e.planta_id=plant_filter)
    and (operator_filter is null
      or (operator_filter='unassigned' and private.equipment_assignees(e.id)='[]'::jsonb)
      or exists(select 1 from public.usuario_equipos ue
        where ue.equipo_id=e.id and ue.usuario_id::text=operator_filter))
    and exists(select 1 from public.equipo_planes ep
      join public.plan_versiones pv on pv.id=ep.plan_version_id
      where ep.equipo_id=e.id and ep.vigente_hasta is null and pv.estado='PUBLISHED');
$$;

create function private.mobile_agenda(filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  quality boolean:=private.current_profile_role()='cliente_jefe_calidad';
  offset_minutes integer:=private.agenda_offset(filters);
  today date:=private.local_date(now(),offset_minutes);
  from_date date; until_date date;
  plant_filter uuid; operator_filter text:=nullif(filters->>'operatorId','');
  result jsonb;
begin
  begin
    from_date:=coalesce(nullif(filters->>'from','')::date,today);
    until_date:=coalesce(nullif(filters->>'to','')::date,from_date+41);
    plant_filter:=nullif(filters->>'plantId','')::uuid;
    if operator_filter is not null and operator_filter<>'unassigned' then
      operator_filter:=operator_filter::uuid::text;
    end if;
  exception when others then
    perform private.admin_assert(false,'INVALID_AGENDA_FILTER');
  end;
  perform private.admin_assert(until_date>=from_date and until_date-from_date<=62,'INVALID_AGENDA_RANGE');
  perform private.admin_assert(operator_filter is null or quality,'QUALITY_MANAGER_REQUIRED');

  with eligible as (
    select * from private.agenda_equipment(cid,plant_filter,operator_filter)
  ), occurrences as (
    select el.id,el.data,o.occurrence_date,
      jsonb_agg(jsonb_build_object('type',o.occurrence_type,'state',o.occurrence_state,
        'doneOn',o.occurrence_done_on) order by o.occurrence_type) tests
    from eligible el
    cross join lateral private.equipment_agenda(el.id,from_date,until_date,offset_minutes) o
    group by el.id,el.data,o.occurrence_date
  ), overdue as (
    select el.id,el.data,jsonb_agg(jsonb_build_object('type',s.item->>'type',
        'dueOn',s.item->>'dueAt') order by s.item->>'type') tests,
      min(s.item->>'dueAt') due_on
    from eligible el
    cross join lateral jsonb_array_elements(private.equipment_schedule_status(el.id,offset_minutes)) s(item)
    where s.item->>'state'='OVERDUE'
    group by el.id,el.data
  )
  select jsonb_build_object(
    'today',to_char(today,'YYYY-MM-DD'),
    'from',to_char(from_date,'YYYY-MM-DD'),
    'to',to_char(until_date,'YYYY-MM-DD'),
    'equipmentCount',(select count(*) from eligible),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
        'date',to_char(oc.occurrence_date,'YYYY-MM-DD'),'equipment',oc.data,'tests',oc.tests)
      order by oc.occurrence_date,coalesce(oc.data->>'cod_interno',oc.data->>'cod_metrica'))
      from occurrences oc),'[]'::jsonb),
    'overdue',coalesce((select jsonb_agg(jsonb_build_object(
        'dueOn',od.due_on,'equipment',od.data,'tests',od.tests)
      order by od.due_on,coalesce(od.data->>'cod_interno',od.data->>'cod_metrica'))
      from overdue od),'[]'::jsonb)
  ) into result;
  return result;
end; $$;

-- Resumen de hoy para Inicio: balanzas que tocan hoy y las vencidas.
create function private.agenda_summary(offset_minutes integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  today date:=private.local_date(now(),offset_minutes);
  due_today integer; done_today integer; overdue integer; unassigned integer:=0;
begin
  select count(*) filter (where day_state.pending),
      count(*) filter (where day_state.done and not day_state.pending),
      count(*) filter (where day_state.late)
    into due_today,done_today,overdue
    from (select
        exists(select 1 from private.equipment_agenda(el.id,today,today,offset_minutes) o
          where o.occurrence_date=today and o.occurrence_state='DUE_TODAY') pending,
        exists(select 1 from private.equipment_agenda(el.id,today,today,offset_minutes) o
          where o.occurrence_date=today and o.occurrence_state='DONE') done,
        exists(select 1 from jsonb_array_elements(private.equipment_schedule_status(el.id,offset_minutes)) s(item)
          where s.item->>'state'='OVERDUE') late
      from private.agenda_equipment(cid,null,null) el) day_state;
  if private.current_profile_role()='cliente_jefe_calidad' then
    select count(*) into unassigned from public.equipos e
      join public.equipos_ivmet i on i.equipo_id=e.id
      join public.plantas p on p.id=e.planta_id
      where e.cliente_id=cid and e.activo and p.activo and e.estado_catalogo='READY'
        and i.habilitado and i.estado_configuracion='READY'
        and private.can_access_plant(e.planta_id)
        and private.equipment_assignees(e.id)='[]'::jsonb;
  end if;
  return jsonb_build_object('today',to_char(today,'YYYY-MM-DD'),'dueToday',due_today,
    'doneToday',done_today,'overdue',overdue,'unassigned',unassigned);
end; $$;

-- Equipo de trabajo de una planta, para el jefe de calidad.
create function private.plant_operator(cid uuid, plant uuid, member uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.perfiles p
    join public.usuario_plantas up on up.usuario_id=p.id and up.planta_id=plant and up.activa
    where p.id=member and p.cliente_id=cid and p.activo and p.rol='cliente_operador');
$$;

create function private.assignable_equipment(cid uuid, plant uuid) returns setof public.equipos
language sql stable security definer set search_path='' as $$
  select e.* from public.equipos e
    join public.equipos_ivmet i on i.equipo_id=e.id
    join public.plantas p on p.id=e.planta_id
  where e.cliente_id=cid and e.planta_id=plant and e.activo and p.activo
    and e.estado_catalogo='READY' and i.habilitado and i.estado_configuracion='READY';
$$;

create function private.mobile_team(section text, filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  plant uuid; member uuid; e public.equipos%rowtype; result jsonb;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  begin
    plant:=nullif(filters->>'plantId','')::uuid;
    member:=nullif(filters->>'userId','')::uuid;
  exception when others then
    perform private.admin_assert(false,'INVALID_ASSIGNMENT');
  end;

  if section='equipment-team' then
    e:=private.customer_equipment(nullif(filters->>'equipmentId','')::uuid);
    return jsonb_build_object('equipmentId',e.id,'plantId',e.planta_id,
      'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.nombre,
          'username',p.usuario,'assigned',exists(select 1 from public.usuario_equipos ue
            where ue.usuario_id=p.id and ue.equipo_id=e.id)) order by p.nombre,p.id)
        from public.perfiles p
        join public.usuario_plantas up on up.usuario_id=p.id and up.planta_id=e.planta_id and up.activa
        where p.cliente_id=cid and p.activo and p.rol='cliente_operador'),'[]'::jsonb));
  end if;

  perform private.admin_assert(plant is not null and private.can_access_plant(plant)
    and exists(select 1 from public.plantas p where p.id=plant and p.cliente_id=cid and p.activo),
    'PLANT_SCOPE_INVALID');

  if section='team' then
    select jsonb_build_object('plantId',plant,
      'equipmentCount',(select count(*) from private.assignable_equipment(cid,plant)),
      'unassignedCount',(select count(*) from private.assignable_equipment(cid,plant) x
        where private.equipment_assignees(x.id)='[]'::jsonb),
      'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.nombre,
          'username',p.usuario,'assignedCount',(select count(*) from public.usuario_equipos ue
            join private.assignable_equipment(cid,plant) x on x.id=ue.equipo_id
            where ue.usuario_id=p.id)) order by p.nombre,p.id)
        from public.perfiles p
        join public.usuario_plantas up on up.usuario_id=p.id and up.planta_id=plant and up.activa
        where p.cliente_id=cid and p.activo and p.rol='cliente_operador'),'[]'::jsonb))
      into result;
    return result;
  end if;

  perform private.admin_assert(section='team-member','UNKNOWN_MOBILE_SECTION');
  perform private.admin_assert(member is not null and private.plant_operator(cid,plant,member),
    'OPERATOR_NOT_IN_PLANT');
  select jsonb_build_object('plantId',plant,
    'member',(select jsonb_build_object('id',p.id,'name',p.nombre,'username',p.usuario)
      from public.perfiles p where p.id=member),
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'cod_metrica',x.cod_metrica,
        'origen',x.origen,
        'cod_interno',coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),nullif(btrim(x.cod_interno),'')),
        'marca',coalesce(nullif(btrim(ec.datos->>'marca'),''),x.marca),
        'modelo',coalesce(nullif(btrim(ec.datos->>'modelo'),''),x.modelo),
        'departamento',coalesce(a.nombre,nullif(btrim(ec.datos->>'ubicacion'),''),
          nullif(btrim(x.ubicacion),''),'Sin departamento'),
        'assigned',exists(select 1 from public.usuario_equipos ue
          where ue.usuario_id=member and ue.equipo_id=x.id),
        'assigneeCount',jsonb_array_length(private.equipment_assignees(x.id)))
      order by coalesce(nullif(btrim(ec.datos->>'cod_interno'),''),nullif(btrim(x.cod_interno),''),x.cod_metrica),x.id)
      from private.assignable_equipment(cid,plant) x
      join public.equipos_ivmet i on i.equipo_id=x.id
      left join public.areas a on a.id=i.area_id
      left join public.equipos_cliente ec on ec.equipo_id=x.id),'[]'::jsonb))
    into result;
  return result;
end; $$;

-- Reemplaza, de forma idempotente, las balanzas de un operador en una planta
-- (`userId` + `plantId` + `equipmentIds`) o los operadores de una balanza
-- (`equipmentId` + `userIds`).
create function public.ivmet_customer_assign_equipment(assignment jsonb, request_id uuid)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require();
  actor_value text:='MOBILE:'||auth.uid()::text;
  digest text; saved private.admin_requests%rowtype; result jsonb;
  action_value text; member uuid; plant uuid; ids uuid[]; e public.equipos%rowtype;
  added integer; removed integer;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(request_id is not null and jsonb_typeof(assignment)='object'
    and octet_length(assignment::text)<=131072,'INVALID_ASSIGNMENT');
  digest:=encode(sha256(convert_to('assignment'||assignment::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));

  -- Revalidar rol y alcance antes de devolver un recibo idempotente.
  if assignment ? 'userId' then
    action_value:='customer.assignment.operator';
    perform private.admin_assert(assignment-array['userId','plantId','equipmentIds']='{}'::jsonb
      and jsonb_typeof(assignment->'equipmentIds')='array'
      and jsonb_array_length(assignment->'equipmentIds')<=2000,'INVALID_ASSIGNMENT');
    begin
      member:=(assignment->>'userId')::uuid;
      plant:=(assignment->>'plantId')::uuid;
      ids:=array(select distinct item::uuid from jsonb_array_elements_text(assignment->'equipmentIds') item);
    exception when others then
      perform private.admin_assert(false,'INVALID_ASSIGNMENT');
    end;
    perform private.admin_assert(plant is not null and private.can_access_plant(plant)
      and exists(select 1 from public.plantas p where p.id=plant and p.cliente_id=cid and p.activo),
      'PLANT_SCOPE_INVALID');
    perform private.admin_assert(member is not null and private.plant_operator(cid,plant,member),
      'OPERATOR_NOT_IN_PLANT');
    perform private.admin_assert(not exists(select 1 from unnest(ids) x
      where x not in (select a.id from private.assignable_equipment(cid,plant) a)),
      'EQUIPMENT_NOT_ACCESSIBLE');
  elsif assignment ? 'equipmentId' then
    action_value:='customer.assignment.equipment';
    perform private.admin_assert(assignment-array['equipmentId','userIds']='{}'::jsonb
      and jsonb_typeof(assignment->'userIds')='array'
      and jsonb_array_length(assignment->'userIds')<=500,'INVALID_ASSIGNMENT');
    begin
      ids:=array(select distinct item::uuid from jsonb_array_elements_text(assignment->'userIds') item);
      e:=private.customer_equipment((assignment->>'equipmentId')::uuid);
    exception when invalid_text_representation then
      perform private.admin_assert(false,'INVALID_ASSIGNMENT');
    end;
    perform private.admin_assert(not exists(select 1 from unnest(ids) x
      where not private.plant_operator(cid,e.planta_id,x)),'OPERATOR_NOT_IN_PLANT');
  else
    perform private.admin_assert(false,'INVALID_ASSIGNMENT');
  end if;

  select * into saved from private.admin_requests r
    where r.request_id=ivmet_customer_assign_equipment.request_id and r.action=action_value;
  if found then
    perform private.admin_assert(saved.actor=actor_value and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;

  if action_value='customer.assignment.operator' then
    perform pg_advisory_xact_lock(hashtextextended(member::text,7));
    delete from public.usuario_equipos ue using public.equipos x
      where ue.usuario_id=member and x.id=ue.equipo_id and x.planta_id=plant
        and not (ue.equipo_id=any(ids));
    get diagnostics removed=row_count;
    insert into public.usuario_equipos(usuario_id,equipo_id,asignado_por)
      select member,x,auth.uid() from unnest(ids) x
      on conflict (usuario_id,equipo_id) do nothing;
    get diagnostics added=row_count;
    result:=jsonb_build_object('userId',member,'plantId',plant,
      'assigned',cardinality(ids),'added',added,'removed',removed);
  else
    perform pg_advisory_xact_lock(hashtextextended(e.id::text,7));
    delete from public.usuario_equipos ue using public.perfiles p
      where ue.equipo_id=e.id and p.id=ue.usuario_id and p.cliente_id=cid
        and not (ue.usuario_id=any(ids));
    get diagnostics removed=row_count;
    insert into public.usuario_equipos(usuario_id,equipo_id,asignado_por)
      select x,e.id,auth.uid() from unnest(ids) x
      on conflict (usuario_id,equipo_id) do nothing;
    get diagnostics added=row_count;
    result:=jsonb_build_object('equipmentId',e.id,'plantId',e.planta_id,
      'assigned',cardinality(ids),'added',added,'removed',removed);
  end if;

  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(auth.uid(),cid,'usuario_equipos',
      coalesce(member::text,e.id::text),action_value,result||jsonb_build_object('ids',to_jsonb(ids)));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,action_value,actor_value,digest,result);
  return result;
end; $$;

alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_operator_scope;
alter function public.mobile_read_before_operator_scope(text,jsonb) set schema private;
do $migration$
begin
  execute replace(
    pg_get_functiondef('private.mobile_read_before_operator_scope(text,jsonb)'::regprocedure),
    'ivmet_mobile_read.','mobile_read_before_operator_scope.');
end;
$migration$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  result jsonb; cid uuid; target uuid;
  offset_minutes integer:=private.agenda_offset(filters);
begin
  if section='instruments' then
    return private.mobile_instruments(filters);
  elsif section='history' then
    return private.mobile_history(filters);
  elsif section='agenda' then
    return private.mobile_agenda(filters);
  elsif section in ('team','team-member','equipment-team') then
    return private.mobile_team(section,filters);
  elsif section='equipment' then
    cid:=private.mobile_require();
    target:=nullif(filters->>'equipmentId','')::uuid;
    perform private.admin_assert(target is not null and private.equipment_in_scope(target),
      'EQUIPMENT_NOT_ACCESSIBLE');
  end if;

  result:=private.mobile_read_before_operator_scope(section,filters);
  if section='equipment' then
    result:=result||jsonb_build_object('schedule',private.equipment_schedule_status(target,offset_minutes));
    if private.current_profile_role()='cliente_jefe_calidad' then
      result:=result||jsonb_build_object('assignees',private.equipment_assignees(target));
    end if;
  elsif section='bootstrap' then
    cid:=private.mobile_require();
    if private.current_profile_role()='cliente_operador' then
      result:=jsonb_set(result,'{plants}',coalesce((
        select jsonb_agg(plant||jsonb_build_object('equipmentCount',(
          select count(*) from private.assignable_equipment(cid,(plant->>'id')::uuid) x
          where private.equipment_in_scope(x.id)
        )) order by ord)
        from jsonb_array_elements(result->'plants') with ordinality plants(plant,ord)
      ),'[]'::jsonb));
      result:=result||jsonb_build_object(
        'equipmentCount',(select coalesce(sum((plant->>'equipmentCount')::integer),0)
          from jsonb_array_elements(result->'plants') plant),
        'openAlerts',(select count(*) from public.alertas a
          join public.verificaciones v on v.id=a.verificacion_id
          where a.cliente_id=cid and a.estado_cliente='OPEN' and private.can_access_plant(a.planta_id)
            and (private.equipment_in_scope(v.equipo_id) or v.capturado_por=auth.uid())));
    end if;
    result:=result||jsonb_build_object(
      'equipmentScope',case when private.current_profile_role()='cliente_operador'
        then 'ASSIGNED' else 'PLANT' end,
      'agenda',private.agenda_summary(offset_minutes));
  end if;
  return result;
end; $$;

-- Guardar y finalizar exigen la balanza asignada. Un reintento sobre una
-- verificación ya finalizada recupera su recibo aunque después se la retiren.
alter function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid)
  rename to mobile_save_before_operator_scope;
alter function public.mobile_save_before_operator_scope(uuid,uuid,uuid,bigint,jsonb,uuid)
  set schema private;

create function public.ivmet_mobile_save_draft(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform private.mobile_require();
  perform private.admin_assert(equipment_id is not null and private.equipment_in_scope(equipment_id),
    'EQUIPMENT_NOT_ACCESSIBLE');
  return private.mobile_save_before_operator_scope(request_id,equipment_id,version_id,
    expected_version,content,save_id);
end; $$;

alter function public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text)
  rename to mobile_finalize_before_operator_scope;
alter function public.mobile_finalize_before_operator_scope(uuid,bigint,uuid,text,text)
  set schema private;
do $migration$
begin
  execute replace(
    pg_get_functiondef('private.mobile_finalize_before_operator_scope(uuid,bigint,uuid,text,text)'::regprocedure),
    'ivmet_mobile_finalize_draft.','mobile_finalize_before_operator_scope.');
end;
$migration$;

create function public.ivmet_mobile_finalize_draft(draft_id uuid,expected_version bigint,
  finalize_id uuid,app_version_value text default null,device_id_value text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid; draft_state text;
begin
  perform private.mobile_require();
  select d.equipo_id,d.estado into target,draft_state
    from public.verificacion_borradores d where d.id=ivmet_mobile_finalize_draft.draft_id;
  if found and draft_state='DRAFT' then
    perform private.admin_assert(private.equipment_in_scope(target),'EQUIPMENT_NOT_ACCESSIBLE');
  end if;
  return private.mobile_finalize_before_operator_scope(draft_id,expected_version,finalize_id,
    app_version_value,device_id_value);
end; $$;

-- ============================================================================
-- 5. Permisos
-- ============================================================================
revoke all on function
  private.equipment_in_scope(uuid),
  private.schedule_normalize(jsonb),
  private.schedule_frequency_days(jsonb),
  private.plan_test_rule(uuid),
  private.schedule_add(date,text,integer),
  private.schedule_month_index(date),
  private.schedule_month_date(jsonb,integer),
  private.schedule_next(jsonb,date),
  private.schedule_previous(jsonb,date),
  private.agenda_offset(jsonb),
  private.local_date(timestamptz,integer),
  private.equipment_run_dates(uuid,text,integer),
  private.equipment_schedule_status(uuid,integer),
  private.equipment_agenda(uuid,date,date,integer),
  private.customer_configure_checks_before_schedules(uuid,jsonb,uuid),
  private.equipment_assignees(uuid),
  private.mobile_instruments(jsonb),
  private.mobile_history(jsonb),
  private.agenda_equipment(uuid,uuid,text),
  private.mobile_agenda(jsonb),
  private.agenda_summary(integer),
  private.plant_operator(uuid,uuid,uuid),
  private.assignable_equipment(uuid,uuid),
  private.mobile_team(text,jsonb),
  private.mobile_read_before_operator_scope(text,jsonb),
  private.mobile_save_before_operator_scope(uuid,uuid,uuid,bigint,jsonb,uuid),
  private.mobile_finalize_before_operator_scope(uuid,bigint,uuid,text,text)
from public,anon,authenticated,service_role;

-- Las políticas RLS evalúan el alcance con el rol de quien consulta.
grant execute on function private.equipment_in_scope(uuid) to authenticated, service_role;

revoke all on function
  public.ivmet_customer_configure_checks(uuid,jsonb,uuid),
  public.ivmet_customer_assign_equipment(jsonb,uuid),
  public.ivmet_mobile_read(text,jsonb),
  public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text)
from public,anon,service_role;
grant execute on function
  public.ivmet_customer_configure_checks(uuid,jsonb,uuid),
  public.ivmet_customer_assign_equipment(jsonb,uuid),
  public.ivmet_mobile_read(text,jsonb),
  public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text)
to authenticated;

commit;

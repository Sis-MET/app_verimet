begin;

/*
 * Contrato HTTP del worker corporativo.
 * Las tablas private siguen fuera de PostgREST; el worker solo puede entrar por
 * estas funciones SECURITY DEFINER concedidas exclusivamente a service_role.
 */

create or replace function private.stringify_ivmet_outbox_numbers(
  target_aggregate_type text,
  target_payload jsonb
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  field_name text;
  numeric_fields text[];
  result jsonb := target_payload;
begin
  numeric_fields := case target_aggregate_type
    when 'public.equipo_rangos' then
      array['capacidad_max', 'division_escala', 'intervalo_verificacion']
    when 'public.precios_plan' then
      array['importe']
    when 'public.facturas' then
      array['subtotal', 'impuestos', 'total', 'saldo']
    when 'public.pagos' then
      array['importe']
    when 'public.patrones' then
      array['capacidad']
    when 'public.plan_puntos' then
      array['carga_nominal', 'tolerancia']
    when 'public.verificaciones' then
      array['temperatura_c', 'humedad_relativa_pct']
    when 'public.pruebas' then
      array['tolerancia', 'error_max_abs', 'media', 'desviacion_estandar', 'rango']
    when 'public.lecturas' then
      array['carga_nominal', 'indicacion', 'retorno_cero', 'error', 'tolerancia']
    else
      array[]::text[]
  end;

  /* Las versiones bigint tambien cruzan HTTP como texto para no depender de 2^53. */
  numeric_fields := numeric_fields || array['source_version', 'row_version'];

  foreach field_name in array numeric_fields loop
    if result ? field_name and jsonb_typeof(result -> field_name) = 'number' then
      result := jsonb_set(
        result,
        array[field_name],
        to_jsonb(result ->> field_name),
        false
      );
    end if;
  end loop;

  return result;
end;
$$;

create or replace function private.capture_sync_outbox()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  key_data jsonb := '{}'::jsonb;
  key_name text;
  operation_code char(1);
  aggregate_name text := tg_table_schema || '.' || tg_table_name;
begin
  if tg_op = 'DELETE' then
    row_data := to_jsonb(old);
    operation_code := 'D';
  else
    row_data := to_jsonb(new);
    operation_code := case when tg_op = 'INSERT' then 'I' else 'U' end;
  end if;

  foreach key_name in array tg_argv loop
    if not (row_data ? key_name) or row_data -> key_name = 'null'::jsonb then
      raise exception 'Missing outbox key % on %.%', key_name, tg_table_schema, tg_table_name;
    end if;
    key_data := key_data || jsonb_build_object(key_name, row_data -> key_name);
  end loop;

  row_data := private.stringify_ivmet_outbox_numbers(aggregate_name, row_data);

  insert into private.sync_outbox (
    aggregate_type,
    aggregate_key,
    operation,
    payload
  ) values (
    aggregate_name,
    key_data,
    operation_code,
    row_data
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

/* Normaliza tambien los eventos aun no consumidos creados antes de esta migracion. */
update private.sync_outbox o
set payload = private.stringify_ivmet_outbox_numbers(o.aggregate_type, o.payload)
where o.estado in ('PENDING', 'CLAIMED');

create or replace function public.list_ivmet_catalog_sync_scopes(
  target_scope_id uuid default null
)
returns table (
  scope_id uuid,
  legacy_cliente_id integer,
  legacy_codigo_cliente varchar,
  supabase_cliente_id uuid,
  scope_status varchar,
  plant_codes text[],
  equipment_codes text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.id,
    s.legacy_cliente_id,
    s.legacy_codigo_cliente,
    s.supabase_cliente_id,
    s.estado,
    coalesce(
      array(
        select p.legacy_codigo_planta::text
        from private.catalog_sync_scope_plants p
        where p.scope_id = s.id and p.habilitada
        order by p.legacy_codigo_planta
      ),
      array[]::text[]
    ),
    coalesce(
      array(
        select e.legacy_cod_metrica::text
        from private.catalog_sync_scope_equipments e
        where e.scope_id = s.id and e.habilitado
        order by e.legacy_cod_metrica
      ),
      array[]::text[]
    )
  from private.catalog_sync_scope s
  where s.estado in ('REQUESTED', 'ACTIVE')
    and (target_scope_id is null or s.id = target_scope_id)
  order by s.solicitado_at, s.id;
$$;

create or replace function public.begin_ivmet_sync_run(
  direction text,
  worker_id text,
  target_scope_id uuid default null,
  run_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_run_id uuid;
begin
  if direction not in ('DATAMET_TO_SUPABASE', 'SUPABASE_TO_SQL_IVMET') then
    raise exception using errcode = '22023', message = 'INVALID_SYNC_DIRECTION';
  end if;
  if worker_id is null or btrim(worker_id) = '' then
    raise exception using errcode = '22023', message = 'WORKER_ID_REQUIRED';
  end if;
  if run_metadata is null or jsonb_typeof(run_metadata) <> 'object' then
    raise exception using errcode = '22023', message = 'RUN_METADATA_MUST_BE_OBJECT';
  end if;

  insert into private.sync_runs (direccion, worker_id, scope_id, metadata)
  values (direction, worker_id, target_scope_id, run_metadata)
  returning id into created_run_id;

  return created_run_id;
end;
$$;

create or replace function public.finish_ivmet_sync_run(
  target_run_id uuid,
  final_status text,
  scanned_count integer,
  accepted_count integer,
  unchanged_count integer,
  rejected_count integer,
  error_message text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  if final_status not in ('SUCCEEDED', 'PARTIAL', 'FAILED') then
    raise exception using errcode = '22023', message = 'INVALID_SYNC_RUN_STATUS';
  end if;
  if scanned_count < 0 or accepted_count < 0
     or unchanged_count < 0 or rejected_count < 0
     or accepted_count + unchanged_count + rejected_count > scanned_count then
    raise exception using errcode = '22023', message = 'INVALID_SYNC_RUN_COUNTS';
  end if;

  update private.sync_runs r
  set estado = final_status,
      finished_at = now(),
      scanned_count = finish_ivmet_sync_run.scanned_count,
      accepted_count = finish_ivmet_sync_run.accepted_count,
      unchanged_count = finish_ivmet_sync_run.unchanged_count,
      rejected_count = finish_ivmet_sync_run.rejected_count,
      error = left(error_message, 4000)
  where r.id = target_run_id and r.estado = 'RUNNING';

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.record_ivmet_legacy_identity(
  target_run_id uuid,
  target_entity_type text,
  target_legacy_key text,
  target_supabase_id uuid,
  target_source_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity_id uuid;
begin
  if target_entity_type not in ('CLIENT', 'PLANT', 'EQUIPMENT', 'EQUIPMENT_RANGE') then
    raise exception using errcode = '22023', message = 'INVALID_LEGACY_ENTITY_TYPE';
  end if;
  if target_legacy_key is null or btrim(target_legacy_key) = '' then
    raise exception using errcode = '22023', message = 'LEGACY_KEY_REQUIRED';
  end if;
  if target_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_SOURCE_HASH';
  end if;

  insert into private.legacy_identity_map (
    entity_type,
    legacy_key,
    supabase_id,
    last_seen_at,
    last_source_hash,
    last_run_id
  ) values (
    target_entity_type,
    target_legacy_key,
    target_supabase_id,
    now(),
    target_source_hash,
    target_run_id
  )
  on conflict (entity_type, legacy_key) do update
  set supabase_id = excluded.supabase_id,
      last_seen_at = excluded.last_seen_at,
      last_source_hash = excluded.last_source_hash,
      last_run_id = excluded.last_run_id
  returning id into identity_id;

  return identity_id;
end;
$$;

create or replace function public.record_ivmet_sync_quarantine(
  target_run_id uuid,
  target_entity_type text,
  target_source_key text,
  target_reason_code text,
  target_reason_detail text,
  target_safe_payload jsonb,
  target_payload_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  quarantine_id uuid;
begin
  if target_source_key is null or btrim(target_source_key) = '' then
    raise exception using errcode = '22023', message = 'SOURCE_KEY_REQUIRED';
  end if;
  if target_reason_code is null or btrim(target_reason_code) = '' then
    raise exception using errcode = '22023', message = 'REASON_CODE_REQUIRED';
  end if;
  if target_payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_PAYLOAD_HASH';
  end if;

  insert into private.sync_quarantine (
    run_id,
    entity_type,
    source_key,
    reason_code,
    reason_detail,
    safe_payload,
    payload_hash
  ) values (
    target_run_id,
    target_entity_type,
    target_source_key,
    target_reason_code,
    left(target_reason_detail, 4000),
    coalesce(target_safe_payload, '{}'::jsonb),
    target_payload_hash
  )
  returning id into quarantine_id;

  return quarantine_id;
end;
$$;

create or replace function public.mark_ivmet_catalog_sync_scope(
  target_scope_id uuid,
  target_supabase_cliente_id uuid,
  successful boolean,
  detail text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  update private.catalog_sync_scope s
  set supabase_cliente_id = coalesce(target_supabase_cliente_id, s.supabase_cliente_id),
      estado = case when successful then 'ACTIVE' else s.estado end,
      activado_at = case when successful then coalesce(s.activado_at, now()) else s.activado_at end,
      motivo = case when successful then null else left(detail, 4000) end
  where s.id = target_scope_id
    and s.estado in ('REQUESTED', 'ACTIVE');

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

/*
 * Un CLAIMED abandonado por una caida vuelve a ser reclamable tras cinco
 * minutos. El procesamiento en SQL Server sigue siendo idempotente por event_id.
 */
create or replace function public.claim_ivmet_sync_outbox(
  worker_id text,
  batch_size integer default 100
)
returns table (
  event_id uuid,
  sequence bigint,
  aggregate_type varchar,
  aggregate_key jsonb,
  operation char,
  payload jsonb,
  attempts integer,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if worker_id is null or btrim(worker_id) = '' then
    raise exception using errcode = '22023', message = 'WORKER_ID_REQUIRED';
  end if;

  return query
  with candidates as (
    select o.event_id
    from private.sync_outbox o
    where (
        (o.estado = 'PENDING' and o.available_at <= now())
        or (o.estado = 'CLAIMED' and o.claimed_at < now() - interval '5 minutes')
      )
      and not exists (
        select 1
        from private.sync_outbox blocked
        where blocked.estado = 'DEAD'
          and blocked.sequence < o.sequence
      )
    order by o.sequence
    for update skip locked
    limit least(greatest(batch_size, 1), 500)
  ), claimed as (
    update private.sync_outbox o
    set estado = 'CLAIMED',
        claimed_at = now(),
        claimed_by = worker_id,
        attempts = o.attempts + 1,
        last_error = null
    from candidates c
    where o.event_id = c.event_id
    returning o.*
  )
  select c.event_id, c.sequence, c.aggregate_type, c.aggregate_key,
         c.operation, c.payload, c.attempts, c.created_at
  from claimed c
  order by c.sequence;
end;
$$;

create or replace function public.release_ivmet_sync_outbox(
  worker_id text,
  event_ids uuid[],
  retry_after_seconds integer default 5
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  update private.sync_outbox o
  set estado = 'PENDING',
      available_at = now() + make_interval(
        secs => least(greatest(retry_after_seconds, 1), 3600)
      ),
      claimed_at = null,
      claimed_by = null
  where o.event_id = any(event_ids)
    and o.estado = 'CLAIMED'
    and o.claimed_by = worker_id;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.list_ivmet_catalog_sync_scopes(uuid)
  from public, anon, authenticated;
revoke all on function public.begin_ivmet_sync_run(text, text, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.finish_ivmet_sync_run(uuid, text, integer, integer, integer, integer, text)
  from public, anon, authenticated;
revoke all on function public.record_ivmet_legacy_identity(uuid, text, text, uuid, text)
  from public, anon, authenticated;
revoke all on function public.record_ivmet_sync_quarantine(uuid, text, text, text, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.mark_ivmet_catalog_sync_scope(uuid, uuid, boolean, text)
  from public, anon, authenticated;
revoke all on function public.release_ivmet_sync_outbox(text, uuid[], integer)
  from public, anon, authenticated;

grant execute on function public.list_ivmet_catalog_sync_scopes(uuid) to service_role;
grant execute on function public.begin_ivmet_sync_run(text, text, uuid, jsonb) to service_role;
grant execute on function public.finish_ivmet_sync_run(uuid, text, integer, integer, integer, integer, text)
  to service_role;
grant execute on function public.record_ivmet_legacy_identity(uuid, text, text, uuid, text)
  to service_role;
grant execute on function public.record_ivmet_sync_quarantine(uuid, text, text, text, text, jsonb, text)
  to service_role;
grant execute on function public.mark_ivmet_catalog_sync_scope(uuid, uuid, boolean, text)
  to service_role;
grant execute on function public.release_ivmet_sync_outbox(text, uuid[], integer)
  to service_role;

commit;

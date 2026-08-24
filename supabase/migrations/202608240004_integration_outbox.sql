begin;

create table private.catalog_sync_scope (
  id uuid primary key default extensions.gen_random_uuid(),
  legacy_cliente_id integer not null unique,
  legacy_codigo_cliente varchar(20) not null,
  supabase_cliente_id uuid unique references public.clientes(id),
  estado varchar(20) not null default 'REQUESTED',
  solicitado_por varchar(150) not null,
  solicitado_at timestamptz not null default now(),
  activado_at timestamptz,
  desactivado_at timestamptz,
  motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint catalog_sync_scope_codigo_ck check (
    legacy_codigo_cliente = btrim(legacy_codigo_cliente)
    and legacy_codigo_cliente <> ''
  ),
  constraint catalog_sync_scope_estado_ck check (
    estado in ('REQUESTED', 'ACTIVE', 'SUSPENDED', 'OFFBOARDING', 'DISABLED')
  )
);

create table private.catalog_sync_scope_plants (
  id uuid primary key default extensions.gen_random_uuid(),
  scope_id uuid not null references private.catalog_sync_scope(id),
  legacy_codigo_planta varchar(50) not null,
  habilitada boolean not null default true,
  requested_by varchar(150) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint catalog_sync_scope_plants_uq unique (scope_id, legacy_codigo_planta),
  constraint catalog_sync_scope_plants_codigo_ck check (
    legacy_codigo_planta = btrim(legacy_codigo_planta)
    and legacy_codigo_planta <> ''
  )
);

create table private.catalog_sync_scope_equipments (
  id uuid primary key default extensions.gen_random_uuid(),
  scope_id uuid not null references private.catalog_sync_scope(id),
  legacy_cod_metrica varchar(12) not null,
  habilitado boolean not null default true,
  requested_by varchar(150) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint catalog_sync_scope_equipments_uq unique (scope_id, legacy_cod_metrica),
  constraint catalog_sync_scope_equipments_codigo_ck check (
    legacy_cod_metrica ~ '^[0-9]{4}-[0-9]{2}-[0-9]{3}$'
  )
);

create table private.sync_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  direccion varchar(30) not null,
  worker_id varchar(150) not null,
  estado varchar(20) not null default 'RUNNING',
  scope_id uuid references private.catalog_sync_scope(id),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  scanned_count integer not null default 0,
  accepted_count integer not null default 0,
  unchanged_count integer not null default 0,
  rejected_count integer not null default 0,
  error text,
  metadata jsonb not null default '{}'::jsonb,
  constraint sync_runs_direction_ck check (
    direccion in ('DATAMET_TO_SUPABASE', 'SUPABASE_TO_SQL_IVMET')
  ),
  constraint sync_runs_estado_ck check (
    estado in ('RUNNING', 'SUCCEEDED', 'PARTIAL', 'FAILED')
  ),
  constraint sync_runs_counts_ck check (
    scanned_count >= 0 and accepted_count >= 0
    and unchanged_count >= 0 and rejected_count >= 0
  )
);

create index sync_runs_timeline_idx
  on private.sync_runs (direccion, started_at desc);

create table private.legacy_identity_map (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type varchar(30) not null,
  legacy_key varchar(150) not null,
  supabase_id uuid not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_source_hash text not null,
  last_run_id uuid references private.sync_runs(id),
  constraint legacy_identity_map_key_uq unique (entity_type, legacy_key),
  constraint legacy_identity_map_target_uq unique (entity_type, supabase_id),
  constraint legacy_identity_map_type_ck check (
    entity_type in ('CLIENT', 'PLANT', 'EQUIPMENT', 'EQUIPMENT_RANGE')
  ),
  constraint legacy_identity_map_hash_ck check (
    last_source_hash ~ '^[0-9a-f]{64}$'
  )
);

create table private.sync_quarantine (
  id uuid primary key default extensions.gen_random_uuid(),
  run_id uuid not null references private.sync_runs(id),
  entity_type varchar(30) not null,
  source_key varchar(150) not null,
  reason_code varchar(80) not null,
  reason_detail text,
  safe_payload jsonb not null default '{}'::jsonb,
  payload_hash text not null,
  estado varchar(20) not null default 'OPEN',
  resolved_at timestamptz,
  resolved_by varchar(150),
  resolution_note text,
  created_at timestamptz not null default now(),
  constraint sync_quarantine_hash_ck check (payload_hash ~ '^[0-9a-f]{64}$'),
  constraint sync_quarantine_estado_ck check (estado in ('OPEN', 'RESOLVED', 'IGNORED'))
);

create index sync_quarantine_open_idx
  on private.sync_quarantine (estado, created_at desc)
  where estado = 'OPEN';

create table private.sync_outbox (
  event_id uuid primary key default extensions.gen_random_uuid(),
  sequence bigint generated always as identity unique,
  aggregate_type varchar(80) not null,
  aggregate_key jsonb not null,
  operation char(1) not null,
  payload jsonb not null,
  estado varchar(20) not null default 'PENDING',
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by varchar(150),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  constraint sync_outbox_operation_ck check (operation in ('I', 'U', 'D')),
  constraint sync_outbox_estado_ck check (
    estado in ('PENDING', 'CLAIMED', 'PROCESSED', 'DEAD')
  ),
  constraint sync_outbox_attempts_ck check (attempts >= 0)
);

create index sync_outbox_pending_idx
  on private.sync_outbox (available_at, sequence)
  where estado = 'PENDING';

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

  insert into private.sync_outbox (
    aggregate_type,
    aggregate_key,
    operation,
    payload
  ) values (
    tg_table_schema || '.' || tg_table_name,
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

create trigger clientes_sync_outbox after insert or update or delete on public.clientes
for each row execute function private.capture_sync_outbox('id');
create trigger plantas_sync_outbox after insert or update or delete on public.plantas
for each row execute function private.capture_sync_outbox('id');
create trigger equipos_sync_outbox after insert or update or delete on public.equipos
for each row execute function private.capture_sync_outbox('id');
create trigger equipo_rangos_sync_outbox after insert or update or delete on public.equipo_rangos
for each row execute function private.capture_sync_outbox('id');
create trigger perfiles_sync_outbox after insert or update or delete on public.perfiles
for each row execute function private.capture_sync_outbox('id');
create trigger usuario_plantas_sync_outbox after insert or update or delete on public.usuario_plantas
for each row execute function private.capture_sync_outbox('usuario_id', 'planta_id');

create trigger planes_comerciales_sync_outbox after insert or update or delete on public.planes_comerciales
for each row execute function private.capture_sync_outbox('id');
create trigger precios_plan_sync_outbox after insert or update or delete on public.precios_plan
for each row execute function private.capture_sync_outbox('id');
create trigger contratos_sync_outbox after insert or update or delete on public.contratos
for each row execute function private.capture_sync_outbox('id');
create trigger suscripciones_sync_outbox after insert or update or delete on public.suscripciones
for each row execute function private.capture_sync_outbox('id');
create trigger facturas_sync_outbox after insert or update or delete on public.facturas
for each row execute function private.capture_sync_outbox('id');
create trigger pagos_sync_outbox after insert or update or delete on public.pagos
for each row execute function private.capture_sync_outbox('id');
create trigger suscripcion_cupos_sync_outbox after insert or update or delete on public.suscripcion_cupos
for each row execute function private.capture_sync_outbox('id');
create trigger licencias_usuario_sync_outbox after insert or update or delete on public.licencias_usuario
for each row execute function private.capture_sync_outbox('id');
create trigger eventos_licencia_sync_outbox after insert on public.eventos_licencia
for each row execute function private.capture_sync_outbox('id');

create trigger areas_sync_outbox after insert or update or delete on public.areas
for each row execute function private.capture_sync_outbox('id');
create trigger equipos_ivmet_sync_outbox after insert or update or delete on public.equipos_ivmet
for each row execute function private.capture_sync_outbox('equipo_id');
create trigger patrones_sync_outbox after insert or update or delete on public.patrones
for each row execute function private.capture_sync_outbox('id');
create trigger patron_plantas_sync_outbox after insert or update or delete on public.patron_plantas
for each row execute function private.capture_sync_outbox('patron_id', 'planta_id');
create trigger patron_certificados_sync_outbox after insert or update or delete on public.patron_certificados
for each row execute function private.capture_sync_outbox('id');
create trigger planes_sync_outbox after insert or update or delete on public.planes
for each row execute function private.capture_sync_outbox('id');
create trigger plan_versiones_sync_outbox after insert or update or delete on public.plan_versiones
for each row execute function private.capture_sync_outbox('id');
create trigger plan_pruebas_sync_outbox after insert or update or delete on public.plan_pruebas
for each row execute function private.capture_sync_outbox('id');
create trigger plan_puntos_sync_outbox after insert or update or delete on public.plan_puntos
for each row execute function private.capture_sync_outbox('id');
create trigger equipo_planes_sync_outbox after insert or update or delete on public.equipo_planes
for each row execute function private.capture_sync_outbox('id');
create trigger verificacion_borradores_sync_outbox after insert or update or delete on public.verificacion_borradores
for each row execute function private.capture_sync_outbox('id');
create trigger verificaciones_sync_outbox after insert or update on public.verificaciones
for each row execute function private.capture_sync_outbox('id');
create trigger verificacion_patrones_sync_outbox after insert on public.verificacion_patrones
for each row execute function private.capture_sync_outbox('verificacion_id', 'patron_id', 'rol');
create trigger pruebas_sync_outbox after insert on public.pruebas
for each row execute function private.capture_sync_outbox('id');
create trigger lecturas_sync_outbox after insert on public.lecturas
for each row execute function private.capture_sync_outbox('id');
create trigger alertas_sync_outbox after insert or update or delete on public.alertas
for each row execute function private.capture_sync_outbox('id');
create trigger auditoria_sync_outbox after insert on public.auditoria
for each row execute function private.capture_sync_outbox('id');

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
    where o.estado = 'PENDING'
      and o.available_at <= now()
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

create or replace function public.ack_ivmet_sync_outbox(
  worker_id text,
  event_ids uuid[]
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
  set estado = 'PROCESSED',
      processed_at = now(),
      claimed_at = null,
      claimed_by = null
  where o.event_id = any(event_ids)
    and o.estado = 'CLAIMED'
    and o.claimed_by = worker_id;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function public.fail_ivmet_sync_outbox(
  worker_id text,
  target_event_id uuid,
  error_message text,
  retry_after_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  update private.sync_outbox o
  set estado = case when o.attempts >= 10 then 'DEAD' else 'PENDING' end,
      available_at = case
        when o.attempts >= 10 then o.available_at
        else now() + make_interval(secs => least(greatest(retry_after_seconds, 1), 86400))
      end,
      claimed_at = null,
      claimed_by = null,
      last_error = left(error_message, 4000)
  where o.event_id = target_event_id
    and o.estado = 'CLAIMED'
    and o.claimed_by = worker_id;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create trigger catalog_sync_scope_set_updated_at
before update on private.catalog_sync_scope
for each row execute function private.set_updated_at();
create trigger catalog_sync_scope_plants_set_updated_at
before update on private.catalog_sync_scope_plants
for each row execute function private.set_updated_at();
create trigger catalog_sync_scope_equipments_set_updated_at
before update on private.catalog_sync_scope_equipments
for each row execute function private.set_updated_at();

revoke all on all tables in schema private from anon, authenticated;
grant select, insert, update on private.catalog_sync_scope to service_role;
grant select, insert, update on private.catalog_sync_scope_plants to service_role;
grant select, insert, update on private.catalog_sync_scope_equipments to service_role;
grant select, insert, update on private.sync_runs to service_role;
grant select, insert, update on private.legacy_identity_map to service_role;
grant select, insert, update on private.sync_quarantine to service_role;
grant select, insert, update on private.sync_outbox to service_role;

revoke all on function public.claim_ivmet_sync_outbox(text, integer)
  from public, anon, authenticated;
revoke all on function public.ack_ivmet_sync_outbox(text, uuid[])
  from public, anon, authenticated;
revoke all on function public.fail_ivmet_sync_outbox(text, uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.claim_ivmet_sync_outbox(text, integer) to service_role;
grant execute on function public.ack_ivmet_sync_outbox(text, uuid[]) to service_role;
grant execute on function public.fail_ivmet_sync_outbox(text, uuid, text, integer) to service_role;

commit;

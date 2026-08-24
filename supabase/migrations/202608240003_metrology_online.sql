begin;

create table public.areas (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  nombre varchar(150) not null,
  nombre_normalizado varchar(150) generated always as (lower(btrim(nombre))) stored,
  activa boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint areas_nombre_uq unique (cliente_id, planta_id, nombre_normalizado),
  constraint areas_id_scope_uq unique (id, cliente_id, planta_id),
  constraint areas_planta_cliente_fk foreign key (planta_id, cliente_id)
    references public.plantas(id, cliente_id),
  constraint areas_nombre_ck check (btrim(nombre) <> '')
);

create index areas_scope_idx on public.areas (cliente_id, planta_id, activa);

create table public.equipos_ivmet (
  equipo_id uuid primary key references public.equipos(id),
  area_id uuid references public.areas(id),
  habilitado boolean not null default false,
  estado_configuracion varchar(20) not null default 'PENDING',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint equipos_ivmet_estado_ck check (
    estado_configuracion in ('PENDING', 'READY', 'SUSPENDED')
  )
);

create index equipos_ivmet_habilitados_idx
  on public.equipos_ivmet (habilitado, estado_configuracion)
  where habilitado;

create table public.patrones (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  codigo varchar(100) not null,
  descripcion varchar(300) not null,
  tipo varchar(50) not null,
  clase varchar(50),
  unidad varchar(20),
  capacidad numeric(19,9),
  activo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint patrones_codigo_uq unique (cliente_id, codigo),
  constraint patrones_capacidad_ck check (capacidad is null or capacidad > 0)
);

create table public.patron_plantas (
  patron_id uuid not null references public.patrones(id) on delete restrict,
  planta_id uuid not null references public.plantas(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (patron_id, planta_id)
);

create index patron_plantas_planta_idx on public.patron_plantas (planta_id, patron_id);

create table public.patron_certificados (
  id uuid primary key default extensions.gen_random_uuid(),
  patron_id uuid not null references public.patrones(id),
  numero varchar(150) not null,
  laboratorio varchar(250) not null,
  calibrado_el date not null,
  vence_el date not null,
  estado varchar(20) not null default 'ACTIVE',
  archivo_path text,
  archivo_hash text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint patron_certificados_numero_uq unique (patron_id, numero),
  constraint patron_certificados_estado_ck check (estado in ('ACTIVE', 'ANNULLED')),
  constraint patron_certificados_fechas_ck check (vence_el >= calibrado_el),
  constraint patron_certificados_hash_ck check (
    archivo_hash is null or archivo_hash ~ '^[0-9a-f]{64}$'
  )
);

create index patron_certificados_vigencia_idx
  on public.patron_certificados (patron_id, estado, vence_el desc);

create table public.planes (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid references public.clientes(id),
  nombre varchar(200) not null,
  descripcion text,
  activo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint planes_nombre_uq unique nulls not distinct (cliente_id, nombre)
);

create table public.plan_versiones (
  id uuid primary key default extensions.gen_random_uuid(),
  plan_id uuid not null references public.planes(id),
  version integer not null,
  estado varchar(20) not null default 'DRAFT',
  procedimiento_referencia varchar(300),
  notas text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  published_by uuid references auth.users(id),
  published_at timestamptz,
  retired_by uuid references auth.users(id),
  retired_at timestamptz,
  constraint plan_versiones_numero_uq unique (plan_id, version),
  constraint plan_versiones_version_ck check (version > 0),
  constraint plan_versiones_estado_ck check (estado in ('DRAFT', 'PUBLISHED', 'RETIRED')),
  constraint plan_versiones_publicacion_ck check (
    (estado = 'DRAFT' and published_at is null and published_by is null)
    or (estado in ('PUBLISHED', 'RETIRED') and published_at is not null and published_by is not null)
  )
);

create index plan_versiones_estado_idx on public.plan_versiones (estado, plan_id, version desc);

create table public.plan_pruebas (
  id uuid primary key default extensions.gen_random_uuid(),
  plan_version_id uuid not null references public.plan_versiones(id),
  tipo varchar(30) not null,
  metodo_evaluacion varchar(60) not null,
  unidad varchar(20) not null,
  frecuencia_dias integer not null,
  aviso_dias integer not null default 7,
  metadata jsonb not null default '{}'::jsonb,
  constraint plan_pruebas_tipo_uq unique (plan_version_id, tipo),
  constraint plan_pruebas_tipo_ck check (
    tipo in ('eccentricity', 'repeatability', 'linearity')
  ),
  constraint plan_pruebas_metodo_ck check (
    metodo_evaluacion in ('absolute_error', 'range', 'sample_standard_deviation')
  ),
  constraint plan_pruebas_frecuencia_ck check (frecuencia_dias > 0 and aviso_dias >= 0)
);

create table public.plan_puntos (
  id uuid primary key default extensions.gen_random_uuid(),
  plan_prueba_id uuid not null references public.plan_pruebas(id),
  grupo integer not null default 1,
  orden integer not null,
  codigo varchar(100) not null,
  etiqueta varchar(200) not null,
  carga_nominal numeric(19,9) not null,
  tolerancia numeric(19,9) not null,
  posicion varchar(100),
  direccion varchar(30),
  metadata jsonb not null default '{}'::jsonb,
  constraint plan_puntos_orden_uq unique (plan_prueba_id, orden),
  constraint plan_puntos_codigo_uq unique (plan_prueba_id, codigo),
  constraint plan_puntos_grupo_ck check (grupo > 0 and orden > 0),
  constraint plan_puntos_valores_ck check (carga_nominal >= 0 and tolerancia >= 0)
);

create table public.equipo_planes (
  id uuid primary key default extensions.gen_random_uuid(),
  equipo_id uuid not null references public.equipos(id),
  plan_version_id uuid not null references public.plan_versiones(id),
  vigente_desde timestamptz not null,
  vigente_hasta timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint equipo_planes_vigencia_ck check (
    vigente_hasta is null or vigente_hasta > vigente_desde
  )
);

create unique index equipo_planes_vigente_uq
  on public.equipo_planes (equipo_id)
  where vigente_hasta is null;

create table public.verificacion_borradores (
  id uuid primary key default extensions.gen_random_uuid(),
  request_uuid uuid not null unique,
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  area_id uuid references public.areas(id),
  equipo_id uuid not null references public.equipos(id),
  plan_version_id uuid not null references public.plan_versiones(id),
  usuario_id uuid not null references public.perfiles(id),
  estado varchar(20) not null default 'DRAFT',
  paso_actual varchar(30) not null default 'instrument',
  payload jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  finalized_at timestamptz,
  verificacion_id uuid,
  constraint verificacion_borradores_estado_ck check (
    estado in ('DRAFT', 'FINALIZING', 'FINALIZED', 'ABANDONED', 'EXPIRED')
  ),
  constraint verificacion_borradores_version_ck check (version > 0),
  constraint verificacion_borradores_finalizacion_ck check (
    (estado in ('DRAFT', 'ABANDONED', 'EXPIRED')
      and finalized_at is null and verificacion_id is null)
    or (estado = 'FINALIZING' and finalized_at is null and verificacion_id is null)
    or (estado = 'FINALIZED' and finalized_at is not null and verificacion_id is not null)
  ),
  constraint verificacion_borradores_equipo_scope_fk
    foreign key (equipo_id, cliente_id, planta_id)
    references public.equipos(id, cliente_id, planta_id),
  constraint verificacion_borradores_area_scope_fk
    foreign key (area_id, cliente_id, planta_id)
    references public.areas(id, cliente_id, planta_id),
  constraint verificacion_borradores_expira_ck check (expires_at > created_at)
);

create index verificacion_borradores_usuario_idx
  on public.verificacion_borradores (usuario_id, estado, updated_at desc);

create table public.verificaciones (
  id uuid primary key default extensions.gen_random_uuid(),
  request_uuid uuid not null unique,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  area_id uuid references public.areas(id),
  equipo_id uuid not null references public.equipos(id),
  plan_version_id uuid not null references public.plan_versiones(id),
  capturado_por uuid not null references public.perfiles(id),
  finalizado_por uuid not null references public.perfiles(id),
  realizado_at timestamptz not null,
  recibido_at timestamptz not null default now(),
  alcance varchar(20) not null,
  veredicto_global varchar(20),
  trazabilidad varchar(20) not null,
  temperatura_c numeric(9,3),
  humedad_relativa_pct numeric(9,3),
  observaciones text,
  equipo_snapshot jsonb not null,
  plan_snapshot jsonb not null,
  app_version varchar(50),
  dispositivo_id varchar(200),
  estado varchar(20) not null default 'ACTIVE',
  anulada_at timestamptz,
  anulada_por uuid references public.perfiles(id),
  motivo_anulacion text,
  constraint verificaciones_id_scope_uq unique (
    id, cliente_id, planta_id, equipo_id
  ),
  constraint verificaciones_equipo_scope_fk
    foreign key (equipo_id, cliente_id, planta_id)
    references public.equipos(id, cliente_id, planta_id),
  constraint verificaciones_area_scope_fk
    foreign key (area_id, cliente_id, planta_id)
    references public.areas(id, cliente_id, planta_id),
  constraint verificaciones_alcance_ck check (alcance in ('complete', 'partial')),
  constraint verificaciones_veredicto_ck check (
    veredicto_global is null or veredicto_global in ('pass', 'fail')
  ),
  constraint verificaciones_trazabilidad_ck check (
    trazabilidad in ('traceable', 'non_traceable')
  ),
  constraint verificaciones_humedad_ck check (
    humedad_relativa_pct is null or humedad_relativa_pct between 0 and 100
  ),
  constraint verificaciones_estado_ck check (estado in ('ACTIVE', 'ANNULLED')),
  constraint verificaciones_anulacion_ck check (
    (estado = 'ACTIVE' and anulada_at is null and anulada_por is null and motivo_anulacion is null)
    or (estado = 'ANNULLED' and anulada_at is not null and anulada_por is not null and btrim(motivo_anulacion) <> '')
  )
);

alter table public.verificacion_borradores
  add constraint verificacion_borradores_verificacion_fk
  foreign key (verificacion_id) references public.verificaciones(id);

create index verificaciones_historial_idx
  on public.verificaciones (cliente_id, planta_id, equipo_id, realizado_at desc);

create table public.verificacion_patrones (
  verificacion_id uuid not null references public.verificaciones(id),
  patron_id uuid not null references public.patrones(id),
  certificado_id uuid not null references public.patron_certificados(id),
  rol varchar(30) not null,
  snapshot jsonb not null,
  primary key (verificacion_id, patron_id, rol)
);

create table public.pruebas (
  id uuid primary key default extensions.gen_random_uuid(),
  verificacion_id uuid not null references public.verificaciones(id),
  plan_prueba_id uuid not null references public.plan_pruebas(id),
  tipo varchar(30) not null,
  estado_ejecucion varchar(20) not null,
  motivo_omision text,
  metodo_evaluacion varchar(60) not null,
  unidad varchar(20) not null,
  tolerancia numeric(19,9),
  veredicto varchar(20),
  error_max_abs numeric(19,9),
  media numeric(19,9),
  desviacion_estandar numeric(19,9),
  rango numeric(19,9),
  observaciones text,
  constraint pruebas_tipo_uq unique (verificacion_id, tipo),
  constraint pruebas_tipo_ck check (tipo in ('eccentricity', 'repeatability', 'linearity')),
  constraint pruebas_estado_ck check (estado_ejecucion in ('executed', 'omitted')),
  constraint pruebas_omision_ck check (
    (estado_ejecucion = 'executed' and motivo_omision is null)
    or (estado_ejecucion = 'omitted' and btrim(motivo_omision) <> '')
  ),
  constraint pruebas_veredicto_ck check (veredicto is null or veredicto in ('pass', 'fail'))
);

create table public.lecturas (
  id uuid primary key default extensions.gen_random_uuid(),
  prueba_id uuid not null references public.pruebas(id),
  plan_punto_id uuid references public.plan_puntos(id),
  grupo integer not null,
  orden integer not null,
  punto_codigo varchar(100) not null,
  etiqueta varchar(200) not null,
  carga_nominal numeric(19,9) not null,
  indicacion numeric(19,9) not null,
  retorno_cero numeric(19,9),
  error numeric(19,9) not null,
  tolerancia numeric(19,9) not null,
  veredicto varchar(20) not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint lecturas_orden_uq unique (prueba_id, orden),
  constraint lecturas_grupo_ck check (grupo > 0 and orden > 0),
  constraint lecturas_tolerancia_ck check (tolerancia >= 0),
  constraint lecturas_veredicto_ck check (veredicto in ('pass', 'fail'))
);

create table public.alertas (
  id uuid primary key default extensions.gen_random_uuid(),
  verificacion_id uuid not null unique references public.verificaciones(id),
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  equipo_id uuid not null references public.equipos(id),
  tipo varchar(30) not null,
  resumen text not null,
  estado_cliente varchar(20) not null default 'OPEN',
  visibilidad_metrica varchar(20) not null default 'PRIVATE',
  compartida_at timestamptz,
  compartida_por uuid references public.perfiles(id),
  mensaje_compartido text,
  estado_metrica varchar(20) not null default 'PENDING',
  reconocida_at timestamptz,
  reconocida_por uuid references public.perfiles(id),
  atendida_at timestamptz,
  atendida_por uuid references public.perfiles(id),
  nota_atencion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint alertas_verificacion_scope_fk
    foreign key (verificacion_id, cliente_id, planta_id, equipo_id)
    references public.verificaciones(id, cliente_id, planta_id, equipo_id),
  constraint alertas_estado_cliente_ck check (estado_cliente in ('OPEN', 'CLOSED')),
  constraint alertas_visibilidad_ck check (visibilidad_metrica in ('PRIVATE', 'SHARED')),
  constraint alertas_estado_metrica_ck check (
    estado_metrica in ('PENDING', 'ACKNOWLEDGED', 'ATTENDED')
  ),
  constraint alertas_compartida_ck check (
    (visibilidad_metrica = 'PRIVATE'
      and compartida_at is null and compartida_por is null and mensaje_compartido is null)
    or (visibilidad_metrica = 'SHARED'
      and compartida_at is not null and compartida_por is not null)
  ),
  constraint alertas_atencion_ck check (
    (estado_metrica = 'PENDING'
      and reconocida_at is null and reconocida_por is null
      and atendida_at is null and atendida_por is null and nota_atencion is null)
    or (estado_metrica = 'ACKNOWLEDGED'
      and reconocida_at is not null and reconocida_por is not null
      and atendida_at is null and atendida_por is null and nota_atencion is null)
    or (estado_metrica = 'ATTENDED'
      and reconocida_at is not null and reconocida_por is not null
      and atendida_at is not null and atendida_por is not null
      and btrim(nota_atencion) <> '')
  )
);

create index alertas_cliente_idx
  on public.alertas (cliente_id, planta_id, estado_cliente, created_at desc);

create table public.auditoria (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid references auth.users(id),
  actor_externo varchar(150),
  cliente_id uuid references public.clientes(id),
  entidad varchar(80) not null,
  entidad_id varchar(150) not null,
  accion varchar(80) not null,
  antes jsonb,
  despues jsonb,
  ip inet,
  dispositivo_id varchar(200),
  created_at timestamptz not null default now()
);

create index auditoria_entidad_idx on public.auditoria (entidad, entidad_id, created_at desc);
create index auditoria_cliente_idx on public.auditoria (cliente_id, created_at desc);

create or replace function private.protect_published_plan_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_state text;
begin
  if tg_table_name = 'plan_pruebas' then
    select pv.estado into version_state
    from public.plan_versiones pv
    where pv.id = case when tg_op = 'DELETE' then old.plan_version_id else new.plan_version_id end;
  else
    select pv.estado into version_state
    from public.plan_versiones pv
    join public.plan_pruebas pt on pt.plan_version_id = pv.id
    where pt.id = case when tg_op = 'DELETE' then old.plan_prueba_id else new.plan_prueba_id end;
  end if;

  if version_state <> 'DRAFT' then
    raise exception using errcode = 'P0001', message = 'PUBLISHED_PLAN_IS_IMMUTABLE';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger plan_pruebas_immutable
before insert or update or delete on public.plan_pruebas
for each row execute function private.protect_published_plan_content();

create trigger plan_puntos_immutable
before insert or update or delete on public.plan_puntos
for each row execute function private.protect_published_plan_content();

create or replace function private.protect_plan_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.estado <> 'DRAFT' then
      raise exception using errcode = 'P0001', message = 'PUBLISHED_PLAN_IS_IMMUTABLE';
    end if;
    return old;
  end if;

  if old.estado = 'DRAFT' then
    if new.estado = 'DRAFT' then
      return new;
    end if;
    if new.estado = 'PUBLISHED'
       and new.published_at is not null
       and new.published_by is not null
       and (to_jsonb(new) - array['estado','published_at','published_by'])
           = (to_jsonb(old) - array['estado','published_at','published_by']) then
      return new;
    end if;
  elsif old.estado = 'PUBLISHED'
        and new.estado = 'RETIRED'
        and new.retired_at is not null
        and new.retired_by is not null
        and (to_jsonb(new) - array['estado','retired_at','retired_by'])
            = (to_jsonb(old) - array['estado','retired_at','retired_by']) then
    return new;
  end if;

  raise exception using errcode = 'P0001', message = 'INVALID_PLAN_VERSION_TRANSITION';
end;
$$;

create trigger plan_versiones_controlled_mutation
before update or delete on public.plan_versiones
for each row execute function private.protect_plan_version();

create or replace function private.prevent_evidence_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using errcode = 'P0001', message = 'ACCEPTED_EVIDENCE_IS_IMMUTABLE';
end;
$$;

create trigger verificacion_patrones_immutable
before update or delete on public.verificacion_patrones
for each row execute function private.prevent_evidence_mutation();

create trigger pruebas_immutable
before update or delete on public.pruebas
for each row execute function private.prevent_evidence_mutation();

create trigger lecturas_immutable
before update or delete on public.lecturas
for each row execute function private.prevent_evidence_mutation();

create or replace function private.protect_verification_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (to_jsonb(new) - array['estado','anulada_at','anulada_por','motivo_anulacion'])
       is distinct from
     (to_jsonb(old) - array['estado','anulada_at','anulada_por','motivo_anulacion']) then
    raise exception using errcode = 'P0001', message = 'ACCEPTED_EVIDENCE_IS_IMMUTABLE';
  end if;

  if not (
    old.estado = 'ACTIVE'
    and new.estado = 'ANNULLED'
    and new.anulada_at is not null
    and new.anulada_por is not null
    and btrim(new.motivo_anulacion) <> ''
  ) then
    raise exception using errcode = 'P0001', message = 'INVALID_VERIFICATION_TRANSITION';
  end if;
  return new;
end;
$$;

create trigger verificaciones_controlled_update
before update on public.verificaciones
for each row execute function private.protect_verification_update();

create trigger verificaciones_prevent_delete
before delete on public.verificaciones
for each row execute function private.prevent_evidence_mutation();

create trigger auditoria_immutable
before update or delete on public.auditoria
for each row execute function private.prevent_evidence_mutation();

create or replace function private.set_draft_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end;
$$;

create trigger areas_set_updated_at
before update on public.areas
for each row execute function private.set_updated_at();

create trigger equipos_ivmet_set_updated_at
before update on public.equipos_ivmet
for each row execute function private.set_updated_at();

create trigger patrones_set_updated_at
before update on public.patrones
for each row execute function private.set_updated_at();

create trigger planes_set_updated_at
before update on public.planes
for each row execute function private.set_updated_at();

create trigger verificacion_borradores_set_updated_at
before update on public.verificacion_borradores
for each row execute function private.set_draft_updated_at();

create trigger alertas_set_updated_at
before update on public.alertas
for each row execute function private.set_updated_at();

alter table public.areas enable row level security;
alter table public.equipos_ivmet enable row level security;
alter table public.patrones enable row level security;
alter table public.patron_plantas enable row level security;
alter table public.patron_certificados enable row level security;
alter table public.planes enable row level security;
alter table public.plan_versiones enable row level security;
alter table public.plan_pruebas enable row level security;
alter table public.plan_puntos enable row level security;
alter table public.equipo_planes enable row level security;
alter table public.verificacion_borradores enable row level security;
alter table public.verificaciones enable row level security;
alter table public.verificacion_patrones enable row level security;
alter table public.pruebas enable row level security;
alter table public.lecturas enable row level security;
alter table public.alertas enable row level security;
alter table public.auditoria enable row level security;

revoke all on public.areas from anon, authenticated;
revoke all on public.equipos_ivmet from anon, authenticated;
revoke all on public.patrones from anon, authenticated;
revoke all on public.patron_plantas from anon, authenticated;
revoke all on public.patron_certificados from anon, authenticated;
revoke all on public.planes from anon, authenticated;
revoke all on public.plan_versiones from anon, authenticated;
revoke all on public.plan_pruebas from anon, authenticated;
revoke all on public.plan_puntos from anon, authenticated;
revoke all on public.equipo_planes from anon, authenticated;
revoke all on public.verificacion_borradores from anon, authenticated;
revoke all on public.verificaciones from anon, authenticated;
revoke all on public.verificacion_patrones from anon, authenticated;
revoke all on public.pruebas from anon, authenticated;
revoke all on public.lecturas from anon, authenticated;
revoke all on public.alertas from anon, authenticated;
revoke all on public.auditoria from anon, authenticated;

commit;

begin;

create schema if not exists extensions;
create schema if not exists private;

create extension if not exists pgcrypto with schema extensions;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  if to_jsonb(new) ? 'row_version' then
    new.row_version := coalesce(old.row_version, 0) + 1;
  end if;
  return new;
end;
$$;

create table public.clientes (
  id uuid primary key default extensions.gen_random_uuid(),
  legacy_cliente_id integer not null,
  codigo varchar(20) not null,
  nombre varchar(100),
  razon_social varchar(100),
  estado_legacy varchar(10),
  activo boolean not null default true,
  source_version bigint not null default 1 check (source_version > 0),
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  last_seen_run_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clientes_legacy_cliente_id_uq unique (legacy_cliente_id),
  constraint clientes_codigo_uq unique (codigo),
  constraint clientes_codigo_trim_ck check (codigo = btrim(codigo) and codigo <> '')
);

create table public.plantas (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  legacy_codigo_planta varchar(50) not null,
  legacy_planta_numero integer,
  nombre varchar(100),
  direccion varchar(250),
  departamento_codigo varchar(10),
  departamento_id integer,
  localidad varchar(100),
  ubicacion varchar(100),
  estado_legacy varchar(10),
  activo boolean not null default true,
  source_version bigint not null default 1 check (source_version > 0),
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  last_seen_run_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plantas_legacy_codigo_uq unique (legacy_codigo_planta),
  constraint plantas_id_cliente_uq unique (id, cliente_id),
  constraint plantas_codigo_trim_ck check (
    legacy_codigo_planta = btrim(legacy_codigo_planta)
    and legacy_codigo_planta <> ''
  )
);

create index plantas_cliente_idx
  on public.plantas (cliente_id, activo, legacy_codigo_planta);

create table public.equipos (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  planta_id uuid not null references public.plantas(id),
  legacy_equipo_id integer not null,
  cod_metrica varchar(12) not null,
  cod_interno varchar(50),
  instrumento varchar(50),
  tipo_instrumento varchar(50),
  categoria varchar(20),
  tipo_balanza varchar(100),
  marca varchar(50),
  modelo varchar(50),
  serie varchar(70),
  unidad varchar(10),
  ubicacion varchar(200),
  comunicacion varchar(50),
  material varchar(50),
  acceso varchar(50),
  altura varchar(50),
  numero_celdas integer,
  tecnologia varchar(50),
  proteccion varchar(50),
  plataforma varchar(20),
  clase varchar(50),
  estado_legacy varchar(15),
  estado_catalogo varchar(30) not null default 'READY',
  activo boolean not null default true,
  source_version bigint not null default 1 check (source_version > 0),
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  last_seen_run_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equipos_legacy_equipo_id_uq unique (legacy_equipo_id),
  constraint equipos_cod_metrica_uq unique (cod_metrica),
  constraint equipos_id_scope_uq unique (id, cliente_id, planta_id),
  constraint equipos_planta_cliente_fk foreign key (planta_id, cliente_id)
    references public.plantas(id, cliente_id),
  constraint equipos_cod_metrica_format_ck check (
    cod_metrica ~ '^[0-9]{4}-[0-9]{2}-[0-9]{3}$'
  ),
  constraint equipos_estado_catalogo_ck check (
    estado_catalogo in ('READY', 'REQUIRES_REVIEW', 'QUARANTINED')
  ),
  constraint equipos_numero_celdas_ck check (numero_celdas is null or numero_celdas >= 0)
);

create index equipos_scope_idx
  on public.equipos (cliente_id, planta_id, activo, estado_catalogo);

create table public.equipo_rangos (
  id uuid primary key default extensions.gen_random_uuid(),
  equipo_id uuid not null references public.equipos(id),
  numero_rango smallint not null,
  unidad varchar(10) not null,
  capacidad_max numeric(19,9) not null,
  division_escala numeric(19,9) not null,
  intervalo_verificacion numeric(19,9),
  cantidad_decimales smallint,
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equipo_rangos_equipo_numero_uq unique (equipo_id, numero_rango),
  constraint equipo_rangos_numero_ck check (numero_rango between 1 and 99),
  constraint equipo_rangos_capacidad_ck check (capacidad_max > 0),
  constraint equipo_rangos_division_ck check (division_escala > 0),
  constraint equipo_rangos_intervalo_ck check (
    intervalo_verificacion is null or intervalo_verificacion > 0
  ),
  constraint equipo_rangos_decimales_ck check (
    cantidad_decimales is null or cantidad_decimales between 0 and 9
  )
);

create index equipo_rangos_equipo_idx on public.equipo_rangos (equipo_id);

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete restrict,
  usuario varchar(100) not null,
  usuario_normalizado varchar(100) not null,
  nombre varchar(200) not null,
  rol varchar(40) not null,
  cliente_id uuid references public.clientes(id),
  activo boolean not null default true,
  debe_cambiar_password boolean not null default true,
  ultimo_acceso_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint perfiles_usuario_normalizado_uq unique (usuario_normalizado),
  constraint perfiles_usuario_normalizado_ck check (
    usuario_normalizado = lower(btrim(usuario))
  ),
  constraint perfiles_rol_ck check (
    rol in (
      'cliente_operador',
      'cliente_jefe_calidad',
      'metrica_tecnico',
      'metrica_admin'
    )
  ),
  constraint perfiles_tenant_ck check (
    (rol like 'cliente_%' and cliente_id is not null)
    or (rol like 'metrica_%' and cliente_id is null)
  )
);

create index perfiles_cliente_idx on public.perfiles (cliente_id, activo, rol);

create table public.usuario_plantas (
  usuario_id uuid not null references public.perfiles(id) on delete restrict,
  planta_id uuid not null references public.plantas(id) on delete restrict,
  activa boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (usuario_id, planta_id)
);

create index usuario_plantas_planta_idx
  on public.usuario_plantas (planta_id, usuario_id)
  where activa;

create table private.login_aliases (
  usuario_normalizado varchar(100) primary key,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  auth_email_interno varchar(254) not null unique,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint login_aliases_normalizado_ck check (
    usuario_normalizado = lower(btrim(usuario_normalizado))
    and usuario_normalizado <> ''
  )
);

create table private.staff_access (
  id uuid primary key default extensions.gen_random_uuid(),
  source_system varchar(30) not null default 'RIMMET',
  external_user_id varchar(100) not null,
  usuario varchar(100) not null,
  rol_ivmet varchar(40) not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint staff_access_external_uq unique (source_system, external_user_id),
  constraint staff_access_rol_ck check (
    rol_ivmet in (
      'ivmet_superadmin',
      'ivmet_comercial',
      'ivmet_soporte',
      'ivmet_metrologia',
      'ivmet_consulta'
    )
  )
);

create trigger clientes_set_updated_at
before update on public.clientes
for each row execute function private.set_updated_at();

create trigger plantas_set_updated_at
before update on public.plantas
for each row execute function private.set_updated_at();

create trigger equipos_set_updated_at
before update on public.equipos
for each row execute function private.set_updated_at();

create trigger equipo_rangos_set_updated_at
before update on public.equipo_rangos
for each row execute function private.set_updated_at();

create trigger perfiles_set_updated_at
before update on public.perfiles
for each row execute function private.set_updated_at();

create trigger login_aliases_set_updated_at
before update on private.login_aliases
for each row execute function private.set_updated_at();

create trigger staff_access_set_updated_at
before update on private.staff_access
for each row execute function private.set_updated_at();

alter table public.clientes enable row level security;
alter table public.plantas enable row level security;
alter table public.equipos enable row level security;
alter table public.equipo_rangos enable row level security;
alter table public.perfiles enable row level security;
alter table public.usuario_plantas enable row level security;

revoke all on public.clientes from anon, authenticated;
revoke all on public.plantas from anon, authenticated;
revoke all on public.equipos from anon, authenticated;
revoke all on public.equipo_rangos from anon, authenticated;
revoke all on public.perfiles from anon, authenticated;
revoke all on public.usuario_plantas from anon, authenticated;
grant select on public.perfiles to authenticated;

create policy perfiles_select_self
on public.perfiles
for select
to authenticated
using (id = (select auth.uid()));

commit;

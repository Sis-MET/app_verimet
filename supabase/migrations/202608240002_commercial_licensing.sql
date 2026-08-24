begin;

create table public.planes_comerciales (
  id uuid primary key default extensions.gen_random_uuid(),
  codigo varchar(50) not null unique,
  nombre varchar(150) not null,
  descripcion text,
  cuentas_incluidas integer not null,
  dias_gracia integer not null default 0,
  caracteristicas jsonb not null default '{}'::jsonb,
  activo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint planes_comerciales_codigo_ck check (
    codigo = upper(btrim(codigo)) and codigo <> ''
  ),
  constraint planes_comerciales_cuentas_ck check (cuentas_incluidas > 0),
  constraint planes_comerciales_gracia_ck check (dias_gracia between 0 and 90)
);

create table public.precios_plan (
  id uuid primary key default extensions.gen_random_uuid(),
  plan_id uuid not null references public.planes_comerciales(id),
  periodicidad varchar(10) not null,
  moneda varchar(3) not null,
  importe numeric(19,2) not null,
  vigente_desde date not null,
  vigente_hasta date,
  activo boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint precios_plan_periodicidad_ck check (periodicidad in ('MONTHLY', 'ANNUAL')),
  constraint precios_plan_moneda_ck check (moneda = upper(moneda) and length(moneda) = 3),
  constraint precios_plan_importe_ck check (importe >= 0),
  constraint precios_plan_vigencia_ck check (
    vigente_hasta is null or vigente_hasta >= vigente_desde
  ),
  constraint precios_plan_version_uq unique (
    plan_id, periodicidad, moneda, vigente_desde
  )
);

create table public.contratos (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  numero_contrato varchar(100) not null unique,
  fecha_firma date,
  vigente_desde date not null,
  vigente_hasta date,
  estado varchar(20) not null default 'DRAFT',
  archivo_path text,
  archivo_hash text,
  observaciones text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint contratos_estado_ck check (
    estado in ('DRAFT', 'ACTIVE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')
  ),
  constraint contratos_vigencia_ck check (
    vigente_hasta is null or vigente_hasta >= vigente_desde
  ),
  constraint contratos_archivo_hash_ck check (
    archivo_hash is null or archivo_hash ~ '^[0-9a-f]{64}$'
  )
);

create index contratos_cliente_idx on public.contratos (cliente_id, estado, vigente_hasta);

create table public.suscripciones (
  id uuid primary key default extensions.gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  plan_id uuid not null references public.planes_comerciales(id),
  precio_plan_id uuid references public.precios_plan(id),
  periodicidad varchar(10) not null,
  inicio_periodo timestamptz not null,
  fin_periodo timestamptz not null,
  proximo_cobro date,
  gracia_hasta timestamptz,
  renovacion_automatica boolean not null default false,
  estado varchar(20) not null default 'PENDING',
  motivo_suspension text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint suscripciones_periodicidad_ck check (periodicidad in ('MONTHLY', 'ANNUAL')),
  constraint suscripciones_estado_ck check (
    estado in ('PENDING', 'ACTIVE', 'PAST_DUE', 'GRACE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')
  ),
  constraint suscripciones_periodo_ck check (fin_periodo > inicio_periodo),
  constraint suscripciones_gracia_ck check (
    gracia_hasta is null or gracia_hasta >= fin_periodo
  )
);

create unique index suscripciones_contrato_activa_uq
on public.suscripciones (contrato_id)
where estado in ('ACTIVE', 'PAST_DUE', 'GRACE');

create index suscripciones_estado_idx
  on public.suscripciones (estado, fin_periodo, gracia_hasta);

create table public.facturas (
  id uuid primary key default extensions.gen_random_uuid(),
  suscripcion_id uuid not null references public.suscripciones(id),
  numero_factura varchar(100) not null unique,
  periodo_desde date not null,
  periodo_hasta date not null,
  fecha_emision date not null,
  fecha_vencimiento date not null,
  moneda varchar(3) not null,
  subtotal numeric(19,2) not null,
  impuestos numeric(19,2) not null default 0,
  total numeric(19,2) not null,
  saldo numeric(19,2) not null,
  estado varchar(20) not null default 'PENDING',
  referencia_externa text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint facturas_estado_ck check (
    estado in ('PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'VOID')
  ),
  constraint facturas_periodo_ck check (periodo_hasta >= periodo_desde),
  constraint facturas_fechas_ck check (fecha_vencimiento >= fecha_emision),
  constraint facturas_importes_ck check (
    subtotal >= 0 and impuestos >= 0 and total >= 0 and saldo >= 0 and saldo <= total
  ),
  constraint facturas_moneda_ck check (moneda = upper(moneda) and length(moneda) = 3)
);

create index facturas_suscripcion_idx
  on public.facturas (suscripcion_id, estado, fecha_vencimiento);

create table public.pagos (
  id uuid primary key default extensions.gen_random_uuid(),
  factura_id uuid not null references public.facturas(id),
  fecha_pago timestamptz not null,
  importe numeric(19,2) not null,
  moneda varchar(3) not null,
  metodo varchar(30) not null,
  referencia varchar(200),
  estado varchar(20) not null default 'PENDING',
  registrado_por uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint pagos_importe_ck check (importe > 0),
  constraint pagos_moneda_ck check (moneda = upper(moneda) and length(moneda) = 3),
  constraint pagos_estado_ck check (
    estado in ('PENDING', 'CONFIRMED', 'REJECTED', 'REFUNDED')
  )
);

create index pagos_factura_idx on public.pagos (factura_id, estado, fecha_pago);

create table public.suscripcion_cupos (
  id uuid primary key default extensions.gen_random_uuid(),
  suscripcion_id uuid not null references public.suscripciones(id),
  tipo varchar(20) not null,
  cantidad integer not null,
  factura_id uuid references public.facturas(id),
  vigente_desde timestamptz not null,
  vigente_hasta timestamptz,
  estado varchar(20) not null default 'PENDING',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint suscripcion_cupos_tipo_ck check (tipo in ('PLAN_BASE', 'ADDITIONAL')),
  constraint suscripcion_cupos_cantidad_ck check (cantidad > 0),
  constraint suscripcion_cupos_estado_ck check (
    estado in ('PENDING', 'ACTIVE', 'REVOKED', 'EXPIRED')
  ),
  constraint suscripcion_cupos_vigencia_ck check (
    vigente_hasta is null or vigente_hasta > vigente_desde
  )
);

create index suscripcion_cupos_activos_idx
  on public.suscripcion_cupos (suscripcion_id, vigente_desde, vigente_hasta)
  where estado = 'ACTIVE';

create table public.licencias_usuario (
  id uuid primary key default extensions.gen_random_uuid(),
  suscripcion_id uuid not null references public.suscripciones(id),
  usuario_id uuid not null references public.perfiles(id),
  estado varchar(20) not null default 'ACTIVE',
  asignada_at timestamptz not null default now(),
  asignada_por uuid references auth.users(id),
  revocada_at timestamptz,
  revocada_por uuid references auth.users(id),
  motivo_revocacion text,
  created_at timestamptz not null default now(),
  constraint licencias_usuario_estado_ck check (
    estado in ('ACTIVE', 'REVOKED', 'EXPIRED')
  ),
  constraint licencias_usuario_revocacion_ck check (
    (estado = 'ACTIVE' and revocada_at is null and revocada_por is null)
    or (estado <> 'ACTIVE' and revocada_at is not null)
  )
);

create unique index licencias_usuario_activa_uq
  on public.licencias_usuario (usuario_id)
  where estado = 'ACTIVE';

create index licencias_usuario_suscripcion_idx
  on public.licencias_usuario (suscripcion_id, estado);

create table public.eventos_licencia (
  id uuid primary key default extensions.gen_random_uuid(),
  usuario_id uuid references public.perfiles(id),
  suscripcion_id uuid references public.suscripciones(id),
  contrato_id uuid references public.contratos(id),
  tipo_evento varchar(50) not null,
  estado_anterior jsonb,
  estado_nuevo jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id),
  actor_externo varchar(150),
  motivo text,
  created_at timestamptz not null default now()
);

create index eventos_licencia_timeline_idx
  on public.eventos_licencia (suscripcion_id, created_at desc);

create or replace function private.enforce_license_seat_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  active_seats integer;
  assigned_seats integer;
begin
  if new.estado <> 'ACTIVE' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.suscripcion_id::text, 0));

  select coalesce(sum(c.cantidad), 0)::integer
    into active_seats
  from public.suscripcion_cupos c
  where c.suscripcion_id = new.suscripcion_id
    and c.estado = 'ACTIVE'
    and c.vigente_desde <= now()
    and (c.vigente_hasta is null or c.vigente_hasta > now());

  select count(*)::integer
    into assigned_seats
  from public.licencias_usuario l
  where l.suscripcion_id = new.suscripcion_id
    and l.estado = 'ACTIVE'
    and (tg_op = 'INSERT' or l.id <> new.id);

  if assigned_seats >= active_seats then
    raise exception using
      errcode = 'P0001',
      message = 'LICENSE_SEATS_EXHAUSTED';
  end if;

  return new;
end;
$$;

create trigger licencias_usuario_capacity
before insert or update of suscripcion_id, estado
on public.licencias_usuario
for each row execute function private.enforce_license_seat_capacity();

create or replace function private.user_has_active_license(target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    join public.licencias_usuario l
      on l.usuario_id = p.id and l.estado = 'ACTIVE'
    join public.suscripciones s
      on s.id = l.suscripcion_id
    join public.contratos c
      on c.id = s.contrato_id and c.cliente_id = p.cliente_id
    where p.id = target_user_id
      and p.activo
      and not p.debe_cambiar_password
      and c.estado = 'ACTIVE'
      and c.vigente_desde <= current_date
      and (c.vigente_hasta is null or c.vigente_hasta >= current_date)
      and (
        (s.estado = 'ACTIVE' and s.inicio_periodo <= now() and s.fin_periodo > now())
        or (s.estado = 'GRACE' and s.gracia_hasta is not null and s.gracia_hasta > now())
      )
  );
$$;

create trigger planes_comerciales_set_updated_at
before update on public.planes_comerciales
for each row execute function private.set_updated_at();

create trigger contratos_set_updated_at
before update on public.contratos
for each row execute function private.set_updated_at();

create trigger suscripciones_set_updated_at
before update on public.suscripciones
for each row execute function private.set_updated_at();

create trigger facturas_set_updated_at
before update on public.facturas
for each row execute function private.set_updated_at();

create trigger suscripcion_cupos_set_updated_at
before update on public.suscripcion_cupos
for each row execute function private.set_updated_at();

alter table public.planes_comerciales enable row level security;
alter table public.precios_plan enable row level security;
alter table public.contratos enable row level security;
alter table public.suscripciones enable row level security;
alter table public.facturas enable row level security;
alter table public.pagos enable row level security;
alter table public.suscripcion_cupos enable row level security;
alter table public.licencias_usuario enable row level security;
alter table public.eventos_licencia enable row level security;

revoke all on public.planes_comerciales from anon, authenticated;
revoke all on public.precios_plan from anon, authenticated;
revoke all on public.contratos from anon, authenticated;
revoke all on public.suscripciones from anon, authenticated;
revoke all on public.facturas from anon, authenticated;
revoke all on public.pagos from anon, authenticated;
revoke all on public.suscripcion_cupos from anon, authenticated;
revoke all on public.licencias_usuario from anon, authenticated;
revoke all on public.eventos_licencia from anon, authenticated;

grant select on public.contratos, public.suscripciones, public.licencias_usuario
to authenticated;

create policy contratos_select_own_client
on public.contratos
for select
to authenticated
using (
  cliente_id = (
    select p.cliente_id from public.perfiles p where p.id = (select auth.uid())
  )
);

create policy suscripciones_select_own_client
on public.suscripciones
for select
to authenticated
using (
  exists (
    select 1
    from public.contratos c
    join public.perfiles p on p.cliente_id = c.cliente_id
    where c.id = suscripciones.contrato_id
      and p.id = (select auth.uid())
  )
);

create policy licencias_usuario_select_self
on public.licencias_usuario
for select
to authenticated
using (usuario_id = (select auth.uid()));

commit;

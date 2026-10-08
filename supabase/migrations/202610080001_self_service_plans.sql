begin;

-- IvMET se publica en Play Store: cualquier empresa crea su cuenta desde la app
-- y empieza en el plan gratuito, con límites que invitan a pedir uno superior.
-- Métrica atiende esas solicitudes y cambia el plan desde RimMET; la app no
-- muestra precios ni cobra.
--
-- Una empresa autoregistrada no existe en DataMET: no tiene identificador
-- legado, no se importa ni se exporta al espejo SQL Server, y su jefe de
-- calidad gestiona plantas y usuarios dentro de los cupos de su plan. Las
-- empresas incorporadas por Métrica siguen como estaban: sus planes no traen
-- límites y nada cambia para ellas.

-- ============================================================================
-- 1. Condiciones de cada plan
-- ============================================================================

-- `caracteristicas` ya viaja al espejo como JSON: los límites viven ahí y no en
-- columnas nuevas, así que el worker y SQL Server no cambian. Una clave ausente
-- o nula significa sin límite (límites) o habilitado (funciones): los planes
-- que ya existían conservan todo.
create function private.plan_terms_valid(value jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare item record; catalog jsonb;
begin
  if value is null or jsonb_typeof(value)<>'object' then return false; end if;
  if value ? 'limits' then
    if jsonb_typeof(value->'limits')<>'object' then return false; end if;
    if (value->'limits')-array['plants','equipment','monthlyVerifications','patterns']<>'{}'::jsonb then
      return false;
    end if;
    for item in select l.key,l.value from jsonb_each(value->'limits') l loop
      if jsonb_typeof(item.value)<>'null'
        and (jsonb_typeof(item.value)<>'number' or item.value::text !~ '^[1-9][0-9]{0,5}$') then
        return false;
      end if;
    end loop;
  end if;
  if value ? 'features' then
    if jsonb_typeof(value->'features')<>'object' then return false; end if;
    if (value->'features')-array['fullReport','customSchedules']<>'{}'::jsonb then return false; end if;
    for item in select f.key,f.value from jsonb_each(value->'features') f loop
      if jsonb_typeof(item.value)<>'boolean' then return false; end if;
    end loop;
  end if;
  if value ? 'catalog' then
    catalog:=value->'catalog';
    if jsonb_typeof(catalog)<>'object' then return false; end if;
    if catalog-array['visible','order','selfService','summary']<>'{}'::jsonb then return false; end if;
    if catalog ? 'visible' and jsonb_typeof(catalog->'visible')<>'boolean' then return false; end if;
    if catalog ? 'selfService' and jsonb_typeof(catalog->'selfService')<>'boolean' then return false; end if;
    if catalog ? 'order' and (jsonb_typeof(catalog->'order')<>'number'
      or (catalog->'order')::text !~ '^[0-9]{1,3}$') then return false; end if;
    if catalog ? 'summary' and (jsonb_typeof(catalog->'summary')<>'string'
      or length(catalog->>'summary')>300) then return false; end if;
  end if;
  return true;
end; $$;

-- Las condiciones completas, con los valores por defecto explícitos.
create function private.plan_effective_terms(value jsonb) returns jsonb
language sql immutable set search_path='' as $$
  select jsonb_build_object(
    'limits',jsonb_build_object(
      'plants',coalesce(value->'limits'->'plants','null'::jsonb),
      'equipment',coalesce(value->'limits'->'equipment','null'::jsonb),
      'monthlyVerifications',coalesce(value->'limits'->'monthlyVerifications','null'::jsonb),
      'patterns',coalesce(value->'limits'->'patterns','null'::jsonb)),
    'features',jsonb_build_object(
      'fullReport',coalesce(value->'features'->'fullReport','true'::jsonb),
      'customSchedules',coalesce(value->'features'->'customSchedules','true'::jsonb)),
    'catalog',jsonb_build_object(
      'visible',coalesce(value->'catalog'->'visible','false'::jsonb),
      'order',coalesce(value->'catalog'->'order','999'::jsonb),
      'selfService',coalesce(value->'catalog'->'selfService','false'::jsonb),
      'summary',coalesce(value->'catalog'->'summary','""'::jsonb)));
$$;

alter table public.planes_comerciales add constraint planes_comerciales_caracteristicas_ck
  check (private.plan_terms_valid(caracteristicas));

-- Un solo plan recibe las altas de la app. Desactivarlo pausa el autoregistro.
create unique index planes_comerciales_autoregistro_uq on public.planes_comerciales((true))
  where activo and caracteristicas->'catalog'->'selfService'='true'::jsonb;

create function private.plan_json(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',p.id,'code',p.codigo,'name',p.nombre,'description',p.descripcion,
      'seats',p.cuentas_incluidas,'active',p.activo)
    ||private.plan_effective_terms(p.caracteristicas)
  from public.planes_comerciales p where p.id=target;
$$;

-- El código lo asigna el trigger de códigos comerciales. Sin precios: Métrica
-- los define en RimMET y la app no los muestra.
insert into public.planes_comerciales(codigo,nombre,descripcion,cuentas_incluidas,dias_gracia,caracteristicas) values
  ('AUTO','Gratuito','Para conocer IvMET en una planta.',2,0,
    '{"catalog":{"visible":true,"order":1,"selfService":true,"summary":"Una planta, 5 balanzas y 2 usuarios para empezar."},
      "limits":{"plants":1,"equipment":5,"monthlyVerifications":20,"patterns":3},
      "features":{"fullReport":false,"customSchedules":false}}'),
  ('AUTO','Profesional','Para equipos de calidad con varias plantas.',10,7,
    '{"catalog":{"visible":true,"order":2,"selfService":false,"summary":"Hasta 3 plantas, 50 balanzas y 10 usuarios, con informe completo y periodicidad a medida."},
      "limits":{"plants":3,"equipment":50},
      "features":{"fullReport":true,"customSchedules":true}}'),
  ('AUTO','Empresa','Para operaciones con muchas plantas y balanzas.',30,15,
    '{"catalog":{"visible":true,"order":3,"selfService":false,"summary":"Plantas, balanzas y verificaciones sin límite; usuarios a medida."},
      "limits":{},"features":{}}');

-- ============================================================================
-- 2. Empresas autoregistradas
-- ============================================================================

alter table public.clientes
  add column origen varchar(12) not null default 'DATAMET',
  add column registrado_at timestamptz;
alter table public.clientes alter column legacy_cliente_id drop not null;
alter table public.clientes add constraint clientes_origen_ck check (
  (origen='DATAMET' and legacy_cliente_id is not null and registrado_at is null)
  or (origen='AUTOREGISTRO' and legacy_cliente_id is null and registrado_at is not null)
);

create sequence private.self_service_client_seq as bigint start with 1;
revoke all on sequence private.self_service_client_seq from public,anon,authenticated,service_role;

-- Contacto comercial que deja la empresa al registrarse. Es privado: solo lo
-- leen RimMET y la propia empresa a través de sus RPC.
create table private.empresas_autoregistro (
  cliente_id uuid primary key references public.clientes(id),
  propietario_id uuid not null unique references auth.users(id),
  correo varchar(100) not null,
  telefono varchar(40),
  ciudad varchar(100),
  pais varchar(100),
  terminos_version varchar(40) not null,
  terminos_aceptados_at timestamptz not null,
  created_at timestamptz not null default now()
);
revoke all on private.empresas_autoregistro from public,anon,authenticated,service_role;

create function private.clean_text(value text) returns text
language sql immutable set search_path='' as $$
  select btrim(regexp_replace(coalesce(value,''),'\s+',' ','g'));
$$;

-- El correo es también el usuario de la app: cabe en `perfiles.usuario`.
create function private.valid_email(value text) returns boolean
language sql immutable set search_path='' as $$
  select coalesce(length(value) between 6 and 100
    and value ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    and value !~* '\.invalid$',false);
$$;

create function private.self_service_client(cid uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.clientes c where c.id=cid and c.origen='AUTOREGISTRO');
$$;

-- ============================================================================
-- 3. Nada de una empresa autoregistrada llega al espejo corporativo
-- ============================================================================

-- El espejo exige identificadores de DataMET. Igual que las balanzas
-- registradas por el cliente, sus eventos quedan retenidos en Supabase en vez
-- de morir en el worker y detener toda la cola.
create function private.outbox_client(aggregate_name text,payload jsonb) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare target uuid;
begin
  case aggregate_name
    when 'public.clientes' then
      target:=nullif(payload->>'id','')::uuid;
    when 'public.plantas','public.equipos','public.perfiles','public.contratos',
      'public.casos_compartidos','public.actualizaciones_compartidas' then
      target:=nullif(payload->>'cliente_id','')::uuid;
    when 'public.equipo_rangos' then
      select e.cliente_id into target from public.equipos e where e.id=nullif(payload->>'equipo_id','')::uuid;
    when 'public.usuario_plantas' then
      select p.cliente_id into target from public.perfiles p where p.id=nullif(payload->>'usuario_id','')::uuid;
    when 'public.suscripciones' then
      select c.cliente_id into target from public.contratos c where c.id=nullif(payload->>'contrato_id','')::uuid;
    when 'public.facturas','public.suscripcion_cupos','public.licencias_usuario' then
      select c.cliente_id into target from public.suscripciones s join public.contratos c on c.id=s.contrato_id
        where s.id=nullif(payload->>'suscripcion_id','')::uuid;
    when 'public.pagos' then
      select c.cliente_id into target from public.facturas f join public.suscripciones s on s.id=f.suscripcion_id
        join public.contratos c on c.id=s.contrato_id where f.id=nullif(payload->>'factura_id','')::uuid;
    when 'public.eventos_licencia' then
      select c.cliente_id into target from public.contratos c where c.id=nullif(payload->>'contrato_id','')::uuid;
      if target is null then
        select p.cliente_id into target from public.perfiles p where p.id=nullif(payload->>'usuario_id','')::uuid;
      end if;
    else
      target:=null;
  end case;
  return target;
end; $$;

create function private.self_service_outbox_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if not new.privacy_blocked and private.self_service_client(private.outbox_client(new.aggregate_type,new.payload)) then
    new.privacy_blocked:=true;
  end if;
  return new;
end; $$;
create trigger sync_outbox_self_service before insert on private.sync_outbox
for each row execute function private.self_service_outbox_event();

-- ============================================================================
-- 4. Plan vigente, uso y límites
-- ============================================================================

-- La suscripción del contrato abierto del cliente; si hubiera más de una, la
-- que da acceso.
create function private.client_subscription(cid uuid) returns uuid
language sql stable security definer set search_path='' as $$
  select s.id from public.suscripciones s join public.contratos c on c.id=s.contrato_id
  where c.cliente_id=cid and c.estado in ('ACTIVE','SUSPENDED') and s.estado not in ('CANCELLED','EXPIRED')
  order by case s.estado when 'ACTIVE' then 0 when 'GRACE' then 1 when 'PAST_DUE' then 2
    when 'SUSPENDED' then 3 else 4 end,s.created_at desc,s.id
  limit 1;
$$;

create function private.client_plan(cid uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select private.plan_json(s.plan_id)||jsonb_build_object(
    'subscriptionId',s.id,'subscriptionStatus',s.estado,
    'periodEndsAt',case when s.fin_periodo='infinity'::timestamptz then null else s.fin_periodo end,
    'seatsAvailable',(select coalesce(sum(sc.cantidad),0) from public.suscripcion_cupos sc
      where sc.suscripcion_id=s.id and sc.estado='ACTIVE' and sc.vigente_desde<=now()
        and (sc.vigente_hasta is null or sc.vigente_hasta>now())))
  from public.suscripciones s where s.id=private.client_subscription(cid);
$$;

-- El mes del plan se cuenta en hora de Bolivia (UTC−4, sin horario de verano).
create function private.plan_month_start() returns timestamptz
language sql stable set search_path='' as $$
  select (date_trunc('month',(now() at time zone 'UTC')-interval '4 hours')+interval '4 hours') at time zone 'UTC';
$$;

create function private.client_usage(cid uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'plants',(select count(*) from public.plantas p where p.cliente_id=cid and p.activo),
    'equipment',(select count(*) from public.equipos e join public.equipos_ivmet i on i.equipo_id=e.id
      where e.cliente_id=cid and e.activo and i.habilitado),
    'patterns',(select count(*) from public.patrones p where p.cliente_id=cid and p.activo),
    'monthlyVerifications',(select count(*) from public.verificaciones v
      where v.cliente_id=cid and v.recibido_at>=private.plan_month_start()),
    'openDrafts',(select count(*) from public.verificacion_borradores d where d.cliente_id=cid
      and d.estado in ('DRAFT','FINALIZING') and d.expires_at>now()),
    'users',(select count(*) from public.licencias_usuario l join public.perfiles p on p.id=l.usuario_id
      where p.cliente_id=cid and l.estado='ACTIVE'),
    'monthStartsAt',private.plan_month_start());
$$;

-- Comprueba un límite antes de sumar un elemento. El cerrojo por cliente y
-- recurso dura hasta el commit: dos altas simultáneas no pasan juntas.
-- Las verificaciones en curso cuentan contra el mes: cada borrador nuevo
-- ocupa un lugar hasta que se finaliza o vence.
create function private.plan_assert(cid uuid,resource text) returns void
language plpgsql security definer set search_path='' as $$
declare maximum integer; usage jsonb; used integer;
begin
  maximum:=(private.client_plan(cid)->'limits'->>resource)::integer;
  if maximum is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text||':'||resource,7));
  usage:=private.client_usage(cid);
  used:=(usage->>resource)::integer
    +case when resource='monthlyVerifications' then (usage->>'openDrafts')::integer else 0 end;
  if used>=maximum then
    raise exception using errcode='P0001',message=case resource
      when 'plants' then 'PLAN_LIMIT_PLANTS'
      when 'equipment' then 'PLAN_LIMIT_EQUIPMENT'
      when 'patterns' then 'PLAN_LIMIT_PATTERNS'
      else 'PLAN_LIMIT_VERIFICATIONS' end;
  end if;
end; $$;

create function private.plan_feature(cid uuid,feature text) returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((private.client_plan(cid)->'features'->>feature)::boolean,true);
$$;

-- Los accesos rápidos del editor de periodicidad (`SchedulePreset` en la app):
-- fechas fijas cada día, semana, quincena, uno, dos, tres o seis meses, o año.
create function private.schedule_is_preset(rule jsonb) returns boolean
language sql immutable set search_path='' as $$
  select rule->>'mode'='fixed' and (rule->>'unit',rule->>'every') in
    (('day','1'),('week','1'),('week','2'),('month','1'),('month','2'),('month','3'),('month','6'),('year','1'));
$$;

-- ============================================================================
-- 5. Solicitudes de plan superior
-- ============================================================================

create table public.solicitudes_plan (
  id uuid primary key default extensions.gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id),
  plan_actual_id uuid references public.planes_comerciales(id),
  plan_solicitado_id uuid references public.planes_comerciales(id),
  motivo varchar(30) not null,
  mensaje text not null default '',
  contacto_nombre varchar(200) not null,
  contacto_correo varchar(100),
  contacto_telefono varchar(40),
  solicitado_por uuid not null references public.perfiles(id),
  estado varchar(20) not null default 'PENDING',
  resultado varchar(20),
  nota_interna text,
  atendido_por varchar(150),
  atendido_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint solicitudes_plan_motivo_ck check (motivo in ('PLANTS','EQUIPMENT','USERS',
    'VERIFICATIONS','PATTERNS','FULL_REPORT','CUSTOM_SCHEDULES','GENERAL')),
  constraint solicitudes_plan_estado_ck check (estado in ('PENDING','CONTACTED','CLOSED','CANCELLED')),
  constraint solicitudes_plan_resultado_ck check (
    (estado='CLOSED' and resultado in ('UPGRADED','DECLINED')) or (estado<>'CLOSED' and resultado is null)),
  constraint solicitudes_plan_textos_ck check (length(mensaje)<=2000 and length(coalesce(nota_interna,''))<=2000)
);
-- Una solicitud abierta por empresa: otra encima solo duplicaría el contacto.
create unique index solicitudes_plan_abierta_uq on public.solicitudes_plan(cliente_id)
  where estado in ('PENDING','CONTACTED');
create index solicitudes_plan_bandeja_idx on public.solicitudes_plan(estado,created_at desc);
create trigger solicitudes_plan_set_updated_at before update on public.solicitudes_plan
for each row execute function private.set_updated_at();
alter table public.solicitudes_plan enable row level security;
revoke all on public.solicitudes_plan from public,anon,authenticated,service_role;

create function private.upgrade_request_json(r public.solicitudes_plan) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',r.id,'version',r.row_version::text,'state',r.estado,'result',r.resultado,
    'reason',r.motivo,'message',r.mensaje,'contactName',r.contacto_nombre,'contactEmail',r.contacto_correo,
    'contactPhone',r.contacto_telefono,'createdAt',r.created_at,'attendedAt',r.atendido_at,
    'currentPlan',(select jsonb_build_object('id',p.id,'name',p.nombre) from public.planes_comerciales p where p.id=r.plan_actual_id),
    'requestedPlan',(select jsonb_build_object('id',p.id,'name',p.nombre) from public.planes_comerciales p where p.id=r.plan_solicitado_id));
$$;

-- Lo que la app sabe del plan: condiciones, uso, si la empresa se gestiona
-- sola y la solicitud abierta. Con `detailed`, además, los planes ofrecidos
-- (`offers`; `catalog` es la ficha comercial de cada plan).
create function private.commercial_plan_summary(cid uuid,detailed boolean) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(private.client_plan(cid),'{}'::jsonb)||jsonb_build_object(
    'usage',private.client_usage(cid),
    'selfService',private.self_service_client(cid),
    'contactEmail',(select r.correo from private.empresas_autoregistro r where r.cliente_id=cid),
    'upgradeRequest',(select private.upgrade_request_json(s) from public.solicitudes_plan s
      where s.cliente_id=cid and s.estado in ('PENDING','CONTACTED')))
  ||case when detailed then jsonb_build_object('offers',coalesce((
      select jsonb_agg(private.plan_json(p.id)
        order by (private.plan_effective_terms(p.caracteristicas)->'catalog'->>'order')::integer,p.nombre)
      from public.planes_comerciales p
      where p.activo and p.caracteristicas->'catalog'->'visible'='true'::jsonb),'[]'::jsonb))
    else '{}'::jsonb end;
$$;

-- ============================================================================
-- 6. Alta de una empresa y cuentas de su equipo (Edge Functions)
-- ============================================================================

-- `ivmet-signup` pregunta antes de enviar el código.
create function public.ivmet_signup_status(target_email text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare normalized text:=lower(btrim(coalesce(target_email,''))); account uuid;
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform private.admin_assert(private.valid_email(normalized),'INVALID_EMAIL');
  select u.id into account from auth.users u where lower(u.email)=normalized order by u.id limit 1;
  return jsonb_build_object(
    'registered',exists(select 1 from private.login_aliases la
        where la.usuario_normalizado=normalized or lower(la.auth_email_interno)=normalized)
      or (account is not null and exists(select 1 from public.perfiles p where p.id=account)),
    'authUserId',account);
end; $$;

-- Crea la empresa con el correo ya verificado por un código. Todo nace en una
-- transacción: cliente, primera planta, jefe de calidad, contrato sin precio,
-- suscripción sin vencimiento al plan de autoregistro, cupos y licencia.
create function public.ivmet_signup_complete(target_user uuid,data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  email text:=lower(btrim(coalesce(data->>'email','')));
  account_email text; existing public.perfiles%rowtype; plan public.planes_comerciales%rowtype;
  company text:=private.clean_text(data->>'company'); owner_name text:=private.clean_text(data->>'name');
  plant_name text:=private.clean_text(data->>'plantName'); phone text:=private.clean_text(data->>'phone');
  city text:=private.clean_text(data->>'city'); country text:=private.clean_text(data->>'country');
  code text; cid uuid; plant uuid; contract uuid; subscription uuid;
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform private.admin_assert(target_user is not null and jsonb_typeof(data)='object'
    and octet_length(data::text)<=8192,'INVALID_SIGNUP');
  select lower(u.email) into account_email from auth.users u where u.id=target_user;
  perform private.admin_assert(account_email is not null and account_email=email,'INVALID_SIGNUP');
  perform pg_advisory_xact_lock(hashtextextended('signup:'||email,0));
  select * into existing from public.perfiles p where p.id=target_user;
  if found then
    -- Respuesta perdida: el mismo dueño recupera su alta sin duplicarla.
    perform private.admin_assert(exists(select 1 from private.empresas_autoregistro r
      where r.propietario_id=target_user),'EMAIL_ALREADY_REGISTERED');
    return jsonb_build_object('clientId',existing.cliente_id,'userId',target_user,'replayed',true);
  end if;
  perform private.admin_assert(not exists(select 1 from private.login_aliases la
    where la.usuario_normalizado=email or lower(la.auth_email_interno)=email),'EMAIL_ALREADY_REGISTERED');
  if plant_name='' then plant_name:='Planta principal'; end if;
  perform private.admin_assert(private.valid_email(email) and length(company) between 2 and 100
    and length(owner_name) between 2 and 200 and length(plant_name)<=100
    and length(phone)<=40 and length(city)<=100 and length(country)<=100,'INVALID_SIGNUP');
  perform private.admin_assert(data->'acceptTerms'='true'::jsonb
    and data->>'termsVersion'='ivmet-terms-v1','TERMS_REQUIRED');
  select * into plan from public.planes_comerciales p
    where p.activo and p.caracteristicas->'catalog'->'selfService'='true'::jsonb;
  perform private.admin_assert(found,'SELF_SERVICE_UNAVAILABLE');

  loop
    code:='IV'||lpad(nextval('private.self_service_client_seq'::regclass)::text,6,'0');
    exit when not exists(select 1 from public.clientes c where c.codigo=code);
  end loop;
  insert into public.clientes(codigo,nombre,razon_social,origen,registrado_at,source_hash)
    values(code,company,company,'AUTOREGISTRO',now(),
      private.registration_hash(jsonb_build_object('code',code,'name',company)))
    returning id into cid;
  insert into private.empresas_autoregistro(cliente_id,propietario_id,correo,telefono,ciudad,pais,
      terminos_version,terminos_aceptados_at)
    values(cid,target_user,email,nullif(phone,''),nullif(city,''),nullif(country,''),'ivmet-terms-v1',now());
  insert into public.plantas(cliente_id,legacy_codigo_planta,nombre,localidad,source_hash)
    values(cid,code||'-01',plant_name,nullif(city,''),
      private.registration_hash(jsonb_build_object('code',code||'-01','name',plant_name,'city',city)))
    returning id into plant;
  insert into public.perfiles(id,usuario,usuario_normalizado,nombre,rol,cliente_id,debe_cambiar_password,created_by)
    values(target_user,email,email,owner_name,'cliente_jefe_calidad',cid,false,target_user);
  insert into private.login_aliases(usuario_normalizado,auth_user_id,auth_email_interno)
    values(email,target_user,email);
  insert into public.usuario_plantas(usuario_id,planta_id,created_by) values(target_user,plant,target_user);
  insert into public.contratos(cliente_id,numero_contrato,fecha_firma,vigente_desde,estado,observaciones,created_by)
    values(cid,'IVMET-'||code,current_date,current_date,'ACTIVE','Alta por autoregistro en la app IvMET.',target_user)
    returning id into contract;
  -- Sin vencimiento: el plan gratuito no se renueva ni se cobra.
  insert into public.suscripciones(contrato_id,plan_id,periodicidad,inicio_periodo,fin_periodo,estado,created_by)
    values(contract,plan.id,'MONTHLY',now(),'infinity','ACTIVE',target_user)
    returning id into subscription;
  insert into public.suscripcion_cupos(suscripcion_id,tipo,cantidad,vigente_desde,estado,created_by)
    values(subscription,'PLAN_BASE',plan.cuentas_incluidas,now(),'ACTIVE',target_user);
  insert into public.licencias_usuario(suscripcion_id,usuario_id,asignada_por)
    values(subscription,target_user,target_user);
  insert into public.eventos_licencia(usuario_id,suscripcion_id,contrato_id,tipo_evento,actor_id,estado_nuevo)
    values(target_user,subscription,contract,'ASSIGNED',target_user,jsonb_build_object('state','ACTIVE'));
  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(target_user,cid,'cliente',cid::text,'SELF_SERVICE_SIGNUP',
      jsonb_build_object('code',code,'planId',plan.id,'plantId',plant));
  return jsonb_build_object('clientId',cid,'userId',target_user,'plantId',plant,'code',code,'replayed',false);
end; $$;

-- `ivmet-password-reset` solo envía códigos a cuentas cuyo usuario es su
-- correo: las que creó Métrica o un jefe de calidad tienen un correo interno.
create function public.ivmet_password_reset_target(target_email text) returns uuid
language sql stable security definer set search_path='' as $$
  select la.auth_user_id from private.login_aliases la join public.perfiles p on p.id=la.auth_user_id
  where auth.role()='service_role' and la.usuario_normalizado=lower(btrim(coalesce(target_email,'')))
    and lower(la.auth_email_interno)=la.usuario_normalizado and la.activo and p.activo;
$$;

-- El jefe de calidad de una empresa autoregistrada con acceso vigente.
create function private.self_service_manager(actor uuid) returns public.perfiles
language plpgsql stable security definer set search_path='' as $$
declare p public.perfiles%rowtype;
begin
  select * into p from public.perfiles where id=actor and activo;
  perform private.admin_assert(found and private.user_has_active_license(actor),'MOBILE_ACCESS_DENIED');
  perform private.admin_assert(p.rol='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(private.self_service_client(p.cliente_id),'SELF_SERVICE_REQUIRED');
  return p;
end; $$;

create function private.member_plants(cid uuid,payload jsonb) returns uuid[]
language plpgsql stable security definer set search_path='' as $$
declare plants uuid[];
begin
  perform private.admin_assert(jsonb_typeof(payload->'plantIds')='array'
    and jsonb_array_length(payload->'plantIds') between 1 and 100
    and not exists(select 1 from jsonb_array_elements(payload->'plantIds') x
      where jsonb_typeof(x.value)<>'string'
        or x.value#>>'{}' !~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'),'PLANT_SCOPE_INVALID');
  plants:=array(select distinct x::uuid from jsonb_array_elements_text(payload->'plantIds') x);
  perform private.admin_assert((select count(*) from public.plantas p where p.id=any(plants)
    and p.cliente_id=cid and p.activo)=cardinality(plants),'PLANT_SCOPE_INVALID');
  return plants;
end; $$;

-- Cuentas del equipo, con el mismo recorrido que RimMET: reservar el UUID,
-- crear la cuenta Auth con correo interno y después el perfil y su licencia.
-- Un reintento con el mismo `request_id` recupera la reserva sin duplicarla.
create function public.ivmet_team_account(actor uuid,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  manager public.perfiles%rowtype; member public.perfiles%rowtype; actor_value text;
  digest text; saved private.admin_requests%rowtype; reserved jsonb; result jsonb;
  username text:=lower(btrim(coalesce(payload->>'username',''))); member_name text:=private.clean_text(payload->>'name');
  plants uuid[]; target uuid; subscription uuid; plan jsonb;
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform private.admin_assert(actor is not null and request_id is not null and jsonb_typeof(payload)='object'
    and octet_length(payload::text)<=8192 and action in ('reserve','create','reset'),'INVALID_REQUEST');
  manager:=private.self_service_manager(actor);
  actor_value:='TEAM:'||actor::text;
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r
    where r.request_id=ivmet_team_account.request_id and r.action='team.'||ivmet_team_account.action;
  if found then
    perform private.admin_assert(saved.actor=actor_value and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;

  if action in ('reserve','create') then
    -- Sin @: los correos quedan para las cuentas que se recuperan por correo.
    perform private.admin_assert(username ~ '^[a-z0-9][a-z0-9._-]{2,49}$','INVALID_USERNAME');
    perform private.admin_assert(length(member_name) between 2 and 200
      and payload->>'role' in ('cliente_operador','cliente_jefe_calidad'),'INVALID_MEMBER');
    plants:=private.member_plants(manager.cliente_id,payload);
    plan:=private.client_plan(manager.cliente_id);
    subscription:=(plan->>'subscriptionId')::uuid;
    perform private.admin_assert(subscription is not null,'SUBSCRIPTION_NOT_ACTIVE');
  end if;

  if action='reserve' then
    perform private.admin_assert(not exists(select 1 from public.perfiles where usuario_normalizado=username)
      and not exists(select 1 from private.login_aliases where usuario_normalizado=username),'USERNAME_EXISTS');
    perform private.admin_assert((private.client_usage(manager.cliente_id)->>'users')::integer
      <(plan->>'seatsAvailable')::integer,'PLAN_LIMIT_USERS');
    target:=extensions.gen_random_uuid();
    result:=jsonb_build_object('id',target,'email','ivmet.'||target::text||'@users.ivmet.invalid');
  elsif action='create' then
    select r.result into reserved from private.admin_requests r
      where r.request_id=ivmet_team_account.request_id and r.action='team.reserve' and r.actor=actor_value;
    perform private.admin_assert(reserved is not null,'USER_RESERVATION_REQUIRED');
    target:=(reserved->>'id')::uuid;
    perform private.admin_assert(exists(select 1 from auth.users u where u.id=target
      and u.email=reserved->>'email'),'AUTH_ACCOUNT_REQUIRED');
    perform private.admin_assert(not exists(select 1 from public.perfiles where usuario_normalizado=username),
      'USERNAME_EXISTS');
    insert into public.perfiles(id,usuario,usuario_normalizado,nombre,rol,cliente_id,debe_cambiar_password,created_by)
      values(target,username,username,member_name,payload->>'role',manager.cliente_id,true,actor);
    insert into private.login_aliases(usuario_normalizado,auth_user_id,auth_email_interno)
      values(username,target,reserved->>'email');
    insert into public.usuario_plantas(usuario_id,planta_id,created_by) select target,unnest(plants),actor;
    begin
      insert into public.licencias_usuario(suscripcion_id,usuario_id,asignada_por) values(subscription,target,actor);
    exception when raise_exception then
      if sqlerrm='LICENSE_SEATS_EXHAUSTED' then
        raise exception using errcode='P0001',message='PLAN_LIMIT_USERS';
      end if;
      raise;
    end;
    insert into public.eventos_licencia(usuario_id,suscripcion_id,contrato_id,tipo_evento,actor_id,estado_nuevo)
      values(target,subscription,(select contrato_id from public.suscripciones where id=subscription),
        'ASSIGNED',actor,jsonb_build_object('state','ACTIVE'));
    result:=jsonb_build_object('id',target);
  else
    target:=nullif(payload->>'userId','')::uuid;
    perform private.admin_assert(target is distinct from actor,'SELF_CHANGE_NOT_ALLOWED');
    select * into member from public.perfiles where id=target and cliente_id=manager.cliente_id for update;
    perform private.admin_assert(found and member.activo,'USER_NOT_FOUND');
    -- La contraseña anterior deja de servir para operar hasta que se cambie.
    update public.perfiles set debe_cambiar_password=true where id=target;
    result:=jsonb_build_object('id',target);
  end if;

  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(actor,manager.cliente_id,'perfil',coalesce(target::text,request_id::text),'TEAM_'||upper(action),
      jsonb_build_object('requestId',request_id,'result',case when action='reserve'
        then jsonb_build_object('reserved',true) else result end));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,'team.'||action,actor_value,digest,result);
  return result;
end; $$;

-- ============================================================================
-- 7. Gestión de la empresa desde la app
-- ============================================================================

create function private.next_plant_code(cid uuid) returns text
language plpgsql stable security definer set search_path='' as $$
declare prefix text; seq integer; code text;
begin
  select c.codigo into prefix from public.clientes c where c.id=cid;
  seq:=(select count(*) from public.plantas p where p.cliente_id=cid)+1;
  loop
    code:=prefix||'-'||lpad(seq::text,2,'0');
    exit when not exists(select 1 from public.plantas p where p.legacy_codigo_planta=code);
    seq:=seq+1;
  end loop;
  return code;
end; $$;

-- Plantas y usuarios de una empresa autoregistrada y solicitudes de plan de
-- cualquier empresa. Todo lo hace el jefe de calidad.
create function private.self_service_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  cid uuid:=private.mobile_require(); actor_value text:='MOBILE:'||auth.uid()::text;
  digest text; saved private.admin_requests%rowtype; result jsonb; target uuid;
  plant public.plantas%rowtype; member public.perfiles%rowtype; request public.solicitudes_plan%rowtype;
  plants uuid[]; name_value text; city text; address text; activate boolean; plan jsonb; requested uuid;
  phone text; contact_email text;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object'
    and octet_length(payload::text)<=16384,'INVALID_REQUEST');
  if action in ('plant.save','member.update') then
    perform private.admin_assert(private.self_service_client(cid),'SELF_SERVICE_REQUIRED');
  end if;
  if nullif(payload->>'id','') is not null then
    perform private.admin_assert(payload->>'id' ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$','INVALID_REQUEST');
    target:=(payload->>'id')::uuid;
  end if;
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r
    where r.request_id=self_service_mutate.request_id and r.action='customer.'||self_service_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor_value and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;

  if action='plant.save' then
    name_value:=private.clean_text(payload->>'name');
    city:=private.clean_text(payload->>'city');
    address:=private.clean_text(payload->>'address');
    perform private.admin_assert(length(name_value) between 1 and 100 and length(city)<=100
      and length(address)<=250 and jsonb_typeof(payload->'active')='boolean','INVALID_PLANT');
    if target is null then
      perform private.admin_assert(payload->'active'='true'::jsonb,'INVALID_PLANT');
      perform private.plan_assert(cid,'plants');
      perform pg_advisory_xact_lock(hashtextextended(cid::text,9));
      insert into public.plantas(cliente_id,legacy_codigo_planta,nombre,direccion,localidad,source_hash)
        values(cid,private.next_plant_code(cid),name_value,nullif(address,''),nullif(city,''),
          private.registration_hash(jsonb_build_object('name',name_value,'address',address,'city',city)))
        returning * into plant;
      -- Quien la crea trabaja en ella; el resto se asigna desde Usuarios.
      insert into public.usuario_plantas(usuario_id,planta_id,created_by) values(auth.uid(),plant.id,auth.uid());
    else
      select * into plant from public.plantas p where p.id=target and p.cliente_id=cid and p.activo for update;
      perform private.admin_assert(found and private.can_access_plant(target),'PLANT_SCOPE_INVALID');
      perform private.admin_assert(plant.source_version::text=payload->>'version','ROW_VERSION_CONFLICT');
      if payload->'active'='false'::jsonb then
        perform private.admin_assert(not exists(select 1 from public.equipos e
          where e.planta_id=plant.id and e.activo),'PLANT_HAS_EQUIPMENT');
        perform private.admin_assert(exists(select 1 from public.plantas p
          where p.cliente_id=cid and p.activo and p.id<>plant.id),'LAST_PLANT');
      end if;
      update public.plantas set nombre=name_value,direccion=nullif(address,''),localidad=nullif(city,''),
        activo=(payload->>'active')::boolean,source_version=source_version+1,
        source_hash=private.registration_hash(jsonb_build_object('name',name_value,'address',address,'city',city))
      where id=plant.id returning * into plant;
    end if;
    result:=jsonb_build_object('id',plant.id,'version',plant.source_version::text);

  elsif action='member.update' then
    select * into member from public.perfiles p where p.id=target and p.cliente_id=cid for update;
    perform private.admin_assert(found,'USER_NOT_FOUND');
    perform private.admin_assert(member.row_version::text=payload->>'version','ROW_VERSION_CONFLICT');
    name_value:=private.clean_text(payload->>'name');
    perform private.admin_assert(length(name_value) between 2 and 200
      and payload->>'role' in ('cliente_operador','cliente_jefe_calidad')
      and jsonb_typeof(payload->'active')='boolean','INVALID_MEMBER');
    plants:=private.member_plants(cid,payload);
    -- Cada empresa conserva al menos un jefe de calidad activo: el propio.
    perform private.admin_assert(target<>auth.uid() or (payload->>'role'='cliente_jefe_calidad'
      and payload->'active'='true'::jsonb),'SELF_CHANGE_NOT_ALLOWED');
    activate:=not member.activo and (payload->>'active')::boolean;
    if member.activo and payload->'active'='false'::jsonb then
      perform private.admin_assert(length(private.clean_text(payload->>'reason')) between 1 and 500,'REASON_REQUIRED');
    end if;
    update public.perfiles set nombre=name_value,rol=payload->>'role',activo=(payload->>'active')::boolean
      where id=target returning * into member;
    update public.usuario_plantas set activa=false where usuario_id=target and planta_id<>all(plants);
    insert into public.usuario_plantas(usuario_id,planta_id,created_by) select target,unnest(plants),auth.uid()
      on conflict(usuario_id,planta_id) do update set activa=true;
    update private.login_aliases set activo=member.activo,updated_at=now() where auth_user_id=target;
    if not member.activo then
      -- Libera el cupo: la cuenta conserva su historial.
      update public.licencias_usuario set estado='REVOKED',revocada_at=now(),revocada_por=auth.uid(),
        motivo_revocacion=private.clean_text(payload->>'reason')
        where usuario_id=target and estado='ACTIVE';
      if found then
        insert into public.eventos_licencia(usuario_id,tipo_evento,actor_id,motivo)
          values(target,'REVOKED',auth.uid(),private.clean_text(payload->>'reason'));
      end if;
    elsif activate or not exists(select 1 from public.licencias_usuario where usuario_id=target and estado='ACTIVE') then
      plan:=private.client_plan(cid);
      begin
        insert into public.licencias_usuario(suscripcion_id,usuario_id,asignada_por)
          values((plan->>'subscriptionId')::uuid,target,auth.uid());
      exception when raise_exception then
        if sqlerrm='LICENSE_SEATS_EXHAUSTED' then
          raise exception using errcode='P0001',message='PLAN_LIMIT_USERS';
        end if;
        raise;
      end;
      insert into public.eventos_licencia(usuario_id,suscripcion_id,tipo_evento,actor_id,estado_nuevo)
        values(target,(plan->>'subscriptionId')::uuid,'ASSIGNED',auth.uid(),jsonb_build_object('state','ACTIVE'));
    end if;
    result:=jsonb_build_object('id',target,'version',member.row_version::text);

  elsif action='upgrade.request' then
    perform private.admin_assert((payload-array['planId','reason','message','phone'])='{}'::jsonb
      and payload->>'reason' in ('PLANTS','EQUIPMENT','USERS','VERIFICATIONS','PATTERNS',
        'FULL_REPORT','CUSTOM_SCHEDULES','GENERAL')
      and length(coalesce(payload->>'message',''))<=2000,'INVALID_UPGRADE_REQUEST');
    phone:=private.clean_text(payload->>'phone');
    perform private.admin_assert(length(phone)<=40,'INVALID_UPGRADE_REQUEST');
    plan:=private.client_plan(cid);
    if nullif(payload->>'planId','') is not null then
      perform private.admin_assert(payload->>'planId' ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$','PLAN_NOT_AVAILABLE');
      requested:=(payload->>'planId')::uuid;
      perform private.admin_assert(exists(select 1 from public.planes_comerciales p where p.id=requested and p.activo
        and p.caracteristicas->'catalog'->'visible'='true'::jsonb)
        and requested is distinct from (plan->>'id')::uuid,'PLAN_NOT_AVAILABLE');
    end if;
    select r.correo into contact_email from private.empresas_autoregistro r where r.cliente_id=cid;
    perform private.admin_assert(phone<>'' or contact_email is not null,'CONTACT_REQUIRED');
    perform pg_advisory_xact_lock(hashtextextended(cid::text,8));
    perform private.admin_assert(not exists(select 1 from public.solicitudes_plan s
      where s.cliente_id=cid and s.estado in ('PENDING','CONTACTED')),'UPGRADE_REQUEST_OPEN');
    insert into public.solicitudes_plan(cliente_id,plan_actual_id,plan_solicitado_id,motivo,mensaje,
        contacto_nombre,contacto_correo,contacto_telefono,solicitado_por)
      values(cid,(plan->>'id')::uuid,requested,payload->>'reason',btrim(coalesce(payload->>'message','')),
        (select p.nombre from public.perfiles p where p.id=auth.uid()),contact_email,nullif(phone,''),auth.uid())
      returning * into request;
    result:=jsonb_build_object('id',request.id,'version',request.row_version::text);

  elsif action='upgrade.cancel' then
    select * into request from public.solicitudes_plan s where s.id=target and s.cliente_id=cid for update;
    perform private.admin_assert(found and request.estado in ('PENDING','CONTACTED'),'UPGRADE_REQUEST_NOT_OPEN');
    perform private.admin_assert(request.row_version::text=payload->>'version','ROW_VERSION_CONFLICT');
    update public.solicitudes_plan set estado='CANCELLED' where id=request.id returning * into request;
    result:=jsonb_build_object('id',request.id,'version',request.row_version::text);
  else
    raise exception using errcode='22023',message='UNKNOWN_CUSTOMER_ACTION';
  end if;

  insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues)
    values(auth.uid(),cid,split_part(action,'.',1),coalesce(target,(result->>'id')::uuid)::text,action,
      jsonb_build_object('requestId',request_id,'result',result));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,'customer.'||action,actor_value,digest,result);
  return result;
end; $$;

-- Usuarios de la empresa, para el jefe de calidad de una empresa autoregistrada.
create function private.self_service_members() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); plan jsonb;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(private.self_service_client(cid),'SELF_SERVICE_REQUIRED');
  plan:=private.client_plan(cid);
  return jsonb_build_object(
    'seats',coalesce((plan->>'seatsAvailable')::integer,0),
    'used',(private.client_usage(cid)->>'users')::integer,
    'plants',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.nombre,p.legacy_codigo_planta))
      order by p.legacy_codigo_planta) from public.plantas p where p.cliente_id=cid and p.activo),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.nombre,'username',p.usuario,
        'role',p.rol,'active',p.activo,'mustChangePassword',p.debe_cambiar_password,'version',p.row_version::text,
        'self',p.id=auth.uid(),
        'owner',exists(select 1 from private.empresas_autoregistro r where r.propietario_id=p.id),
        'licensed',exists(select 1 from public.licencias_usuario l where l.usuario_id=p.id and l.estado='ACTIVE'),
        'plantIds',coalesce((select jsonb_agg(up.planta_id order by up.planta_id) from public.usuario_plantas up
          join public.plantas pl on pl.id=up.planta_id where up.usuario_id=p.id and up.activa and pl.activo),'[]'::jsonb))
      order by not p.activo,p.nombre,p.id) from public.perfiles p where p.cliente_id=cid),'[]'::jsonb));
end; $$;

-- Plantas de una empresa autoregistrada, con lo que pide su formulario.
create function private.self_service_plants() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.mobile_require();
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  perform private.admin_assert(private.self_service_client(cid),'SELF_SERVICE_REQUIRED');
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,
      'code',p.legacy_codigo_planta,'name',p.nombre,'city',coalesce(p.localidad,''),'address',coalesce(p.direccion,''),
      'version',p.source_version::text,
      'equipmentCount',(select count(*) from public.equipos e where e.planta_id=p.id and e.activo))
    order by p.legacy_codigo_planta) from public.plantas p
    where p.cliente_id=cid and p.activo and private.can_access_plant(p.id)),'[]'::jsonb));
end; $$;

-- ============================================================================
-- 8. Límites en las RPC de la app
-- ============================================================================

-- Se envuelven como en entregas anteriores. PL/pgSQL conserva el nombre
-- anterior en las referencias calificadas: cada cuerpo se recompila.
alter function public.ivmet_customer_mutate(text,jsonb,uuid) rename to customer_mutate_before_plans;
alter function public.customer_mutate_before_plans(text,jsonb,uuid) set schema private;
alter function public.ivmet_customer_read(text,jsonb) rename to customer_read_before_plans;
alter function public.customer_read_before_plans(text,jsonb) set schema private;
alter function public.ivmet_customer_configure_checks(uuid,jsonb,uuid) rename to customer_configure_checks_before_plans;
alter function public.customer_configure_checks_before_plans(uuid,jsonb,uuid) set schema private;
alter function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) rename to mobile_save_before_plans;
alter function public.mobile_save_before_plans(uuid,uuid,uuid,bigint,jsonb,uuid) set schema private;
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_plans;
alter function public.mobile_read_before_plans(text,jsonb) set schema private;
alter function public.ivmet_admin_read(text,uuid,jsonb) rename to admin_read_before_plans;
alter function public.admin_read_before_plans(text,uuid,jsonb) set schema private;
alter function public.ivmet_admin_mutate(text,text,jsonb,uuid) rename to admin_mutate_before_plans;
alter function public.admin_mutate_before_plans(text,text,jsonb,uuid) set schema private;
do $migration$
declare item record;
begin
  for item in select * from (values
    ('private.customer_mutate_before_plans(text,jsonb,uuid)','ivmet_customer_mutate.','customer_mutate_before_plans.'),
    ('private.customer_read_before_plans(text,jsonb)','ivmet_customer_read.','customer_read_before_plans.'),
    ('private.customer_configure_checks_before_plans(uuid,jsonb,uuid)','ivmet_customer_configure_checks.',
      'customer_configure_checks_before_plans.'),
    ('private.mobile_save_before_plans(uuid,uuid,uuid,bigint,jsonb,uuid)','ivmet_mobile_save_draft.','mobile_save_before_plans.'),
    ('private.mobile_read_before_plans(text,jsonb)','ivmet_mobile_read.','mobile_read_before_plans.'),
    ('private.admin_read_before_plans(text,uuid,jsonb)','ivmet_admin_read.','admin_read_before_plans.'),
    ('private.admin_mutate_before_plans(text,text,jsonb,uuid)','ivmet_admin_mutate.','admin_mutate_before_plans.')
  ) v(signature,previous_name,next_name) loop
    execute replace(pg_get_functiondef(item.signature::regprocedure),item.previous_name,item.next_name);
  end loop;
end;
$migration$;

create function public.ivmet_customer_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; pattern public.patrones%rowtype;
begin
  if action in ('plant.save','member.update','upgrade.request','upgrade.cancel') then
    return private.self_service_mutate(action,payload,request_id);
  end if;
  cid:=private.mobile_require();
  -- Un reintento de algo ya hecho recupera su recibo aunque el plan esté lleno.
  if jsonb_typeof(payload)='object' and request_id is not null and not exists(select 1 from private.admin_requests r
      where r.request_id=ivmet_customer_mutate.request_id and r.action='customer.'||ivmet_customer_mutate.action) then
    if action='equipment.register' then
      perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
      perform private.plan_assert(cid,'equipment');
    elsif action='pattern.save' and payload->'active'='true'::jsonb then
      if nullif(payload->>'id','') is null then
        perform private.plan_assert(cid,'patterns');
      else
        select * into pattern from public.patrones p where p.id=nullif(payload->>'id','')::uuid and p.cliente_id=cid;
        if found and not pattern.activo then perform private.plan_assert(cid,'patterns'); end if;
      end if;
    end if;
  end if;
  return private.customer_mutate_before_plans(action,payload,request_id);
end; $$;

create function public.ivmet_customer_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if section='members' then return private.self_service_members(); end if;
  if section='plants' then return private.self_service_plants(); end if;
  return private.customer_read_before_plans(section,filters);
end; $$;

create function public.ivmet_customer_configure_checks(equipment_id uuid,configuration jsonb,request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require(); test_value jsonb;
begin
  perform private.admin_assert(private.current_profile_role()='cliente_jefe_calidad','QUALITY_MANAGER_REQUIRED');
  if jsonb_typeof(configuration)='object' and jsonb_typeof(configuration->'tests')='array'
      and not private.plan_feature(cid,'customSchedules') then
    for test_value in select value from jsonb_array_elements(configuration->'tests') loop
      if jsonb_typeof(test_value)='object' then
        perform private.admin_assert(test_value ? 'schedule'
          and private.schedule_is_preset(private.schedule_normalize(test_value->'schedule')),
          'PLAN_FEATURE_CUSTOM_SCHEDULES');
      end if;
    end loop;
  end if;
  return private.customer_configure_checks_before_plans(equipment_id,configuration,request_id);
end; $$;

-- Cada captura nueva ocupa un lugar del mes. Guardar un borrador que ya
-- existe nunca se bloquea: el trabajo empezado se termina.
create function public.ivmet_mobile_save_draft(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.mobile_require();
begin
  if request_id is not null and not exists(select 1 from public.verificacion_borradores d
      where d.request_uuid=ivmet_mobile_save_draft.request_id) then
    perform private.plan_assert(cid,'monthlyVerifications');
  end if;
  return private.mobile_save_before_plans(request_id,equipment_id,version_id,expected_version,content,save_id);
end; $$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; cid uuid;
begin
  if section='plan' then
    cid:=private.mobile_require();
    return private.commercial_plan_summary(cid,true);
  end if;
  result:=private.mobile_read_before_plans(section,filters);
  if section='bootstrap' then
    cid:=private.mobile_require();
    result:=result||jsonb_build_object('plan',private.commercial_plan_summary(cid,false));
  end if;
  return result;
end; $$;

-- ============================================================================
-- 9. RimMET: planes con condiciones, solicitudes y cambio de plan
-- ============================================================================

create function public.ivmet_admin_read(section text,client_id uuid default null,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
  page_number integer:=greatest(coalesce((filters->>'page')::integer,1),1);
  page_size integer:=least(greatest(coalesce((filters->>'pageSize')::integer,20),1),100);
  search_text text:='%'||coalesce(filters->>'search','')||'%';
  state_filter text:=nullif(filters->>'state','');
begin
  if section='upgrade-requests' then
    perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
    perform private.admin_assert(state_filter is null or state_filter in ('OPEN','PENDING','CONTACTED','CLOSED','CANCELLED'),
      'INVALID_FILTER');
    with matching as (
      select s.id,s.created_at from public.solicitudes_plan s join public.clientes c on c.id=s.cliente_id
      where (client_id is null or s.cliente_id=client_id)
        and (state_filter is null or s.estado=state_filter
          or (state_filter='OPEN' and s.estado in ('PENDING','CONTACTED')))
        and (c.codigo ilike search_text or c.nombre ilike search_text or s.contacto_nombre ilike search_text
          or coalesce(s.contacto_correo,'') ilike search_text)
    ), page_rows as (select * from matching order by created_at desc,id limit page_size offset (page_number-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,
      'open',(select count(*) from public.solicitudes_plan where estado in ('PENDING','CONTACTED')),
      'items',coalesce((select jsonb_agg(private.upgrade_request_json(s)
          ||jsonb_build_object('note',s.nota_interna,'attendedBy',s.atendido_por,
            'client',(select jsonb_build_object('id',c.id,'code',c.codigo,'name',coalesce(c.nombre,c.razon_social,c.codigo),
              'origin',c.origen) from public.clientes c where c.id=s.cliente_id))
        order by s.created_at desc,s.id) from page_rows r join public.solicitudes_plan s on s.id=r.id),'[]'::jsonb)) into result;
    return result;
  end if;

  result:=private.admin_read_before_plans(section,client_id,filters);
  if section='clients' then
    result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(x.item||jsonb_build_object(
        'origin',c.origen,
        'plan',(select jsonb_build_object('id',p.id,'name',p.nombre) from public.suscripciones s
          join public.planes_comerciales p on p.id=s.plan_id where s.id=private.client_subscription(c.id)),
        'openUpgradeRequest',exists(select 1 from public.solicitudes_plan s where s.cliente_id=c.id
          and s.estado in ('PENDING','CONTACTED')))
        order by x.ord)
      from jsonb_array_elements(result->'items') with ordinality x(item,ord)
        left join public.clientes c on c.id=nullif(x.item->>'id','')::uuid),'[]'::jsonb));
  elsif section='client' then
    result:=result||jsonb_build_object(
      'origin',(select c.origen from public.clientes c where c.id=client_id),
      'selfService',(select jsonb_build_object('email',r.correo,'phone',r.telefono,'city',r.ciudad,
          'country',r.pais,'registeredAt',r.created_at,
          'owner',(select jsonb_build_object('id',p.id,'name',p.nombre) from public.perfiles p where p.id=r.propietario_id))
        from private.empresas_autoregistro r where r.cliente_id=client_id),
      'plan',private.client_plan(client_id),
      'usage',private.client_usage(client_id),
      'upgradeRequests',coalesce((select jsonb_agg(private.upgrade_request_json(s)
          ||jsonb_build_object('note',s.nota_interna,'attendedBy',s.atendido_por) order by s.created_at desc)
        from public.solicitudes_plan s where s.cliente_id=client_id),'[]'::jsonb));
  elsif section='plans' then
    result:=coalesce((select jsonb_agg(x.item||jsonb_build_object('terms',private.plan_effective_terms(x.item->'caracteristicas'))
        order by x.ord)
      from jsonb_array_elements(result) with ordinality x(item,ord)),'[]'::jsonb);
  elsif section='overview' then
    result:=result||jsonb_build_object(
      'selfServiceClients',(select count(*) from public.clientes where activo and origen='AUTOREGISTRO'),
      'upgradeRequests',(select count(*) from public.solicitudes_plan where estado in ('PENDING','CONTACTED')));
  end if;
  return result;
end; $$;

create function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  digest text; saved private.admin_requests%rowtype; result jsonb; before_row jsonb;
  target uuid; customer uuid; plan public.planes_comerciales%rowtype; subscription public.suscripciones%rowtype;
  contract public.contratos%rowtype; request public.solicitudes_plan%rowtype; price public.precios_plan%rowtype;
  terms jsonb; base_seat uuid; additional integer; assigned integer; ends date; reason text;
  name_value text; note text;
begin
  if action not in ('plan.save','subscription.change-plan','upgrade.attend') then
    return private.admin_mutate_before_plans(actor,action,payload,request_id);
  end if;
  perform private.staff_require(actor,'commercial');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object'
    and octet_length(payload::text)<=65536,'INVALID_REQUEST');
  digest:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r
    where r.request_id=ivmet_admin_mutate.request_id and r.action=ivmet_admin_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;
  if nullif(payload->>'id','') is not null then
    perform private.admin_assert(payload->>'id' ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$','INVALID_REQUEST');
    target:=(payload->>'id')::uuid;
  end if;
  reason:=nullif(private.clean_text(payload->>'reason'),'');

  if action='plan.save' then
    -- Igual que antes, más las condiciones. Sin `terms`, una edición las conserva.
    name_value:=private.clean_text(payload->>'name');
    perform private.admin_assert(length(name_value) between 1 and 150
      and coalesce(payload->>'seats','') ~ '^[1-9][0-9]{0,4}$'
      and coalesce(payload->>'graceDays','') ~ '^[0-9]{1,2}$' and (payload->>'graceDays')::integer<=90
      and length(coalesce(payload->>'description',''))<=2000
      and (not payload ? 'active' or jsonb_typeof(payload->'active')='boolean'),'INVALID_PLAN');
    if payload ? 'terms' then
      terms:=payload->'terms';
      perform private.admin_assert(private.plan_terms_valid(terms),'INVALID_PLAN_TERMS');
    end if;
    begin
      if target is null then
        insert into public.planes_comerciales(codigo,nombre,descripcion,cuentas_incluidas,dias_gracia,activo,caracteristicas)
          values('AUTO',name_value,nullif(payload->>'description',''),(payload->>'seats')::integer,
            (payload->>'graceDays')::integer,coalesce((payload->>'active')::boolean,true),coalesce(terms,'{}'::jsonb))
          returning id into target;
      else
        select * into plan from public.planes_comerciales p where p.id=target for update;
        perform private.admin_assert(found,'PLAN_NOT_FOUND');
        perform private.admin_assert(plan.row_version::text=payload->>'version','ROW_VERSION_CONFLICT');
        before_row:=to_jsonb(plan);
        update public.planes_comerciales set nombre=name_value,descripcion=nullif(payload->>'description',''),
          cuentas_incluidas=(payload->>'seats')::integer,dias_gracia=(payload->>'graceDays')::integer,
          activo=coalesce((payload->>'active')::boolean,activo),caracteristicas=coalesce(terms,caracteristicas)
        where id=target;
      end if;
    exception when unique_violation then
      raise exception using errcode='P0001',message='SELF_SERVICE_PLAN_EXISTS';
    end;
    select to_jsonb(p) into result from public.planes_comerciales p where p.id=target;

  elsif action='subscription.change-plan' then
    -- Cambia las condiciones de la suscripción vigente sin cortar el acceso.
    -- El cobro sigue en contrato, facturas y pagos; el gratuito no vence.
    perform private.admin_assert(reason is not null,'REASON_REQUIRED');
    perform private.admin_assert(coalesce(payload->>'clientId','') ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
      and coalesce(payload->>'planId','') ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$','INVALID_REQUEST');
    customer:=(payload->>'clientId')::uuid;
    select * into subscription from public.suscripciones s where s.id=target for update;
    perform private.admin_assert(found,'SUBSCRIPTION_NOT_FOUND');
    select * into contract from public.contratos c where c.id=subscription.contrato_id;
    perform private.admin_assert(contract.cliente_id=customer and contract.estado='ACTIVE'
      and subscription.estado not in ('CANCELLED','EXPIRED','PENDING'),'SUBSCRIPTION_NOT_ACTIVE');
    perform private.admin_assert(subscription.row_version::text=payload->>'version','ROW_VERSION_CONFLICT');
    select * into plan from public.planes_comerciales p where p.id=(payload->>'planId')::uuid and p.activo;
    perform private.admin_assert(found,'PLAN_NOT_FOUND');
    perform private.admin_assert(plan.id<>subscription.plan_id,'PLAN_UNCHANGED');
    if nullif(payload->>'priceId','') is not null then
      select * into price from public.precios_plan pp where pp.id=(payload->>'priceId')::uuid and pp.plan_id=plan.id and pp.activo;
      perform private.admin_assert(found and price.periodicidad=subscription.periodicidad,'PRICE_NOT_EFFECTIVE');
    end if;
    if nullif(payload->>'endsOn','') is not null then
      perform private.admin_assert(payload->>'endsOn' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$','CONTRACT_DATES_INVALID');
      ends:=(payload->>'endsOn')::date;
      perform private.admin_assert(ends>current_date and (contract.vigente_hasta is null or ends<=contract.vigente_hasta+1),
        'CONTRACT_DATES_INVALID');
    end if;
    -- Salir del gratuito exige fijar el fin del período que se cobrará.
    perform private.admin_assert(ends is not null or subscription.fin_periodo<>'infinity'::timestamptz
      or plan.caracteristicas->'catalog'->'selfService'='true'::jsonb,'PERIOD_END_REQUIRED');
    perform pg_advisory_xact_lock(hashtextextended(subscription.id::text,0));
    select sc.id into base_seat from public.suscripcion_cupos sc where sc.suscripcion_id=subscription.id
      and sc.tipo='PLAN_BASE' and sc.estado='ACTIVE' order by sc.created_at desc,sc.id limit 1;
    perform private.admin_assert(base_seat is not null,'SUBSCRIPTION_NOT_ACTIVE');
    select coalesce(sum(sc.cantidad),0) into additional from public.suscripcion_cupos sc
      where sc.suscripcion_id=subscription.id and sc.tipo='ADDITIONAL' and sc.estado='ACTIVE'
        and sc.vigente_desde<=now() and (sc.vigente_hasta is null or sc.vigente_hasta>now());
    select count(*) into assigned from public.licencias_usuario l where l.suscripcion_id=subscription.id and l.estado='ACTIVE';
    perform private.admin_assert(plan.cuentas_incluidas+additional>=assigned,'SEATS_IN_USE');
    before_row:=to_jsonb(subscription);
    update public.suscripcion_cupos set cantidad=plan.cuentas_incluidas where id=base_seat;
    update public.suscripciones set plan_id=plan.id,precio_plan_id=coalesce(price.id,precio_plan_id),
      fin_periodo=case
        when ends is not null then ends::timestamp at time zone 'UTC'
        when plan.caracteristicas->'catalog'->'selfService'='true'::jsonb then 'infinity'::timestamptz
        else fin_periodo end,
      gracia_hasta=case
        when ends is not null then (ends::timestamp at time zone 'UTC')+make_interval(days=>plan.dias_gracia)
        when plan.caracteristicas->'catalog'->'selfService'='true'::jsonb then null
        else gracia_hasta end,
      proximo_cobro=case
        when ends is not null then ends
        when plan.caracteristicas->'catalog'->'selfService'='true'::jsonb then null
        else proximo_cobro end
    where id=subscription.id returning * into subscription;
    insert into public.eventos_licencia(suscripcion_id,contrato_id,tipo_evento,estado_anterior,estado_nuevo,actor_externo,motivo)
      values(subscription.id,contract.id,'PLAN_CHANGED',jsonb_build_object('planId',before_row->>'plan_id'),
        jsonb_build_object('planId',plan.id),actor,reason);
    update public.solicitudes_plan set estado='CLOSED',resultado='UPGRADED',atendido_por=actor,atendido_at=now(),
      nota_interna=coalesce(nullif(nota_interna,'')||' · ','')||'Plan cambiado a '||plan.nombre||'.'
    where cliente_id=customer and estado in ('PENDING','CONTACTED');
    result:=jsonb_build_object('id',subscription.id,'planId',plan.id,'version',subscription.row_version::text);

  else
    select * into request from public.solicitudes_plan s where s.id=target for update;
    perform private.admin_assert(found,'UPGRADE_REQUEST_NOT_FOUND');
    perform private.admin_assert(request.estado in ('PENDING','CONTACTED'),'UPGRADE_REQUEST_NOT_OPEN');
    perform private.admin_assert(request.row_version::text=payload->>'version','ROW_VERSION_CONFLICT');
    note:=btrim(coalesce(payload->>'note',''));
    perform private.admin_assert(length(note)<=2000
      and ((payload->>'state'='CONTACTED' and coalesce(payload->>'result','')='')
        or (payload->>'state'='CLOSED' and payload->>'result' in ('UPGRADED','DECLINED'))),'INVALID_UPGRADE_STATE');
    customer:=request.cliente_id;
    before_row:=to_jsonb(request);
    update public.solicitudes_plan set estado=payload->>'state',resultado=nullif(payload->>'result',''),
      nota_interna=coalesce(nullif(note,''),nota_interna),atendido_por=actor,atendido_at=now()
    where id=request.id returning * into request;
    result:=private.upgrade_request_json(request)||jsonb_build_object('note',request.nota_interna);
  end if;

  insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion,antes,despues)
    values(actor,customer,split_part(action,'.',1),coalesce(target::text,result->>'id',request_id::text),action,
      before_row,jsonb_build_object('requestId',request_id,'reason',reason,'result',result));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result)
    values(request_id,action,actor,digest,result);
  return result;
end; $$;

-- ============================================================================
-- 10. Permisos
-- ============================================================================

revoke all on function
  private.plan_effective_terms(jsonb),private.plan_json(uuid),private.clean_text(text),private.valid_email(text),
  private.self_service_client(uuid),private.outbox_client(text,jsonb),private.self_service_outbox_event(),
  private.client_subscription(uuid),private.client_plan(uuid),private.plan_month_start(),private.client_usage(uuid),
  private.plan_assert(uuid,text),private.plan_feature(uuid,text),private.schedule_is_preset(jsonb),
  private.upgrade_request_json(public.solicitudes_plan),private.commercial_plan_summary(uuid,boolean),
  private.self_service_manager(uuid),private.member_plants(uuid,jsonb),private.next_plant_code(uuid),
  private.self_service_mutate(text,jsonb,uuid),private.self_service_members(),private.self_service_plants(),
  private.customer_mutate_before_plans(text,jsonb,uuid),private.customer_read_before_plans(text,jsonb),
  private.customer_configure_checks_before_plans(uuid,jsonb,uuid),
  private.mobile_save_before_plans(uuid,uuid,uuid,bigint,jsonb,uuid),private.mobile_read_before_plans(text,jsonb),
  private.admin_read_before_plans(text,uuid,jsonb),private.admin_mutate_before_plans(text,text,jsonb,uuid)
from public,anon,authenticated,service_role;
-- La restricción de `planes_comerciales` la evalúa quien inserte.
revoke all on function private.plan_terms_valid(jsonb) from public,anon,authenticated;

revoke all on function public.ivmet_signup_status(text),public.ivmet_signup_complete(uuid,jsonb),
  public.ivmet_password_reset_target(text),public.ivmet_team_account(uuid,text,jsonb,uuid)
from public,anon,authenticated;
grant execute on function public.ivmet_signup_status(text),public.ivmet_signup_complete(uuid,jsonb),
  public.ivmet_password_reset_target(text),public.ivmet_team_account(uuid,text,jsonb,uuid)
to service_role;

revoke all on function public.ivmet_customer_mutate(text,jsonb,uuid),public.ivmet_customer_read(text,jsonb),
  public.ivmet_customer_configure_checks(uuid,jsonb,uuid),
  public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid),public.ivmet_mobile_read(text,jsonb)
from public,anon,service_role;
grant execute on function public.ivmet_customer_mutate(text,jsonb,uuid),public.ivmet_customer_read(text,jsonb),
  public.ivmet_customer_configure_checks(uuid,jsonb,uuid),
  public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid),public.ivmet_mobile_read(text,jsonb)
to authenticated;

revoke all on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid)
  from public,anon,authenticated;
grant execute on function public.ivmet_admin_read(text,uuid,jsonb),public.ivmet_admin_mutate(text,text,jsonb,uuid)
  to service_role;

commit;

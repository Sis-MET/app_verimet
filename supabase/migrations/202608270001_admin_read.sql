begin;

-- Solo el backend RimMET autenticado accede a este contrato. Nunca anon/mobile.
create table private.admin_requests (
  request_id uuid not null,
  action text not null,
  actor text not null,
  payload_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (request_id,action)
);
revoke all on private.admin_requests from public, anon, authenticated, service_role;

create or replace function private.admin_assert(condition boolean, error_code text)
returns void language plpgsql set search_path = '' as $$
begin
  if condition is distinct from true then
    raise exception using errcode = 'P0001', message = error_code;
  end if;
end;
$$;

create or replace function public.ivmet_admin_read(section text, client_id uuid default null, filters jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  result jsonb;
  page_number integer := greatest(coalesce((filters->>'page')::integer,1),1);
  page_size integer := least(greatest(coalesce((filters->>'pageSize')::integer,20),1),100);
  search_text text := '%' || coalesce(filters->>'search','') || '%';
  plant_filter uuid := nullif(filters->>'plantId','')::uuid;
begin
  perform private.admin_assert(auth.role() = 'service_role','ADMIN_REQUIRED');
  if section = 'overview' then
    select jsonb_build_object('clients',(select count(*) from public.clientes where activo),
      'plants',(select count(*) from public.plantas where activo),
      'equipment',(select count(*) from public.equipos where activo),
      'review',(select count(*) from public.equipos where activo and estado_catalogo<>'READY'),
      'licenses',(select count(*) from public.licencias_usuario where estado='ACTIVE'),
      'subscriptions',(select count(*) from public.suscripciones s join public.contratos c on c.id=s.contrato_id where c.estado='ACTIVE' and ((s.estado='ACTIVE' and s.inicio_periodo<=now() and s.fin_periodo>now()) or (s.estado='GRACE' and s.gracia_hasta>now()))),
      'pendingInvoices',(select count(*) from public.facturas where estado in ('PENDING','PARTIALLY_PAID','OVERDUE')),
      'expiresSoon',(select count(*) from public.suscripciones where estado='ACTIVE' and fin_periodo between now() and now()+interval '30 days')) into result;
  elsif section = 'clients' then
    select jsonb_build_object('total',(select count(*) from public.clientes c where c.codigo ilike search_text or c.nombre ilike search_text or c.razon_social ilike search_text),
      'items',coalesce(jsonb_agg(x),'[]'), 'page',page_number,'pageSize',page_size) into result from (
      select c.id,c.codigo,c.nombre,c.razon_social,c.activo,c.synced_at,
        (select count(*) from public.plantas p where p.cliente_id=c.id and p.activo) as plants,
        (select count(*) from public.equipos e where e.cliente_id=c.id and e.activo) as equipment,
        (select count(*) from public.equipos e where e.cliente_id=c.id and e.activo and e.estado_catalogo<>'READY') as review,
        (select count(*) from public.perfiles p where p.cliente_id=c.id and p.activo) as users,
        (select count(*) from public.licencias_usuario l join public.perfiles p on p.id=l.usuario_id where p.cliente_id=c.id and l.estado='ACTIVE') as licenses
      from public.clientes c where c.codigo ilike search_text or c.nombre ilike search_text or c.razon_social ilike search_text
      order by c.codigo,c.id limit page_size offset (page_number-1)*page_size
    ) x;
  elsif section = 'plans' then
    select coalesce(jsonb_agg(x order by x.nombre),'[]') into result from (
      select p.*,coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.precios_plan',to_jsonb(pp)) order by pp.vigente_desde desc) from public.precios_plan pp where pp.plan_id=p.id),'[]') as prices
      from public.planes_comerciales p
    ) x;
  elsif section = 'client' then
    perform private.admin_assert(exists(select 1 from public.clientes c where c.id=client_id),'CLIENT_NOT_FOUND');
    select jsonb_build_object(
      'client',(select to_jsonb(c) from public.clientes c where c.id=client_id),
      'plants',coalesce((select jsonb_agg(p order by p.legacy_codigo_planta) from public.plantas p where p.cliente_id=client_id),'[]'),
      'areas',coalesce((select jsonb_agg(a order by a.nombre) from public.areas a where a.cliente_id=client_id),'[]'),
      'patterns',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.patrones',to_jsonb(p)) || jsonb_build_object(
        'plantIds',coalesce((select jsonb_agg(pp.planta_id) from public.patron_plantas pp where pp.patron_id=p.id),'[]'),
        'certificates',coalesce((select jsonb_agg(pc order by pc.calibrado_el desc) from public.patron_certificados pc where pc.patron_id=p.id),'[]'))) from public.patrones p where p.cliente_id=client_id),'[]'),
      'contracts',coalesce((select jsonb_agg(c order by c.created_at desc) from public.contratos c where c.cliente_id=client_id),'[]'),
      'subscriptions',coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object(
        'planName',p.nombre,'baseSeats',(select coalesce(sum(sc.cantidad),0) from public.suscripcion_cupos sc where sc.suscripcion_id=s.id and sc.tipo='PLAN_BASE' and sc.estado in ('ACTIVE','PENDING')),
        'seats',coalesce((select sum(sc.cantidad) from public.suscripcion_cupos sc where sc.suscripcion_id=s.id and sc.estado='ACTIVE' and sc.vigente_desde<=now() and (sc.vigente_hasta is null or sc.vigente_hasta>now())),0),
        'assigned',(select count(*) from public.licencias_usuario l where l.suscripcion_id=s.id and l.estado='ACTIVE'),
        'cups',coalesce((select jsonb_agg(sc order by sc.created_at) from public.suscripcion_cupos sc where sc.suscripcion_id=s.id),'[]')
      ) order by s.created_at desc) from public.suscripciones s join public.contratos c on c.id=s.contrato_id join public.planes_comerciales p on p.id=s.plan_id where c.cliente_id=client_id),'[]'),
      'invoices',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.facturas',to_jsonb(f)) || jsonb_build_object('payments',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.pagos',to_jsonb(pay))) from public.pagos pay where pay.factura_id=f.id),'[]')) order by f.created_at desc) from public.facturas f join public.suscripciones s on s.id=f.suscripcion_id join public.contratos c on c.id=s.contrato_id where c.cliente_id=client_id),'[]'),
      'metrologyPlans',coalesce((select jsonb_agg(jsonb_build_object('id',pv.id,'name',p.nombre,'version',pv.version)) from public.plan_versiones pv join public.planes p on p.id=pv.plan_id where (p.cliente_id=client_id or p.cliente_id is null) and p.activo and pv.estado='PUBLISHED'),'[]')
    ) into result;
  elsif section = 'equipment' then
    perform private.admin_assert(client_id is not null,'CLIENT_REQUIRED');
    with matching as (
      select e.*,ei.area_id,coalesce(ei.habilitado,false) as habilitado,coalesce(ei.estado_configuracion,'PENDING') as estado_configuracion,
        coalesce(ei.row_version,0)::text as config_version,
        (select ep.plan_version_id from public.equipo_planes ep where ep.equipo_id=e.id and ep.vigente_hasta is null) as plan_version_id
      from public.equipos e left join public.equipos_ivmet ei on ei.equipo_id=e.id
      where e.cliente_id=client_id and (plant_filter is null or e.planta_id=plant_filter)
        and (coalesce(filters->>'status','')='' or e.estado_catalogo=filters->>'status')
        and (e.cod_metrica ilike search_text or e.instrumento ilike search_text or e.marca ilike search_text or e.serie ilike search_text or e.cod_interno ilike search_text)
    ), page_rows as (select * from matching order by cod_metrica,id limit page_size offset (page_number-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,'items',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('ranges',coalesce((select jsonb_agg(private.stringify_ivmet_outbox_numbers('public.equipo_rangos',to_jsonb(r)) order by r.numero_rango) from public.equipo_rangos r where r.equipo_id=e.id),'[]')) order by e.cod_metrica) from page_rows e),'[]')) into result;
  elsif section = 'users' then
    perform private.admin_assert(client_id is not null,'CLIENT_REQUIRED');
    with matching as (select p.id,p.usuario,p.nombre,p.rol,p.cliente_id,p.activo,p.debe_cambiar_password,p.row_version::text,p.created_at from public.perfiles p where p.cliente_id=client_id and (p.usuario ilike search_text or p.nombre ilike search_text)),
    page_rows as (select * from matching order by usuario,id limit page_size offset (page_number-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,
      'items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
        'plantIds',coalesce((select jsonb_agg(up.planta_id) from public.usuario_plantas up where up.usuario_id=p.id and up.activa),'[]'),
        'license',(select to_jsonb(l) from public.licencias_usuario l where l.usuario_id=p.id and l.estado='ACTIVE'),
        'appAccess',private.user_has_active_license(p.id)
      ) order by p.usuario) from page_rows p),'[]')) into result;
  elsif section = 'activity' then
    -- No snapshots ni evidencia privada: solo eventos administrativos de RimMET.
    select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'),'page',page_number,'pageSize',page_size) into result from (
      select a.id,a.actor_externo,a.entidad,a.entidad_id,a.accion,a.created_at
      from public.auditoria a where a.cliente_id=client_id and a.actor_externo like 'RIMMET:%'
      order by a.created_at desc,a.id limit page_size offset (page_number-1)*page_size
    ) x;
  elsif section = 'integration' then
    select jsonb_build_object(
      'scopes',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('plants',coalesce((select jsonb_agg(p.legacy_codigo_planta) from private.catalog_sync_scope_plants p where p.scope_id=s.id and p.habilitada),'[]'),'equipmentCodes',coalesce((select jsonb_agg(e.legacy_cod_metrica) from private.catalog_sync_scope_equipments e where e.scope_id=s.id and e.habilitado),'[]'),'equipmentCount',(select count(*) from private.catalog_sync_scope_equipments e where e.scope_id=s.id and e.habilitado)) order by s.solicitado_at desc) from private.catalog_sync_scope s),'[]'),
      'runs',coalesce((select jsonb_agg(x) from (select id,direccion,worker_id,estado,scope_id,started_at,finished_at,accepted_count,rejected_count from private.sync_runs order by started_at desc limit 15) x),'[]'),
      'outbox',coalesce((select jsonb_object_agg(x.estado,x.n) from (select estado,count(*) as n from private.sync_outbox group by estado) x),'{}')
    ) into result;
  else
    raise exception using errcode='22023', message='UNKNOWN_ADMIN_SECTION';
  end if;
  return result;
end;
$$;
revoke all on function private.admin_assert(boolean,text) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_admin_read(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.ivmet_admin_read(text,uuid,jsonb) to service_role;
commit;

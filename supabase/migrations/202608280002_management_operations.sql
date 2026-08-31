begin;

create table private.rimmet_staff (
  actor text primary key check (actor ~ '^RIMMET:.{1,100}$'),
  nombre text not null,
  rol text not null check (rol in ('admin','commercial','support','metrologist')),
  activo boolean not null default true,
  row_version bigint not null default 1,
  updated_at timestamptz not null default now()
);
create trigger rimmet_staff_updated before update on private.rimmet_staff for each row execute function private.set_updated_at();
revoke all on private.rimmet_staff from public,anon,authenticated,service_role;

create function private.staff_role(actor text) returns text
language plpgsql stable security definer set search_path='' as $$
declare r text;
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='STAFF_ACCESS_DENIED'; end if;
  select s.rol into r from private.rimmet_staff s where s.actor=staff_role.actor and s.activo;
  if r is null then raise exception using errcode='42501',message='STAFF_ACCESS_DENIED'; end if;
  return r;
end; $$;
create function private.staff_require(actor text,capability text) returns void
language plpgsql stable security definer set search_path='' as $$
declare r text:=private.staff_role(actor);
begin
  if r='admin' or (r='commercial' and capability in ('commercial','integration')) or (r='support' and capability='support')
    or (r='metrologist' and capability in ('metrology','support')) then return; end if;
  raise exception using errcode='42501',message='STAFF_PERMISSION_REQUIRED';
end; $$;
create function public.ivmet_bootstrap_admin(target_actor text,target_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  perform pg_advisory_xact_lock(hashtextextended('ivmet-staff-bootstrap',0));
  perform private.admin_assert(target_actor ~ '^RIMMET:.{1,100}$' and length(btrim(target_name)) between 1 and 150,'INVALID_STAFF');
  if exists(select 1 from private.rimmet_staff where activo and rol='admin') then
    perform private.admin_assert(exists(select 1 from private.rimmet_staff where actor=target_actor and activo and rol='admin'),'ADMIN_ALREADY_BOOTSTRAPPED');
  else
    insert into private.rimmet_staff(actor,nombre,rol) values(target_actor,btrim(target_name),'admin')
    on conflict(actor) do update set activo=true,rol='admin',nombre=excluded.nombre;
    insert into public.auditoria(actor_externo,entidad,entidad_id,accion) values(target_actor,'rimmet_staff',target_actor,'BOOTSTRAP_ADMIN');
  end if;
  return jsonb_build_object('actor',target_actor,'role','admin');
end; $$;
create function public.ivmet_staff_authorize(actor text,capability text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r text:=private.staff_role(actor);
begin
  if capability is not null then perform private.staff_require(actor,capability); end if;
  return jsonb_build_object('actor',actor,'role',r,'capabilities',case r
    when 'admin' then jsonb_build_array('commercial','support','metrology','integration','staff')
    when 'commercial' then jsonb_build_array('commercial','integration')
    when 'metrologist' then jsonb_build_array('metrology','support') else jsonb_build_array(r) end);
end; $$;

-- El contrato legado conserva su interfaz; las mutaciones comprueban el permiso también en PostgreSQL.
alter function public.ivmet_admin_mutate(text,text,jsonb,uuid) rename to ivmet_admin_mutate_before_permissions;
alter function public.ivmet_admin_mutate_before_permissions(text,text,jsonb,uuid) set schema private;
-- PL/pgSQL conserva el texto de las referencias a parámetros al renombrar.
do $$ begin
  execute replace(pg_get_functiondef('private.ivmet_admin_mutate_before_permissions(text,text,jsonb,uuid)'::regprocedure),
    'ivmet_admin_mutate.', 'ivmet_admin_mutate_before_permissions.');
end $$;
create function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform private.staff_require(actor,case when action in ('scope.request','scope.extend','scope.retry') then 'integration' else 'commercial' end);
  return private.ivmet_admin_mutate_before_permissions(actor,action,payload,request_id);
end; $$;
revoke all on function private.ivmet_admin_mutate_before_permissions(text,text,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_admin_mutate(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.ivmet_admin_mutate(text,text,jsonb,uuid) to service_role;

-- No se registran métodos demo. Esta lista la completa una migración del motor aprobado.
create table private.approved_metrology_methods (
  method text not null,
  procedure_reference text not null,
  procedure_hash text not null check (procedure_hash ~ '^[0-9a-f]{64}$'),
  golden_tests_reference text not null check (length(btrim(golden_tests_reference))>0),
  engine_version text not null check (length(btrim(engine_version))>0),
  approved_by text not null check (length(btrim(approved_by))>0),
  approved_at timestamptz not null,
  primary key(method,procedure_reference)
);
revoke all on private.approved_metrology_methods from public,anon,authenticated,service_role;
alter table public.plan_versiones add column published_by_external text,
  add column retired_by_external text, add column draft_revision bigint not null default 1;
-- Compatible con eventos de versiones generados antes de esta migración.
update private.sync_outbox set payload=jsonb_build_object('published_by_external',null,'retired_by_external',null,'draft_revision','1')||payload
  where aggregate_type='public.plan_versiones' and estado in ('PENDING','CLAIMED','DEAD');
alter table public.plan_versiones drop constraint plan_versiones_publicacion_ck;
alter table public.plan_versiones add constraint plan_versiones_publicacion_ck check (
  (estado='DRAFT' and published_at is null and published_by is null and published_by_external is null)
  or (estado in ('PUBLISHED','RETIRED') and published_at is not null and num_nonnulls(published_by,published_by_external)=1));

create or replace function private.protect_plan_version() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then
    if old.estado<>'DRAFT' then raise exception 'PUBLISHED_PLAN_IS_IMMUTABLE'; end if;
    return old;
  end if;
  if old.estado='DRAFT' and new.estado='DRAFT' then return new; end if;
  if old.estado='DRAFT' and new.estado='PUBLISHED' and new.published_at is not null
    and num_nonnulls(new.published_by,new.published_by_external)=1
    and (to_jsonb(new)-array['estado','published_at','published_by','published_by_external'])=
        (to_jsonb(old)-array['estado','published_at','published_by','published_by_external']) then return new; end if;
  if old.estado='PUBLISHED' and new.estado='RETIRED' and new.retired_at is not null
    and num_nonnulls(new.retired_by,new.retired_by_external)=1
    and (to_jsonb(new)-array['estado','retired_at','retired_by','retired_by_external'])=
        (to_jsonb(old)-array['estado','retired_at','retired_by','retired_by_external']) then return new; end if;
  raise exception 'INVALID_PLAN_VERSION_TRANSITION';
end; $$;

-- Evita mover contenido publicado a otro borrador y serializa edición/publicación.
create or replace function private.protect_published_plan_content() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_parent uuid; new_parent uuid; parent_id uuid; version_state text;
begin
  if tg_table_name='plan_pruebas' then
    if tg_op<>'INSERT' then old_parent:=old.plan_version_id; end if;
    if tg_op<>'DELETE' then new_parent:=new.plan_version_id; end if;
  else
    if tg_op<>'INSERT' then select p.plan_version_id into old_parent from public.plan_pruebas p where p.id=old.plan_prueba_id; end if;
    if tg_op<>'DELETE' then select p.plan_version_id into new_parent from public.plan_pruebas p where p.id=new.plan_prueba_id; end if;
  end if;
  for parent_id in select distinct x from unnest(array[old_parent,new_parent]) x where x is not null order by x loop
    select estado into version_state from public.plan_versiones where id=parent_id for share;
    if version_state is distinct from 'DRAFT' then raise exception 'PUBLISHED_PLAN_IS_IMMUTABLE'; end if;
  end loop;
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;

create function private.metrology_version_json(target_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(v)||jsonb_build_object('draft_revision',v.draft_revision::text,'name',p.nombre,'description',p.descripcion,'clientId',p.cliente_id,
    'tests',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('points',coalesce((select jsonb_agg(
      private.stringify_ivmet_outbox_numbers('public.plan_puntos',to_jsonb(pt)) order by pt.orden)
      from public.plan_puntos pt where pt.plan_prueba_id=t.id),'[]')) order by t.tipo)
      from public.plan_pruebas t where t.plan_version_id=v.id),'[]'))
  from public.plan_versiones v join public.planes p on p.id=v.plan_id where v.id=target_id;
$$;

create function public.ivmet_ops_read(actor text,section text,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r text:=private.staff_role(actor); result jsonb; selected_id uuid:=nullif(filters->>'id','')::uuid;
  customer uuid:=nullif(filters->>'clientId','')::uuid; plant uuid:=nullif(filters->>'plantId','')::uuid;
  query text:='%'||coalesce(filters->>'search','')||'%'; pg integer:=greatest(coalesce((filters->>'page')::integer,1),1);
  sz integer:=least(greatest(coalesce((filters->>'pageSize')::integer,20),1),100); target public.casos_compartidos%rowtype;
begin
  if section='session' then return public.ivmet_staff_authorize(actor); end if;
  perform private.staff_require(actor,case when section in ('cases','case','assignees') then 'support'
    when section in ('metrology','metrology-catalog') then 'metrology'
    when section in ('readiness','billing') then 'commercial' when section='privacy' then 'integration' else 'staff' end);
  if section='cases' then
    with matching as (select c.id,c.codigo,c.cliente_id,c.planta_id,c.equipo_id,c.estado,c.responsable,c.autorizado_at,c.row_version::text,
      cl.nombre as cliente,pl.legacy_codigo_planta as planta,e.cod_metrica
      from public.casos_compartidos c join public.clientes cl on cl.id=c.cliente_id
      join public.plantas pl on pl.id=c.planta_id join public.equipos e on e.id=c.equipo_id
      where c.visibilidad='SHARED' and (customer is null or c.cliente_id=customer) and (plant is null or c.planta_id=plant)
        and (nullif(filters->>'status','') is null or c.estado=filters->>'status')
        and (c.codigo ilike query or cl.nombre ilike query or e.cod_metrica ilike query)),
      page_rows as(select * from matching order by autorizado_at desc,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('items',coalesce((select jsonb_agg(p order by p.autorizado_at desc,p.id) from page_rows p),'[]'),
      'total',(select count(*) from matching),'page',pg,'pageSize',sz) into result;
  elsif section='case' then
    select * into target from public.casos_compartidos where id=selected_id and visibilidad='SHARED';
    perform private.admin_assert(found,'CASE_NOT_ACCESSIBLE');
    insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion)
      values(actor,target.cliente_id,'caso_compartido',target.id::text,'CASE_READ');
    result:=private.case_export(target.id);
  elsif section='assignees' then
    select coalesce(jsonb_agg(jsonb_build_object('actor',s.actor,'name',s.nombre) order by s.nombre),'[]') into result
      from private.rimmet_staff s where s.activo and s.rol in ('admin','support','metrologist');
  elsif section='staff' then
    select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('row_version',s.row_version::text) order by s.nombre),'[]') into result from private.rimmet_staff s;
  elsif section='metrology' then
    with matching as(select v.id,v.created_at from public.plan_versiones v join public.planes p on p.id=v.plan_id
      where (customer is null or p.cliente_id=customer or p.cliente_id is null) and (selected_id is null or v.id=selected_id)
        and (p.nombre ilike query or v.procedimiento_referencia ilike query)
        and (nullif(filters->>'status','') is null or v.estado=filters->>'status')),
      page_rows as(select * from matching order by created_at desc,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('items',coalesce((select jsonb_agg(private.metrology_version_json(p.id) order by p.created_at desc,p.id) from page_rows p),'[]'),
      'total',(select count(*) from matching),'page',pg,'pageSize',sz,
      'approvedMethods',coalesce((select jsonb_agg(to_jsonb(m) order by m.method,m.procedure_reference) from private.approved_metrology_methods m),'[]')) into result;
  elsif section='metrology-catalog' then
    -- Solo catálogos; no contratos, facturas ni resultados privados para el metrólogo.
    with matching as(select e.id,e.cod_metrica,e.planta_id from public.equipos e where customer is not null and e.cliente_id=customer
      and e.activo and e.estado_catalogo='READY' and e.cod_metrica ilike query),
      page_rows as(select * from matching order by cod_metrica,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('clients',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.nombre,'code',c.codigo) order by c.codigo)
      from public.clientes c where c.activo),'[]'),'equipment',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'code',e.cod_metrica,'plantId',e.planta_id) order by e.cod_metrica)
      from page_rows e),'[]'),'total',(select count(*) from matching),'page',pg,'pageSize',sz) into result;
  elsif section='readiness' then
    with matching as(select c.* from public.clientes c where c.activo and (customer is null or c.id=customer) and (c.codigo ilike query or c.nombre ilike query)),
      page_rows as(select * from matching order by codigo,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('total',(select count(*) from matching),'page',pg,'pageSize',sz,'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'code',c.codigo,'name',c.nombre,'syncedAt',c.synced_at,
      'contract',exists(select 1 from public.contratos ct where ct.cliente_id=c.id and ct.estado='ACTIVE' and ct.vigente_desde<=current_date and (ct.vigente_hasta is null or ct.vigente_hasta>=current_date)),
      'subscription',exists(select 1 from public.suscripciones s join public.contratos ct on ct.id=s.contrato_id where ct.cliente_id=c.id and ct.estado='ACTIVE' and s.estado='ACTIVE' and s.inicio_periodo<=now() and s.fin_periodo>now()),
      'users',exists(select 1 from public.perfiles p where p.cliente_id=c.id and p.activo and private.user_has_active_license(p.id)),
      'equipment',exists(select 1 from public.equipos e join public.equipos_ivmet ei on ei.equipo_id=e.id where e.cliente_id=c.id and e.activo and e.estado_catalogo='READY' and ei.habilitado),
      'standards',exists(select 1 from public.plantas pl where pl.cliente_id=c.id and pl.activo)
        and not exists(select 1 from public.plantas pl where pl.cliente_id=c.id and pl.activo and not exists(select 1 from public.patron_plantas pp
          join public.patrones p on p.id=pp.patron_id join public.patron_certificados pc on pc.patron_id=p.id
          where pp.planta_id=pl.id and p.activo and pc.estado='ACTIVE' and pc.calibrado_el<=current_date and pc.vence_el>=current_date)),
      'plans',exists(select 1 from public.equipos e join public.equipos_ivmet ei on ei.equipo_id=e.id where e.cliente_id=c.id and ei.habilitado)
        and not exists(select 1 from public.equipos e join public.equipos_ivmet ei on ei.equipo_id=e.id where e.cliente_id=c.id and ei.habilitado and not exists(
          select 1 from public.equipo_planes ep join public.plan_versiones v on v.id=ep.plan_version_id where ep.equipo_id=e.id and v.estado='PUBLISHED'
          and ep.vigente_desde<=now() and (ep.vigente_hasta is null or ep.vigente_hasta>now())))
    ) order by c.codigo) from page_rows c),'[]')) into result;
  elsif section='billing' then
    with matching as(select f.id,f.numero_factura as numero,f.estado,f.saldo::text,f.moneda,f.fecha_vencimiento as vence_el,c.nombre as cliente,c.id as cliente_id
      from public.facturas f join public.suscripciones s on s.id=f.suscripcion_id join public.contratos ct on ct.id=s.contrato_id
      join public.clientes c on c.id=ct.cliente_id where f.estado in ('PENDING','PARTIALLY_PAID','OVERDUE')
      and (customer is null or c.id=customer) and (c.nombre ilike query or f.numero_factura ilike query)),
      page_rows as(select * from matching order by vence_el,id limit sz offset(pg-1)*sz)
    select jsonb_build_object('items',coalesce((select jsonb_agg(p order by p.vence_el,p.id) from page_rows p),'[]'),
      'total',(select count(*) from matching),'page',pg,'pageSize',sz) into result;
  elsif section='privacy' then
    result:=jsonb_build_object('contractVersion',public.ivmet_worker_contract(),'privateEvidenceExport',false,'sharedCasesOnly',true,
      'queue',coalesce((select jsonb_object_agg(q.estado,q.n) from(select estado,count(*) n from private.sync_outbox
        where not privacy_blocked and private.ivmet_export_allowed(aggregate_type) group by estado) q),'{}'));
  elsif section='audit' then
    select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'),'page',pg,'pageSize',sz) into result from(
      select a.id,a.actor_externo,a.entidad,a.entidad_id,a.accion,a.created_at from public.auditoria a
      where a.actor_externo like 'RIMMET:%' and (customer is null or a.cliente_id=customer)
      order by a.created_at desc,a.id limit sz offset(pg-1)*sz) x;
  else raise exception 'UNKNOWN_OPS_SECTION'; end if;
  return result;
end; $$;

create function public.ivmet_ops_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved private.admin_requests%rowtype; target_id uuid:=nullif(payload->>'id','')::uuid;
  digest text:=encode(sha256(convert_to(action||payload::text,'UTF8')),'hex'); result jsonb;
  c public.casos_compartidos%rowtype; pv public.plan_versiones%rowtype; met_plan_id uuid; test_id uuid;
  t jsonb; pt jsonb; seq integer; tests_count integer; target_actor text; old_version bigint; assigned_at timestamptz;
begin
  perform private.staff_require(actor,case when action like 'case.%' then 'support' when action like 'metrology.%' then 'metrology' else 'staff' end);
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object','INVALID_REQUEST');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r where r.request_id=ivmet_ops_mutate.request_id and r.action=ivmet_ops_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=digest,'IDEMPOTENCY_CONFLICT');
    -- No devolver un expediente que el cliente haya retirado entre reintentos.
    return saved.result;
  end if;
  if action='case.update' then
    select * into c from public.casos_compartidos where id=target_id and visibilidad='SHARED' for update;
    perform private.admin_assert(found,'CASE_NOT_ACCESSIBLE');
    perform private.admin_assert(c.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert(length(btrim(payload->>'comment')) between 1 and 2000,'COMMENT_REQUIRED');
    perform private.admin_assert(payload->>'status' in ('NEW','IN_REVIEW','WAITING_CLIENT','RESOLVED'),'INVALID_CASE_STATUS');
    target_actor:=nullif(payload->>'assignee','');
    perform private.admin_assert(target_actor is null or exists(select 1 from private.rimmet_staff s where s.actor=target_actor and s.activo and s.rol in ('admin','support','metrologist')),'ASSIGNEE_NOT_AVAILABLE');
    update public.casos_compartidos set estado=payload->>'status',responsable=target_actor where id=c.id;
    insert into public.caso_eventos(caso_id,actor_externo,accion,comentario) values(c.id,actor,'STATUS_'||(payload->>'status'),btrim(payload->>'comment'));
    result:=jsonb_build_object('id',c.id);
  elsif action='staff.save' then
    perform private.staff_require(actor,'staff');
    perform pg_advisory_xact_lock(hashtextextended('ivmet-staff-bootstrap',0));
    target_actor:=payload->>'actor';
    perform private.admin_assert(target_actor ~ '^RIMMET:.{1,100}$' and length(btrim(payload->>'name')) between 1 and 150,'INVALID_STAFF');
    select row_version into old_version from private.rimmet_staff where rimmet_staff.actor=target_actor for update;
    if found then perform private.admin_assert(old_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT'); end if;
    perform private.admin_assert(not exists(select 1 from private.rimmet_staff s where s.actor=target_actor and s.rol='admin' and s.activo)
      or ((payload->>'role')='admin' and (payload->>'active')::boolean)
      or exists(select 1 from private.rimmet_staff s where s.actor<>target_actor and s.rol='admin' and s.activo),'LAST_ADMIN_REQUIRED');
    insert into private.rimmet_staff(actor,nombre,rol,activo) values(target_actor,btrim(payload->>'name'),payload->>'role',(payload->>'active')::boolean)
    on conflict on constraint rimmet_staff_pkey do update set nombre=excluded.nombre,rol=excluded.rol,activo=excluded.activo;
    result:=jsonb_build_object('actor',target_actor);
  elsif action='metrology.save' then
    perform private.admin_assert(length(btrim(payload->>'name')) between 1 and 200,'PLAN_NAME_REQUIRED');
    tests_count:=jsonb_array_length(payload->'tests');
    perform private.admin_assert(tests_count between 1 and 3,'PLAN_TESTS_REQUIRED');
    if target_id is null then
      met_plan_id:=nullif(payload->>'planId','')::uuid;
      if met_plan_id is null then
        insert into public.planes(cliente_id,nombre,descripcion) values(nullif(payload->>'clientId','')::uuid,btrim(payload->>'name'),payload->>'description') returning id into met_plan_id;
      else perform 1 from public.planes p where p.id=met_plan_id for update; perform private.admin_assert(found,'PLAN_NOT_FOUND'); end if;
      insert into public.plan_versiones(plan_id,version,procedimiento_referencia,notas)
        select met_plan_id,coalesce(max(v.version),0)+1,nullif(btrim(payload->>'procedureReference'),''),payload->>'notes' from public.plan_versiones v where v.plan_id=met_plan_id
        returning id into target_id;
    else
      select * into pv from public.plan_versiones where id=target_id for update;
      perform private.admin_assert(found and pv.estado='DRAFT','PUBLISHED_PLAN_IS_IMMUTABLE');
      perform private.admin_assert(pv.draft_revision=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      delete from public.plan_puntos where plan_prueba_id in(select id from public.plan_pruebas where plan_version_id=target_id);
      delete from public.plan_pruebas where plan_version_id=target_id;
      update public.plan_versiones set procedimiento_referencia=nullif(btrim(payload->>'procedureReference'),''),notas=payload->>'notes',draft_revision=draft_revision+1 where id=target_id;
    end if;
    for t in select value from jsonb_array_elements(payload->'tests') loop
      perform private.admin_assert(jsonb_array_length(t->'points') between 1 and 200,'PLAN_POINTS_REQUIRED');
      perform private.admin_assert((t->>'warningDays')::integer<(t->>'frequencyDays')::integer,'PLAN_WARNING_INVALID');
      insert into public.plan_pruebas(plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,aviso_dias)
      values(target_id,t->>'type',t->>'method',t->>'unit',(t->>'frequencyDays')::integer,(t->>'warningDays')::integer) returning id into test_id;
      seq:=0;
      for pt in select value from jsonb_array_elements(t->'points') loop
        seq:=seq+1;
        perform private.admin_assert(jsonb_typeof(pt->'load')='string' and (pt->>'load') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$'
          and jsonb_typeof(pt->'tolerance')='string' and (pt->>'tolerance') ~ '^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$','EXACT_DECIMAL_REQUIRED');
        insert into public.plan_puntos(plan_prueba_id,grupo,orden,codigo,etiqueta,carga_nominal,tolerancia,posicion,direccion,metadata)
        values(test_id,(pt->>'group')::integer,seq,pt->>'code',pt->>'label',(pt->>'load')::numeric,(pt->>'tolerance')::numeric,
          pt->>'position',pt->>'direction',coalesce(pt->'metadata','{}'));
      end loop;
    end loop;
    result:=jsonb_build_object('id',target_id);
  elsif action in ('metrology.publish','metrology.retire') then
    select * into pv from public.plan_versiones where id=target_id for update;
    perform private.admin_assert(found and pv.draft_revision=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    if action='metrology.publish' then
      perform private.admin_assert(pv.estado='DRAFT','PUBLISHED_PLAN_IS_IMMUTABLE');
      perform private.admin_assert(exists(select 1 from public.plan_pruebas where plan_version_id=pv.id)
        and not exists(select 1 from public.plan_pruebas t where t.plan_version_id=pv.id and not exists(select 1 from public.plan_puntos p where p.plan_prueba_id=t.id)),'PLAN_POINTS_REQUIRED');
      perform private.admin_assert(pv.procedimiento_referencia is not null and not exists(select 1 from public.plan_pruebas t where t.plan_version_id=pv.id
        and not exists(select 1 from private.approved_metrology_methods m where m.method=t.metodo_evaluacion and m.procedure_reference=pv.procedimiento_referencia)),'OFFICIAL_PROCEDURE_REQUIRED');
      update public.plan_versiones set estado='PUBLISHED',published_at=now(),published_by_external=actor where id=pv.id;
    else
      perform private.admin_assert(pv.estado='PUBLISHED','PUBLISHED_PLAN_REQUIRED');
      update public.plan_versiones set estado='RETIRED',retired_at=now(),retired_by_external=actor where id=pv.id;
    end if;
    result:=jsonb_build_object('id',pv.id);
  elsif action='metrology.assign' then
    perform 1 from public.equipos e where e.id=(payload->>'equipmentId')::uuid and e.activo and e.estado_catalogo='READY' for update;
    perform private.admin_assert(found,'EQUIPMENT_REQUIRES_REVIEW');
    select v.* into pv from public.plan_versiones v join public.planes p on p.id=v.plan_id
      join public.equipos e on e.id=(payload->>'equipmentId')::uuid where v.id=(payload->>'planVersionId')::uuid and v.estado='PUBLISHED'
      and (p.cliente_id is null or p.cliente_id=e.cliente_id) for share of v;
    perform private.admin_assert(found,'PUBLISHED_PLAN_REQUIRED');
    perform private.admin_assert(pv.procedimiento_referencia is not null and exists(select 1 from public.plan_pruebas where plan_version_id=pv.id)
      and not exists(select 1 from public.plan_pruebas t where t.plan_version_id=pv.id and not exists(
        select 1 from private.approved_metrology_methods m where m.method=t.metodo_evaluacion and m.procedure_reference=pv.procedimiento_referencia)),
      'OFFICIAL_PROCEDURE_REQUIRED');
    assigned_at:=clock_timestamp();
    update public.equipo_planes set vigente_hasta=assigned_at where equipo_id=(payload->>'equipmentId')::uuid and vigente_hasta is null;
    insert into public.equipo_planes(equipo_id,plan_version_id,vigente_desde) values((payload->>'equipmentId')::uuid,pv.id,assigned_at) returning id into target_id;
    result:=jsonb_build_object('id',target_id);
  else raise exception 'UNKNOWN_OPS_ACTION'; end if;
  insert into public.auditoria(actor_externo,entidad,entidad_id,accion,despues)
    values(actor,split_part(action,'.',1),coalesce(target_id::text,target_actor,'operacion'),action,result);
  insert into private.admin_requests(request_id,action,actor,payload_hash,result) values(request_id,action,actor,digest,result);
  return result;
end; $$;

-- Las escrituras de configuración pasan por las RPC, no por tablas service_role.
revoke insert,update,delete on public.planes,public.plan_versiones,public.plan_pruebas,public.plan_puntos,public.equipo_planes from service_role;
revoke all on function private.staff_role(text),private.staff_require(text,text),private.metrology_version_json(uuid) from public,anon,authenticated,service_role;
revoke all on function public.ivmet_bootstrap_admin(text,text),public.ivmet_staff_authorize(text,text),public.ivmet_ops_read(text,text,jsonb),
  public.ivmet_ops_mutate(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.ivmet_bootstrap_admin(text,text),public.ivmet_staff_authorize(text,text),public.ivmet_ops_read(text,text,jsonb),
  public.ivmet_ops_mutate(text,text,jsonb,uuid) to service_role;

create or replace function public.ivmet_worker_contract() returns integer
language sql stable security definer set search_path='' as $$ select 3 $$;

commit;

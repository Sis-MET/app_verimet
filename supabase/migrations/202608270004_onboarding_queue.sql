begin;

-- Estado operativo privado: no añade columnas al contrato del espejo SQL Server.
alter table private.catalog_sync_scope add column client_name text;
create table private.catalog_jobs (
  scope_id uuid primary key references private.catalog_sync_scope(id),
  requested_version bigint not null default 1,
  completed_version bigint not null default 0,
  claimed_version bigint,
  status text not null default 'QUEUED' check (status in ('QUEUED','RUNNING','SUCCEEDED','PARTIAL','FAILED')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  run_id uuid references private.sync_runs(id),
  lease_until timestamptz,
  constraint catalog_jobs_versions_ck check (requested_version >= completed_version and completed_version >= 0)
);
create index catalog_jobs_due_idx on private.catalog_jobs(next_attempt_at);
create index sync_runs_scope_idx on private.sync_runs(scope_id,started_at desc);
create index sync_quarantine_run_idx on private.sync_quarantine(run_id,created_at);
create table private.worker_heartbeats (
  worker_id text primary key check (length(worker_id) between 3 and 150),
  instance_id uuid not null,
  mode text not null check (mode in ('daemon','catalog','outbox','once')),
  state text not null check (state in ('STARTING','ONLINE','DEGRADED','STOPPED','BLOCKED')),
  scope_id uuid references private.catalog_sync_scope(id),
  poll_seconds integer not null check (poll_seconds between 1 and 3600),
  last_seen_at timestamptz not null default now()
);
revoke all on private.catalog_jobs, private.worker_heartbeats from public,anon,authenticated,service_role;

insert into private.catalog_jobs(scope_id,status,completed_version)
select id,case when estado='ACTIVE' then 'SUCCEEDED' else 'QUEUED' end,
  case when estado='ACTIVE' then 1 else 0 end from private.catalog_sync_scope;
update private.catalog_sync_scope s set client_name=c.nombre
from public.clientes c where c.legacy_cliente_id=s.legacy_cliente_id;

create function private.enqueue_catalog_scope() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into private.catalog_jobs(scope_id) values(new.id);
  return new;
end; $$;
create trigger catalog_scope_enqueue after insert on private.catalog_sync_scope
for each row execute function private.enqueue_catalog_scope();
revoke all on function private.enqueue_catalog_scope() from public,anon,authenticated,service_role;

create function public.ivmet_worker_contract() returns integer
language sql stable security definer set search_path='' as $$select 2$$;

create function public.report_ivmet_worker(worker_id text,instance_id uuid,mode text,state text,
  target_scope_id uuid default null,poll_seconds integer default 10) returns void
language plpgsql security definer set search_path='' as $$
begin
  insert into private.worker_heartbeats as h(worker_id,instance_id,mode,state,scope_id,poll_seconds)
  values(worker_id,instance_id,mode,state,target_scope_id,poll_seconds)
  on conflict on constraint worker_heartbeats_pkey do update set instance_id=excluded.instance_id,mode=excluded.mode,
    state=excluded.state,scope_id=excluded.scope_id,poll_seconds=excluded.poll_seconds,last_seen_at=clock_timestamp()
    where h.instance_id=excluded.instance_id or excluded.state in ('STARTING','BLOCKED');
end; $$;

-- Reclamar y registrar el intento es una única transacción. El run_id es el token
-- de propiedad; un proceso antiguo nunca puede cerrar el intento que lo reemplazó.
create function public.claim_ivmet_catalog_job(worker_id text,target_scope_id uuid default null,
  lease_seconds integer default 300) returns jsonb
language plpgsql security definer set search_path='' as $$
declare job private.catalog_jobs%rowtype; selected_scope uuid; new_run uuid; result jsonb;
begin
  perform private.admin_assert(length(worker_id) between 3 and 150 and lease_seconds between 30 and 3600,'INVALID_WORKER_CONFIG');
  -- Mismo orden de bloqueo que scope.extend: alcance antes de trabajo.
  select s.id into selected_scope from private.catalog_sync_scope s join private.catalog_jobs j on s.id=j.scope_id
    where s.estado in ('REQUESTED','ACTIVE') and j.next_attempt_at<=clock_timestamp()
      and (j.lease_until is null or j.lease_until<=clock_timestamp())
      and (target_scope_id is null or j.scope_id=target_scope_id)
    order by (j.requested_version>j.completed_version) desc,j.next_attempt_at,j.scope_id
    for update of s skip locked limit 1;
  if not found then return null; end if;
  select * into job from private.catalog_jobs where scope_id=selected_scope for update;
  if job.run_id is not null then
    update private.sync_runs set estado='FAILED',finished_at=clock_timestamp(),error='WORKER_INTERRUPTED'
      where id=job.run_id and estado='RUNNING';
  end if;
  insert into private.sync_runs(direccion,worker_id,scope_id,metadata)
    values('DATAMET_TO_SUPABASE',worker_id,job.scope_id,jsonb_build_object('generation',job.requested_version::text)) returning id into new_run;
  update private.catalog_jobs set run_id=new_run,claimed_version=requested_version,status='RUNNING',
    attempts=attempts+1,lease_until=clock_timestamp()+make_interval(secs=>lease_seconds) where scope_id=job.scope_id;
  select to_jsonb(s)||jsonb_build_object('run_id',new_run,'generation',job.requested_version::text)
    into result from public.list_ivmet_catalog_sync_scopes(job.scope_id) s;
  return result;
end; $$;

create function public.renew_ivmet_catalog_job(target_run_id uuid,lease_seconds integer default 300) returns boolean
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
  perform private.admin_assert(lease_seconds between 30 and 3600,'INVALID_WORKER_CONFIG');
  update private.catalog_jobs set lease_until=clock_timestamp()+make_interval(secs=>lease_seconds)
    where run_id=target_run_id and status='RUNNING' and lease_until>clock_timestamp();
  get diagnostics n=row_count; return n=1;
end; $$;

create function public.finish_ivmet_catalog_job(target_run_id uuid,target_client_id uuid,final_status text,
  scanned_count integer,accepted_count integer,unchanged_count integer,rejected_count integer,
  error_message text default null,refresh_seconds integer default 300,retry_seconds integer default 60) returns boolean
language plpgsql security definer set search_path='' as $$
declare job private.catalog_jobs%rowtype;
begin
  perform private.admin_assert(refresh_seconds between 30 and 86400 and retry_seconds between 1 and 86400,'INVALID_WORKER_CONFIG');
  perform 1 from private.catalog_sync_scope s join private.catalog_jobs j on j.scope_id=s.id
    where j.run_id=target_run_id for update of s;
  select * into job from private.catalog_jobs where run_id=target_run_id and status='RUNNING'
    and lease_until>clock_timestamp() for update;
  if not found then return false; end if;
  perform private.admin_assert(final_status<>'SUCCEEDED' or (target_client_id is not null and rejected_count=0),'INVALID_SUCCESS_RESULT');
  perform private.admin_assert(target_client_id is null or exists(select 1 from public.clientes c
    join private.catalog_sync_scope s on s.legacy_cliente_id=c.legacy_cliente_id and s.legacy_codigo_cliente=c.codigo
    where s.id=job.scope_id and c.id=target_client_id),'CLIENT_SCOPE_MISMATCH');
  perform private.admin_assert(public.finish_ivmet_sync_run(target_run_id,final_status,scanned_count,accepted_count,unchanged_count,rejected_count,error_message),'RUN_ALREADY_FINISHED');
  update private.catalog_jobs set
    status=case when requested_version>claimed_version then 'QUEUED' else final_status end,
    completed_version=case when final_status='SUCCEEDED' then claimed_version else completed_version end,
    completed_at=case when final_status='SUCCEEDED' then clock_timestamp() else completed_at end,
    next_attempt_at=case when requested_version>claimed_version then clock_timestamp()
      else clock_timestamp()+make_interval(secs=>case when final_status='SUCCEEDED' then refresh_seconds
        else least(3600,retry_seconds*power(2,least(attempts-1,6)))::integer end) end,
    attempts=case when final_status='SUCCEEDED' or requested_version>claimed_version then 0 else attempts end,
    lease_until=null where scope_id=job.scope_id;
  -- El motivo contractual no se sobrescribe con errores técnicos.
  update private.catalog_sync_scope set supabase_cliente_id=coalesce(target_client_id,supabase_cliente_id),
    estado=case when final_status='SUCCEEDED' and job.requested_version=job.claimed_version then 'ACTIVE' else estado end,
    activado_at=case when final_status='SUCCEEDED' then coalesce(activado_at,clock_timestamp()) else activado_at end
    where id=job.scope_id and estado in ('REQUESTED','ACTIVE');
  return true;
end; $$;

-- Mantener el contrato anterior en una función privada evita duplicar toda la
-- lógica comercial. Las migraciones ya aplicadas permanecen intactas.
alter function public.ivmet_admin_mutate(text,text,jsonb,uuid) set schema private;
revoke all on function private.ivmet_admin_mutate(text,text,jsonb,uuid) from public,anon,authenticated,service_role;
create function public.ivmet_admin_mutate(actor text,action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; saved private.admin_requests%rowtype; job private.catalog_jobs%rowtype;
  request_hash text:=encode(sha256(convert_to(action||(case when action in ('scope.request','scope.extend') then payload-'clientName' else payload end)::text,'UTF8')),'hex');
begin
  perform private.admin_assert(auth.role()='service_role' and actor like 'RIMMET:%' and length(actor) between 8 and 150,'ADMIN_REQUIRED');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object','INVALID_REQUEST');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r where r.request_id=ivmet_admin_mutate.request_id and r.action=ivmet_admin_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=request_hash,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;
  if action='scope.retry' then
    perform private.admin_assert(length(btrim(payload->>'reason')) between 1 and 1000,'REASON_REQUIRED');
    select j.* into job from private.catalog_jobs j join private.catalog_sync_scope s on s.id=j.scope_id
      where j.scope_id=(payload->>'id')::uuid and s.estado in ('REQUESTED','ACTIVE') for update of j;
    perform private.admin_assert(found,'SCOPE_NOT_EDITABLE');
    perform private.admin_assert(job.status in ('FAILED','PARTIAL') or (job.status='RUNNING' and job.lease_until<=clock_timestamp()),'SCOPE_NOT_RETRYABLE');
    update private.catalog_jobs set status='QUEUED',requested_version=requested_version+1,attempts=0,
      requested_at=clock_timestamp(),next_attempt_at=clock_timestamp() where scope_id=job.scope_id;
    result:=jsonb_build_object('id',job.scope_id);
    insert into public.auditoria(actor_externo,entidad,entidad_id,accion,despues)
      values(actor,'scope',job.scope_id::text,action,jsonb_build_object('reason',payload->>'reason','requestId',request_id));
    insert into private.admin_requests(request_id,action,actor,payload_hash,result) values(request_id,action,actor,request_hash,result);
    return result;
  end if;
  result:=private.ivmet_admin_mutate(actor,action,case when action in ('scope.request','scope.extend') then payload-'clientName' else payload end,request_id);
  if action in ('scope.request','scope.extend') then
    if nullif(btrim(payload->>'clientName'),'') is not null then
      update private.catalog_sync_scope set client_name=left(btrim(payload->>'clientName'),250) where id=(result->>'id')::uuid;
    end if;
    if action='scope.extend' then
      update private.catalog_jobs set requested_version=requested_version+1,requested_at=clock_timestamp(),
        next_attempt_at=clock_timestamp(),attempts=0,
        status=case when status='RUNNING' then status else 'QUEUED' end where scope_id=(result->>'id')::uuid;
    end if;
  end if;
  return result;
end; $$;

-- Proyección administrativa sin snapshots, SQL interno ni detalles de errores
-- que pudieran contener datos de conexión. Códigos de incidencia únicamente.
create function private.catalog_scope_status(target_scope uuid,include_details boolean default false) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(s)||jsonb_build_object('row_version',s.row_version::text,
    'syncStatus',case when s.estado not in ('REQUESTED','ACTIVE') then 'SUSPENDED'
      when j.status='RUNNING' and j.lease_until<=now() then 'RETRYING' else j.status end,
    'nextAttemptAt',j.next_attempt_at,'lastCompletedAt',j.completed_at,'attempts',j.attempts,
    'requestedVersion',j.requested_version::text,'completedVersion',j.completed_version::text,
    'lastRun',case when r.id is null then null else jsonb_build_object('id',r.id,'status',r.estado,
      'startedAt',r.started_at,'finishedAt',r.finished_at,'accepted',r.accepted_count,'unchanged',r.unchanged_count,'rejected',r.rejected_count) end,
    'issueCount',(select count(*) from private.sync_quarantine q where q.run_id=j.run_id),
    'issues',case when include_details then coalesce((select jsonb_agg(x) from (select q.entity_type,q.source_key,q.reason_code from private.sync_quarantine q
      where q.run_id=j.run_id order by q.created_at,q.id limit 50) x),'[]') else '[]'::jsonb end,
    'plants',coalesce((select jsonb_agg(p.legacy_codigo_planta order by p.legacy_codigo_planta) from private.catalog_sync_scope_plants p where p.scope_id=s.id and p.habilitada),'[]'),
    'equipmentCodes',case when include_details then coalesce((select jsonb_agg(e.legacy_cod_metrica order by e.legacy_cod_metrica) from private.catalog_sync_scope_equipments e where e.scope_id=s.id and e.habilitado),'[]') else '[]'::jsonb end,
    'equipmentCount',(select count(*) from private.catalog_sync_scope_equipments e where e.scope_id=s.id and e.habilitado))
  from private.catalog_sync_scope s join private.catalog_jobs j on j.scope_id=s.id
  left join private.sync_runs r on r.id=j.run_id where s.id=target_scope;
$$;
revoke all on function private.catalog_scope_status(uuid,boolean) from public,anon,authenticated,service_role;

alter function public.ivmet_admin_read(text,uuid,jsonb) set schema private;
revoke all on function private.ivmet_admin_read(text,uuid,jsonb) from public,anon,authenticated,service_role;
create function public.ivmet_admin_read(section text,client_id uuid default null,filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; page_number integer:=greatest(coalesce((filters->>'page')::integer,1),1);
  page_size integer:=least(greatest(coalesce((filters->>'pageSize')::integer,20),1),100);
  search_text text:='%'||coalesce(filters->>'search','')||'%';
begin
  perform private.admin_assert(auth.role()='service_role','ADMIN_REQUIRED');
  if section='clients' then
    with matching as (
      select c.id,coalesce(c.codigo,s.legacy_codigo_cliente) as codigo,coalesce(c.nombre,s.client_name) as nombre,
        c.razon_social,c.activo,c.synced_at,s.id as scope_id,
        case when s.id is not null then private.catalog_scope_status(s.id)-'equipmentCodes'-'issues'-'motivo' else null end as onboarding
      from public.clientes c full join private.catalog_sync_scope s on s.legacy_cliente_id=c.legacy_cliente_id
      where coalesce(c.codigo,s.legacy_codigo_cliente) ilike search_text or coalesce(c.nombre,s.client_name) ilike search_text or c.razon_social ilike search_text
    ), page_rows as (select * from matching order by codigo limit page_size offset (page_number-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,
      'items',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object(
        'plants',(select count(*) from public.plantas p where p.cliente_id=x.id and p.activo),
        'equipment',(select count(*) from public.equipos e where e.cliente_id=x.id and e.activo),
        'review',(select count(*) from public.equipos e where e.cliente_id=x.id and e.activo and e.estado_catalogo<>'READY'),
        'licenses',(select count(*) from public.licencias_usuario l join public.perfiles p on p.id=l.usuario_id where p.cliente_id=x.id and l.estado='ACTIVE')
      ) order by x.codigo) from page_rows x),'[]')) into result;
  elsif section in ('integration','onboarding') then
    with matching as (select s.id,s.solicitado_at from private.catalog_sync_scope s
      where (nullif(filters->>'legacyClientId','') is null or s.legacy_cliente_id=(filters->>'legacyClientId')::integer)
        and (nullif(filters->>'scopeId','') is null or s.id=(filters->>'scopeId')::uuid)
        and (s.legacy_codigo_cliente ilike search_text or s.client_name ilike search_text)),
    page_rows as (select * from matching order by solicitado_at desc,id limit page_size offset (page_number-1)*page_size)
    select jsonb_build_object('total',(select count(*) from matching),'page',page_number,'pageSize',page_size,
      'scopes',coalesce((select jsonb_agg(private.catalog_scope_status(p.id,nullif(filters->>'scopeId','') is not null) order by p.solicitado_at desc,p.id) from page_rows p),'[]'),
      'workers',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object('available',
        w.mode='daemon' and w.state in ('ONLINE','DEGRADED') and w.last_seen_at>now()-make_interval(secs=>greatest(90,w.poll_seconds*3)))) from private.worker_heartbeats w),'[]'),
      'runs',coalesce((select jsonb_agg(x) from (select id,direccion,worker_id,estado,scope_id,started_at,finished_at,accepted_count,rejected_count
        from private.sync_runs order by started_at desc limit 15) x),'[]'),
      'outbox',coalesce((select jsonb_object_agg(x.estado,x.n) from (select estado,count(*) as n from private.sync_outbox group by estado) x),'{}')) into result;
  else result:=private.ivmet_admin_read(section,client_id,filters);
  end if;
  return result;
end; $$;

revoke all on function public.ivmet_worker_contract(),public.report_ivmet_worker(text,uuid,text,text,uuid,integer),
  public.claim_ivmet_catalog_job(text,uuid,integer),public.renew_ivmet_catalog_job(uuid,integer),
  public.finish_ivmet_catalog_job(uuid,uuid,text,integer,integer,integer,integer,text,integer,integer),
  public.ivmet_admin_mutate(text,text,jsonb,uuid),public.ivmet_admin_read(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.ivmet_worker_contract(),public.report_ivmet_worker(text,uuid,text,text,uuid,integer),
  public.claim_ivmet_catalog_job(text,uuid,integer),public.renew_ivmet_catalog_job(uuid,integer),
  public.finish_ivmet_catalog_job(uuid,uuid,text,integer,integer,integer,integer,text,integer,integer),
  public.ivmet_admin_mutate(text,text,jsonb,uuid),public.ivmet_admin_read(text,uuid,jsonb) to service_role;
commit;

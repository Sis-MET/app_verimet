begin;

create or replace function public.ivmet_admin_mutate(actor text, action text, payload jsonb, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  request_hash text := encode(sha256(convert_to(action || payload::text,'UTF8')),'hex');
  saved private.admin_requests%rowtype;
  target_id uuid := nullif(payload->>'id','')::uuid;
  customer_id uuid := nullif(payload->>'clientId','')::uuid;
  result jsonb;
  before_row jsonb;
  contract public.contratos%rowtype;
  subscription public.suscripciones%rowtype;
  price public.precios_plan%rowtype;
  commercial_plan public.planes_comerciales%rowtype;
  profile public.perfiles%rowtype;
  invoice public.facturas%rowtype;
  equipment public.equipos%rowtype;
  base_count integer;
  assigned_count integer;
  amount numeric(19,2);
  start_date date;
  end_date date;
  invoice_id uuid;
  reference_data jsonb;
  plant_ids uuid[];
  reason text := nullif(btrim(payload->>'reason'),'');
  current_version bigint;
  row_id uuid;
begin
  perform private.admin_assert(auth.role()='service_role' and actor like 'RIMMET:%' and length(actor) between 8 and 150,'ADMIN_REQUIRED');
  perform private.admin_assert(request_id is not null and jsonb_typeof(payload)='object','INVALID_REQUEST');
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,1));
  select * into saved from private.admin_requests r where r.request_id=ivmet_admin_mutate.request_id and r.action=ivmet_admin_mutate.action;
  if found then
    perform private.admin_assert(saved.actor=actor and saved.payload_hash=request_hash,'IDEMPOTENCY_CONFLICT');
    return saved.result;
  end if;
  if customer_id is not null then
    perform private.admin_assert(exists(select 1 from public.clientes where id=customer_id and activo),'CLIENT_NOT_FOUND');
  end if;

  if action='plan.save' then
    if target_id is null then
      insert into public.planes_comerciales(codigo,nombre,descripcion,cuentas_incluidas,dias_gracia,activo)
      values(upper(btrim(payload->>'code')),btrim(payload->>'name'),payload->>'description',(payload->>'seats')::integer,(payload->>'graceDays')::integer,coalesce((payload->>'active')::boolean,true))
      returning id into target_id;
    else
      select to_jsonb(p),p.row_version into before_row,current_version from public.planes_comerciales p where p.id=target_id for update;
      perform private.admin_assert(current_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      update public.planes_comerciales set nombre=btrim(payload->>'name'),descripcion=payload->>'description',cuentas_incluidas=(payload->>'seats')::integer,dias_gracia=(payload->>'graceDays')::integer,activo=(payload->>'active')::boolean where id=target_id;
    end if;
    select to_jsonb(p) into result from public.planes_comerciales p where p.id=target_id;

  elsif action='price.create' then
    select * into commercial_plan from public.planes_comerciales where id=(payload->>'planId')::uuid and activo for update;
    perform private.admin_assert(found,'PLAN_NOT_FOUND');
    start_date:=(payload->>'startsOn')::date;
    perform private.admin_assert(not exists(select 1 from public.precios_plan p where p.plan_id=commercial_plan.id and p.periodicidad=payload->>'periodicity' and p.moneda=payload->>'currency' and p.activo and p.vigente_desde>=start_date),'PRICE_DATE_CONFLICT');
    update public.precios_plan set vigente_hasta=start_date-1 where plan_id=commercial_plan.id and periodicidad=payload->>'periodicity' and moneda=payload->>'currency' and activo and (vigente_hasta is null or vigente_hasta>=start_date);
    insert into public.precios_plan(plan_id,periodicidad,moneda,importe,vigente_desde)
    values(commercial_plan.id,payload->>'periodicity',payload->>'currency',(payload->>'amount')::numeric,start_date)
      returning private.stringify_ivmet_outbox_numbers('public.precios_plan',to_jsonb(precios_plan)),id into result,target_id;

  elsif action='contract.create' then
    perform private.admin_assert(customer_id is not null,'CLIENT_REQUIRED');
    perform pg_advisory_xact_lock(hashtextextended(customer_id::text,2));
    perform private.admin_assert(not exists(select 1 from public.contratos c where c.cliente_id=customer_id and c.estado in ('ACTIVE','SUSPENDED','DRAFT')),'CLIENT_HAS_CONTRACT');
    select * into price from public.precios_plan where id=(payload->>'priceId')::uuid and activo;
    perform private.admin_assert(found,'PRICE_NOT_FOUND');
    select * into commercial_plan from public.planes_comerciales where id=price.plan_id and activo;
    perform private.admin_assert(found,'PLAN_NOT_FOUND');
    start_date:=(payload->>'startsOn')::date;
    end_date:=(start_date+case when price.periodicidad='MONTHLY' then interval '1 month' else interval '1 year' end)::date;
    perform private.admin_assert(start_date>=price.vigente_desde and (price.vigente_hasta is null or start_date<=price.vigente_hasta),'PRICE_NOT_EFFECTIVE');
    perform private.admin_assert((payload->>'signedOn')::date<=current_date and (payload->>'endsOn')::date>=end_date-1,'CONTRACT_DATES_INVALID');
    insert into public.contratos(cliente_id,numero_contrato,fecha_firma,vigente_desde,vigente_hasta,estado,observaciones)
    values(customer_id,payload->>'number',(payload->>'signedOn')::date,start_date,(payload->>'endsOn')::date,'ACTIVE',payload->>'notes') returning * into contract;
    insert into public.suscripciones(contrato_id,plan_id,precio_plan_id,periodicidad,inicio_periodo,fin_periodo,proximo_cobro,estado,gracia_hasta)
    values(contract.id,price.plan_id,price.id,price.periodicidad,start_date::timestamp at time zone 'UTC',end_date::timestamp at time zone 'UTC',end_date,case when price.importe=0 then 'ACTIVE' else 'PENDING' end,(end_date::timestamp at time zone 'UTC')+make_interval(days=>commercial_plan.dias_gracia)) returning * into subscription;
    insert into public.facturas(suscripcion_id,numero_factura,periodo_desde,periodo_hasta,fecha_emision,fecha_vencimiento,moneda,subtotal,total,saldo,estado,referencia_externa)
    values(subscription.id,payload->>'invoiceNumber',start_date,end_date-1,current_date,greatest(current_date,start_date),price.moneda,price.importe,price.importe,price.importe,case when price.importe=0 then 'PAID' else 'PENDING' end,jsonb_build_object('kind','PERIOD','end',end_date)::text) returning id into invoice_id;
    insert into public.suscripcion_cupos(suscripcion_id,tipo,cantidad,factura_id,vigente_desde,vigente_hasta,estado)
    values(subscription.id,'PLAN_BASE',commercial_plan.cuentas_incluidas,invoice_id,subscription.inicio_periodo,subscription.fin_periodo,case when price.importe=0 then 'ACTIVE' else 'PENDING' end);
    target_id:=contract.id;
    result:=jsonb_build_object('id',contract.id,'subscriptionId',subscription.id,'invoiceId',invoice_id);

  elsif action in ('subscription.renew','seats.purchase') then
    select * into subscription from public.suscripciones where id=target_id for update;
    perform private.admin_assert(found,'SUBSCRIPTION_NOT_FOUND');
    select * into contract from public.contratos where id=subscription.contrato_id;
    perform private.admin_assert(contract.cliente_id=customer_id and contract.estado='ACTIVE' and subscription.estado not in ('CANCELLED','PENDING'),'SUBSCRIPTION_NOT_ACTIVE');
    perform private.admin_assert(subscription.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    select * into commercial_plan from public.planes_comerciales where id=subscription.plan_id;
    if action='subscription.renew' then
      start_date:=(subscription.fin_periodo at time zone 'UTC')::date;
      end_date:=(start_date+case when subscription.periodicidad='MONTHLY' then interval '1 month' else interval '1 year' end)::date;
      perform private.admin_assert(contract.vigente_hasta is null or end_date-1<=contract.vigente_hasta,'CONTRACT_EXTENSION_REQUIRED');
      select * into price from public.precios_plan where id=(payload->>'priceId')::uuid and activo and plan_id=subscription.plan_id and periodicidad=subscription.periodicidad and vigente_desde<=start_date and (vigente_hasta is null or vigente_hasta>=start_date);
      perform private.admin_assert(found,'PRICE_NOT_EFFECTIVE');
      perform private.admin_assert(not exists(select 1 from public.facturas f where f.suscripcion_id=target_id and f.periodo_desde=start_date and f.estado<>'VOID' and f.referencia_externa::jsonb->>'kind'='PERIOD'),'RENEWAL_ALREADY_EXISTS');
      select coalesce(sum(cantidad),0) into base_count from public.suscripcion_cupos where suscripcion_id=target_id and tipo='PLAN_BASE' and estado in ('ACTIVE','PENDING');
      select count(*) into assigned_count from public.licencias_usuario where suscripcion_id=target_id and estado='ACTIVE';
      perform private.admin_assert(base_count+coalesce((payload->>'seats')::integer,0)>=assigned_count,'RENEWAL_SEATS_INSUFFICIENT');
      amount:=price.importe+(payload->>'additionalAmount')::numeric;
    else
      start_date:=current_date;
      end_date:=(subscription.fin_periodo at time zone 'UTC')::date;
      perform private.admin_assert(end_date>start_date,'SUBSCRIPTION_EXPIRED');
      select * into price from public.precios_plan where id=subscription.precio_plan_id;
      amount:=(payload->>'amount')::numeric;
    end if;
    perform private.admin_assert(amount>=0 and (amount>0 or action='subscription.renew'),'PAYMENT_AMOUNT_INVALID');
    insert into public.facturas(suscripcion_id,numero_factura,periodo_desde,periodo_hasta,fecha_emision,fecha_vencimiento,moneda,subtotal,total,saldo,estado,referencia_externa)
    values(target_id,payload->>'invoiceNumber',start_date,end_date-1,current_date,current_date,price.moneda,amount,amount,amount,case when amount=0 then 'PAID' else 'PENDING' end,jsonb_build_object('kind',case when action='subscription.renew' then 'PERIOD' else 'SEATS' end,'end',end_date,'priceId',price.id)::text) returning id into invoice_id;
    if (payload->>'seats')::integer>0 then
      insert into public.suscripcion_cupos(suscripcion_id,tipo,cantidad,factura_id,vigente_desde,vigente_hasta,estado)
      values(target_id,'ADDITIONAL',(payload->>'seats')::integer,invoice_id,start_date::timestamp at time zone 'UTC',end_date::timestamp at time zone 'UTC',case when amount=0 then 'ACTIVE' else 'PENDING' end);
    end if;
    if amount=0 then
      update public.suscripciones set fin_periodo=end_date::timestamp at time zone 'UTC',
        estado=case when estado='SUSPENDED' then estado else 'ACTIVE' end,
        precio_plan_id=price.id,proximo_cobro=end_date,
        gracia_hasta=(end_date::timestamp at time zone 'UTC')+make_interval(days=>commercial_plan.dias_gracia) where id=target_id;
      update public.suscripcion_cupos set vigente_hasta=end_date::timestamp at time zone 'UTC' where suscripcion_id=target_id and tipo='PLAN_BASE' and estado='ACTIVE';
    end if;
    result:=jsonb_build_object('id',invoice_id);

  elsif action='payment.record' then
    select * into invoice from public.facturas where id=target_id for update;
    perform private.admin_assert(found and invoice.estado in ('PENDING','PARTIALLY_PAID','OVERDUE'),'INVOICE_NOT_PAYABLE');
    select * into subscription from public.suscripciones where id=invoice.suscripcion_id for update;
    select * into contract from public.contratos where id=subscription.contrato_id;
    perform private.admin_assert(contract.cliente_id=customer_id and contract.estado='ACTIVE' and subscription.estado<>'CANCELLED','SUBSCRIPTION_NOT_ACTIVE');
    perform private.admin_assert(invoice.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    amount:=(payload->>'amount')::numeric;
    perform private.admin_assert(amount>0 and amount<=invoice.saldo,'PAYMENT_AMOUNT_INVALID');
    perform private.admin_assert((payload->>'paidOn')::date<=current_date,'PAYMENT_DATE_INVALID');
    insert into public.pagos(factura_id,fecha_pago,importe,moneda,metodo,referencia,estado)
    values(target_id,(payload->>'paidOn')::date::timestamp at time zone 'UTC',amount,invoice.moneda,payload->>'method',payload->>'reference','CONFIRMED');
    update public.facturas set saldo=saldo-amount,estado=case when saldo=amount then 'PAID' else 'PARTIALLY_PAID' end where id=target_id returning * into invoice;
    if invoice.estado='PAID' then
      reference_data:=invoice.referencia_externa::jsonb;
      if reference_data->>'kind'='PERIOD' then
        select * into commercial_plan from public.planes_comerciales where id=subscription.plan_id;
        end_date:=(reference_data->>'end')::date;
        update public.suscripciones set fin_periodo=greatest(fin_periodo,end_date::timestamp at time zone 'UTC'),
          estado=case when estado='SUSPENDED' then estado else 'ACTIVE' end,
          precio_plan_id=coalesce((reference_data->>'priceId')::uuid,precio_plan_id),
          proximo_cobro=end_date,gracia_hasta=(end_date::timestamp at time zone 'UTC')+make_interval(days=>commercial_plan.dias_gracia)
          where id=subscription.id;
        update public.suscripcion_cupos set estado='ACTIVE',vigente_hasta=end_date::timestamp at time zone 'UTC' where suscripcion_id=subscription.id and tipo='PLAN_BASE' and estado in ('PENDING','ACTIVE');
      end if;
      update public.suscripcion_cupos set estado='ACTIVE' where factura_id=invoice.id and estado='PENDING';
    end if;
    result:=private.stringify_ivmet_outbox_numbers('public.facturas',to_jsonb(invoice));

  elsif action='invoice.void' then
    perform private.admin_assert(reason is not null,'REASON_REQUIRED');
    select * into invoice from public.facturas where id=target_id for update;
    perform private.admin_assert(found and invoice.saldo=invoice.total and invoice.estado in ('PENDING','OVERDUE'),'INVOICE_HAS_PAYMENTS');
    perform private.admin_assert(exists(select 1 from public.suscripciones s join public.contratos c on c.id=s.contrato_id where s.id=invoice.suscripcion_id and c.cliente_id=customer_id),'CLIENT_MISMATCH');
    perform private.admin_assert(invoice.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    update public.facturas set estado='VOID' where id=target_id returning to_jsonb(facturas) into result;
    update public.suscripcion_cupos set estado='REVOKED' where factura_id=target_id and estado='PENDING';
    select * into subscription from public.suscripciones where id=invoice.suscripcion_id for update;
    if subscription.estado='PENDING' then
      -- Anular la factura inicial cancela el alta aún impagada; se puede registrar un contrato corregido.
      update public.suscripciones set estado='CANCELLED',motivo_suspension=reason where id=subscription.id;
      update public.contratos set estado='CANCELLED' where id=subscription.contrato_id;
    end if;

  elsif action='subscription.state' then
    perform private.admin_assert(reason is not null,'REASON_REQUIRED');
    select * into subscription from public.suscripciones where id=target_id for update;
    select * into contract from public.contratos where id=subscription.contrato_id;
    perform private.admin_assert(contract.cliente_id=customer_id and subscription.estado<>'CANCELLED','SUBSCRIPTION_NOT_FOUND');
    perform private.admin_assert(subscription.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert(payload->>'state' in ('ACTIVE','SUSPENDED','CANCELLED','GRACE'),'INVALID_STATE');
    perform private.admin_assert(subscription.estado<>'PENDING' or payload->>'state'='CANCELLED','SUBSCRIPTION_NOT_PAID');
    if payload->>'state'='ACTIVE' then
      perform private.admin_assert(contract.estado='ACTIVE' and subscription.fin_periodo>now() and exists(select 1 from public.suscripcion_cupos where suscripcion_id=target_id and tipo='PLAN_BASE' and estado='ACTIVE'),'SUBSCRIPTION_NOT_PAID');
    elsif payload->>'state'='GRACE' then
      perform private.admin_assert(contract.estado='ACTIVE' and subscription.fin_periodo<=now() and subscription.gracia_hasta>now(),'GRACE_NOT_AVAILABLE');
      update public.suscripcion_cupos set vigente_hasta=subscription.gracia_hasta where suscripcion_id=target_id and estado='ACTIVE' and vigente_hasta=subscription.fin_periodo;
    end if;
    before_row:=to_jsonb(subscription);
    update public.suscripciones set estado=payload->>'state',motivo_suspension=reason where id=target_id returning to_jsonb(suscripciones) into result;
    if payload->>'state'='CANCELLED' then
      update public.licencias_usuario set estado='REVOKED',revocada_at=now(),motivo_revocacion=reason where suscripcion_id=target_id and estado='ACTIVE';
      update public.suscripcion_cupos set estado='REVOKED' where suscripcion_id=target_id and estado in ('ACTIVE','PENDING');
      update public.facturas set estado='VOID' where suscripcion_id=target_id and estado in ('PENDING','OVERDUE') and saldo=total;
      update public.contratos set estado='CANCELLED' where id=contract.id;
    end if;

  elsif action='contract.extend' then
    perform private.admin_assert(reason is not null,'REASON_REQUIRED');
    select * into contract from public.contratos where id=target_id and cliente_id=customer_id for update;
    perform private.admin_assert(found and contract.estado='ACTIVE','CONTRACT_NOT_FOUND');
    perform private.admin_assert(contract.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    perform private.admin_assert((payload->>'endsOn')::date>contract.vigente_hasta,'CONTRACT_DATES_INVALID');
    update public.contratos set vigente_hasta=(payload->>'endsOn')::date where id=target_id returning to_jsonb(contratos) into result;

  elsif action='seat.revoke' then
    perform private.admin_assert(reason is not null,'REASON_REQUIRED');
    select sc.suscripcion_id into row_id from public.suscripcion_cupos sc where sc.id=target_id;
    perform pg_advisory_xact_lock(hashtextextended(row_id::text,0));
    perform private.admin_assert(exists(select 1 from public.suscripcion_cupos sc join public.suscripciones s on s.id=sc.suscripcion_id join public.contratos c on c.id=s.contrato_id where sc.id=target_id and c.cliente_id=customer_id and sc.tipo='ADDITIONAL' and sc.estado='ACTIVE' and sc.row_version=(payload->>'version')::bigint),'SEAT_NOT_FOUND');
    select count(*) into assigned_count from public.licencias_usuario where suscripcion_id=row_id and estado='ACTIVE';
    select coalesce(sum(cantidad),0) into base_count from public.suscripcion_cupos where suscripcion_id=row_id and id<>target_id and estado='ACTIVE' and vigente_desde<=now() and (vigente_hasta is null or vigente_hasta>now());
    perform private.admin_assert(base_count>=assigned_count,'SEATS_IN_USE');
    update public.suscripcion_cupos set estado='REVOKED' where id=target_id returning to_jsonb(suscripcion_cupos) into result;

  elsif action='user.reserve' then
    perform private.admin_assert(customer_id is not null,'CLIENT_REQUIRED');
    plant_ids:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
    perform private.admin_assert(cardinality(plant_ids)>0 and (select count(*) from public.plantas p where p.id=any(plant_ids) and p.cliente_id=customer_id and p.activo)=cardinality(plant_ids),'PLANT_SCOPE_INVALID');
    perform private.admin_assert(payload->>'role' in ('cliente_operador','cliente_jefe_calidad'),'INVALID_ROLE');
    perform private.admin_assert(not exists(select 1 from public.perfiles where usuario_normalizado=lower(btrim(payload->>'username'))),'USERNAME_EXISTS');
    row_id:=extensions.gen_random_uuid();
    result:=jsonb_build_object('id',row_id,'email','ivmet.'||row_id::text||'@users.ivmet.invalid');

  elsif action='user.create' then
    select r.result into reference_data from private.admin_requests r where r.request_id=ivmet_admin_mutate.request_id and r.action='user.reserve' and r.actor=ivmet_admin_mutate.actor;
    perform private.admin_assert(reference_data is not null,'USER_RESERVATION_REQUIRED');
    target_id:=(reference_data->>'id')::uuid;
    perform private.admin_assert(exists(select 1 from auth.users u where u.id=target_id and u.email=reference_data->>'email'),'AUTH_ACCOUNT_REQUIRED');
    plant_ids:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
    perform private.admin_assert(cardinality(plant_ids)>0 and (select count(*) from public.plantas p where p.id=any(plant_ids) and p.cliente_id=customer_id and p.activo)=cardinality(plant_ids),'PLANT_SCOPE_INVALID');
    perform private.admin_assert(payload->>'role' in ('cliente_operador','cliente_jefe_calidad'),'INVALID_ROLE');
    insert into public.perfiles(id,usuario,usuario_normalizado,nombre,rol,cliente_id) values(target_id,btrim(payload->>'username'),lower(btrim(payload->>'username')),btrim(payload->>'name'),payload->>'role',customer_id);
    insert into private.login_aliases(usuario_normalizado,auth_user_id,auth_email_interno) values(lower(btrim(payload->>'username')),target_id,reference_data->>'email');
    insert into public.usuario_plantas(usuario_id,planta_id) select target_id,unnest(plant_ids);
    result:=jsonb_build_object('id',target_id);

  elsif action='user.reset.complete' then
    perform private.admin_assert(exists(select 1 from private.admin_requests r where r.request_id=ivmet_admin_mutate.request_id and r.action='user.reset' and r.actor=ivmet_admin_mutate.actor),'USER_RESERVATION_REQUIRED');
    result:=jsonb_build_object('id',target_id);
  elsif action in ('user.update','user.reset','license.assign','license.revoke') then
    select * into profile from public.perfiles where id=target_id and cliente_id=customer_id for update;
    perform private.admin_assert(found,'USER_NOT_FOUND');
    if action in ('user.update','user.reset') then
      perform private.admin_assert(profile.row_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      if action='user.update' then
        plant_ids:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
        perform private.admin_assert(cardinality(plant_ids)>0 and (select count(*) from public.plantas p where p.id=any(plant_ids) and p.cliente_id=customer_id and p.activo)=cardinality(plant_ids),'PLANT_SCOPE_INVALID');
        perform private.admin_assert(payload->>'role' in ('cliente_operador','cliente_jefe_calidad'),'INVALID_ROLE');
        update public.perfiles set nombre=btrim(payload->>'name'),rol=payload->>'role',activo=(payload->>'active')::boolean where id=target_id;
        update public.usuario_plantas set activa=false where usuario_id=target_id;
        insert into public.usuario_plantas(usuario_id,planta_id) select target_id,unnest(plant_ids) on conflict(usuario_id,planta_id) do update set activa=true;
        update private.login_aliases set activo=(payload->>'active')::boolean where auth_user_id=target_id;
        if not (payload->>'active')::boolean then
          perform private.admin_assert(reason is not null,'REASON_REQUIRED');
          update public.licencias_usuario set estado='REVOKED',revocada_at=now(),motivo_revocacion=reason where usuario_id=target_id and estado='ACTIVE';
        end if;
      else
        perform private.admin_assert(reason is not null,'REASON_REQUIRED');
        update public.perfiles set debe_cambiar_password=true where id=target_id;
      end if;
    elsif action='license.assign' then
      select * into subscription from public.suscripciones where id=(payload->>'subscriptionId')::uuid for update;
      perform private.admin_assert(profile.activo and exists(select 1 from public.contratos c where c.id=subscription.contrato_id and c.cliente_id=customer_id and c.estado='ACTIVE' and c.vigente_desde<=current_date and (c.vigente_hasta is null or c.vigente_hasta>=current_date)) and ((subscription.estado='ACTIVE' and subscription.inicio_periodo<=now() and subscription.fin_periodo>now()) or (subscription.estado='GRACE' and subscription.gracia_hasta>now())),'SUBSCRIPTION_NOT_ACTIVE');
      insert into public.licencias_usuario(suscripcion_id,usuario_id) values(subscription.id,target_id);
      insert into public.eventos_licencia(usuario_id,suscripcion_id,contrato_id,tipo_evento,actor_externo,estado_nuevo) values(target_id,subscription.id,subscription.contrato_id,'ASSIGNED',actor,jsonb_build_object('state','ACTIVE'));
    else
      perform private.admin_assert(reason is not null,'REASON_REQUIRED');
      update public.licencias_usuario set estado='REVOKED',revocada_at=now(),motivo_revocacion=reason where usuario_id=target_id and estado='ACTIVE';
      insert into public.eventos_licencia(usuario_id,tipo_evento,actor_externo,motivo) values(target_id,'REVOKED',actor,reason);
    end if;
    result:=jsonb_build_object('id',target_id);

  elsif action='area.save' then
    perform private.admin_assert(exists(select 1 from public.plantas where id=(payload->>'plantId')::uuid and cliente_id=customer_id and activo),'PLANT_SCOPE_INVALID');
    if target_id is null then
      insert into public.areas(cliente_id,planta_id,nombre,activa) values(customer_id,(payload->>'plantId')::uuid,btrim(payload->>'name'),coalesce((payload->>'active')::boolean,true)) returning id into target_id;
    else
      select a.row_version into current_version from public.areas a where id=target_id and cliente_id=customer_id and planta_id=(payload->>'plantId')::uuid for update;
      perform private.admin_assert(current_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      update public.areas set nombre=btrim(payload->>'name'),activa=(payload->>'active')::boolean where id=target_id;
    end if;
    result:=jsonb_build_object('id',target_id);

  elsif action='pattern.save' then
    plant_ids:=array(select value::uuid from jsonb_array_elements_text(payload->'plantIds'));
    perform private.admin_assert(cardinality(plant_ids)>0 and (select count(*) from public.plantas p where p.id=any(plant_ids) and p.cliente_id=customer_id and p.activo)=cardinality(plant_ids),'PLANT_SCOPE_INVALID');
    if target_id is null then
      insert into public.patrones(cliente_id,codigo,descripcion,tipo,clase,unidad,capacidad,activo) values(customer_id,payload->>'code',payload->>'description',payload->>'type',payload->>'class',payload->>'unit',nullif(payload->>'capacity','')::numeric,coalesce((payload->>'active')::boolean,true)) returning id into target_id;
    else
      select p.row_version into current_version from public.patrones p where p.id=target_id and p.cliente_id=customer_id for update;
      perform private.admin_assert(current_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      update public.patrones set descripcion=payload->>'description',tipo=payload->>'type',clase=payload->>'class',unidad=payload->>'unit',capacidad=nullif(payload->>'capacity','')::numeric,activo=(payload->>'active')::boolean where id=target_id;
    end if;
    delete from public.patron_plantas where patron_id=target_id and planta_id<>all(plant_ids);
    insert into public.patron_plantas(patron_id,planta_id) select target_id,unnest(plant_ids) on conflict do nothing;
    result:=jsonb_build_object('id',target_id);

  elsif action in ('certificate.create','certificate.annul') then
    if action='certificate.create' then
      perform private.admin_assert(exists(select 1 from public.patrones where id=(payload->>'patternId')::uuid and cliente_id=customer_id),'PATTERN_NOT_FOUND');
      insert into public.patron_certificados(patron_id,numero,laboratorio,calibrado_el,vence_el)
      values((payload->>'patternId')::uuid,payload->>'number',payload->>'lab',(payload->>'calibratedOn')::date,(payload->>'expiresOn')::date) returning id into target_id;
    else
      perform private.admin_assert(reason is not null,'REASON_REQUIRED');
      perform private.admin_assert(exists(select 1 from public.patron_certificados pc join public.patrones p on p.id=pc.patron_id where pc.id=target_id and p.cliente_id=customer_id and pc.estado='ACTIVE'),'CERTIFICATE_NOT_FOUND');
      update public.patron_certificados set estado='ANNULLED',row_version=row_version+1 where id=target_id;
    end if;
    result:=jsonb_build_object('id',target_id);

  elsif action='equipment.configure' then
    select * into equipment from public.equipos where id=target_id and cliente_id=customer_id for update;
    perform private.admin_assert(found,'EQUIPMENT_NOT_FOUND');
    select ei.row_version into current_version from public.equipos_ivmet ei where equipo_id=target_id for update;
    perform private.admin_assert(coalesce(current_version,0)=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
    if nullif(payload->>'areaId','') is not null then
      perform private.admin_assert(exists(select 1 from public.areas where id=(payload->>'areaId')::uuid and cliente_id=customer_id and planta_id=equipment.planta_id and activa),'AREA_SCOPE_INVALID');
    end if;
    if (payload->>'enabled')::boolean then
      perform private.admin_assert(equipment.activo and equipment.estado_catalogo='READY','EQUIPMENT_REQUIRES_REVIEW');
      perform private.admin_assert(exists(select 1 from public.plan_versiones pv join public.planes p on p.id=pv.plan_id where pv.id=(payload->>'planVersionId')::uuid and pv.estado='PUBLISHED' and p.activo and (p.cliente_id is null or p.cliente_id=customer_id)),'PUBLISHED_PLAN_REQUIRED');
    end if;
    if nullif(payload->>'planVersionId','') is not null then
      perform private.admin_assert(exists(select 1 from public.plan_versiones pv join public.planes p on p.id=pv.plan_id where pv.id=(payload->>'planVersionId')::uuid and pv.estado='PUBLISHED' and (p.cliente_id is null or p.cliente_id=customer_id)),'PUBLISHED_PLAN_REQUIRED');
      if not exists(select 1 from public.equipo_planes where equipo_id=target_id and vigente_hasta is null and plan_version_id=(payload->>'planVersionId')::uuid) then
        update public.equipo_planes set vigente_hasta=clock_timestamp() where equipo_id=target_id and vigente_hasta is null;
        insert into public.equipo_planes(equipo_id,plan_version_id,vigente_desde) values(target_id,(payload->>'planVersionId')::uuid,clock_timestamp());
      end if;
    end if;
    insert into public.equipos_ivmet(equipo_id,area_id,habilitado,estado_configuracion) values(target_id,nullif(payload->>'areaId','')::uuid,(payload->>'enabled')::boolean,case when (payload->>'enabled')::boolean then 'READY' else 'SUSPENDED' end)
    on conflict(equipo_id) do update set area_id=excluded.area_id,habilitado=excluded.habilitado,estado_configuracion=excluded.estado_configuracion;
    result:=jsonb_build_object('id',target_id);

  elsif action in ('scope.request','scope.extend') then
    perform private.admin_assert(reason is not null and (payload->>'paidConfirmed')::boolean,'PAID_CONFIRMATION_REQUIRED');
    perform pg_advisory_xact_lock((payload->>'legacyClientId')::bigint);
    perform private.admin_assert(jsonb_array_length(payload->'plantCodes')>0 and jsonb_array_length(payload->'equipmentCodes')>0,'SCOPE_EMPTY');
    perform private.admin_assert(not exists(select 1 from jsonb_array_elements_text(payload->'plantCodes') x where x.value !~ ('^'||(payload->>'clientCode')||'-[0-9]{2}$')) and not exists(select 1 from jsonb_array_elements_text(payload->'equipmentCodes') x where x.value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{3}$' or not (payload->'plantCodes') ? left(x.value,7)),'PLANT_SCOPE_INVALID');
    if action='scope.request' then
      perform private.admin_assert(not exists(select 1 from private.catalog_sync_scope where legacy_cliente_id=(payload->>'legacyClientId')::integer),'SCOPE_ALREADY_EXISTS');
      insert into private.catalog_sync_scope(legacy_cliente_id,legacy_codigo_cliente,solicitado_por,motivo) values((payload->>'legacyClientId')::integer,payload->>'clientCode',actor,reason) returning id into target_id;
    else
      select s.row_version,s.supabase_cliente_id into current_version,customer_id from private.catalog_sync_scope s where s.id=target_id and s.legacy_cliente_id=(payload->>'legacyClientId')::integer and s.legacy_codigo_cliente=payload->>'clientCode' and s.estado in ('REQUESTED','ACTIVE') for update;
      perform private.admin_assert(found,'SCOPE_NOT_EDITABLE');
      perform private.admin_assert(current_version=(payload->>'version')::bigint,'ROW_VERSION_CONFLICT');
      update private.catalog_sync_scope set motivo=reason where id=target_id;
    end if;
    insert into private.catalog_sync_scope_plants(scope_id,legacy_codigo_planta,requested_by) select target_id,value,actor from jsonb_array_elements_text(payload->'plantCodes') on conflict(scope_id,legacy_codigo_planta) do update set habilitada=true,requested_by=excluded.requested_by;
    insert into private.catalog_sync_scope_equipments(scope_id,legacy_cod_metrica,requested_by) select target_id,value,actor from jsonb_array_elements_text(payload->'equipmentCodes') on conflict(scope_id,legacy_cod_metrica) do update set habilitado=true,requested_by=excluded.requested_by;
    result:=jsonb_build_object('id',target_id);
  else
    raise exception using errcode='22023',message='UNKNOWN_ADMIN_ACTION';
  end if;

  -- Datos de autenticación y contraseñas no se incluyen en auditoría/outbox.
  insert into public.auditoria(actor_externo,cliente_id,entidad,entidad_id,accion,antes,despues)
  values(actor,customer_id,split_part(action,'.',1),coalesce(target_id::text,request_id::text),action,before_row,
    jsonb_build_object('requestId',request_id,'reason',reason,'result',case when action='user.reserve' then jsonb_build_object('reserved',true) else result end));
  insert into private.admin_requests(request_id,action,actor,payload_hash,result) values(request_id,action,actor,request_hash,result);
  return result;
end;
$$;
revoke all on function public.ivmet_admin_mutate(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.ivmet_admin_mutate(text,text,jsonb,uuid) to service_role;

create or replace function public.ivmet_admin_request_result(target_actor text,target_request_id uuid,target_action text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select r.result from private.admin_requests r where auth.role()='service_role' and r.actor=target_actor and r.request_id=target_request_id and r.action=target_action;
$$;
revoke all on function public.ivmet_admin_request_result(text,uuid,text) from public,anon,authenticated;
grant execute on function public.ivmet_admin_request_result(text,uuid,text) to service_role;

-- Control en tiempo de consulta, sin depender de un cron para vencer cupos.
-- Si caducan adicionales, se conservan las asignaciones más antiguas hasta el cupo vigente.
create or replace function private.user_has_active_license(target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select (target_user_id=auth.uid() or auth.role()='service_role') and exists (
    select 1 from public.perfiles p
    join public.clientes cl on cl.id=p.cliente_id and cl.activo
    join public.licencias_usuario l on l.usuario_id=p.id and l.estado='ACTIVE'
    join public.suscripciones s on s.id=l.suscripcion_id
    join public.contratos c on c.id=s.contrato_id and c.cliente_id=p.cliente_id
    where p.id=target_user_id and p.activo and not p.debe_cambiar_password
      and c.estado='ACTIVE' and c.vigente_desde<=current_date and (c.vigente_hasta is null or c.vigente_hasta>=current_date)
      and ((s.estado='ACTIVE' and s.inicio_periodo<=now() and s.fin_periodo>now()) or (s.estado='GRACE' and s.gracia_hasta>now()))
      and (select count(*) from public.licencias_usuario l2 where l2.suscripcion_id=s.id and l2.estado='ACTIVE' and (l2.asignada_at,l2.id)<=(l.asignada_at,l.id))
        <=(select coalesce(sum(sc.cantidad),0) from public.suscripcion_cupos sc where sc.suscripcion_id=s.id and sc.estado='ACTIVE' and sc.vigente_desde<=now() and (sc.vigente_hasta is null or sc.vigente_hasta>now()))
  );
$$;
commit;

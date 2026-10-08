import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('autoregistro, límites de plan y solicitudes en PostgreSQL desechable', async (t) => {
  const db = new PGlite();
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const admin = 'RIMMET:fixture';
  const identity = async (id = '', role = 'authenticated') => {
    await db.exec('reset role');
    await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role',$2,false)", [id, role]);
    if (role === 'authenticated') await db.exec('set role authenticated');
  };
  const service = () => identity('', 'service_role');
  const mutate = async (action, payload, request = uuid()) =>
    (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, action, payload, request]))[0].r;
  const adminRead = async (section, clientId = null, filters = {}) =>
    (await q('select public.ivmet_admin_read($1,$2,$3) r', [section, clientId, filters]))[0].r;
  const read = async (section, filters = {}) => (await q('select public.ivmet_mobile_read($1,$2) r', [section, filters]))[0].r;
  const customer = async (action, payload, request = uuid()) =>
    (await q('select public.ivmet_customer_mutate($1,$2,$3) r', [action, payload, request]))[0].r;
  const setup = async (section, filters = {}) => (await q('select public.ivmet_customer_read($1,$2) r', [section, filters]))[0].r;
  const team = async (actor, action, payload, request = uuid()) =>
    (await q('select public.ivmet_team_account($1,$2,$3,$4) r', [actor, action, payload, request]))[0].r;
  const configure = async (equipmentId, configuration, request = uuid()) =>
    (await q('select public.ivmet_customer_configure_checks($1,$2,$3) r', [equipmentId, configuration, request]))[0].r;
  const saveDraft = async (equipmentId, planId, content, request = uuid(), expected = 0) =>
    (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [request, equipmentId, planId, expected, content, uuid()]))[0].r;
  // Un alta completa como la hace `ivmet-signup`: la cuenta Auth existe antes.
  const signup = async (email, extra = {}) => {
    await service();
    const user = uuid();
    await q('insert into auth.users(id,email) values($1,$2)', [user, email]);
    const result = (await q('select public.ivmet_signup_complete($1,$2) r', [user, {
      email, company: 'Acme Alimentos', name: 'Ana Pérez', plantName: 'Planta Norte', phone: '+591 70000000',
      city: 'Santa Cruz', country: 'Bolivia', acceptTerms: true, termsVersion: 'ivmet-terms-v1', ...extra,
    }]))[0].r;
    return { user, ...result };
  };
  const registration = (plantId, code) => ({
    plantId, areaId: '', areaName: 'Despacho',
    data: { cod_interno: code, marca: 'Marca', modelo: 'M', serie: '', ubicacion: '', tipo: 'PLATFORM', clase: 'III', unidad: 'kg' },
    ranges: [{ capacity: '60', division: '0.01', interval: '0.01' }],
  });
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema extensions; create table auth.users(id uuid primary key,email text);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
      create function extensions.gen_random_uuid() returns uuid language sql as $$select gen_random_uuid()$$;
      set request.jwt.claim.role='service_role';`);
    const directory = new URL('../supabase/migrations/', import.meta.url);
    for (const name of (await readdir(directory)).filter(n => n.endsWith('.sql')).sort()) {
      await db.exec((await readFile(new URL(name, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', ''));
    }
    await q('select public.ivmet_bootstrap_admin($1,$2)', [admin, 'Fixture aislado']);
    const plans = Object.fromEntries((await adminRead('plans')).map(p => [p.nombre, p]));

    let owner, client, plant;
    await t.test('una empresa se registra con su correo y queda en el plan gratuito', async () => {
      await service();
      const status = (await q('select public.ivmet_signup_status($1) r', ['  Ana@Acme.example ']))[0].r;
      assert.deepEqual(status, { registered: false, authUserId: null });
      await assert.rejects(q('select public.ivmet_signup_status($1)', ['ivmet.x@users.ivmet.invalid']), /INVALID_EMAIL/);

      const created = await signup('ana@acme.example');
      ({ user: owner, clientId: client, plantId: plant } = created);
      assert.equal(created.replayed, false);
      assert.match(created.code, /^IV[0-9]{6}$/);
      const replay = (await q('select public.ivmet_signup_complete($1,$2) r', [owner, { email: 'ana@acme.example' }]))[0].r;
      assert.deepEqual(replay, { clientId: client, userId: owner, replayed: true });
      assert.equal((await q('select public.ivmet_signup_status($1) r', ['ana@acme.example']))[0].r.registered, true);
      assert.equal((await q('select public.ivmet_password_reset_target($1) r', ['ANA@acme.example']))[0].r, owner);

      const [row] = await q('select origen,legacy_cliente_id,nombre from public.clientes where id=$1', [client]);
      assert.deepEqual(row, { origen: 'AUTOREGISTRO', legacy_cliente_id: null, nombre: 'Acme Alimentos' });
      const [alias] = await q('select auth_email_interno from private.login_aliases where usuario_normalizado=$1', ['ana@acme.example']);
      assert.equal(alias.auth_email_interno, 'ana@acme.example');

      await identity(owner);
      const access = (await q('select public.ivmet_access_status() r'))[0].r;
      assert.equal(access.allowed, true);
      assert.equal(access.planName, 'Gratuito');
      const bootstrap = await read('bootstrap');
      assert.equal(bootstrap.plants.length, 1);
      assert.equal(bootstrap.plan.name, 'Gratuito');
      assert.equal(bootstrap.plan.selfService, true);
      assert.equal(bootstrap.plan.periodEndsAt, null, 'el gratuito no vence');
      assert.deepEqual(bootstrap.plan.limits, { plants: 1, equipment: 5, monthlyVerifications: 20, patterns: 3 });
      assert.deepEqual(bootstrap.plan.features, { fullReport: false, customSchedules: false });
      assert.equal(bootstrap.plan.seatsAvailable, 2);
      assert.equal(bootstrap.plan.usage.users, 1);
      assert.equal(bootstrap.plan.offers, undefined, 'los planes ofrecidos solo viajan en la sección plan');
      assert.equal(bootstrap.plan.catalog.selfService, true);
      const detail = await read('plan');
      assert.deepEqual(detail.offers.map(p => p.name), ['Gratuito', 'Profesional', 'Empresa']);
      assert.equal(detail.contactEmail, 'ana@acme.example');
    });

    await t.test('rechaza altas incompletas, sin términos o con un correo ya usado', async () => {
      await assert.rejects(signup('ana@acme.example'), /duplicate key|EMAIL_ALREADY_REGISTERED/);
      await assert.rejects(signup('sin-terminos@acme.example', { acceptTerms: false }), /TERMS_REQUIRED/);
      await assert.rejects(signup('corta@acme.example', { company: 'A' }), /INVALID_SIGNUP/);
      await service();
      const stranger = uuid();
      await q('insert into auth.users(id,email) values($1,$2)', [stranger, 'otro@acme.example']);
      await assert.rejects(q('select public.ivmet_signup_complete($1,$2)', [stranger, {
        email: 'distinto@acme.example', company: 'Otra', name: 'Otro', acceptTerms: true, termsVersion: 'ivmet-terms-v1',
      }]), /INVALID_SIGNUP/);
      await identity(owner);
      await assert.rejects(q('select public.ivmet_signup_complete($1,$2)', [owner, {}]), /permission denied/);
    });

    await t.test('nada de la empresa autoregistrada viaja al espejo SQL Server', async () => {
      await service();
      const open = await q(`select aggregate_type from private.sync_outbox o
        where not o.privacy_blocked and private.ivmet_export_allowed(o.aggregate_type)
          and private.outbox_client(o.aggregate_type,o.payload)=$1`, [client]);
      assert.deepEqual(open, []);
      const blocked = await q(`select distinct aggregate_type from private.sync_outbox o
        where o.privacy_blocked and private.outbox_client(o.aggregate_type,o.payload)=$1 order by 1`, [client]);
      assert.deepEqual(blocked.map(r => r.aggregate_type), ['public.clientes', 'public.contratos', 'public.eventos_licencia',
        'public.licencias_usuario', 'public.perfiles', 'public.plantas', 'public.suscripcion_cupos', 'public.suscripciones',
        'public.usuario_plantas']);
    });

    let operator;
    await t.test('el jefe crea usuarios dentro de los cupos y los gestiona', async () => {
      await service();
      const payload = { username: 'Operador.Uno', name: 'Operador Uno', role: 'cliente_operador', plantIds: [plant] };
      await assert.rejects(team(owner, 'reserve', { ...payload, username: 'op@acme' }), /INVALID_USERNAME/);
      const request = uuid();
      const reserved = await team(owner, 'reserve', payload, request);
      assert.match(reserved.email, /^ivmet\..+@users\.ivmet\.invalid$/);
      assert.deepEqual(await team(owner, 'reserve', payload, request), reserved, 'reintentar recupera la reserva');
      await assert.rejects(team(owner, 'create', payload, request), /AUTH_ACCOUNT_REQUIRED/);
      await q('insert into auth.users(id,email) values($1,$2)', [reserved.id, reserved.email]);
      operator = (await team(owner, 'create', payload, request)).id;
      assert.equal(operator, reserved.id);
      const [profile] = await q('select usuario,rol,debe_cambiar_password from public.perfiles where id=$1', [operator]);
      assert.deepEqual(profile, { usuario: 'operador.uno', rol: 'cliente_operador', debe_cambiar_password: true });
      await assert.rejects(team(owner, 'reserve', { ...payload, username: 'operador.dos' }), /PLAN_LIMIT_USERS/);
      await assert.rejects(team(operator, 'reserve', { ...payload, username: 'operador.dos' }), /MOBILE_ACCESS_DENIED|QUALITY_MANAGER_REQUIRED/);
      await assert.rejects(team(owner, 'reset', { userId: owner }), /SELF_CHANGE_NOT_ALLOWED/);

      await identity(owner);
      const members = await setup('members');
      assert.equal(members.seats, 2);
      assert.equal(members.used, 2);
      const row = members.items.find(m => m.id === operator);
      assert.deepEqual(row.plantIds, [plant]);
      assert.equal(row.licensed, true);
      assert.equal(members.items.find(m => m.id === owner).owner, true);
      await assert.rejects(customer('member.update', { id: owner, version: members.items.find(m => m.id === owner).version,
        name: 'Ana', role: 'cliente_operador', plantIds: [plant], active: true }), /SELF_CHANGE_NOT_ALLOWED/);
      await assert.rejects(customer('member.update', { id: operator, version: row.version, name: 'Operador Uno',
        role: 'cliente_operador', plantIds: [plant], active: false }), /REASON_REQUIRED/);
      const off = await customer('member.update', { id: operator, version: row.version, name: 'Operador Uno',
        role: 'cliente_operador', plantIds: [plant], active: false, reason: 'Dejó la empresa' });
      assert.equal((await setup('members')).used, 1, 'desactivar libera el cupo');
      await service();
      assert.equal((await q('select activo from private.login_aliases where auth_user_id=$1', [operator]))[0].activo, false);
      await identity(owner);
      await customer('member.update', { id: operator, version: off.version, name: 'Operador Uno',
        role: 'cliente_operador', plantIds: [plant], active: true });
      assert.equal((await setup('members')).used, 2);
      await service();
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [operator]);
      assert.deepEqual(await team(owner, 'reset', { userId: operator }), { id: operator });
      assert.equal((await q('select debe_cambiar_password from public.perfiles where id=$1', [operator]))[0].debe_cambiar_password, true);
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [operator]);
      assert.equal((await q('select public.ivmet_password_reset_target($1) r', ['operador.uno']))[0].r, null,
        'una cuenta con correo interno no se recupera por correo');
      await identity(operator);
      await assert.rejects(customer('plant.save', { name: 'Otra', active: true }), /QUALITY_MANAGER_REQUIRED/);
      await assert.rejects(setup('members'), /QUALITY_MANAGER_REQUIRED/);
    });

    let equipment = [];
    await t.test('balanzas, plantas y patrones se detienen en el límite del plan', async () => {
      await identity(owner);
      for (let i = 1; i <= 5; i++) equipment.push((await customer('equipment.register', registration(plant, `BAL-${i}`))).id);
      const sixth = uuid();
      await assert.rejects(customer('equipment.register', registration(plant, 'BAL-6'), sixth), /PLAN_LIMIT_EQUIPMENT/);
      // El reintento de un alta confirmada devuelve su recibo aunque el plan esté lleno.
      const done = uuid();
      await customer('equipment.retire', { id: equipment[4], version: '1', reason: 'Prueba' });
      const fifth = await customer('equipment.register', registration(plant, 'BAL-5B'), done);
      assert.deepEqual(await customer('equipment.register', registration(plant, 'BAL-5B'), done), fifth);
      equipment[4] = fifth.id;
      assert.equal((await read('bootstrap')).plan.usage.equipment, 5);

      await assert.rejects(customer('plant.save', { name: 'Planta Sur', city: '', address: '', active: true }), /PLAN_LIMIT_PLANTS/);
      const listed = (await setup('plants')).items;
      assert.deepEqual(listed.map(p => [p.name, p.city, p.version, p.equipmentCount]), [['Planta Norte', 'Santa Cruz', '1', 5]]);
      const renamed = await customer('plant.save', { id: plant, version: '1', name: 'Planta Norte 2', city: 'Santa Cruz', address: '', active: true });
      assert.equal(renamed.version, '2');
      await assert.rejects(customer('plant.save', { id: plant, version: '2', name: 'Planta Norte 2', active: false }), /PLANT_HAS_EQUIPMENT/);

      const pattern = n => ({ code: `P-${n}`, description: 'Pesa', type: 'pesas', class: '', unit: 'kg', capacity: '', active: true, plantIds: [plant] });
      for (let i = 1; i <= 3; i++) await customer('pattern.save', pattern(i));
      await assert.rejects(customer('pattern.save', pattern(4)), /PLAN_LIMIT_PATTERNS/);
    });

    let plan;
    await t.test('el plan gratuito usa periodicidades predefinidas y limita las capturas del mes', async () => {
      await identity(owner);
      const today = (await q("select to_char(current_date,'YYYY-MM-DD') d"))[0].d;
      const monthly = { mode: 'fixed', unit: 'month', every: 1, warningDays: 5, startsOn: today, monthMode: 'day', monthDay: 1 };
      await assert.rejects(configure(equipment[0], { tests: [{ type: 'linearity', tolerance: '0.5',
        schedule: { mode: 'rolling', unit: 'day', every: 10, warningDays: 2 } }] }), /PLAN_FEATURE_CUSTOM_SCHEDULES/);
      await assert.rejects(configure(equipment[0], { tests: [{ type: 'linearity', tolerance: '0.5',
        schedule: { ...monthly, every: 4 } }] }), /PLAN_FEATURE_CUSTOM_SCHEDULES/);
      await assert.rejects(configure(equipment[0], { tests: [{ type: 'linearity', frequencyDays: '30', tolerance: '0.5' }] }),
        /PLAN_FEATURE_CUSTOM_SCHEDULES/);
      await configure(equipment[0], { tests: [{ type: 'linearity', tolerance: '0.5', schedule: monthly }] });
      await identity(operator);
      await assert.rejects(configure(equipment[0], { tests: [] }), /QUALITY_MANAGER_REQUIRED/);

      await service();
      await q(`update public.planes_comerciales set caracteristicas=jsonb_set(caracteristicas,'{limits,monthlyVerifications}','2')
        where id=$1`, [plans.Gratuito.id]);
      await identity(owner);
      plan = (await read('equipment', { equipmentId: equipment[0] })).plan;
      const content = { tests: [{ id: plan.tests[0].id, omitted: false, reason: '', readings: [] }], certificates: [],
        temperature: '', humidity: '', observations: '' };
      const first = await saveDraft(equipment[0], plan.id, content);
      await saveDraft(equipment[0], plan.id, content);
      const usage = (await read('bootstrap')).plan.usage;
      assert.equal(usage.openDrafts, 2);
      await assert.rejects(saveDraft(equipment[0], plan.id, content), /PLAN_LIMIT_VERIFICATIONS/);
      // Seguir guardando un borrador ya empezado nunca se bloquea.
      const again = await saveDraft(equipment[0], plan.id, { ...content, observations: 'Sigue' }, first.requestId, Number(first.version));
      assert.equal(again.id, first.id);
    });

    let request;
    await t.test('el jefe pide un plan superior y RimMET lo atiende', async () => {
      await identity(operator);
      await assert.rejects(customer('upgrade.request', { reason: 'EQUIPMENT', planId: plans.Profesional.id, message: '', phone: '' }),
        /QUALITY_MANAGER_REQUIRED/);
      await identity(owner);
      await assert.rejects(customer('upgrade.request', { reason: 'EQUIPMENT', planId: plans.Gratuito.id, message: '', phone: '' }),
        /PLAN_NOT_AVAILABLE/);
      await assert.rejects(customer('upgrade.request', { reason: 'OTRO', planId: '', message: '', phone: '' }), /INVALID_UPGRADE_REQUEST/);
      request = await customer('upgrade.request', { reason: 'EQUIPMENT', planId: plans.Profesional.id,
        message: 'Necesitamos 20 balanzas más', phone: '+591 7111111' });
      await assert.rejects(customer('upgrade.request', { reason: 'GENERAL', planId: '', message: '', phone: '' }), /UPGRADE_REQUEST_OPEN/);
      const open = (await read('plan')).upgradeRequest;
      assert.equal(open.state, 'PENDING');
      assert.equal(open.requestedPlan.name, 'Profesional');
      assert.equal(open.contactEmail, 'ana@acme.example');
      await customer('upgrade.cancel', { id: request.id, version: request.version });
      assert.equal((await read('plan')).upgradeRequest, null);
      request = await customer('upgrade.request', { reason: 'EQUIPMENT', planId: plans.Profesional.id, message: 'De nuevo', phone: '' });

      await service();
      const overview = await adminRead('overview');
      assert.equal(overview.selfServiceClients, 1);
      assert.equal(overview.upgradeRequests, 1);
      const inbox = await adminRead('upgrade-requests', null, { state: 'OPEN' });
      assert.equal(inbox.total, 1);
      assert.equal(inbox.items[0].client.origin, 'AUTOREGISTRO');
      assert.equal(inbox.items[0].reason, 'EQUIPMENT');
      const directory = await adminRead('clients', null, { search: 'Acme' });
      assert.equal(directory.items[0].origin, 'AUTOREGISTRO');
      assert.equal(directory.items[0].plan.name, 'Gratuito');
      assert.equal(directory.items[0].openUpgradeRequest, true);
      const contacted = await mutate('upgrade.attend', { id: request.id, version: inbox.items[0].version, state: 'CONTACTED', note: 'Llamada hecha' });
      assert.equal(contacted.state, 'CONTACTED');
      await assert.rejects(mutate('upgrade.attend', { id: request.id, version: contacted.version, state: 'CLOSED', result: '' }), /INVALID_UPGRADE_STATE/);
    });

    await t.test('RimMET cambia el plan y la empresa pasa a sus nuevos límites', async () => {
      await service();
      const detail = await adminRead('client', client);
      assert.equal(detail.origin, 'AUTOREGISTRO');
      assert.equal(detail.selfService.email, 'ana@acme.example');
      assert.equal(detail.plan.name, 'Gratuito');
      assert.equal(detail.usage.equipment, 5);
      const subscription = detail.subscriptions[0];
      const base = { clientId: client, id: subscription.id, version: String(subscription.row_version), planId: plans.Profesional.id, reason: 'Contrato firmado' };
      await assert.rejects(mutate('subscription.change-plan', { ...base, reason: '' }), /REASON_REQUIRED/);
      await assert.rejects(mutate('subscription.change-plan', base), /PERIOD_END_REQUIRED/);
      await assert.rejects(mutate('subscription.change-plan', { ...base, planId: plans.Gratuito.id }), /PLAN_UNCHANGED/);
      const endsOn = (await q("select (current_date+30)::text d"))[0].d;
      const changed = await mutate('subscription.change-plan', { ...base, endsOn });
      assert.equal(changed.planId, plans.Profesional.id);
      const after = await adminRead('client', client);
      assert.equal(after.plan.name, 'Profesional');
      assert.equal(after.plan.seatsAvailable, 10);
      assert.ok(after.plan.periodEndsAt, 'un plan de pago tiene fin de período');
      assert.equal(after.upgradeRequests[0].state, 'CLOSED');
      assert.equal(after.upgradeRequests[0].result, 'UPGRADED');

      await identity(owner);
      const bootstrap = await read('bootstrap');
      assert.equal(bootstrap.plan.name, 'Profesional');
      assert.equal(bootstrap.plan.features.fullReport, true);
      assert.equal((await customer('plant.save', { name: 'Planta Sur', city: '', address: '', active: true })).version, '1');
      await customer('equipment.register', registration(plant, 'BAL-6'));
      const today = (await q("select to_char(current_date,'YYYY-MM-DD') d"))[0].d;
      await configure(equipment[1], { tests: [{ type: 'linearity', tolerance: '0.5',
        schedule: { mode: 'rolling', unit: 'day', every: 10, warningDays: 2 } }] });
      assert.ok(today);
      const refreshed = (await read('bootstrap')).plants.map(p => p.name).sort();
      assert.deepEqual(refreshed, ['Planta Norte 2', 'Planta Sur']);

      // Volver a uno con menos cupos que los usuarios activos no deja a nadie fuera.
      await service();
      const current = (await adminRead('client', client)).subscriptions[0];
      const fewer = await mutate('plan.save', { name: 'Unipersonal', seats: 1, graceDays: 0, active: true });
      await assert.rejects(mutate('subscription.change-plan', { clientId: client, id: current.id, version: String(current.row_version),
        planId: fewer.id, reason: 'Prueba', endsOn }), /SEATS_IN_USE/);
    });

    await t.test('RimMET define las condiciones de cada plan', async () => {
      await service();
      await assert.rejects(mutate('plan.save', { name: 'Malo', seats: 3, graceDays: 0, terms: { limits: { plants: 0 } } }), /INVALID_PLAN_TERMS/);
      await assert.rejects(mutate('plan.save', { name: 'Malo', seats: 3, graceDays: 0, terms: { features: { fullReport: 'si' } } }), /INVALID_PLAN_TERMS/);
      await assert.rejects(mutate('plan.save', { name: 'Malo', seats: 3, graceDays: 0, terms: { otra: 1, limits: { trucks: 1 } } }), /INVALID_PLAN_TERMS/);
      await assert.rejects(mutate('plan.save', { name: 'Otro gratuito', seats: 2, graceDays: 0, terms: { catalog: { selfService: true } } }),
        /SELF_SERVICE_PLAN_EXISTS/);
      const created = await mutate('plan.save', { name: 'Medida', description: 'A medida', seats: 4, graceDays: 5,
        terms: { limits: { equipment: 12 }, features: { fullReport: true } } });
      assert.match(created.codigo, /^PLAN-[0-9]{6,}$/);
      const edited = await mutate('plan.save', { id: created.id, version: String(created.row_version), name: 'Medida 2', seats: 4, graceDays: 5 });
      assert.deepEqual(edited.caracteristicas, { limits: { equipment: 12 }, features: { fullReport: true } }, 'sin terms se conservan');
      const listed = (await adminRead('plans')).find(p => p.id === created.id);
      assert.deepEqual(listed.terms.limits, { plants: null, equipment: 12, monthlyVerifications: null, patterns: null });
      assert.equal(listed.terms.features.customSchedules, true);
    });

    await t.test('las empresas de DataMET siguen sin límites ni gestión propia', async () => {
      await service();
      const legacy = uuid(), legacyPlant = uuid();
      await q("insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,77,'0077','Legado',repeat('a',64))", [legacy]);
      await q("insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values($1,$2,'0077-01',repeat('a',64))", [legacyPlant, legacy]);
      await assert.rejects(q("insert into public.clientes(codigo,nombre,source_hash,origen) values('X1','Sin legado',repeat('a',64),'DATAMET')"),
        /clientes_origen_ck/);
      const legacyPlan = await mutate('plan.save', { name: 'Legado', seats: 5, graceDays: 0 });
      const today = (await q('select current_date::text d'))[0].d;
      const price = await mutate('price.create', { planId: legacyPlan.id, periodicity: 'MONTHLY', currency: 'BOB', amount: '0', startsOn: today });
      const endsOn = (await q("select (current_date+interval '2 years')::date::text d"))[0].d;
      await mutate('contract.create', { clientId: legacy, priceId: price.id, number: 'LEG-C', invoiceNumber: 'LEG-F', signedOn: today, startsOn: today, endsOn });
      const subscription = (await q('select s.id from public.suscripciones s join public.contratos c on c.id=s.contrato_id where c.cliente_id=$1', [legacy]))[0].id;
      const request = uuid(), payload = { clientId: legacy, username: 'jefe.legado', name: 'Jefe', role: 'cliente_jefe_calidad', plantIds: [legacyPlant] };
      const u = await mutate('user.reserve', payload, request);
      await q('insert into auth.users(id,email) values($1,$2)', [u.id, u.email]);
      await mutate('user.create', payload, request);
      await mutate('license.assign', { id: u.id, clientId: legacy, subscriptionId: subscription });
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [u.id]);
      await assert.rejects(team(u.id, 'reserve', { username: 'nuevo', name: 'Nuevo', role: 'cliente_operador', plantIds: [legacyPlant] }),
        /SELF_SERVICE_REQUIRED/);
      await identity(u.id);
      const bootstrap = await read('bootstrap');
      assert.equal(bootstrap.plan.selfService, false);
      assert.deepEqual(bootstrap.plan.limits, { plants: null, equipment: null, monthlyVerifications: null, patterns: null });
      for (let i = 1; i <= 6; i++) await customer('equipment.register', registration(legacyPlant, `LEG-${i}`));
      await assert.rejects(customer('plant.save', { name: 'Nueva', active: true }), /SELF_SERVICE_REQUIRED/);
      await assert.rejects(setup('members'), /SELF_SERVICE_REQUIRED/);
      // Una empresa de DataMET también puede pedir asesoría, pero necesita un teléfono.
      await assert.rejects(customer('upgrade.request', { reason: 'GENERAL', planId: '', message: '', phone: '' }), /CONTACT_REQUIRED/);
      assert.ok((await customer('upgrade.request', { reason: 'GENERAL', planId: '', message: 'Hola', phone: '7000' })).id);
      await service();
      const clients = await adminRead('clients', null, { search: 'Legado' });
      assert.equal(clients.items[0].origin, 'DATAMET');
    });
  } finally {
    await db.close();
  }
});

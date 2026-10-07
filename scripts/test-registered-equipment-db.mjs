import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('balanzas registradas por la empresa en PostgreSQL desechable', async (t) => {
  const db = new PGlite();
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const admin = 'RIMMET:fixture';
  const mutate = async (action, payload) => (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, action, payload, uuid()]))[0].r;
  const read = async (section, filters = {}) => (await q('select public.ivmet_mobile_read($1,$2) r', [section, filters]))[0].r;
  const customer = async (action, payload, request = uuid()) => (await q('select public.ivmet_customer_mutate($1,$2,$3) r', [action, payload, request]))[0].r;
  const setup = async (section, filters = {}) => (await q('select public.ivmet_customer_read($1,$2) r', [section, filters]))[0].r;
  const configureChecks = async (equipmentId, configuration) =>
    (await q('select public.ivmet_customer_configure_checks($1,$2,$3) r', [equipmentId, configuration, uuid()]))[0].r;
  const identity = async (id = '', role = 'authenticated') => {
    await db.exec('reset role');
    await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role',$2,false)", [id, role]);
    if (role === 'authenticated') await db.exec('set role authenticated');
  };
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
    const client = uuid(), plant = uuid(), hiddenPlant = uuid(), catalogEquipment = uuid(), hiddenCatalog = uuid();
    await q("insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,1,'0001','Cliente',repeat('a',64))", [client]);
    await q(`insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values
      ($1,$2,'0001-01',repeat('a',64)),($3,$2,'0001-02',repeat('b',64))`, [plant, client, hiddenPlant]);
    await q(`insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,cod_interno,marca,serie,source_hash) values
      ($1,$2,$3,1,'0001-01-001','CAT-01','Catálogo','S-CAT',repeat('a',64)),
      ($4,$2,$3,2,'0001-01-002','OCULTA-01','Oculta','S-OCULTA',repeat('b',64))`, [catalogEquipment, client, plant, hiddenCatalog]);
    await q(`insert into public.equipo_rangos(equipo_id,numero_rango,unidad,capacidad_max,division_escala,source_hash)
      values($1,1,'kg',100,0.1,repeat('a',64))`, [catalogEquipment]);
    await q(`insert into public.equipos_ivmet(equipo_id,habilitado,estado_configuracion) values($1,true,'READY'),($2,false,'PENDING')`,
      [catalogEquipment, hiddenCatalog]);
    const today = (await q('select current_date::text d'))[0].d;
    const commercial = await mutate('plan.save', { name: 'Fixture', seats: 5, graceDays: 0 });
    const price = await mutate('price.create', { planId: commercial.id, periodicity: 'MONTHLY', currency: 'BOB', amount: '0', startsOn: today });
    const endsOn = (await q("select (current_date+interval '2 years')::date::text d"))[0].d;
    await mutate('contract.create', { clientId: client, priceId: price.id, number: 'TEST-C', invoiceNumber: 'TEST-F', signedOn: today, startsOn: today, endsOn });
    const subscription = (await q('select id from public.suscripciones'))[0].id;
    const user = async (name, role) => {
      const request = uuid(), payload = { clientId: client, username: name, name, role, plantIds: [plant] };
      const u = (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, 'user.reserve', payload, request]))[0].r;
      await q('insert into auth.users(id,email) values($1,$2)', [u.id, u.email]);
      await q('select public.ivmet_admin_mutate($1,$2,$3,$4)', [admin, 'user.create', payload, request]);
      await mutate('license.assign', { id: u.id, clientId: client, subscriptionId: subscription });
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [u.id]);
      return u.id;
    };
    const operator = await user('operator', 'cliente_operador'), quality = await user('quality', 'cliente_jefe_calidad');
    const pattern = uuid(), certificate = uuid();
    await q("insert into public.patrones(id,cliente_id,codigo,descripcion,tipo) values($1,$2,'PATRON','PRIVADO-PATRON','pesas')", [pattern, client]);
    await q('insert into public.patron_plantas(patron_id,planta_id) values($1,$2)', [pattern, plant]);
    await q(`insert into public.patron_certificados(id,patron_id,numero,laboratorio,calibrado_el,vence_el)
      values($1,$2,'CERT','Laboratorio',current_date-1,current_date+365)`, [certificate, pattern]);

    const registration = {
      plantId: plant, areaId: '', areaName: '  Laboratorio   Nuevo ',
      data: { cod_interno: 'BAL-NUEVA', marca: 'Marca', modelo: 'Modelo', serie: 'S-NUEVA', ubicacion: 'Mesón 3', tipo: 'PLATFORM', clase: 'III', unidad: 'kg' },
      ranges: [{ capacity: '60', division: '0.01', interval: '0.01' }, { capacity: '150.000', division: '0.02', interval: '' }],
    };
    let registered, area;

    await t.test('solo el jefe de calidad registra y el área nueva nace con la balanza', async () => {
      await identity(operator);
      await assert.rejects(customer('equipment.register', registration), /QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      const request = uuid();
      registered = (await customer('equipment.register', registration, request)).id;
      await q('select public.ivmet_customer_assign_equipment($1,$2)', [{ userId: operator, plantId: plant, equipmentIds: [registered, catalogEquipment] }, uuid()]);
      assert.deepEqual(await customer('equipment.register', registration, request), { id: registered });
      await assert.rejects(customer('equipment.register', { ...registration, data: { ...registration.data, serie: 'OTRA' } }, request), /IDEMPOTENCY_CONFLICT/);
      area = (await setup('areas', { plantId: plant })).items.find(a => a.name === 'Laboratorio Nuevo');
      assert.ok(area, 'el nombre del área se normaliza y se crea en la planta');
      const list = await read('instruments', { plantId: plant });
      const item = list.items.find(i => i.id === registered);
      assert.equal(item.origen, 'CLIENTE');
      assert.equal(item.cod_metrica, null);
      assert.equal(item.cod_interno, 'BAL-NUEVA');
      assert.equal(item.area, 'Laboratorio Nuevo');
      assert.equal((await read('bootstrap')).equipmentCount, 2);
      const detail = await read('equipment', { equipmentId: registered });
      assert.equal(detail.registeredByCustomer, true);
      assert.equal(detail.customerValidated, true);
      assert.equal(detail.customerUpdatePending, false);
      assert.equal(detail.registrationInUse, false);
      assert.equal(detail.registrationSharePending, true);
      assert.deepEqual(detail.ranges.map(r => [Number(r.capacidad_max), Number(r.division_escala), r.intervalo_verificacion && Number(r.intervalo_verificacion)]),
        [[60, 0.01, 0.01], [150, 0.02, null]]);
      const form = await setup('registration', { id: registered });
      assert.deepEqual(form.data, { ...registration.data, ubicacion: 'Mesón 3' });
      assert.deepEqual(form.ranges, [{ capacity: '60', division: '0.01', interval: '0.01' }, { capacity: '150', division: '0.02', interval: '' }]);
      assert.equal(form.areaId, area.id);
      assert.equal(form.version, '1');
      assert.equal(form.inUse, false);
      await identity(operator);
      assert.equal((await read('equipment', { equipmentId: registered })).registeredByCustomer, true);
      await assert.rejects(setup('registration', { id: registered }), /QUALITY_MANAGER_REQUIRED/);
      await assert.rejects(setup('registration', { id: catalogEquipment }), /QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      await assert.rejects(setup('registration', { id: catalogEquipment }), /REGISTERED_EQUIPMENT_REQUIRED/);
    });

    await t.test('rechaza datos incompletos, rangos incoherentes, duplicados y plantas ajenas', async () => {
      const variant = (data = {}, extra = {}) => ({ ...registration, areaName: '', areaId: area.id, ...extra,
        data: { ...registration.data, cod_interno: 'BAL-X', serie: '', ...data } });
      await assert.rejects(customer('equipment.register', variant({ unidad: 'lb' })), /INVALID_EQUIPMENT_DATA/);
      await assert.rejects(customer('equipment.register', variant({ tipo: 'GRUA' })), /INVALID_EQUIPMENT_DATA/);
      await assert.rejects(customer('equipment.register', variant({ cod_interno: '   ' })), /EQUIPMENT_CODE_REQUIRED/);
      await assert.rejects(customer('equipment.register', variant({ marca: 'x'.repeat(51) })), /INVALID_EQUIPMENT_DATA/);
      const range = (capacity, division, interval = '') => ({ capacity, division, interval });
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('10', '1'), range('20', '1'), range('30', '1'), range('40', '1')] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('100', '1'), range('50', '1')] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('100', '0.1', '0.01')] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('100', '100')] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('0', '0')] })), /INVALID_EQUIPMENT_RANGES/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [{ capacity: 100, division: '1', interval: '' }] })), /EXACT_DECIMAL_REQUIRED/);
      await assert.rejects(customer('equipment.register', variant({}, { ranges: [range('100,5', '1')] })), /EXACT_DECIMAL_REQUIRED/);
      await assert.rejects(customer('equipment.register', variant({}, { areaId: '' })), /AREA_REQUIRED/);
      await assert.rejects(customer('equipment.register', variant({}, { plantId: hiddenPlant })), /PLANT_SCOPE_INVALID/);
      await assert.rejects(customer('equipment.register', variant({ cod_interno: ' bal-nueva ' })), /EQUIPMENT_CODE_EXISTS/);
      await assert.rejects(customer('equipment.register', variant({ cod_interno: 'cat-01' })), /EQUIPMENT_CODE_EXISTS/);
      await assert.rejects(customer('equipment.register', variant({ marca: 'catalogo', serie: 's-cat' })), /EQUIPMENT_SERIAL_EXISTS/);
      // Una balanza del catálogo que la empresa no ve no bloquea ni se revela.
      const unrelated = await customer('equipment.register', variant({ cod_interno: 'OCULTA-01', marca: 'Oculta', serie: 'S-OCULTA' }));
      assert.ok(unrelated.id);
      await customer('equipment.retire', { id: unrelated.id, version: '1', reason: 'Alta de prueba' });
    });

    let verification;
    await t.test('configuración guiada, borrador y finalización sin código de Métrica', async () => {
      await configureChecks(registered, { tests: [{ type: 'linearity', frequencyDays: '30', tolerance: '0.5' }] });
      await identity('', 'service_role');
      assert.equal((await q(`select p.nombre from private.equipment_configuration_plans l join public.planes p on p.id=l.plan_id
        where l.equipo_id=$1`, [registered]))[0].nombre, 'Configuración BAL-NUEVA');
      await identity(operator);
      const bundle = await read('equipment', { equipmentId: registered });
      assert.equal(bundle.plan.finalizationEnabled, true);
      const trial = bundle.plan.tests[0];
      assert.equal(Number(trial.points.at(-1).load), 150, 'los puntos salen de la capacidad del rango mayor');
      const content = {
        tests: [{ id: trial.id, omitted: false, reason: '', readings: trial.points.map(p => ({ pointId: p.id, indication: p.load, zero: '' })) }],
        certificates: [certificate], temperature: '21', humidity: '40', observations: '',
      };
      const draft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [uuid(), registered, bundle.plan.id, 0, content, uuid()]))[0].r;
      assert.equal((await read('equipment', { equipmentId: registered })).registrationInUse, true);
      verification = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5) r',
        [draft.id, Number(draft.version), uuid(), 'fixture-1.0', 'fixture-device']))[0].r;
      assert.equal(verification.verdict, 'pass');
      const history = await read('history', { equipmentId: registered });
      assert.equal(history.total, 1);
      assert.equal(history.items[0].origen, 'CLIENTE');
      assert.equal(history.items[0].cod_interno, 'BAL-NUEVA');
    });

    await t.test('identificación y área se corrigen siempre; los datos técnicos, solo sin uso', async () => {
      await identity(quality);
      const edit = (version, data = {}, extra = {}) => ({ id: registered, version, areaId: area.id, areaName: '',
        data: { ...registration.data, ...data }, ranges: registration.ranges, ...extra });
      await assert.rejects(customer('equipment.edit', edit('1', {}, { ranges: [{ capacity: '200', division: '0.05', interval: '' }] })), /EQUIPMENT_IN_USE/);
      await assert.rejects(customer('equipment.edit', edit('1', { clase: 'II' })), /EQUIPMENT_IN_USE/);
      const corrected = await customer('equipment.edit', edit('1', { marca: 'Marca Corregida' }, { areaId: '', areaName: 'Despacho' }));
      assert.deepEqual(corrected, { id: registered, version: '2', configurationReset: false });
      await assert.rejects(customer('equipment.edit', edit('1', { marca: 'Otra' })), /ROW_VERSION_CONFLICT/);
      await assert.rejects(customer('equipment.edit', edit('2', { cod_interno: 'CAT-01' })), /EQUIPMENT_CODE_EXISTS/);
      const detail = await read('equipment', { equipmentId: registered });
      assert.equal(detail.equipment.marca, 'Marca Corregida');
      assert.equal(detail.customerValidated, true);
      assert.ok(detail.plan, 'corregir la identificación no retira la configuración');
      assert.equal((await read('instruments', { search: 'despacho' })).items[0].id, registered);

      const spare = (await customer('equipment.register', { ...registration, areaName: '', areaId: area.id,
        data: { ...registration.data, cod_interno: 'BAL-REPUESTO', serie: '' } })).id;
      await configureChecks(spare, { tests: [{ type: 'linearity', frequencyDays: '30', tolerance: '0.5' }] });
      const reset = await customer('equipment.edit', { id: spare, version: '1', areaId: area.id, areaName: '',
        data: { ...registration.data, cod_interno: 'BAL-REPUESTO', serie: '', tipo: 'TRUCK', unidad: 't', clase: '' },
        ranges: [{ capacity: '60', division: '0.02', interval: '' }] });
      assert.equal(reset.configurationReset, true);
      const spareDetail = await read('equipment', { equipmentId: spare });
      assert.equal(spareDetail.plan, null);
      assert.equal(spareDetail.ranges.length, 1);
      assert.equal(spareDetail.equipment.tipo_balanza, 'Báscula camionera');
      assert.equal((await setup('registration', { id: spare })).data.tipo, 'TRUCK');
    });

    await t.test('nada llega al espejo corporativo ni a RimMET sin consentimiento', async () => {
      await identity(operator);
      await assert.rejects(customer('equipment.validate', { id: registered, version: '1', catalogHash: 'a'.repeat(64), areaId: '',
        data: { ubicacion: '', cod_interno: 'X', marca: '', modelo: '', serie: '' } }), /REGISTERED_EQUIPMENT_USES_EDIT/);
      await identity('', 'service_role');
      const events = await q(`select aggregate_type,privacy_blocked from private.sync_outbox
        where (aggregate_type='public.equipos' and payload->>'id'=$1) or (aggregate_type='public.equipo_rangos' and payload->>'equipo_id'=$1)`, [registered]);
      assert.ok(events.length >= 3);
      assert.ok(events.every(e => e.privacy_blocked));
      await q("update public.equipos set cod_interno='CAT-01-B' where id=$1", [catalogEquipment]);
      await q(`insert into private.sync_outbox(aggregate_type,aggregate_key,operation,payload)
        values('public.casos_compartidos',jsonb_build_object('id',gen_random_uuid()),'I',jsonb_build_object('equipo_id',$1::text))`, [registered]);
      const queue = JSON.stringify(await q("select * from public.claim_ivmet_sync_outbox('test-registered',500)"));
      assert.ok(!queue.includes(registered), 'ningún evento de la balanza registrada se entrega al worker');
      assert.ok(queue.includes('CAT-01-B'), 'el catálogo de DataMET sigue exportándose');
      const equipment = (await q("select public.ivmet_admin_read('equipment',$1,'{}') r", [client]))[0].r;
      assert.deepEqual(equipment.items.map(e => e.id).sort(), [catalogEquipment, hiddenCatalog].sort());
      assert.equal(equipment.total, 2);
      assert.equal((await q("select public.ivmet_admin_read('overview',null,'{}') r"))[0].r.equipment, 2);
      assert.equal((await q("select public.ivmet_admin_read('clients',null,'{}') r"))[0].r.items[0].equipment, 2);
      await assert.rejects(mutate('equipment.configure', { id: registered, clientId: client, enabled: false, version: '1' }), /CUSTOMER_REGISTERED_EQUIPMENT/);
      await identity(operator);
    });

    let sharedRegistration;
    await t.test('la empresa decide enviar la balanza a Métrica por RimMET', async () => {
      await assert.rejects(setup('registration-preview', { id: registered }), /QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      const preview = await setup('registration-preview', { id: registered });
      assert.equal(preview.snapshot.kind, 'registration');
      assert.equal(preview.snapshot.code, 'BAL-NUEVA');
      assert.equal(preview.snapshot.area, 'Despacho');
      assert.deepEqual(preview.snapshot.technical.ranges.map(r => r.capacity), ['60', '150']);
      assert.ok(!JSON.stringify(preview).includes('PRIVADO-PATRON'));
      const share = { id: registered, hash: preview.hash, message: 'Balanza nueva para la próxima visita',
        consentVersion: preview.consentVersion, consent: true };
      await assert.rejects(customer('registration.share', { ...share, consent: false }), /EXPLICIT_CONSENT_REQUIRED/);
      await assert.rejects(customer('registration.share', { ...share, hash: '0'.repeat(64) }), /SHARE_PREVIEW_CHANGED/);
      await assert.rejects(customer('registration.share', { ...share, message: ' ' }), /MESSAGE_REQUIRED/);
      await assert.rejects(customer('update.share', { ...share, consentVersion: 'equipment-sharing-v1' }), /REGISTERED_EQUIPMENT_USES_EDIT/);
      const request = uuid();
      sharedRegistration = await customer('registration.share', share, request);
      assert.deepEqual(await customer('registration.share', share, request), sharedRegistration);
      await assert.rejects(customer('registration.share', share), /REGISTRATION_ALREADY_SHARED/);
      await assert.rejects(setup('registration-preview', { id: registered }), /REGISTRATION_ALREADY_SHARED/);
      const detail = await read('equipment', { equipmentId: registered });
      assert.equal(detail.registrationSharePending, false);
      assert.equal(detail.registrationShared, true);
      await identity('', 'service_role');
      const inbox = (await q("select public.ivmet_ops_read($1,'equipment-updates',$2) r", [admin, { search: 'bal-nueva' }]))[0].r;
      assert.equal(inbox.total, 1);
      assert.equal(inbox.items[0].snapshot.kind, 'registration');
      assert.equal(inbox.items[0].snapshot.technical.unit, 'kg');
      assert.equal((await q(`select privacy_blocked from private.sync_outbox
        where aggregate_type='public.actualizaciones_compartidas' and aggregate_key->>'id'=$1`, [sharedRegistration.id]))[0].privacy_blocked, true);
      await q("select public.ivmet_ops_mutate($1,'equipment-update.review',$2,$3)", [admin, { id: sharedRegistration.id, version: '1', comment: 'Registrada en la agenda' }, uuid()]);
      await identity(quality);
      const version = (await setup('registration', { id: registered })).version;
      await customer('equipment.edit', { id: registered, version, areaId: '', areaName: 'Despacho',
        data: { ...registration.data, marca: 'Marca Corregida', ubicacion: 'Mesón 4' }, ranges: registration.ranges });
      assert.equal((await read('equipment', { equipmentId: registered })).registrationSharePending, true);
      const receipt = (await setup('updates', { id: registered })).items[0];
      assert.equal(receipt.estado, 'REVIEWED');
      await customer('update.withdraw', { id: sharedRegistration.id, version: receipt.row_version, reason: 'Retiro de acceso' });
      await identity('', 'service_role');
      assert.equal((await q("select public.ivmet_ops_read($1,'equipment-updates','{}') r", [admin]))[0].r.total, 0);
    });

    await t.test('dar de baja exige cerrar capturas y conserva el historial', async () => {
      await identity(operator);
      const bundle = await read('equipment', { equipmentId: registered });
      const trial = bundle.plan.tests[0];
      const draft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [uuid(), registered, bundle.plan.id, 0, {
        tests: [{ id: trial.id, omitted: false, reason: '', readings: [] }], certificates: [], temperature: '', humidity: '', observations: '',
      }, uuid()]))[0].r;
      const version = bundle.equipment.source_version.toString();
      await assert.rejects(customer('equipment.retire', { id: registered, version, reason: 'Vendida' }), /QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      await assert.rejects(customer('equipment.retire', { id: registered, version, reason: 'Vendida' }), /EQUIPMENT_HAS_OPEN_DRAFTS/);
      await assert.rejects(customer('equipment.retire', { id: catalogEquipment, version: '1', reason: 'No' }), /EQUIPMENT_NOT_ACCESSIBLE/);
      await db.exec('reset role');
      await q("update public.verificacion_borradores set estado='ABANDONED' where id=$1", [draft.id]);
      await identity(quality);
      await assert.rejects(customer('equipment.retire', { id: registered, version, reason: ' ' }), /REASON_REQUIRED/);
      const request = uuid();
      const retired = await customer('equipment.retire', { id: registered, version, reason: 'Vendida' }, request);
      assert.deepEqual(await customer('equipment.retire', { id: registered, version, reason: 'Vendida' }, request), retired);
      await assert.rejects(read('equipment', { equipmentId: registered }), /EQUIPMENT_NOT_ACCESSIBLE/);
      assert.ok(!(await read('instruments')).items.some(i => i.id === registered));
      assert.equal((await read('history', { equipmentId: registered })).items[0].id, verification.id);
    });
  } finally {
    await db.close();
  }
});

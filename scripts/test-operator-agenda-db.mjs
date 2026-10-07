import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('agenda, periodicidad y balanzas por operador en PostgreSQL desechable', async (t) => {
  const db = new PGlite();
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const admin = 'RIMMET:fixture';
  // Desfase cero: "hoy" es el día UTC, igual que en las fechas que calcula la prueba.
  const clock = { utcOffsetMinutes: 0 };
  const mutate = async (action, payload) => (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, action, payload, uuid()]))[0].r;
  const read = async (section, filters = {}) => (await q('select public.ivmet_mobile_read($1,$2) r', [section, { ...clock, ...filters }]))[0].r;
  const customer = async (action, payload, request = uuid()) => (await q('select public.ivmet_customer_mutate($1,$2,$3) r', [action, payload, request]))[0].r;
  const configure = async (equipmentId, configuration, request = uuid()) =>
    (await q('select public.ivmet_customer_configure_checks($1,$2,$3) r', [equipmentId, configuration, request]))[0].r;
  const assign = async (assignment, request = uuid()) =>
    (await q('select public.ivmet_customer_assign_equipment($1,$2) r', [assignment, request]))[0].r;
  const identity = async (id = '', role = 'authenticated') => {
    await db.exec('reset role');
    await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role',$2,false)", [id, role]);
    if (role === 'authenticated') await db.exec('set role authenticated');
  };
  const scalar = async (sql, params = []) => Object.values((await q(sql, params))[0])[0];
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

    await t.test('fechas fijas: días, semanas, meses, último día del mes y años bisiestos', async () => {
      const next = (rule, date) => scalar('select private.schedule_next($1,$2::date)::text', [rule, date]);
      const previous = (rule, date) => scalar('select private.schedule_previous($1,$2::date)::text', [rule, date]);
      const days = { mode: 'fixed', unit: 'day', every: 3, warningDays: 0, startsOn: '2026-01-01' };
      assert.equal(await next(days, '2025-06-01'), '2026-01-01');
      assert.equal(await next(days, '2026-01-02'), '2026-01-04');
      assert.equal(await previous(days, '2026-01-06'), '2026-01-04');
      assert.equal(await previous(days, '2025-12-31'), null);
      // Empieza un miércoles: el lunes de esa semana queda antes del inicio.
      const weeks = { mode: 'fixed', unit: 'week', every: 2, warningDays: 0, startsOn: '2026-10-07', weekdays: [1, 4] };
      assert.equal(await next(weeks, '2026-10-01'), '2026-10-08');
      assert.equal(await next(weeks, '2026-10-09'), '2026-10-19');
      assert.equal(await next(weeks, '2026-10-20'), '2026-10-22');
      assert.equal(await previous(weeks, '2026-10-18'), '2026-10-08');
      assert.equal(await previous(weeks, '2026-10-07'), null);
      assert.equal(await previous(weeks, '2026-10-30'), '2026-10-22');
      const monthEnd = { mode: 'fixed', unit: 'month', every: 1, warningDays: 0, startsOn: '2026-01-15', monthMode: 'day', monthDay: 31 };
      assert.equal(await next(monthEnd, '2026-02-01'), '2026-02-28');
      assert.equal(await previous(monthEnd, '2026-03-30'), '2026-02-28');
      const lastFriday = { mode: 'fixed', unit: 'month', every: 1, warningDays: 0, startsOn: '2026-10-01', monthMode: 'weekday', weekOfMonth: 5, weekday: 5 };
      assert.equal(await next(lastFriday, '2026-10-01'), '2026-10-30');
      const firstMonday = { mode: 'fixed', unit: 'month', every: 3, warningDays: 0, startsOn: '2026-10-01', monthMode: 'weekday', weekOfMonth: 1, weekday: 1 };
      assert.equal(await next(firstMonday, '2026-10-01'), '2026-10-05');
      assert.equal(await next(firstMonday, '2026-10-06'), '2027-01-04');
      assert.equal(await previous(firstMonday, '2027-01-03'), '2026-10-05');
      const leap = { mode: 'fixed', unit: 'year', every: 1, warningDays: 0, startsOn: '2028-02-29', monthMode: 'day', monthDay: 29 };
      assert.equal(await next(leap, '2029-01-01'), '2029-02-28');
      assert.equal(await scalar("select private.schedule_add('2026-01-31','month',1)::text"), '2026-02-28');
    });

    await t.test('la regla se normaliza y rechaza combinaciones imposibles', async () => {
      const normalize = rule => scalar('select private.schedule_normalize($1)', [rule]);
      assert.deepEqual(
        await normalize({ mode: 'fixed', unit: 'week', every: 1, warningDays: 1, startsOn: '2026-10-07', weekdays: [5, 1, 3] }),
        { mode: 'fixed', unit: 'week', every: 1, warningDays: 1, startsOn: '2026-10-07', weekdays: [1, 3, 5] });
      for (const invalid of [
        { mode: 'fixed', unit: 'day', every: 0, warningDays: 0, startsOn: '2026-10-07' },
        { mode: 'fixed', unit: 'day', every: 1, warningDays: 0, startsOn: '2026-02-30' },
        { mode: 'fixed', unit: 'week', every: 1, warningDays: 0, startsOn: '2026-10-07', weekdays: [1, 1] },
        { mode: 'fixed', unit: 'week', every: 1, warningDays: 0, startsOn: '2026-10-07', weekdays: [] },
        { mode: 'fixed', unit: 'month', every: 1, warningDays: 0, startsOn: '2026-10-07', monthMode: 'day', monthDay: 32 },
        { mode: 'fixed', unit: 'month', every: 25, warningDays: 0, startsOn: '2026-10-07', monthMode: 'day', monthDay: 1 },
        { mode: 'rolling', unit: 'week', every: 1, warningDays: 0, weekdays: [1] },
        { mode: 'rolling', unit: 'day', every: '7', warningDays: 0 },
        { mode: 'fixed', unit: 'day', every: 1, warningDays: 91, startsOn: '2026-10-07' },
      ]) {
        await assert.rejects(normalize(invalid), /INVALID_CHECK_SCHEDULE/, JSON.stringify(invalid));
      }
    });

    await q('select public.ivmet_bootstrap_admin($1,$2)', [admin, 'Fixture aislado']);
    const client = uuid(), plant = uuid(), otherPlant = uuid();
    const [weekly, overdue, legacy, other] = [uuid(), uuid(), uuid(), uuid()];
    await q("insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,1,'0001','Cliente',repeat('a',64))", [client]);
    await q(`insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values
      ($1,$2,'0001-01',repeat('a',64)),($3,$2,'0001-02',repeat('b',64))`, [plant, client, otherPlant]);
    await q(`insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,cod_interno,source_hash) values
      ($1,$5,$6,1,'0001-01-001','SEMANAL',repeat('a',64)),($2,$5,$6,2,'0001-01-002','ATRASADA',repeat('a',64)),
      ($3,$5,$6,3,'0001-01-003','HEREDADA',repeat('a',64)),($4,$5,$7,4,'0001-02-001','OTRA-PLANTA',repeat('a',64))`,
      [weekly, overdue, legacy, other, client, plant, otherPlant]);
    for (const id of [weekly, overdue, legacy, other]) {
      await q(`insert into public.equipo_rangos(equipo_id,numero_rango,unidad,capacidad_max,division_escala,source_hash)
        values($1,1,'kg',100,0.1,repeat('a',64))`, [id]);
      await q(`insert into public.equipos_ivmet(equipo_id,habilitado,estado_configuracion) values($1,true,'READY')`, [id]);
    }
    const today = await scalar("select ((now() at time zone 'UTC')::date)::text");
    const shift = async days => scalar("select ($1::date+$2::integer)::text", [today, days]);
    const isoDay = async date => Number(await scalar('select extract(isodow from $1::date)::integer', [date]));
    const commercial = await mutate('plan.save', { name: 'Fixture', seats: 10, graceDays: 0 });
    const price = await mutate('price.create', { planId: commercial.id, periodicity: 'MONTHLY', currency: 'BOB', amount: '0', startsOn: today });
    const endsOn = await scalar("select (current_date+interval '2 years')::date::text");
    await mutate('contract.create', { clientId: client, priceId: price.id, number: 'TEST-C', invoiceNumber: 'TEST-F', signedOn: today, startsOn: today, endsOn });
    const subscription = (await q('select id from public.suscripciones'))[0].id;
    const user = async (name, role, plantIds = [plant]) => {
      const request = uuid(), payload = { clientId: client, username: name, name, role, plantIds };
      const u = (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, 'user.reserve', payload, request]))[0].r;
      await q('insert into auth.users(id,email) values($1,$2)', [u.id, u.email]);
      await q('select public.ivmet_admin_mutate($1,$2,$3,$4)', [admin, 'user.create', payload, request]);
      await mutate('license.assign', { id: u.id, clientId: client, subscriptionId: subscription });
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [u.id]);
      return u.id;
    };
    const ana = await user('Ana', 'cliente_operador'), beto = await user('Beto', 'cliente_operador');
    const foreigner = await user('Ciro', 'cliente_operador', [otherPlant]);
    const quality = await user('Jefa', 'cliente_jefe_calidad', [plant, otherPlant]);

    const weeklyRule = { mode: 'fixed', unit: 'week', every: 1, warningDays: 0, startsOn: today, weekdays: [await isoDay(today)] };
    const lateStart = await shift(-3);
    const lateRule = { mode: 'fixed', unit: 'week', every: 1, warningDays: 1, startsOn: lateStart, weekdays: [await isoDay(lateStart)] };

    await t.test('el jefe guarda la periodicidad; los clientes anteriores siguen enviando días', async () => {
      await identity(quality);
      for (const id of [weekly, overdue, legacy, other]) {
        await customer('equipment.validate', { id, version: '0', catalogHash: 'a'.repeat(64), areaId: '',
          data: { ubicacion: '', cod_interno: '', marca: '', modelo: '', serie: '' } });
      }
      const request = uuid();
      const configured = await configure(weekly, { tests: [{ type: 'linearity', tolerance: '0.5', schedule: { ...weeklyRule } }] }, request);
      assert.deepEqual(configured.schedules.linearity, weeklyRule);
      assert.deepEqual(await configure(weekly, { tests: [{ type: 'linearity', tolerance: '0.5', schedule: { ...weeklyRule } }] }, request), configured);
      await assert.rejects(configure(weekly, { tests: [{ type: 'linearity', tolerance: '0.5', schedule: { ...weeklyRule, warningDays: 3 } }] }, request),
        /IDEMPOTENCY_CONFLICT/);
      await assert.rejects(configure(weekly, { tests: [{ type: 'linearity', tolerance: '0.5', schedule: { ...weeklyRule, every: 0 } }] }),
        /INVALID_CHECK_SCHEDULE/);
      await configure(overdue, { tests: [{ type: 'linearity', tolerance: '0.5', schedule: lateRule }] });
      await configure(legacy, { tests: [{ type: 'linearity', tolerance: '0.5', frequencyDays: '30' }] });
      await configure(other, { tests: [{ type: 'linearity', tolerance: '0.5', frequencyDays: '7' }] });
      const legacySchedule = (await read('equipment', { equipmentId: legacy })).schedule[0];
      assert.deepEqual(legacySchedule.rule, { mode: 'rolling', unit: 'day', every: 30, warningDays: 7 });
      assert.equal(legacySchedule.dueAt, await shift(30));
      assert.equal(legacySchedule.state, 'CURRENT');
      const lateSchedule = (await read('equipment', { equipmentId: overdue })).schedule[0];
      assert.equal(lateSchedule.dueAt, lateStart);
      assert.equal(lateSchedule.state, 'OVERDUE');
      await identity('', 'service_role');
      assert.equal(await scalar('select frecuencia_dias from public.plan_pruebas t join private.plan_test_schedules s on s.plan_prueba_id=t.id where s.rule=$1', [weeklyRule]), 7);
    });

    await t.test('un operador sin asignaciones no ve balanzas de su planta', async () => {
      await identity(ana);
      const boot = await read('bootstrap');
      assert.equal(boot.equipmentScope, 'ASSIGNED');
      assert.equal(boot.equipmentCount, 0);
      assert.equal(boot.plants[0].equipmentCount, 0);
      assert.equal((await read('instruments')).total, 0);
      assert.deepEqual((await read('agenda', { from: today, to: await shift(13) })).items, []);
      await assert.rejects(read('equipment', { equipmentId: weekly }), /EQUIPMENT_NOT_ACCESSIBLE/);
      await assert.rejects(q('select public.ivmet_mobile_save_draft($1,$2,$3,0,$4,$5)',
        [uuid(), weekly, uuid(), { tests: [], certificates: [], temperature: '', humidity: '', observations: '' }, uuid()]), /EQUIPMENT_NOT_ACCESSIBLE/);
      assert.equal((await q('select id from public.equipos')).length, 0, 'RLS aplica el mismo alcance por REST');
      await assert.rejects(read('team', { plantId: plant }), /QUALITY_MANAGER_REQUIRED/);
      await assert.rejects(assign({ userId: ana, plantId: plant, equipmentIds: [weekly] }), /QUALITY_MANAGER_REQUIRED/);
    });

    await t.test('el jefe asigna por operador o por balanza, de forma idempotente', async () => {
      await identity(quality);
      const team = await read('team', { plantId: plant });
      assert.deepEqual(team.members.map(m => m.name), ['Ana', 'Beto']);
      assert.equal(team.equipmentCount, 3);
      assert.equal(team.unassignedCount, 3);
      assert.equal((await read('bootstrap')).agenda.unassigned, 4);
      const request = uuid();
      const result = await assign({ userId: ana, plantId: plant, equipmentIds: [weekly, overdue] }, request);
      assert.deepEqual(result, { userId: ana, plantId: plant, assigned: 2, added: 2, removed: 0 });
      assert.deepEqual(await assign({ userId: ana, plantId: plant, equipmentIds: [weekly, overdue] }, request), result);
      await assert.rejects(assign({ userId: ana, plantId: plant, equipmentIds: [weekly] }, request), /IDEMPOTENCY_CONFLICT/);
      await assert.rejects(assign({ userId: foreigner, plantId: plant, equipmentIds: [] }), /OPERATOR_NOT_IN_PLANT/);
      await assert.rejects(assign({ userId: quality, plantId: plant, equipmentIds: [] }), /OPERATOR_NOT_IN_PLANT/);
      await assert.rejects(assign({ userId: ana, plantId: plant, equipmentIds: [other] }), /EQUIPMENT_NOT_ACCESSIBLE/);
      await assert.rejects(assign({ userId: ana, plantId: plant, equipmentIds: ['x'] }), /INVALID_ASSIGNMENT/);
      const member = await read('team-member', { plantId: plant, userId: ana });
      assert.deepEqual(member.items.filter(i => i.assigned).map(i => i.cod_interno), ['ATRASADA', 'SEMANAL']);
      assert.equal((await read('team', { plantId: plant })).unassignedCount, 1);
      // Por balanza: Beto se suma a SEMANAL sin tocar a Ana.
      await assign({ equipmentId: weekly, userIds: [ana, beto] });
      assert.deepEqual((await read('equipment-team', { equipmentId: weekly })).members.map(m => [m.name, m.assigned]),
        [['Ana', true], ['Beto', true]]);
      assert.deepEqual((await read('equipment', { equipmentId: weekly })).assignees.map(a => a.name), ['Ana', 'Beto']);
      await assert.rejects(assign({ equipmentId: weekly, userIds: [foreigner] }), /OPERATOR_NOT_IN_PLANT/);
    });

    let draftBundle;
    await t.test('el operador ve solo lo asignado: catálogo, ficha, REST y conteos', async () => {
      await identity(ana);
      const boot = await read('bootstrap');
      assert.equal(boot.equipmentCount, 2);
      assert.deepEqual((await read('instruments')).items.map(i => i.cod_interno).sort(), ['ATRASADA', 'SEMANAL']);
      await assert.rejects(read('equipment', { equipmentId: legacy }), /EQUIPMENT_NOT_ACCESSIBLE/);
      draftBundle = await read('equipment', { equipmentId: weekly });
      assert.equal(draftBundle.assignees, undefined, 'el operador no recibe el equipo de trabajo');
      assert.equal((await q('select id from public.equipos')).length, 2);
    });

    await t.test('la agenda marca hoy, la próxima semana y lo atrasado', async () => {
      await identity(ana);
      const agenda = await read('agenda', { from: today, to: await shift(13) });
      const at = (date, code) => agenda.items.find(i => i.date === date && i.equipment.cod_interno === code);
      assert.equal(at(today, 'SEMANAL').tests[0].state, 'DUE_TODAY');
      assert.equal(at(await shift(7), 'SEMANAL').tests[0].state, 'SCHEDULED');
      assert.equal(at(await shift(4), 'ATRASADA').tests[0].state, 'SCHEDULED');
      assert.deepEqual(agenda.overdue.map(o => [o.equipment.cod_interno, o.dueOn]), [['ATRASADA', lateStart]]);
      const past = await read('agenda', { from: await shift(-6), to: today });
      assert.equal(past.items.find(i => i.date === lateStart).tests[0].state, 'OVERDUE');
      const summary = (await read('bootstrap')).agenda;
      assert.deepEqual([summary.dueToday, summary.doneToday, summary.overdue], [1, 0, 1]);
      await assert.rejects(read('agenda', { from: today, to: await shift(90) }), /INVALID_AGENDA_RANGE/);
      await assert.rejects(read('agenda', { from: today, to: await shift(5), operatorId: beto }), /QUALITY_MANAGER_REQUIRED/);
    });

    await t.test('cualquier verificación finalizada cumple la fecha, con o sin trazabilidad', async () => {
      await identity(ana);
      const trial = draftBundle.plan.tests[0];
      const content = {
        tests: [{ id: trial.id, omitted: false, reason: '', readings: trial.points.map(p => ({ pointId: p.id, indication: p.load, zero: '' })) }],
        certificates: [], temperature: '21', humidity: '40', observations: '',
      };
      const draft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r',
        [uuid(), weekly, draftBundle.plan.id, 0, content, uuid()]))[0].r;
      const finalized = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3) r', [draft.id, Number(draft.version), uuid()]))[0].r;
      assert.notEqual(finalized.traceability, 'traceable');
      const agenda = await read('agenda', { from: today, to: await shift(7) });
      const done = agenda.items.find(i => i.date === today && i.equipment.cod_interno === 'SEMANAL');
      assert.deepEqual(done.tests[0], { type: 'linearity', state: 'DONE', doneOn: today });
      const schedule = (await read('equipment', { equipmentId: weekly })).schedule[0];
      assert.equal(schedule.dueAt, await shift(7));
      assert.equal(schedule.state, 'CURRENT');
      assert.equal(schedule.lastTraceableAt, null);
      const summary = (await read('bootstrap')).agenda;
      assert.deepEqual([summary.dueToday, summary.doneToday], [0, 1]);
    });

    await t.test('el jefe filtra por operador y lo capturado sigue en el historial de quien lo hizo', async () => {
      await identity(quality);
      const byBeto = await read('agenda', { from: today, to: await shift(7), operatorId: beto });
      assert.deepEqual([...new Set(byBeto.items.map(i => i.equipment.cod_interno))], ['SEMANAL']);
      const unassigned = await read('agenda', { from: today, to: await shift(40), operatorId: 'unassigned' });
      assert.deepEqual([...new Set(unassigned.items.map(i => i.equipment.cod_interno))].sort(), ['HEREDADA', 'OTRA-PLANTA']);
      assert.deepEqual(byBeto.items[0].equipment.assignees.map(a => a.name), ['Ana', 'Beto']);
      // A Ana se le retira SEMANAL: conserva su verificación, no la balanza.
      await assign({ equipmentId: weekly, userIds: [beto] });
      await identity(ana);
      assert.equal((await read('history')).total, 1);
      await assert.rejects(read('equipment', { equipmentId: weekly }), /EQUIPMENT_NOT_ACCESSIBLE/);
      await identity(beto);
      assert.equal((await read('history')).total, 1);
      assert.equal((await read('instruments')).total, 1);
    });
  } finally {
    await db.close();
  }
});

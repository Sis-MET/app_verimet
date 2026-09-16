import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('avisos por cliente y habilitación de balanzas en lote', async (t) => {
  const db = new PGlite();
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const admin = 'RIMMET:fixture';
  const mutate = async (action, payload, request = uuid(), actor = admin) =>
    (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [actor, action, payload, request]))[0].r;
  const read = async (section, clientId = null, filters = {}) =>
    (await q('select public.ivmet_admin_read($1,$2,$3) r', [section, clientId, filters]))[0].r;
  const state = async (id) =>
    (await q('select habilitado,estado_configuracion,row_version::int v from public.equipos_ivmet where equipo_id=$1', [id]))[0];
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema extensions; create table auth.users(id uuid primary key,email text);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
      create function extensions.gen_random_uuid() returns uuid language sql as $$select gen_random_uuid()$$;
      set request.jwt.claim.role='service_role';`);
    const directory = new URL('../supabase/migrations/', import.meta.url);
    for (const name of (await readdir(directory)).filter((n) => n.endsWith('.sql')).sort()) {
      await db.exec((await readFile(new URL(name, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', ''));
    }
    await q('select public.ivmet_bootstrap_admin($1,$2)', [admin, 'Fixture aislado']);
    const [c1, c2, p1, p2, p3] = [uuid(), uuid(), uuid(), uuid(), uuid()];
    await q(`insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values
      ($1,1,'0001','Cliente uno',repeat('a',64)),($2,2,'0002','Cliente dos',repeat('b',64))`, [c1, c2]);
    await q(`insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values
      ($1,$4,'0001-01',repeat('a',64)),($2,$4,'0001-02',repeat('b',64)),($3,$5,'0002-01',repeat('c',64))`, [p1, p2, p3, c1, c2]);
    const scale = {};
    const catalog = [
      ['pending', c1, p1, 'READY', true], ['pendingRow', c1, p1, 'READY', true], ['suspended', c1, p2, 'READY', true],
      ['review', c1, p1, 'REQUIRES_REVIEW', true], ['enabled', c1, p2, 'READY', true], ['inactive', c1, p1, 'READY', false],
      ['other', c2, p3, 'READY', true],
    ];
    for (const [index, [key, client, plant, status, active]] of catalog.entries()) {
      scale[key] = uuid();
      await q(`insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,source_hash,estado_catalogo,activo)
        values($1,$2,$3,$4,$5,repeat('a',64),$6,$7)`,
      [scale[key], client, plant, index + 1, `${client === c1 ? '0001' : '0002'}-0${plant === p2 ? 2 : 1}-00${index + 1}`, status, active]);
    }
    await q(`insert into public.equipos_ivmet(equipo_id,habilitado,estado_configuracion) values
      ($1,false,'PENDING'),($2,false,'SUSPENDED'),($3,true,'READY')`, [scale.pendingRow, scale.suspended, scale.enabled]);
    // Expedientes y fichas mínimos: no hace falta reconstruir verificaciones completas para contar.
    scale.registered = uuid();
    await db.exec('set session_replication_role = replica');
    await q(`insert into public.equipos(id,cliente_id,planta_id,origen,cod_interno,source_hash,registrado_por,registrado_at)
      values($1,$2,$3,'CLIENTE','BAL-EMPRESA',repeat('c',64),gen_random_uuid(),now())`, [scale.registered, c1, p1]);
    const shared = `insert into public.casos_compartidos(alerta_id,verificacion_id,cliente_id,planta_id,equipo_id,autorizado_por,
      snapshot_hash,snapshot,mensaje,estado,visibilidad,retirado_at,retirado_por,motivo_retiro)
      values(gen_random_uuid(),gen_random_uuid(),$1,$2,$3,gen_random_uuid(),repeat('a',64),'{}','Caso',$4,$5,$6,$7,$8)`;
    await q(shared, [c1, p1, scale.pending, 'NEW', 'SHARED', null, null, null]);
    await q(shared, [c1, p1, scale.registered, 'NEW', 'SHARED', null, null, null]);
    await q(shared, [c1, p1, scale.pending, 'IN_REVIEW', 'SHARED', null, null, null]);
    await q(shared, [c1, p1, scale.pending, 'NEW', 'WITHDRAWN', new Date().toISOString(), uuid(), 'Retirado']);
    await q(shared, [c2, p3, scale.other, 'NEW', 'SHARED', null, null, null]);
    const update = `insert into public.actualizaciones_compartidas(equipo_id,cliente_id,planta_id,autorizado_por,snapshot,snapshot_hash,
      mensaje,estado,comentario,revisado_por) values($1,$2,$3,gen_random_uuid(),'{}',repeat('a',64),'Ficha',$4,$5,$6)`;
    await q(update, [scale.pending, c1, p1, 'NEW', null, null]);
    await q(update, [scale.pending, c1, p1, 'REVIEWED', 'Revisada', admin]);
    await db.exec('set session_replication_role = origin');

    await t.test('el directorio y la ficha cuentan solo lo compartido y sin revisar de cada cliente', async () => {
      const items = Object.fromEntries((await read('clients')).items.map((c) => [c.id, c]));
      assert.equal(items[c1].newCases, 2);
      assert.equal(items[c1].pendingUpdates, 1);
      assert.equal(items[c2].newCases, 1);
      assert.equal(items[c2].pendingUpdates, 0);
      assert.equal(items[c1].equipment, 5, 'la balanza registrada por la empresa sigue fuera del conteo');
      assert.deepEqual((await read('client', c1)).attention, { newCases: 2, pendingUpdates: 1 });
      assert.deepEqual((await read('client', c2)).attention, { newCases: 1, pendingUpdates: 0 });
    });

    await t.test('pendientes son las validadas y activas que nadie habilitó ni suspendió', async () => {
      assert.equal((await read('equipment', c1)).pendingEnable, 2);
      assert.equal((await read('equipment', c1, { plantId: p1 })).pendingEnable, 2);
      assert.equal((await read('equipment', c1, { plantId: p2 })).pendingEnable, 0);
      assert.equal((await read('equipment', c2)).pendingEnable, 1);
    });

    await t.test('habilitar una selección es idempotente y no toca otras balanzas', async () => {
      const request = uuid();
      const payload = { clientId: c1, enabled: true, ids: [scale.pending, scale.pendingRow] };
      const result = await mutate('equipment.bulk-configure', payload, request);
      assert.deepEqual(result, { requested: 2, changed: 2, enabled: true });
      assert.deepEqual(await mutate('equipment.bulk-configure', payload, request), result);
      await assert.rejects(mutate('equipment.bulk-configure', { ...payload, ids: [scale.pending] }, request), /IDEMPOTENCY_CONFLICT/);
      assert.deepEqual(await state(scale.pending), { habilitado: true, estado_configuracion: 'READY', v: 1 });
      assert.equal((await state(scale.pendingRow)).estado_configuracion, 'READY');
      assert.equal((await state(scale.suspended)).estado_configuracion, 'SUSPENDED');
      assert.equal(await state(scale.review), undefined);
      assert.equal(await state(scale.inactive), undefined);
      assert.equal(await state(scale.other), undefined, 'otro cliente no cambia');
      assert.equal((await read('equipment', c1)).pendingEnable, 0);
      const audit = await q(`select entidad_id from public.auditoria where accion='equipment.bulk-configure' and cliente_id=$1 order by 1`, [c1]);
      assert.deepEqual(audit.map((a) => a.entidad_id), [scale.pending, scale.pendingRow].sort());
      await assert.rejects(mutate('equipment.bulk-configure', { ...payload, clientId: uuid() }), /CLIENT_NOT_FOUND/);
      await assert.rejects(mutate('equipment.bulk-configure', { ...payload, clientId: 'no-uuid' }), /INVALID_REQUEST/);
    });

    await t.test('la selección se aplica completa o no se aplica', async () => {
      const before = await state(scale.suspended);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [scale.suspended, scale.review] }), /EQUIPMENT_REQUIRES_REVIEW/);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [scale.suspended, scale.inactive] }), /EQUIPMENT_REQUIRES_REVIEW/);
      assert.deepEqual(await state(scale.suspended), before, 'ninguna balanza cambia si una no cumple');
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [scale.suspended, scale.other] }), /EQUIPMENT_NOT_FOUND/);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: false, ids: [scale.registered] }), /CUSTOMER_REGISTERED_EQUIPMENT/);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [scale.suspended, scale.suspended] }), /DUPLICATE_EQUIPMENT/);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [] }), /INVALID_REQUEST/);
      await assert.rejects(mutate('equipment.bulk-configure', { clientId: c1, enabled: 'true', ids: [scale.suspended] }), /INVALID_REQUEST/);
      assert.deepEqual(await mutate('equipment.bulk-configure', { clientId: c1, enabled: true, ids: [scale.suspended, scale.enabled] }),
        { requested: 2, changed: 1, enabled: true });
      assert.deepEqual(await state(scale.enabled), { habilitado: true, estado_configuracion: 'READY', v: 1 }, 'la ya habilitada no cambia de versión');
      // Suspender también se permite en una balanza que luego pidió revisión en DataMET.
      assert.deepEqual(await mutate('equipment.bulk-configure', { clientId: c1, enabled: false, ids: [scale.enabled, scale.review] }),
        { requested: 2, changed: 2, enabled: false });
      assert.equal((await state(scale.review)).estado_configuracion, 'SUSPENDED');
      assert.equal((await read('equipment', c1)).pendingEnable, 0, 'la suspensión explícita no vuelve a pendientes');
    });

    await t.test('solo la gestión comercial habilita en lote', async () => {
      const payload = { clientId: c2, enabled: true, ids: [scale.other] };
      await q("select public.ivmet_ops_mutate($1,'staff.save',$2,$3)", [admin, { actor: 'RIMMET:soporte', name: 'Soporte', role: 'support', active: true }, uuid()]);
      await assert.rejects(mutate('equipment.bulk-configure', payload, uuid(), 'RIMMET:soporte'), /STAFF_PERMISSION_REQUIRED/);
      await assert.rejects(mutate('equipment.bulk-configure', payload, uuid(), 'RIMMET:desconocido'), /STAFF_ACCESS_DENIED/);
      assert.equal(await state(scale.other), undefined);
      // Las acciones previas siguen llegando por la cadena existente.
      await assert.rejects(mutate('equipment.configure', { id: scale.registered, clientId: c1, enabled: false, version: '0' }), /CUSTOMER_REGISTERED_EQUIPMENT/);
    });
  } finally {
    await db.close();
  }
});

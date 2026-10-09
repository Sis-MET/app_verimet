import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('eliminación de cuentas y empresas en PostgreSQL desechable', async (t) => {
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
  const read = async (section, filters = {}) => (await q('select public.ivmet_mobile_read($1,$2) r', [section, filters]))[0].r;
  const customer = async (action, payload, request = uuid()) =>
    (await q('select public.ivmet_customer_mutate($1,$2,$3) r', [action, payload, request]))[0].r;
  const team = async (actor, action, payload, request = uuid()) =>
    (await q('select public.ivmet_team_account($1,$2,$3,$4) r', [actor, action, payload, request]))[0].r;
  const remove = async (user, scope, origin = 'APP') =>
    (await q('select public.ivmet_account_delete($1,$2,$3) r', [user, scope, origin]))[0].r;
  // Lo que hace ivmet-account-delete con Auth: la cuenta queda con un correo interno.
  const closeAuth = async (ids) => {
    for (const id of ids) await q("update auth.users set email='deleted.'||id::text||'@users.ivmet.invalid' where id=$1", [id]);
  };
  const signup = async (email, company = 'Acme Alimentos') => {
    await service();
    const user = uuid();
    await q('insert into auth.users(id,email) values($1,$2)', [user, email]);
    const created = (await q('select public.ivmet_signup_complete($1,$2) r', [user, {
      email, company, name: 'Ana Pérez', plantName: 'Planta Norte', phone: '+591 70000000',
      city: 'Santa Cruz', country: 'Bolivia', acceptTerms: true, termsVersion: 'ivmet-terms-v1',
    }]))[0].r;
    return { user, ...created };
  };
  const member = async (manager, plant, username, role = 'cliente_operador') => {
    await service();
    const request = uuid(), payload = { username, name: `Nombre ${username}`, role, plantIds: [plant] };
    const reserved = await team(manager, 'reserve', payload, request);
    await q('insert into auth.users(id,email) values($1,$2)', [reserved.id, reserved.email]);
    await team(manager, 'create', payload, request);
    await q('update public.perfiles set debe_cambiar_password=false where id=$1', [reserved.id]);
    return reserved.id;
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
    // El plan gratuito admite dos usuarios: para el equipo de prueba hacen falta tres.
    await q(`update public.planes_comerciales set cuentas_incluidas=5,
      caracteristicas=jsonb_set(caracteristicas,'{features,customSchedules}','true')
      where caracteristicas->'catalog'->'selfService'='true'::jsonb`);

    const { user: owner, clientId: client, plantId: plant } = await signup('ana@acme.example');
    const operator = await member(owner, plant, 'operador.uno');
    const other = await member(owner, plant, 'operador.dos');
    await identity(owner);
    const equipment = (await customer('equipment.register', {
      plantId: plant, areaId: '', areaName: 'Despacho',
      data: { cod_interno: 'BAL-1', marca: 'Marca', modelo: 'M', serie: '', ubicacion: '', tipo: 'PLATFORM', clase: 'III', unidad: 'kg' },
      ranges: [{ capacity: '60', division: '0.01', interval: '0.01' }],
    })).id;
    await q('select public.ivmet_customer_assign_equipment($1,$2)', [{ userId: operator, plantId: plant, equipmentIds: [equipment] }, uuid()]);
    await q('select public.ivmet_customer_configure_checks($1,$2,$3)', [equipment, { tests: [{ type: 'linearity', tolerance: '0.5',
      schedule: { mode: 'rolling', unit: 'day', every: 30, warningDays: 5 } }] }, uuid()]);
    await customer('upgrade.request', { reason: 'EQUIPMENT', planId: '', message: 'Llamar a Ana al 70000000', phone: '70000000' });

    // Una verificación finalizada y un borrador del operador.
    await identity(operator);
    const bundle = await read('equipment', { equipmentId: equipment });
    const trial = bundle.plan.tests[0];
    const content = {
      tests: [{ id: trial.id, omitted: false, reason: '', readings: trial.points.map(p => ({ pointId: p.id, indication: p.load, zero: '' })) }],
      certificates: [], temperature: '21', humidity: '40', observations: '',
    };
    const draft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [uuid(), equipment, bundle.plan.id, 0, content, uuid()]))[0].r;
    const verification = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5) r',
      [draft.id, Number(draft.version), uuid(), 'fixture-1.0', 'fixture-device']))[0].r;
    const open = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [uuid(), equipment, bundle.plan.id, 0, content, uuid()]))[0].r;

    await t.test('solo el servidor elimina, y con alcance y origen válidos', async () => {
      await identity(operator);
      await assert.rejects(remove(operator, 'ACCOUNT'), /permission denied/);
      await service();
      await assert.rejects(remove(operator, 'TODO'), /INVALID_REQUEST/);
      await assert.rejects(remove(operator, 'ACCOUNT', 'CORREO'), /INVALID_REQUEST/);
      await assert.rejects(remove(uuid(), 'ACCOUNT'), /ACCOUNT_NOT_FOUND/);
    });

    let deletion;
    await t.test('un operador elimina su cuenta: sin acceso ni datos personales, con la evidencia intacta', async () => {
      await service();
      await assert.rejects(remove(operator, 'COMPANY'), /QUALITY_MANAGER_REQUIRED/);
      deletion = await remove(operator, 'ACCOUNT', 'WEB');
      assert.deepEqual(deletion.users, [operator]);
      assert.equal(deletion.replayed, false);
      assert.deepEqual(await remove(operator, 'ACCOUNT', 'WEB'), { ...deletion, replayed: true }, 'un doble envío no repite');

      const [profile] = await q('select usuario,nombre,activo from public.perfiles where id=$1', [operator]);
      assert.deepEqual(profile, { usuario: 'eliminado.' + operator.replaceAll('-', ''), nombre: 'Usuario eliminado', activo: false });
      assert.deepEqual(await q('select 1 from private.login_aliases where auth_user_id=$1', [operator]), []);
      assert.deepEqual(await q("select 1 from public.licencias_usuario where usuario_id=$1 and estado='ACTIVE'", [operator]), []);
      assert.deepEqual(await q('select 1 from public.usuario_equipos where usuario_id=$1', [operator]), []);
      assert.equal((await q('select estado from public.verificacion_borradores where id=$1', [open.id]))[0].estado, 'ABANDONED');
      // La verificación sigue ahí y apunta a un perfil anónimo.
      const [record] = await q(`select v.estado,p.nombre from public.verificaciones v join public.perfiles p on p.id=v.capturado_por
        where v.id=$1`, [verification.id]);
      assert.deepEqual(record, { estado: 'ACTIVE', nombre: 'Usuario eliminado' });
      const [entry] = await q('select alcance,origen,usuarios,auth_cerrado_at from private.eliminaciones_cuenta where id=$1', [deletion.deletionId]);
      assert.deepEqual(entry, { alcance: 'ACCOUNT', origen: 'WEB', usuarios: [operator], auth_cerrado_at: null });
      assert.deepEqual(await q('select id,usuarios from public.ivmet_account_deletions_pending(5)'),
        [{ id: deletion.deletionId, usuarios: [operator] }]);
      await q('select public.ivmet_account_deletion_done($1)', [deletion.deletionId]);
      assert.ok((await q('select auth_cerrado_at from private.eliminaciones_cuenta where id=$1', [deletion.deletionId]))[0].auth_cerrado_at);
      assert.deepEqual(await q('select id from public.ivmet_account_deletions_pending(5)'), []);
      await identity(operator);
      await assert.rejects(read('bootstrap'), /MOBILE_ACCESS_DENIED/);
      await identity(owner);
      const members = (await q("select public.ivmet_customer_read('members','{}') r"))[0].r;
      assert.equal(members.used, 2, 'libera el cupo');
    });

    await t.test('el único jefe de calidad no deja la empresa sin responsable', async () => {
      await service();
      await assert.rejects(remove(owner, 'ACCOUNT'), /LAST_QUALITY_MANAGER/);
    });

    let company;
    await t.test('el jefe elimina la empresa completa', async () => {
      await service();
      company = await remove(owner, 'COMPANY');
      assert.deepEqual([...company.users].sort(), [operator, other, owner].sort(), 'todas las cuentas de la empresa, también las ya eliminadas');
      assert.deepEqual(await q("select usuario from public.perfiles where cliente_id=$1 and usuario not like 'eliminado.%'", [client]), []);
      assert.deepEqual(await q('select 1 from private.login_aliases la join public.perfiles p on p.id=la.auth_user_id where p.cliente_id=$1', [client]), []);
      const [row] = await q('select nombre,activo from public.clientes where id=$1', [client]);
      assert.deepEqual(row, { nombre: 'Empresa eliminada', activo: false });
      assert.deepEqual(await q('select 1 from private.empresas_autoregistro where cliente_id=$1', [client]), []);
      assert.deepEqual((await q('select distinct estado from public.contratos where cliente_id=$1', [client])).map(r => r.estado), ['CANCELLED']);
      const [request] = await q('select estado,contacto_nombre,contacto_correo,contacto_telefono,mensaje from public.solicitudes_plan where cliente_id=$1', [client]);
      assert.deepEqual(request, { estado: 'CANCELLED', contacto_nombre: 'Empresa eliminada', contacto_correo: null, contacto_telefono: null, mensaje: '' });
      assert.equal((await q('select count(*)::int n from public.verificaciones where cliente_id=$1', [client]))[0].n, 1, 'la evidencia se conserva');
      assert.deepEqual(await q('select 1 from private.sync_outbox o where not o.privacy_blocked and private.outbox_client(o.aggregate_type,o.payload)=$1', [client]), []);
      await identity(owner);
      await assert.rejects(read('bootstrap'), /MOBILE_ACCESS_DENIED/);
    });

    await t.test('el mismo correo puede registrar otra empresa', async () => {
      await service();
      await closeAuth(company.users);
      assert.equal((await q('select public.ivmet_signup_status($1) r', ['ana@acme.example']))[0].r.registered, false);
      const again = await signup('ana@acme.example', 'Acme Nueva');
      assert.notEqual(again.clientId, client);
    });

    await t.test('en una empresa de Métrica solo se elimina la propia cuenta, y el espejo la recibe anónima', async () => {
      await service();
      const legacy = uuid(), legacyPlant = uuid();
      await q("insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,77,'0077','Legado',repeat('a',64))", [legacy]);
      await q("insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values($1,$2,'0077-01',repeat('a',64))", [legacyPlant, legacy]);
      const plan = await mutate('plan.save', { name: 'Legado', seats: 5, graceDays: 0 });
      const today = (await q('select current_date::text d'))[0].d;
      const endsOn = (await q("select (current_date+interval '2 years')::date::text d"))[0].d;
      const price = await mutate('price.create', { planId: plan.id, periodicity: 'MONTHLY', currency: 'BOB', amount: '0', startsOn: today });
      await mutate('contract.create', { clientId: legacy, priceId: price.id, number: 'LEG-C', invoiceNumber: 'LEG-F', signedOn: today, startsOn: today, endsOn });
      const subscription = (await q('select s.id from public.suscripciones s join public.contratos c on c.id=s.contrato_id where c.cliente_id=$1', [legacy]))[0].id;
      const request = uuid(), payload = { clientId: legacy, username: 'jefe.legado', name: 'Jefe Legado', role: 'cliente_jefe_calidad', plantIds: [legacyPlant] };
      const u = await mutate('user.reserve', payload, request);
      await q('insert into auth.users(id,email) values($1,$2)', [u.id, u.email]);
      await mutate('user.create', payload, request);
      await mutate('license.assign', { id: u.id, clientId: legacy, subscriptionId: subscription });
      await q('update public.perfiles set debe_cambiar_password=false where id=$1', [u.id]);
      await assert.rejects(remove(u.id, 'COMPANY'), /SELF_SERVICE_REQUIRED/);
      await remove(u.id, 'ACCOUNT');
      const [event] = await q(`select payload->>'nombre' nombre from private.sync_outbox
        where aggregate_type='public.perfiles' and payload->>'id'=$1 and not privacy_blocked order by created_at desc limit 1`, [u.id]);
      assert.equal(event.nombre, 'Usuario eliminado');
      assert.equal((await q('select activo from public.clientes where id=$1', [legacy]))[0].activo, true);
    });
  } finally {
    await db.close();
  }
});

import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('contrato administrativo de RimMET sobre PostgreSQL aislado', async (t) => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema extensions;
      create table auth.users(id uuid primary key, email text);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
      create function extensions.gen_random_uuid() returns uuid language sql as $$select gen_random_uuid()$$;
      set request.jwt.claim.role='service_role';`);
    const directory = fileURLToPath(
      new URL('../supabase/migrations/', import.meta.url),
    );
    for (const name of (await readdir(directory))
      .filter((n) => n.endsWith('.sql'))
      .sort()) {
      if (name === '202608270003_generated_plan_codes.sql') {
        // Simula un plan creado antes del despliegue. El código debe sobrevivir.
        await db.exec(`insert into public.planes_comerciales(codigo,nombre,cuentas_incluidas)
          values ('PLAN-000123','Plan anterior',5),('LEGADO','Otro plan anterior',2);`);
      }
      const sql = (await readFile(`${directory}/${name}`, 'utf8')).replace(
        'create extension if not exists pgcrypto with schema extensions;',
        '',
      );
      try {
        await db.exec(sql);
      } catch (error) {
        throw new Error(`${name}: ${error.message}`, { cause: error });
      }
    }
    await db.query('select public.ivmet_bootstrap_admin($1,$2)', ['RIMMET:test','Administrador de pruebas']);
    const c1 = randomUUID(),
      c2 = randomUUID(),
      p1 = randomUUID(),
      p2 = randomUUID(),
      equipment = randomUUID();
    await db.query(
      `insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values ($1,1,'0001','Prueba A',repeat('a',64)),($2,2,'0002','Prueba B',repeat('b',64))`,
      [c1, c2],
    );
    await db.query(
      `insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values ($1,$2,'0001-01',repeat('a',64)),($3,$4,'0002-01',repeat('b',64))`,
      [p1, c1, p2, c2],
    );
    await db.query(
      `insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,source_hash,estado_catalogo) values ($1,$2,$3,1,'0001-01-001',repeat('a',64),'REQUIRES_REVIEW')`,
      [equipment, c1, p1],
    );
    const today = (await db.query('select current_date::text as d')).rows[0].d;
    const yearEnd = (
      await db.query(
        "select (current_date+interval '2 years')::date::text as d",
      )
    ).rows[0].d;
    const mutate = async (action, payload, id = randomUUID()) =>
      (
        await db.query(
          'select public.ivmet_admin_mutate($1,$2,$3,$4) as result',
          ['RIMMET:test', action, payload, id],
        )
      ).rows[0].result;
    const read = async (section, clientId = null, filters = {}) =>
      (
        await db.query('select public.ivmet_admin_read($1,$2,$3) as result', [
          section,
          clientId,
          filters,
        ])
      ).rows[0].result;
    let plan, price, contract, workspace, user, subscription;
    await t.test(
      'códigos generados, únicos, inmutables e idempotentes; conserva planes previos',
      async () => {
        assert.equal(
          (
            await db.query(
              "select count(*)::int as n from public.planes_comerciales where codigo in ('PLAN-000123','LEGADO')",
            )
          ).rows[0].n,
          2,
        );
        const payload = {
          name: 'Autogenerado',
          seats: 5,
          graceDays: 0,
          active: true,
        };
        // Las migraciones posteriores siembran planes (el gratuito y los que
        // ofrece la app): la numeración sigue al último código generado.
        const last = (
          await db.query(
            "select max(substring(codigo from 6)::int)::int as n from public.planes_comerciales where codigo ~ '^PLAN-[0-9]+$'",
          )
        ).rows[0].n;
        assert.ok(last >= 123);
        const code = (n) => `PLAN-${String(n).padStart(6, '0')}`;
        const request = randomUUID();
        const created = await mutate('plan.save', payload, request);
        assert.equal(created.codigo, code(last + 1));
        assert.deepEqual(await mutate('plan.save', payload, request), created);
        const second = await mutate('plan.save', {
          ...payload,
          code: 'MANUAL-IGNORADO',
        });
        assert.equal(second.codigo, code(last + 2));
        const batch = await Promise.all(
          Array.from({ length: 5 }, (_, i) =>
            mutate('plan.save', { ...payload, name: `Plan ${i}` }),
          ),
        );
        assert.equal(
          new Set([created, second, ...batch].map((p) => p.codigo)).size,
          7,
        );
        const edited = await mutate('plan.save', {
          ...payload,
          id: created.id,
          version: String(created.row_version),
          name: 'Renombrado',
          code: 'NO-CAMBIAR',
        });
        assert.equal(edited.codigo, created.codigo);
        await assert.rejects(
          db.query(
            'update public.planes_comerciales set codigo=$1 where id=$2',
            ['OTRO', created.id],
          ),
          /PLAN_CODE_IMMUTABLE/,
        );
        const prior = (
          await db.query(
            "select * from public.planes_comerciales where codigo='LEGADO'",
          )
        ).rows[0];
        const priorEdited = await mutate('plan.save', {
          ...payload,
          id: prior.id,
          version: String(prior.row_version),
        });
        assert.equal(priorEdited.codigo, 'LEGADO');
        assert.equal(
          (
            await db.query(
              "select has_sequence_privilege('authenticated','private.plan_code_seq','USAGE') as allowed",
            )
          ).rows[0].allowed,
          false,
        );
        assert.equal(
          (
            await db.query(
              "select has_sequence_privilege('service_role','private.plan_code_seq','UPDATE') as allowed",
            )
          ).rows[0].allowed,
          false,
        );
        await db.exec('set role service_role');
        try {
          const viaApiRole = await mutate('plan.save', {
            ...payload,
            name: 'Rol real del API',
          });
          assert.match(viaApiRole.codigo, /^PLAN-\d{6,}$/);
        } finally {
          await db.exec('reset role');
        }
      },
    );
    await t.test(
      'plan, tarifa exacta y contrato pendiente de pago',
      async () => {
        plan = await mutate('plan.save', {
          code: 'TEST',
          name: 'Prueba',
          description: 'Plan de prueba',
          seats: 1,
          graceDays: 3,
        });
        price = await mutate('price.create', {
          planId: plan.id,
          periodicity: 'MONTHLY',
          currency: 'BOB',
          amount: '100.10',
          startsOn: today,
        });
        contract = await mutate('contract.create', {
          clientId: c1,
          priceId: price.id,
          number: 'C-001',
          invoiceNumber: 'F-001',
          signedOn: today,
          startsOn: today,
          endsOn: yearEnd,
        });
        workspace = await read('client', c1);
        subscription = workspace.subscriptions[0];
        assert.equal(subscription.estado, 'PENDING');
        assert.equal(workspace.invoices[0].saldo, '100.10');
        assert.equal(subscription.seats, 0);
      },
    );
    await t.test(
      'pagos parciales, idempotencia y activación al completar saldo',
      async () => {
        let invoice = workspace.invoices[0];
        const requestId = randomUUID();
        const payload = {
          id: invoice.id,
          clientId: c1,
          version: String(invoice.row_version),
          amount: '40.05',
          paidOn: today,
          method: 'TRANSFER',
          reference: 'REC-1',
        };
        await mutate('payment.record', payload, requestId);
        await mutate('payment.record', payload, requestId);
        await assert.rejects(
          mutate('payment.record', { ...payload, amount: '40.06' }, requestId),
          /IDEMPOTENCY_CONFLICT/,
        );
        workspace = await read('client', c1);
        invoice = workspace.invoices[0];
        assert.equal(invoice.saldo, '60.05');
        assert.equal(invoice.payments.length, 1);
        assert.equal(workspace.subscriptions[0].estado, 'PENDING');
        await mutate('payment.record', {
          ...payload,
          version: String(invoice.row_version),
          amount: '60.05',
        });
        workspace = await read('client', c1);
        subscription = workspace.subscriptions[0];
        assert.equal(subscription.estado, 'ACTIVE');
        assert.equal(subscription.seats, 1);
      },
    );
    const createUser = async (username, plantId = p1) => {
      const requestId = randomUUID();
      const body = {
        clientId: c1,
        username,
        name: username,
        role: 'cliente_operador',
        plantIds: [plantId],
      };
      const reserved = await mutate('user.reserve', body, requestId);
      await db.query('insert into auth.users(id,email) values($1,$2)', [
        reserved.id,
        reserved.email,
      ]);
      await mutate('user.create', body, requestId);
      return reserved.id;
    };
    await t.test('alcance de planta, licencia y límite de cupos', async () => {
      await assert.rejects(createUser('wrong', p2), /PLANT_SCOPE_INVALID/);
      user = await createUser('operator');
      await mutate('license.assign', {
        id: user,
        clientId: c1,
        subscriptionId: subscription.id,
      });
      const second = await createUser('second');
      await assert.rejects(
        mutate('license.assign', {
          id: second,
          clientId: c1,
          subscriptionId: subscription.id,
        }),
        /LICENSE_SEATS_EXHAUSTED/,
      );
      await assert.rejects(
        mutate('license.revoke', {
          id: user,
          clientId: c2,
          reason: 'Intento cruzado',
        }),
        /USER_NOT_FOUND/,
      );
    });
    await t.test('lectura por cliente y paginación sin mezcla', async () => {
      assert.equal((await read('users', c1, { pageSize: 1 })).items.length, 1);
      assert.equal((await read('users', c2)).items.length, 0);
      assert.equal((await read('equipment', c1)).total, 1);
      assert.equal((await read('equipment', c2)).total, 0);
      assert.equal((await read('equipment', c1, { plantId: p2 })).total, 0);
    });
    await t.test(
      'equipo pendiente no puede habilitarse y versión obsoleta se rechaza',
      async () => {
        await assert.rejects(
          mutate('equipment.configure', {
            id: equipment,
            clientId: c1,
            version: '0',
            enabled: true,
          }),
          /EQUIPMENT_REQUIRES_REVIEW/,
        );
        await assert.rejects(
          mutate('plan.save', {
            id: plan.id,
            version: '0',
            name: 'viejo',
            seats: 1,
            graceDays: 0,
            active: true,
          }),
          /ROW_VERSION_CONFLICT/,
        );
      },
    );
    await t.test(
      'cupos adicionales pendientes no se asignan antes del pago',
      async () => {
        workspace = await read('client', c1);
        subscription = workspace.subscriptions[0];
        const purchase = await mutate('seats.purchase', {
          id: subscription.id,
          version: String(subscription.row_version),
          clientId: c1,
          seats: 2,
          amount: '25.50',
          invoiceNumber: 'F-ADD',
        });
        workspace = await read('client', c1);
        assert.equal(workspace.subscriptions[0].seats, 1);
        const invoice = workspace.invoices.find((i) => i.id === purchase.id);
        await mutate('payment.record', {
          id: invoice.id,
          version: String(invoice.row_version),
          clientId: c1,
          amount: '25.50',
          paidOn: today,
          method: 'TRANSFER',
          reference: 'REC-2',
        });
        assert.equal((await read('client', c1)).subscriptions[0].seats, 3);
      },
    );
    await t.test(
      'renovación anticipada no corta el período actual',
      async () => {
        workspace = await read('client', c1);
        subscription = workspace.subscriptions[0];
        const renewal = await mutate('subscription.renew', {
          id: subscription.id,
          version: String(subscription.row_version),
          clientId: c1,
          priceId: price.id,
          seats: 0,
          additionalAmount: '0.00',
          invoiceNumber: 'F-NEXT',
        });
        const invoice = (await read('client', c1)).invoices.find(
          (i) => i.id === renewal.id,
        );
        await mutate('payment.record', {
          id: invoice.id,
          version: String(invoice.row_version),
          clientId: c1,
          amount: invoice.total,
          paidOn: today,
          method: 'TRANSFER',
          reference: 'REC-3',
        });
        const renewed = (await read('client', c1)).subscriptions[0];
        assert.equal(renewed.inicio_periodo, subscription.inicio_periodo);
        assert.ok(renewed.fin_periodo > subscription.fin_periodo);
      },
    );
    await t.test(
      'vencimiento de adicionales impide exceder cupos en el acceso real',
      async () => {
        const second = (await read('users', c1)).items.find(
          (u) => u.usuario === 'second',
        );
        await mutate('license.assign', {
          id: second.id,
          clientId: c1,
          subscriptionId: subscription.id,
        });
        await db.query(
          'update public.perfiles set debe_cambiar_password=false where cliente_id=$1',
          [c1],
        );
        assert.equal(
          (await read('users', c1)).items.filter((u) => u.appAccess).length,
          2,
        );
        // Paso del tiempo simulado en el fixture; no se reescribe evidencia real.
        await db.query(
          "update public.suscripcion_cupos set vigente_desde=now()-interval '2 days',vigente_hasta=now()-interval '1 day' where suscripcion_id=$1 and tipo='ADDITIONAL'",
          [subscription.id],
        );
        assert.equal(
          (await read('users', c1)).items.filter((u) => u.appAccess).length,
          1,
        );
        await mutate('license.revoke', {
          id: second.id,
          clientId: c1,
          reason: 'Fin de prueba de cupos',
        });
      },
    );
    await t.test('RimMET habilita sin plan y no gestiona configuración privada', async () => {
      for (const action of ['area.save','pattern.save','certificate.create','certificate.annul']) {
        await assert.rejects(mutate(action,{clientId:c1}), /CUSTOMER_MANAGED_CONFIGURATION/);
      }
      await db.query("update public.equipos set estado_catalogo='READY' where id=$1",[equipment]);
      const payload={id:equipment,clientId:c1,version:'0',enabled:true};
      const request=randomUUID();
      await mutate('equipment.configure',payload,request);
      await mutate('equipment.configure',payload,request);
      const configured=(await read('equipment',c1)).items[0];
      assert.equal(configured.habilitado,true);
      assert.equal(configured.area_id,undefined);
      assert.equal(configured.plan_version_id,undefined);
      await assert.rejects(mutate('equipment.configure',{...payload,version:configured.config_version,areaId:randomUUID()}),/CUSTOMER_MANAGED_CONFIGURATION/);
      assert.deepEqual((await read('client',c1)).patterns,[]);
      assert.deepEqual((await read('client',c1)).metrologyPlans,[]);
    });
    await t.test(
      'anular factura inicial cierra el alta impagada y permite corregirla',
      async () => {
        await mutate('contract.create', {
          clientId: c2,
          priceId: price.id,
          number: 'C-BAD',
          invoiceNumber: 'F-BAD',
          signedOn: today,
          startsOn: today,
          endsOn: yearEnd,
        });
        const initial = await read('client', c2);
        const sub = initial.subscriptions[0];
        const invoice = initial.invoices[0];
        await assert.rejects(
          mutate('subscription.state', {
            id: sub.id,
            clientId: c2,
            version: String(sub.row_version),
            state: 'SUSPENDED',
            reason: 'No eludir pago inicial',
          }),
          /SUBSCRIPTION_NOT_PAID/,
        );
        await mutate('invoice.void', {
          id: invoice.id,
          clientId: c2,
          version: String(invoice.row_version),
          reason: 'Documento equivocado',
        });
        assert.equal(
          (await read('client', c2)).contracts[0].estado,
          'CANCELLED',
        );
        await mutate('contract.create', {
          clientId: c2,
          priceId: price.id,
          number: 'C-GOOD',
          invoiceNumber: 'F-GOOD',
          signedOn: today,
          startsOn: today,
          endsOn: yearEnd,
        });
        assert.equal(
          (await read('client', c2)).contracts.filter(
            (c) => c.estado === 'ACTIVE',
          ).length,
          1,
        );
      },
    );
    await t.test(
      'revocar licencia y cancelar conserva evidencia y auditoría',
      async () => {
        await mutate('license.revoke', {
          id: user,
          clientId: c1,
          reason: 'Baja solicitada',
        });
        assert.equal(
          (await read('users', c1)).items.find((u) => u.id === user).license,
          null,
        );
        workspace = await read('client', c1);
        subscription = workspace.subscriptions[0];
        await mutate('subscription.state', {
          id: subscription.id,
          clientId: c1,
          version: String(subscription.row_version),
          state: 'CANCELLED',
          reason: 'Fin del piloto',
        });
        assert.equal(
          (await read('client', c1)).contracts[0].estado,
          'CANCELLED',
        );
        assert.ok((await read('activity', c1)).items.length > 0);
      },
    );
    await t.test(
      'planes de cortesía permiten renovar sin simular pagos',
      async () => {
        const free = await mutate('price.create', {
          planId: plan.id,
          periodicity: 'ANNUAL',
          currency: 'BOB',
          amount: '0.00',
          startsOn: today,
        });
        await mutate('contract.create', {
          clientId: c1,
          priceId: free.id,
          number: 'C-FREE',
          invoiceNumber: 'F-FREE',
          signedOn: today,
          startsOn: today,
          endsOn: yearEnd,
        });
        const freeSub = (await read('client', c1)).subscriptions.find(
          (s) => s.estado === 'ACTIVE',
        );
        const renewed = await mutate('subscription.renew', {
          id: freeSub.id,
          clientId: c1,
          version: String(freeSub.row_version),
          priceId: free.id,
          seats: 0,
          additionalAmount: '0.00',
          invoiceNumber: 'F-FREE-NEXT',
        });
        const freeInvoice = (await read('client', c1)).invoices.find(
          (f) => f.id === renewed.id,
        );
        assert.equal(freeInvoice.estado, 'PAID');
        assert.equal(freeInvoice.payments.length, 0);
      },
    );
    await t.test(
      'incorporación y ampliación selectiva conservan el alcance previo',
      async () => {
        const payload = {
          legacyClientId: 1,
          clientCode: '0001',
          plantCodes: ['0001-01'],
          equipmentCodes: ['0001-01-001'],
          paidConfirmed: true,
          reason: 'Piloto contratado',
        };
        await assert.rejects(
          mutate('scope.request', {
            ...payload,
            equipmentCodes: ['0002-01-001'],
          }),
          /PLANT_SCOPE_INVALID/,
        );
        await mutate('scope.request', payload);
        const scope = (await read('integration')).scopes[0];
        await assert.rejects(
          mutate('scope.extend', { ...payload, id: scope.id, version: '0' }),
          /ROW_VERSION_CONFLICT/,
        );
        await mutate('scope.extend', {
          ...payload,
          id: scope.id,
          version: String(scope.row_version),
          plantCodes: ['0001-02'],
          equipmentCodes: ['0001-02-002'],
        });
        const expanded = (await read('integration')).scopes[0];
        assert.equal(expanded.equipmentCount, 2);
        assert.deepEqual(expanded.plants.sort(), ['0001-01', '0001-02']);
        assert.equal(
          (await db.query('select count(*)::integer as n from public.equipos'))
            .rows[0].n,
          1,
        );
      },
    );
    const claim = async (scopeId) =>
      (
        await db.query(
          'select public.claim_ivmet_catalog_job($1,$2,300) as result',
          ['worker-test', scopeId],
        )
      ).rows[0].result;
    const finish = async (job, clientId, status = 'SUCCEEDED', rejected = 0) =>
      (
        await db.query(
          'select public.finish_ivmet_catalog_job($1,$2,$3,3,$4,0,$5,null,300,60) as result',
          [job.run_id, clientId, status, 3 - rejected, rejected],
        )
      ).rows[0].result;
    const pendingPayload = {
      legacyClientId: 103,
      clientCode: '0103',
      clientName: 'Cliente pendiente',
      plantCodes: ['0103-11'],
      equipmentCodes: ['0103-11-001'],
      paidConfirmed: true,
      reason: 'Contrato de prueba autorizado',
    };
    let queued, job, importedId;
    await t.test(
      'la solicitud aparece inmediatamente y la repetición no crea otra incorporación',
      async () => {
        const requestId = randomUUID();
        queued = await mutate('scope.request', pendingPayload, requestId);
        assert.deepEqual(
          await mutate(
            'scope.request',
            { ...pendingPayload, clientName: 'Nombre actualizado' },
            requestId,
          ),
          queued,
        );
        await assert.rejects(
          mutate('scope.request', pendingPayload),
          /SCOPE_ALREADY_EXISTS/,
        );
        const directory = await read('clients', null, { search: '0103' });
        assert.equal(directory.total, 1);
        assert.equal(directory.items[0].id, null);
        assert.equal(directory.items[0].nombre, 'Cliente pendiente');
        assert.equal(directory.items[0].onboarding.syncStatus, 'QUEUED');
        assert.equal(
          (await read('onboarding', null, { legacyClientId: 103 })).scopes[0]
            .id,
          queued.id,
        );
        assert.equal(
          (await read('onboarding', null, { legacyClientId: 999 })).scopes
            .length,
          0,
        );
      },
    );
    await t.test(
      'reclamación exclusiva, renovación y alcance exacto',
      async () => {
        [job] = await Promise.all([claim(queued.id), claim(queued.id)]).then(
          (jobs) => {
            assert.equal(jobs.filter(Boolean).length, 1);
            return jobs.filter(Boolean);
          },
        );
        assert.deepEqual(job.equipment_codes, ['0103-11-001']);
        assert.equal(await claim(queued.id), null);
        assert.equal(
          (await read('onboarding', null, { scopeId: queued.id })).scopes[0]
            .syncStatus,
          'RUNNING',
        );
        assert.equal(
          (
            await db.query(
              'select public.renew_ivmet_catalog_job($1,300) as ok',
              [job.run_id],
            )
          ).rows[0].ok,
          true,
        );
        await assert.rejects(
          mutate('scope.retry', {
            id: queued.id,
            reason: 'No debe duplicar un intento activo',
          }),
          /SCOPE_NOT_RETRYABLE/,
        );
      },
    );
    await t.test(
      'una ampliación concurrente no se pierde al finalizar el intento anterior',
      async () => {
        importedId = randomUUID();
        await db.query(
          "insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,103,'0103','Cliente importado',repeat('c',64))",
          [importedId],
        );
        const scope = (await read('onboarding', null, { scopeId: queued.id }))
          .scopes[0];
        await mutate('scope.extend', {
          ...pendingPayload,
          id: queued.id,
          version: scope.row_version,
          plantCodes: ['0103-21'],
          equipmentCodes: ['0103-21-001'],
        });
        assert.equal(await finish(job, importedId), true);
        const status = (await read('onboarding', null, { scopeId: queued.id }))
          .scopes[0];
        assert.equal(status.syncStatus, 'QUEUED');
        assert.equal(status.motivo, pendingPayload.reason);
        assert.equal(status.estado, 'REQUESTED');
        assert.equal(
          (await read('clients', null, { search: '0103' })).total,
          1,
        );
        job = await claim(queued.id);
        assert.deepEqual(job.equipment_codes, ['0103-11-001', '0103-21-001']);
        assert.equal(await finish(job, importedId), true);
        assert.equal(
          (await read('onboarding', null, { scopeId: queued.id })).scopes[0]
            .syncStatus,
          'SUCCEEDED',
        );
        assert.equal(
          (await read('onboarding', null, { scopeId: queued.id })).scopes[0]
            .estado,
          'ACTIVE',
        );
        assert.equal(await claim(queued.id), null);
      },
    );
    await t.test(
      'recupera un proceso caído y rechaza el cierre o renovación del propietario anterior',
      async () => {
        await db.query(
          "update private.catalog_jobs set next_attempt_at=now()-interval '1 minute' where scope_id=$1",
          [queued.id],
        );
        const abandoned = await claim(queued.id);
        await db.query(
          "update private.catalog_jobs set lease_until=now()-interval '1 second' where scope_id=$1",
          [queued.id],
        );
        assert.equal(
          (await read('onboarding', null, { scopeId: queued.id })).scopes[0]
            .syncStatus,
          'RETRYING',
        );
        job = await claim(queued.id);
        assert.notEqual(job.run_id, abandoned.run_id);
        assert.equal(await finish(abandoned, importedId), false);
        assert.equal(
          (
            await db.query(
              'select public.renew_ivmet_catalog_job($1,300) as ok',
              [abandoned.run_id],
            )
          ).rows[0].ok,
          false,
        );
        assert.equal(
          (
            await db.query('select estado from private.sync_runs where id=$1', [
              abandoned.run_id,
            ])
          ).rows[0].estado,
          'FAILED',
        );
        assert.equal(await finish(job, importedId, 'PARTIAL', 1), true);
        assert.equal(await claim(queued.id), null);
      },
    );
    await t.test(
      'reintento auditado e idempotente, sin activar licencias ni borrar incidencias',
      async () => {
        const requestId = randomUUID();
        const payload = { id: queued.id, reason: 'Datos revisados en DataMET' };
        const response = await mutate('scope.retry', payload, requestId);
        assert.deepEqual(
          await mutate('scope.retry', payload, requestId),
          response,
        );
        await assert.rejects(
          mutate('scope.retry', { ...payload, reason: 'distinto' }, requestId),
          /IDEMPOTENCY_CONFLICT/,
        );
        assert.equal(
          (await read('onboarding', null, { scopeId: queued.id })).scopes[0]
            .syncStatus,
          'QUEUED',
        );
        assert.equal(
          (
            await db.query(
              "select count(*)::int as n from public.auditoria where accion='scope.retry' and entidad_id=$1",
              [queued.id],
            )
          ).rows[0].n,
          1,
        );
        assert.equal(
          (
            await db.query(
              'select count(*)::int as n from public.perfiles where cliente_id=$1',
              [importedId],
            )
          ).rows[0].n,
          0,
        );
        job = await claim(queued.id);
        await db.query(
          "select public.record_ivmet_sync_quarantine($1,'EQUIPMENT','0103-11-001','EQUIPMENT_AMBIGUOUS','internal-secret-host','{}',repeat('a',64))",
          [job.run_id],
        );
        await finish(job, importedId, 'PARTIAL', 1);
        const status = (await read('onboarding', null, { scopeId: queued.id }))
          .scopes[0];
        assert.equal(status.issueCount, 1);
        assert.equal(status.issues[0].reason_code, 'EQUIPMENT_AMBIGUOUS');
        assert.ok(!JSON.stringify(status).includes('internal-secret-host'));
      },
    );
    await t.test(
      'la disponibilidad exige un daemon reciente; health no registra latidos',
      async () => {
        assert.equal(
          (await db.query('select public.ivmet_worker_contract() as n')).rows[0]
            .n,
          4,
        );
        assert.equal((await read('integration')).workers.length, 0);
        const instance = randomUUID();
        await db.query(
          "select public.report_ivmet_worker('worker-test',$1,'once','ONLINE',null,10)",
          [instance],
        );
        assert.equal((await read('integration')).workers[0].available, false);
        await db.query(
          "select public.report_ivmet_worker('worker-test',$1,'daemon','ONLINE',null,10)",
          [instance],
        );
        assert.equal((await read('integration')).workers[0].available, true);
        await db.exec(
          "update private.worker_heartbeats set last_seen_at=now()-interval '5 minutes'",
        );
        assert.equal((await read('integration')).workers[0].available, false);
        for (const signature of [
          'public.claim_ivmet_catalog_job(text,uuid,integer)',
          'public.renew_ivmet_catalog_job(uuid,integer)',
          'public.report_ivmet_worker(text,uuid,text,text,uuid,integer)',
        ]) {
          assert.equal(
            (
              await db.query(
                "select has_function_privilege('authenticated',$1,'execute') as ok",
                [signature],
              )
            ).rows[0].ok,
            false,
          );
        }
        assert.equal(
          (
            await db.query(
              "select has_table_privilege('service_role','private.catalog_jobs','update') as ok",
            )
          ).rows[0].ok,
          false,
        );
        assert.equal(
          (
            await db.query(
              "select has_function_privilege('service_role','private.ivmet_admin_mutate(text,text,jsonb,uuid)','execute') as ok",
            )
          ).rows[0].ok,
          false,
        );
      },
    );
    await t.test(
      'funciones administrativas denegadas a clientes móviles',
      async () => {
        assert.equal(
          (
            await db.query(
              "select has_function_privilege('authenticated','public.ivmet_admin_mutate(text,text,jsonb,uuid)','execute') as allowed",
            )
          ).rows[0].allowed,
          false,
        );
        await db.exec("set request.jwt.claim.role='authenticated'");
        await assert.rejects(read('integration'), /ADMIN_REQUIRED/);
      },
    );
  } finally {
    await db.close();
  }
});

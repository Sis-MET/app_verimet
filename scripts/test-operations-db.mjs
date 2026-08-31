import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('privacidad, consentimiento y operaciones en PostgreSQL aislado', async (t) => {
  const db = new PGlite(),
    admin = 'RIMMET:admin';
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const op = async (action, payload, actor = admin, request = uuid()) =>
    (
      await q('select public.ivmet_ops_mutate($1,$2,$3,$4) r', [
        actor,
        action,
        payload,
        request,
      ])
    )[0].r;
  const read = async (section, filters = {}, actor = admin) =>
    (
      await q('select public.ivmet_ops_read($1,$2,$3) r', [
        actor,
        section,
        filters,
      ])
    )[0].r;
  const mutate = async (action, payload, request = uuid()) =>
    (
      await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [
        admin,
        action,
        payload,
        request,
      ])
    )[0].r;
  const identity = async (id = '', role = 'service_role') =>
    q(
      "select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role',$2,false)",
      [id, role],
    );
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema extensions; create table auth.users(id uuid primary key,email text);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
      create function extensions.gen_random_uuid() returns uuid language sql as $$select gen_random_uuid()$$;
      set request.jwt.claim.role='service_role';`);
    const directory = new URL('../supabase/migrations/', import.meta.url);
    for (const name of (await readdir(directory))
      .filter((n) => n.endsWith('.sql'))
      .sort()) {
      if (name === '202608280001_private_evidence_and_cases.sql')
        await db.exec(`insert into private.sync_outbox(aggregate_type,aggregate_key,operation,payload,estado)
          values('public.lecturas','{}','I','{"private":"never-export"}','DEAD');`);
      await db.exec(
        (await readFile(new URL(name, directory), 'utf8')).replace(
          'create extension if not exists pgcrypto with schema extensions;',
          '',
        ),
      );
    }
    await q('select public.ivmet_bootstrap_admin($1,$2)', [
      admin,
      'Admin aislado',
    ]);
    const client = uuid(),
      other = uuid(),
      plant = uuid(),
      otherPlant = uuid(),
      equipment = uuid();
    await q(
      `insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values($1,1,'0001','Uno',repeat('a',64)),($2,2,'0002','Dos',repeat('b',64))`,
      [client, other],
    );
    await q(
      `insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values($1,$2,'0001-01',repeat('a',64)),($3,$4,'0002-01',repeat('b',64))`,
      [plant, client, otherPlant, other],
    );
    await q(
      `insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,source_hash,estado_catalogo) values($1,$2,$3,1,'0001-01-001',repeat('a',64),'READY')`,
      [equipment, client, plant],
    );
    const today = (await q('select current_date::text d'))[0].d;
    const nextYear = (
      await q("select (current_date+interval '2 years')::date::text d")
    )[0].d;
    const commercial = await mutate('plan.save', {
      name: 'Cortesía aislada',
      seats: 5,
      graceDays: 0,
    });
    const price = await mutate('price.create', {
      planId: commercial.id,
      periodicity: 'MONTHLY',
      currency: 'BOB',
      amount: '0',
      startsOn: today,
    });
    await mutate('contract.create', {
      clientId: client,
      priceId: price.id,
      number: 'C-TEST',
      invoiceNumber: 'F-TEST',
      signedOn: today,
      startsOn: today,
      endsOn: nextYear,
    });
    const subscription = (await q('select id from public.suscripciones'))[0].id;
    const user = async (name, role) => {
      const request = uuid(),
        payload = {
          clientId: client,
          username: name,
          name,
          role,
          plantIds: [plant],
        };
      const u = await mutate('user.reserve', payload, request);
      await q('insert into auth.users(id,email) values($1,$2)', [
        u.id,
        u.email,
      ]);
      await mutate('user.create', payload, request);
      await mutate('license.assign', {
        id: u.id,
        clientId: client,
        subscriptionId: subscription,
      });
      await q(
        'update public.perfiles set debe_cambiar_password=false where id=$1',
        [u.id],
      );
      return u.id;
    };
    const quality = await user('quality', 'cliente_jefe_calidad'),
      operator = await user('operator', 'cliente_operador');
    const definition = {
      name: 'Plan aislado',
      clientId: client,
      description: '',
      notes: '',
      procedureReference: 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
      tests: [
        {
          type: 'linearity',
          method: 'absolute_error',
          decisionRule: 'direct',
          toleranceSource: 'CLIENT_PROCESS',
          uncertainty: '',
          unit: 'kg',
          frequencyDays: 30,
          warningDays: 5,
          points: Array.from({length:5},(_,index) => ({
            code: `P${index+1}`,
            label: `Carga ${index+1}`,
            group: 1,
            load: index === 0 ? '0.123456789' : `${index}`,
            tolerance: '0.000000001',
            position: '',
            direction: 'ascending',
            metadata: {},
          })),
        },
      ],
    };
    let plan;
    const customerOp = async (action,payload) => {
      await identity(quality,'authenticated');
      return (await q('select public.ivmet_customer_mutate($1,$2,$3) r',[action.replace('metrology.','plan.'),payload,uuid()]))[0].r;
    };
    await t.test(
      'permisos específicos, bootstrap único y último administrador',
      async () => {
        await assert.rejects(
          q('select public.ivmet_bootstrap_admin($1,$2)', [
            'RIMMET:otro',
            'Otro',
          ]),
          /ADMIN_ALREADY_BOOTSTRAPPED/,
        );
        await op('staff.save', {
          actor: 'RIMMET:soporte',
          name: 'Soporte',
          role: 'support',
          active: true,
        });
        await op('staff.save', {
          actor: 'RIMMET:comercial',
          name: 'Comercial',
          role: 'commercial',
          active: true,
        });
        await assert.rejects(
          read('cases', {}, 'RIMMET:comercial'),
          /STAFF_PERMISSION_REQUIRED/,
        );
        await assert.rejects(
          read('billing', {}, 'RIMMET:soporte'),
          /STAFF_PERMISSION_REQUIRED/,
        );
        await assert.rejects(
          read('session', {}, 'RIMMET:desconocido'),
          /STAFF_ACCESS_DENIED/,
        );
        await assert.rejects(
          op('staff.save', {
            actor: admin,
            name: 'Admin',
            role: 'support',
            active: true,
            version: '1',
          }),
          /LAST_ADMIN_REQUIRED/,
        );
      },
    );
    await t.test(
      'decimales exactos, versión optimista y rechazo de fórmulas arbitrarias',
      async () => {
        await assert.rejects(op('metrology.save',definition), /CUSTOMER_MANAGED_CONFIGURATION/);
        await assert.rejects(read('metrology'), /CUSTOMER_MANAGED_CONFIGURATION/);
        await mutate('equipment.configure',{id:equipment,clientId:client,version:'0',enabled:true});
        plan = await customerOp('metrology.save', definition);
        const record = (await q("select public.ivmet_customer_read('plan',$1) r",[{id:plan.id}]))[0].r;
        assert.equal(record.tests[0].points[0].carga_nominal, '0.123456789');
        await assert.rejects(
          customerOp('metrology.save', {
            ...definition,
            id: plan.id,
            version: record.draft_revision,
            name: 'Nombre alterado',
          }),
          /PLAN_NAME_IS_IMMUTABLE/,
        );
        await assert.rejects(customerOp('metrology.save', {
          ...definition,
          name: 'Fórmula arbitraria',
          procedureReference: 'FIXTURE-NOT-OFFICIAL',
        }), /NORMATIVE_PROFILE_REQUIRED/);
        await assert.rejects(
          customerOp('metrology.save', { ...definition, id: plan.id, version: '999' }),
          /ROW_VERSION_CONFLICT/,
        );
        await assert.rejects(
          customerOp('metrology.save', {
            ...definition,
            name: 'Decimal numérico',
            tests: [
              {
                ...definition.tests[0],
                points: definition.tests[0].points.map((point,index) =>
                  index === 0 ? {...point,load:0.1} : point),
              },
            ],
          }),
          /EXACT_DECIMAL_REQUIRED/,
        );
        await customerOp('metrology.publish', { id: plan.id, version: '1' });
        await assert.rejects(
          customerOp('metrology.save', { ...definition, id: plan.id, version: '1' }),
          /PUBLISHED_PLAN_IS_IMMUTABLE/,
        );
        await customerOp('equipment.validate',{id:equipment,version:'0',catalogHash:'a'.repeat(64),areaId:'',
          data:{ubicacion:'Mi área',cod_interno:'',marca:'',modelo:'',serie:''}});
        await customerOp('metrology.assign', {
          equipmentId: equipment,
          planVersionId: plan.id,
        });
        const next = await customerOp('metrology.save', {
          ...definition,
          planId: record.plan_id,
        });
        await assert.rejects(
          q(
            'update public.plan_pruebas set plan_version_id=$1 where plan_version_id=$2',
            [next.id, plan.id],
          ),
          /PUBLISHED_PLAN_IS_IMMUTABLE/,
        );
        await assert.rejects(
          q(
            'update public.plan_puntos set carga_nominal=1 where plan_prueba_id in(select id from public.plan_pruebas where plan_version_id=$1)',
            [plan.id],
          ),
          /PUBLISHED_PLAN_IS_IMMUTABLE/,
        );
        await identity();
      },
    );
    const verification = uuid(),
      alert = uuid(),
      trial = uuid();
    const planTrial = (
      await q('select id from public.plan_pruebas where plan_version_id=$1', [
        plan.id,
      ])
    )[0].id;
    // Datos sintéticos insertados por el dueño de la BD de pruebas, no por la app.
    await q(
      `insert into public.verificaciones(id,request_uuid,payload_hash,cliente_id,planta_id,equipo_id,plan_version_id,capturado_por,finalizado_por,
      realizado_at,alcance,veredicto_global,trazabilidad,equipo_snapshot,plan_snapshot,observaciones)
      values($1,$2,repeat('c',64),$3,$4,$5,$6,$7,$7,now(),'complete','fail','traceable','{"codigo":"0001-01-001"}','{}','PRIVATE-SENTINEL')`,
      [verification, uuid(), client, plant, equipment, plan.id, quality],
    );
    await q(
      `insert into public.pruebas(id,verificacion_id,plan_prueba_id,tipo,estado_ejecucion,metodo_evaluacion,unidad,veredicto)
      values($1,$2,$3,'linearity','executed','absolute_error','kg','fail')`,
      [trial, verification, planTrial],
    );
    await q(
      `insert into public.lecturas(id,prueba_id,grupo,orden,punto_codigo,etiqueta,carga_nominal,indicacion,error,tolerancia,veredicto)
      values($1,$2,1,1,'P1','Prueba',0.123456789,0.123456799,0.000000010,0.000000001,'fail')`,
      [uuid(), trial],
    );
    await q(
      `insert into public.alertas(id,verificacion_id,cliente_id,planta_id,equipo_id,tipo,resumen) values($1,$2,$3,$4,$5,'FAILED','Prueba')`,
      [alert, verification, client, plant, equipment],
    );
    await q(
      `insert into public.auditoria(actor_id,cliente_id,entidad,entidad_id,accion,despues) values($1,$2,'lectura','test','PRIVATE','{"private":"PRIVATE-SENTINEL"}')`,
      [quality, client],
    );
    await t.test(
      'no exporta evidencia ni auditoría; eventos privados antiguos no bloquean catálogos',
      async () => {
        const events = await q(
          "select * from public.claim_ivmet_sync_outbox('fixture',500)",
        );
        assert.ok(events.length > 0);
        assert.ok(!JSON.stringify(events).includes('PRIVATE-SENTINEL'));
        assert.ok(
          !events.some((e) =>
            [
              'public.lecturas',
              'public.alertas',
              'public.verificaciones',
              'public.auditoria',
            ].includes(e.aggregate_type),
          ),
        );
        assert.equal(
          (
            await q(
              "select privacy_blocked from private.sync_outbox where aggregate_type='public.lecturas'",
            )
          )[0].privacy_blocked,
          true,
        );
        assert.equal((await read('cases')).total, 0);
        const integration = (
          await q("select public.ivmet_admin_read('integration',null,'{}') r")
        )[0].r;
        assert.equal(integration.outbox.DEAD, undefined);
        assert.equal(
          (
            await q(
              "select has_table_privilege('service_role','public.verificaciones','SELECT') allowed",
            )
          )[0].allowed,
          false,
        );
        await db.exec('set role service_role');
        await assert.rejects(
          q('select * from public.verificaciones'),
          /permission denied/,
        );
        await db.exec('reset role');
      },
    );
    let preview, shared;
    await t.test(
      'solo jefe autorizado, vista previa, hash confirmado y reintentos idempotentes',
      async () => {
        await identity(operator, 'authenticated');
        await assert.rejects(
          q('select public.preview_ivmet_alert_share($1)', [alert]),
          /QUALITY_MANAGER_REQUIRED/,
        );
        await identity(quality, 'authenticated');
        preview = (
          await q('select public.preview_ivmet_alert_share($1) p', [alert])
        )[0].p;
        assert.equal(
          preview.snapshot.pruebas[0].lecturas[0].error,
          '0.000000010',
        );
        await assert.rejects(
          q('select public.confirm_ivmet_alert_share($1,$2,$3,$4)', [
            alert,
            preview.alertVersion,
            '0'.repeat(64),
            'Evaluación',
          ]),
          /SHARE_PREVIEW_CHANGED/,
        );
        shared = (
          await q('select public.confirm_ivmet_alert_share($1,$2,$3,$4) c', [
            alert,
            preview.alertVersion,
            preview.snapshotHash,
            'Evaluación',
          ])
        )[0].c;
        const retry = (
          await q('select public.confirm_ivmet_alert_share($1,$2,$3,$4) c', [
            alert,
            preview.alertVersion,
            preview.snapshotHash,
            'Evaluación',
          ])
        )[0].c;
        assert.equal(shared.id, retry.id);
        assert.equal(
          (await q('select count(*)::int n from public.casos_compartidos'))[0]
            .n,
          1,
        );
        await identity();
      },
    );
    await t.test(
      'RLS real limita la evidencia y los casos al cliente, planta y licencia vigentes',
      async () => {
        await identity(quality, 'authenticated');
        await db.exec('set role authenticated');
        assert.equal(
          (await q('select count(*)::int n from public.verificaciones'))[0].n,
          1,
        );
        assert.equal(
          (await q('select count(*)::int n from public.casos_compartidos'))[0]
            .n,
          1,
        );
        await assert.rejects(
          q('select public.ivmet_case_delivery($1)', [shared.id]),
          /permission denied/,
        );
        await assert.rejects(
          q('select public.acknowledge_ivmet_alert($1,1)', [alert]),
          /permission denied/,
        );
        await db.exec('reset role');
        await q(
          'update public.usuario_plantas set activa=false where usuario_id=$1',
          [quality],
        );
        await db.exec('set role authenticated');
        assert.equal(
          (await q('select count(*)::int n from public.verificaciones'))[0].n,
          0,
        );
        assert.equal(
          (await q('select count(*)::int n from public.casos_compartidos'))[0]
            .n,
          0,
        );
        await assert.rejects(
          q('select public.preview_ivmet_alert_share($1)', [alert]),
          /ALERT_NOT_ACCESSIBLE/,
        );
        await db.exec('reset role');
        await q(
          'update public.usuario_plantas set activa=true where usuario_id=$1',
          [quality],
        );
        await q(
          'update public.perfiles set debe_cambiar_password=true where id=$1',
          [quality],
        );
        await db.exec('set role authenticated');
        assert.equal(
          (await q('select count(*)::int n from public.caso_eventos'))[0].n,
          0,
        );
        await db.exec('reset role');
        await q(
          'update public.perfiles set debe_cambiar_password=false where id=$1',
          [quality],
        );
        // Una identidad sin perfil del cliente nunca obtiene filas aunque adivine UUID.
        await identity(uuid(), 'authenticated');
        await db.exec('set role authenticated');
        assert.equal(
          (
            await q(
              'select count(*)::int n from public.verificaciones where id=$1',
              [verification],
            )
          )[0].n,
          0,
        );
        await db.exec('reset role');
        await identity();
      },
    );
    await t.test(
      'expediente acotado, aislamiento, seguimiento y auditoría sin snapshots',
      async () => {
        assert.equal((await read('cases', { clientId: other })).total, 0);
        assert.equal((await read('cases', { plantId: otherPlant })).total, 0);
        const inbox = await read('cases', { pageSize: 1 }, 'RIMMET:soporte');
        assert.equal(inbox.total, 1);
        const detail = await read('case', { id: shared.id }, 'RIMMET:soporte');
        assert.equal(detail.snapshot.verificacion.id, verification);
        const request = uuid(),
          change = {
            id: shared.id,
            version: detail.row_version,
            status: 'IN_REVIEW',
            assignee: 'RIMMET:soporte',
            comment: 'Se revisará con el cliente.',
          };
        await op('case.update', change, 'RIMMET:soporte', request);
        await op('case.update', change, 'RIMMET:soporte', request);
        await assert.rejects(
          op('case.update', change, 'RIMMET:soporte'),
          /ROW_VERSION_CONFLICT/,
        );
        assert.equal((await read('case', { id: shared.id })).eventos.length, 2);
        assert.ok(
          !JSON.stringify(await read('audit')).includes('PRIVATE-SENTINEL'),
        );
      },
    );
    await t.test(
      'retirada oculta el caso y neutraliza la cola conservando la evidencia',
      async () => {
        const before = await read('case', { id: shared.id });
        await identity(quality, 'authenticated');
        await q('select public.withdraw_ivmet_case($1,$2,$3)', [
          shared.id,
          before.row_version,
          'Retiro de prueba',
        ]);
        await identity();
        assert.equal((await read('cases')).total, 0);
        await assert.rejects(
          read('case', { id: shared.id }),
          /CASE_NOT_ACCESSIBLE/,
        );
        const queue = (
          await q("select * from public.claim_ivmet_sync_outbox('fixture',500)")
        ).filter((e) => e.aggregate_type === 'public.casos_compartidos');
        assert.ok(queue.length > 0);
        assert.ok(
          queue.every(
            (e) =>
              e.payload.snapshot === null &&
              e.payload.visibilidad === 'WITHDRAWN',
          ),
        );
        for (const event of queue) {
          const original = (
            await q(
              "select encode(sha256(convert_to(payload::text,'UTF8')),'hex') hash from private.sync_outbox where event_id=$1",
              [event.event_id],
            )
          )[0];
          assert.equal(event.payload._event_payload_hash, original.hash);
        }
        assert.equal(
          (await q('select public.ivmet_case_delivery($1) r', [shared.id]))[0].r
            .snapshot,
          null,
        );
        assert.equal(
          (
            await q(
              'select count(*)::int n from public.verificaciones where id=$1',
              [verification],
            )
          )[0].n,
          1,
        );
      },
    );
    await t.test(
      'checklist, cobros y privacidad no requieren resultados privados',
      async () => {
        const ready = await read('readiness', { clientId: client });
        assert.equal(ready.total, 1);
        assert.equal(ready.items[0].contract, true);
        assert.equal(ready.items[0].users, true);
        assert.equal((await read('billing')).total, 0);
        assert.equal((await read('privacy')).privateEvidenceExport, false);
        await identity(quality, 'authenticated');
        await assert.rejects(
          read('case', { id: shared.id }),
          /STAFF_ACCESS_DENIED/,
        );
        await identity();
      },
    );
  } finally {
    await db.close();
  }
});

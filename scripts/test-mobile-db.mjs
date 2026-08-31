import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID as uuid } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

test('contrato móvil online en PostgreSQL desechable, sin conexiones reales', async (t) => {
  const db = new PGlite();
  const q = async (sql, params = []) => (await db.query(sql, params)).rows;
  const admin = 'RIMMET:fixture';
  const mutate = async (action, payload) => (await q('select public.ivmet_admin_mutate($1,$2,$3,$4) r', [admin, action, payload, uuid()]))[0].r;
  const read = async (section, filters = {}) => (await q('select public.ivmet_mobile_read($1,$2) r', [section, filters]))[0].r;
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
    await t.test('fórmulas doradas OIML R 76 y regla de decisión ILAC', async () => {
      const values = (await q(`select
        private.oiml_r76_mpe(50,0.1,'III',true)::text mpe_500e,
        private.oiml_r76_mpe(200,0.1,'III',true)::text mpe_2000e,
        private.oiml_r76_mpe(1000,0.1,'III',true)::text mpe_10000e,
        private.decision_verdict(0.8,1,'guard_band',0.1) guarded_pass,
        private.decision_verdict(0.95,1,'guard_band',0.1) guarded_inconclusive,
        private.decision_verdict(1.2,1,'guard_band',0.1) guarded_fail,
        private.mass_convert(1000,'g','kg')::text converted`))[0];
      assert.deepEqual(values, {
        mpe_500e: '0.10', mpe_2000e: '0.20', mpe_10000e: '0.30',
        guarded_pass: 'pass', guarded_inconclusive: 'inconclusive', guarded_fail: 'fail', converted: '1.00000000000000000000',
      });
    });
    await q('select public.ivmet_bootstrap_admin($1,$2)', [admin, 'Fixture aislado']);
    const client = uuid(), other = uuid(), plant = uuid(), hiddenPlant = uuid(), otherPlant = uuid(), equipment = uuid(), hiddenEquipment = uuid();
    await q(`insert into public.clientes(id,legacy_cliente_id,codigo,nombre,source_hash) values
      ($1,1,'0001','Cliente móvil',repeat('a',64)),($2,2,'0002','Cliente ajeno',repeat('b',64))`, [client, other]);
    await q(`insert into public.plantas(id,cliente_id,legacy_codigo_planta,source_hash) values
      ($1,$2,'0001-01',repeat('a',64)),($3,$2,'0001-02',repeat('b',64)),($4,$5,'0002-01',repeat('c',64))`, [plant, client, hiddenPlant, otherPlant, other]);
    await q(`insert into public.equipos(id,cliente_id,planta_id,legacy_equipo_id,cod_metrica,source_hash) values
      ($1,$2,$3,1,'0001-01-001',repeat('a',64)),($4,$2,$5,2,'0001-02-001',repeat('b',64))`, [equipment, client, plant, hiddenEquipment, hiddenPlant]);
    await q(`insert into public.equipos_ivmet(equipo_id,habilitado,estado_configuracion) values($1,true,'READY'),($2,true,'READY')`, [equipment, hiddenEquipment]);
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
    const plan = uuid(), version = uuid(), trial = uuid(), point = uuid();
    await q('insert into public.planes(id,cliente_id,nombre) values($1,$2,$3)', [plan, client, 'Plan SOLO fixture']);
    await q('insert into public.plan_versiones(id,plan_id,version) values($1,$2,1)', [version, plan]);
    await q(`insert into public.plan_pruebas(id,plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias)
      values($1,$2,'linearity','absolute_error','kg',30)`, [trial, version]);
    await q(`insert into public.plan_puntos(id,plan_prueba_id,orden,codigo,etiqueta,carga_nominal,tolerancia)
      values($1,$2,1,'P1','Carga',9999999999.123456789,0.000000001)`, [point, trial]);
    // No se registra ningún método como aprobado. La captura no finaliza pruebas.
    await q("update public.plan_versiones set estado='PUBLISHED',published_by=$2,published_at=now() where id=$1", [version, quality]);
    await q("insert into public.equipo_planes(equipo_id,plan_version_id,vigente_desde) values($1,$2,now()-interval '1 day')", [equipment, version]);
    const pattern = uuid(), certificate = uuid();
    await q("insert into public.patrones(id,cliente_id,codigo,descripcion,tipo) values($1,$2,'PATRON','Patrón prueba','pesas')", [pattern, client]);
    await q('insert into public.patron_plantas(patron_id,planta_id) values($1,$2)', [pattern, plant]);
    await q("insert into public.patron_certificados(id,patron_id,numero,laboratorio,calibrado_el,vence_el) values($1,$2,'CERT','Fixture',current_date-100,current_date-1)", [certificate, pattern]);
    await identity(operator);
    await t.test('sesión, licencia, catálogos y paginación no mezclan plantas', async () => {
      assert.equal((await read('session')).access.allowed, true);
      const boot = await read('bootstrap');
      assert.deepEqual(boot.plants.map(p => p.id), [plant]);
      assert.equal(boot.equipmentCount, 1);
      assert.equal((await read('instruments', { plantId: hiddenPlant })).total, 0);
      assert.equal((await read('instruments', { page: 2, pageSize: 1 })).items.length, 0);
      await assert.rejects(read('equipment', { equipmentId: hiddenEquipment }), /EQUIPMENT_NOT_ACCESSIBLE/);
      const bundle = await read('equipment', { equipmentId: equipment });
      assert.equal(bundle.plan.tests[0].points[0].load, '9999999999.123456789');
      assert.equal(bundle.plan.finalizationEnabled, false);
      assert.equal(bundle.patterns[0].certificates[0].expired, true);
    });
    const content = { tests: [{ id: trial, omitted: false, reason: '', readings: [{ pointId: point, indication: '9999999999.123456788', zero: '-0.000000001' }] }],
      certificates: [certificate], temperature: '23.125', humidity: '50', observations: 'PRIVADO-MOVIL' };
    const request = uuid(), saveId = uuid();
    const save = async (data = content, expected = 0, mutation = saveId, req = request) =>
      (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r', [req, equipment, version, expected, data, mutation]))[0].r;
    let draft;
    await t.test('borrador exacto, certificado vencido, UUID idempotente y conflicto', async () => {
      await assert.rejects(save(), /EQUIPMENT_VALIDATION_REQUIRED/);
      await q('select public.ivmet_customer_mutate($1,$2,$3)', ['equipment.validate', {id:equipment,version:'0',catalogHash:'a'.repeat(64),areaId:'',
        data:{ubicacion:'',cod_interno:'',marca:'',modelo:'',serie:''}}, uuid()]);
      draft = await save();
      assert.equal(draft.version, '1');
      assert.deepEqual(await save(), draft);
      const saved = await read('draft', { id: draft.id });
      assert.deepEqual(saved.payload, content);
      assert.equal(saved.context_snapshot.plan.finalizationEnabled, false);
      await assert.rejects(save({ ...content, observations: 'otro' }), /IDEMPOTENCY_CONFLICT/);
      await assert.rejects(save(content, 5, uuid()), /ROW_VERSION_CONFLICT/);
      assert.equal((await read('history')).total, 0);
      await identity('', 'service_role');
      assert.equal((await q("select count(*)::int n from private.sync_outbox where payload::text like '%PRIVADO-MOVIL%'"))[0].n, 0);
      await identity(operator);
    });
    await t.test('decimales numéricos, puntos ajenos, omisiones sin motivo y veredictos se rechazan', async () => {
      const numeric = structuredClone(content); numeric.tests[0].readings[0].indication = 0.1;
      await assert.rejects(save(numeric, 1, uuid()), /INVALID_DECIMAL_STRING/);
      const wrongPoint = structuredClone(content); wrongPoint.tests[0].readings[0].pointId = uuid();
      await assert.rejects(save(wrongPoint, 1, uuid()), /INVALID_POINT/);
      const omitted = structuredClone(content); omitted.tests[0] = { id: trial, omitted: true, reason: '', readings: [] };
      await assert.rejects(save(omitted, 1, uuid()), /OMISSION_REASON_REQUIRED/);
      await assert.rejects(save({ ...content, verdict: 'pass' }, 1, uuid()), /INVALID_DRAFT_CONTENT/);
      await assert.rejects(save({ ...content, tests: [] }, 1, uuid()), /INVALID_DRAFT_CONTENT/);
      omitted.tests[0].reason = 'No se dispone de carga';
      assert.equal((await save(omitted, 1, uuid())).version, '2');
    });
    await t.test('otro usuario, permiso REST y clave de worker no pueden alterar un borrador', async () => {
      await identity(quality);
      assert.equal((await read('drafts')).total, 0);
      await assert.rejects(read('draft', { id: draft.id }), /DRAFT_NOT_ACCESSIBLE/);
      await assert.rejects(save(), /DRAFT_NOT_ACCESSIBLE/);
      await identity(operator);
      await assert.rejects(q("update public.verificacion_borradores set estado='FINALIZED' where id=$1", [draft.id]), /permission denied/);
      await identity('', 'service_role');
      await db.exec('set role service_role');
      await assert.rejects(read('bootstrap'), /permission denied/);
      await assert.rejects(q('select * from public.verificacion_borradores'), /permission denied/);
      await identity(operator);
    });
    await t.test('la versión retirada conserva el contexto de un borrador anterior', async () => {
      await identity('', 'service_role');
      await q("update public.plan_versiones set estado='RETIRED',retired_by=$2,retired_at=now() where id=$1", [version, quality]);
      await identity(operator);
      assert.equal((await read('equipment', { equipmentId: equipment })).plan, null);
      assert.equal((await save(content, 2, uuid())).version, '3');
      await assert.rejects(save(content, 0, uuid(), uuid()), /PLAN_NOT_ASSIGNED/);
      assert.equal((await read('draft', { id: draft.id })).context_snapshot.plan.state, 'PUBLISHED');
    });
    await t.test('detalle privado, decimales exactos y aislamiento de historial', async () => {
      await identity('', 'service_role');
      const verification = uuid(), hiddenVerification = uuid(), acceptedTrial = uuid();
      for (const [id, eq, pl] of [[verification, equipment, plant], [hiddenVerification, hiddenEquipment, hiddenPlant]]) {
        await q(`insert into public.verificaciones(id,request_uuid,payload_hash,cliente_id,planta_id,equipo_id,plan_version_id,
          capturado_por,finalizado_por,realizado_at,alcance,veredicto_global,trazabilidad,equipo_snapshot,plan_snapshot)
          values($1,$2,repeat('f',64),$3,$4,$5,$6,$7,$7,now(),'partial','fail','non_traceable','{}','{}')`,
          [id, uuid(), client, pl, eq, version, quality]);
      }
      await q(`insert into public.pruebas(id,verificacion_id,plan_prueba_id,tipo,estado_ejecucion,metodo_evaluacion,unidad,veredicto)
        values($1,$2,$3,'linearity','executed','absolute_error','kg','fail')`, [acceptedTrial, verification, trial]);
      await q(`insert into public.lecturas(prueba_id,grupo,orden,punto_codigo,etiqueta,carga_nominal,indicacion,error,tolerancia,veredicto)
        values($1,1,1,'P1','Carga',9999999999.123456789,9999999999.123456788,-0.000000001,0.000000001,'fail')`, [acceptedTrial]);
      await q(`insert into public.alertas(verificacion_id,cliente_id,planta_id,equipo_id,tipo,resumen)
        values($1,$2,$3,$4,'FAILED','Solo cliente')`, [verification, client, plant, equipment]);
      await identity(operator);
      assert.equal((await read('history')).total, 1);
      const detail = await read('verification', { id: verification });
      assert.equal(detail.verification.alcance, 'partial');
      assert.equal(detail.tests[0].readings[0].indicacion, '9999999999.123456788');
      assert.equal(detail.alert.visibilidad_metrica, 'PRIVATE');
      assert.equal(detail.cases.length, 0);
      await assert.rejects(read('verification', { id: hiddenVerification }), /VERIFICATION_NOT_ACCESSIBLE/);
    });
    const customer = async (action, payload, request = uuid()) => (await q('select public.ivmet_customer_mutate($1,$2,$3) r', [action,payload,request]))[0].r;
    const setup = async (section, filters = {}) => (await q('select public.ivmet_customer_read($1,$2) r', [section,filters]))[0].r;
    let area, customerPattern, sharedUpdate;
    const equipmentData = { ubicacion:'PRIVADO-UBICACION-CLIENTE', cod_interno:'CLI-01', marca:'Cliente', modelo:'Confirmado', serie:'S-CLIENTE' };
    const validation = {id:equipment, version:'1', catalogHash:'a'.repeat(64), data:equipmentData, areaId:''};
    await t.test('sugerencias por planta, normalización y áreas privadas sin duplicados', async () => {
      await identity('', 'service_role');
      await q("update public.equipos set ubicacion='  Producción   Norte  ' where id=$1", [equipment]);
      await identity(operator);
      const suggestions = await setup('area-suggestions', {plantId:plant});
      assert.equal(suggestions.items[0].name,'Producción Norte');
      await assert.rejects(setup('areas',{plantId:hiddenPlant}), /PLANT_SCOPE_INVALID/);
      area = await customer('area.save',{plantId:plant,name:'Producción Norte',active:true});
      const same = await customer('area.save',{plantId:plant,name:'produccion  norte',active:true});
      assert.equal(same.id,area.id);
      assert.equal((await setup('areas',{plantId:plant})).total,1);
      assert.equal((await setup('area-suggestions',{plantId:plant})).total,0);
      assert.equal((await setup('equipment',{id:equipment})).suggestedAreaId,area.id);
      await assert.rejects(customer('area.save',{plantId:hiddenPlant,name:'Otra',active:true}), /PLANT_SCOPE_INVALID/);
      await identity('', 'service_role');
      assert.equal((await q("select count(*)::int n from private.sync_outbox where aggregate_type='public.areas' and not privacy_blocked"))[0].n,0);
      await assert.rejects(mutate('area.save',{clientId:client,plantId:plant,name:'Interna',active:true}), /CUSTOMER_MANAGED_CONFIGURATION/);
      await identity(operator);
    });
    await t.test('validar una balanza no modifica el maestro ni comparte sus correcciones', async () => {
      validation.areaId=area.id;
      const request=uuid();
      const result=await customer('equipment.validate',validation,request);
      assert.deepEqual(await customer('equipment.validate',validation,request),result);
      const detail=await read('equipment',{equipmentId:equipment});
      assert.equal(detail.equipment.ubicacion,equipmentData.ubicacion);
      assert.equal(detail.customerValidated,true);
      await assert.rejects(customer('equipment.validate',{...validation,data:{...equipmentData,serie:'otra'}},request),/IDEMPOTENCY_CONFLICT/);
      await assert.rejects(customer('equipment.validate',validation),/ROW_VERSION_CONFLICT/);
      await assert.rejects(customer('equipment.validate',{...validation,id:hiddenEquipment}),/EQUIPMENT_NOT_ACCESSIBLE/);
      await identity('', 'service_role');
      assert.notEqual((await q('select ubicacion from public.equipos where id=$1',[equipment]))[0].ubicacion,equipmentData.ubicacion);
      assert.equal((await q("select count(*)::int n from private.sync_outbox where payload::text like '%PRIVADO-UBICACION-CLIENTE%'"))[0].n,0);
      await q("update public.equipos set source_hash=repeat('b',64) where id=$1",[equipment]);
      await identity(operator);
      assert.equal((await read('equipment',{equipmentId:equipment})).customerValidated,false);
      assert.equal((await read('equipment',{equipmentId:equipment})).equipment.ubicacion,equipmentData.ubicacion);
      await assert.rejects(customer('equipment.validate',{...validation,version:'2'}),/CATALOG_CHANGED/);
      await identity('', 'service_role'); await q("update public.equipos set source_hash=repeat('a',64) where id=$1",[equipment]);
      await identity(operator);
    });
    await t.test('el cliente gestiona patrones y certificados sin acceso a plantas ajenas', async () => {
      const p={code:'CLIENTE-P',description:'PRIVADO-PATRON',type:'pesas',class:'M1',unit:'kg',capacity:'0.123456789',active:true,plantIds:[plant]};
      customerPattern=await customer('pattern.save',p);
      await assert.rejects(customer('pattern.save',{...p,code:'MIXTO',plantIds:[plant,hiddenPlant]}),/PLANT_SCOPE_INVALID/);
      await assert.rejects(customer('pattern.save',{...p,code:'NUMERICO',capacity:0.1}),/EXACT_DECIMAL_REQUIRED/);
      const cert=await customer('certificate.create',{patternId:customerPattern.id,number:'CLIENTE-CERT',lab:'Mi laboratorio',calibratedOn:'2025-01-01',expiresOn:'2025-12-31'});
      await customer('certificate.annul',{id:cert.id,version:'1',reason:'Corrección documental'});
      const stored=(await setup('patterns')).items.find(p=>p.id===customerPattern.id);
      assert.equal(stored.capacidad,'0.123456789'); assert.equal(stored.certificates[0].estado,'ANNULLED');
      await assert.rejects(customer('certificate.annul',{id:cert.id,version:'1',reason:'Reintento distinto'}),/ROW_VERSION_CONFLICT/);
      await identity('', 'service_role');
      await q('insert into public.patron_plantas(patron_id,planta_id) values($1,$2)',[customerPattern.id,hiddenPlant]);
      await identity(operator);
      assert.equal((await setup('patterns')).items.find(p=>p.id===customerPattern.id).canEdit,false);
      await assert.rejects(customer('pattern.save',{...p,id:customerPattern.id,version:'1'}),/PATTERN_ALL_PLANTS_REQUIRED/);
    });
    await t.test('vista previa, consentimiento específico, idempotencia y retirada del envío', async () => {
      await assert.rejects(setup('share-preview',{id:equipment}),/QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      const preview=await setup('share-preview',{id:equipment});
      assert.equal(preview.snapshot.customer.ubicacion,equipmentData.ubicacion);
      assert.ok(!JSON.stringify(preview).includes('PRIVADO-PATRON'));
      const share={id:equipment,hash:preview.hash,message:'Preparar siguiente calibración',consentVersion:preview.consentVersion,consent:true};
      await assert.rejects(customer('update.share',{...share,consent:false}),/EXPLICIT_CONSENT_REQUIRED/);
      await assert.rejects(customer('update.share',{...share,hash:'0'.repeat(64)}),/SHARE_PREVIEW_CHANGED/);
      const request=uuid(); sharedUpdate=await customer('update.share',share,request);
      assert.deepEqual(await customer('update.share',share,request),sharedUpdate);
      await customer('equipment.validate',{...validation,version:'2',data:{...equipmentData,serie:'CAMBIO-NO-COMPARTIDO'}});
      await identity('', 'service_role');
      const inbox=(await q("select public.ivmet_ops_read($1,'equipment-updates','{}') r",[admin]))[0].r;
      assert.equal(inbox.total,1); assert.equal(inbox.items[0].snapshot.customer.serie,'S-CLIENTE');
      await q("select public.ivmet_ops_mutate($1,'equipment-update.review',$2,$3)",[admin,{id:sharedUpdate.id,version:'1',comment:'Revisado para próxima visita'},uuid()]);
      const queue=await q("select * from public.claim_ivmet_sync_outbox('test-customer',500)");
      assert.ok(queue.some(e=>e.aggregate_type==='public.actualizaciones_compartidas'));
      assert.ok(!JSON.stringify(queue).includes('CAMBIO-NO-COMPARTIDO'));
      assert.ok(!JSON.stringify(queue).includes('PRIVADO-PATRON'));
      await identity(quality);
      const item=(await setup('updates',{id:equipment})).items[0]; assert.equal(item.estado,'REVIEWED');
      await customer('update.withdraw',{id:sharedUpdate.id,version:item.row_version,reason:'Retiro de acceso'});
      await identity('', 'service_role');
      assert.equal((await q('select public.ivmet_equipment_update_delivery($1) r',[sharedUpdate.id]))[0].r.snapshot,null);
      assert.equal((await q("select public.ivmet_ops_read($1,'equipment-updates','{}') r",[admin]))[0].r.total,0);
      await db.exec('set role service_role');
      for (const table of ['equipos_cliente','areas','patrones','planes','actualizaciones_compartidas']) await assert.rejects(q(`select * from public.${table}`),/permission denied/);
      await assert.rejects(setup('equipment',{id:equipment}),/permission denied/);
      await identity(operator);
    });
    await t.test('plan normativo finaliza evidencia inmutable, trazable e idempotente', async () => {
      await identity(quality);
      const validCertificate = await customer('certificate.create', {
        patternId: pattern,
        number: 'CERT-VIGENTE',
        lab: 'Laboratorio trazable',
        calibratedOn: (await q("select (current_date-interval '1 day')::date::text d"))[0].d,
        expiresOn: (await q("select (current_date+interval '1 year')::date::text d"))[0].d,
      });
      const loads = ['0', '25', '50', '75', '100'];
      const normative = await customer('plan.save', {
        name: 'Control interno plataforma',
        procedureReference: 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
        notes: 'Fixture normativo',
        tests: [{
          type: 'linearity', frequencyDays: '30', warningDays: '5', unit: 'kg',
          decisionRule: 'direct', toleranceSource: 'CLIENT_PROCESS', uncertainty: '',
          points: loads.map((load, index) => ({
            group: '1', code: `L${index + 1}`, label: `Carga ${load} kg`, load,
            tolerance: '0.5', position: '', direction: '', metadata: {},
          })),
        }, {
          type: 'repeatability', frequencyDays: '15', warningDays: '3', unit: 'kg',
          decisionRule: 'direct', toleranceSource: 'CLIENT_PROCESS', uncertainty: '',
          points: Array.from({length: 5}, (_, index) => ({
            group: '1', code: `R${index + 1}`, label: `Repetición ${index + 1}`, load: '50',
            tolerance: '0.5', position: '', direction: '', metadata: {},
          })),
        }],
      });
      const normativeVersion = normative.id;
      await customer('plan.publish', { id: normativeVersion, version: '1' });
      await customer('plan.assign', { equipmentId: equipment, planVersionId: normativeVersion });
      await identity(operator);
      const bundle = await read('equipment', { equipmentId: equipment });
      assert.equal(bundle.plan.finalizationEnabled, true);
      assert.equal(bundle.plan.claimScope, 'INTERNAL_CHECK_ONLY');
      const normativeTrial = bundle.plan.tests.find(test => test.type === 'linearity');
      const repeatabilityTrial = bundle.plan.tests.find(test => test.type === 'repeatability');
      assert.equal(normativeTrial.methodCode, 'EURAMET-CG18-V4-ERROR-INDICATION');
      const indications = ['0.1', '25.1', '49.9', '75.2', '100'];
      const normativeContent = {
        tests: [
          {
            id: normativeTrial.id, omitted: false, reason: '',
            readings: normativeTrial.points.map((p, index) => ({ pointId: p.id, indication: indications[index], zero: '' })),
          },
          {
            id: repeatabilityTrial.id, omitted: false, reason: '',
            readings: repeatabilityTrial.points.map((p, index) => ({
              pointId: p.id, indication: ['50', '50.1', '49.9', '50', '50.1'][index], zero: '',
            })),
          },
        ],
        certificates: [validCertificate.id], temperature: '22.5', humidity: '45', observations: 'CONTROL-INTERNO-PRIVADO',
      };
      const normativeDraft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r',
        [uuid(), equipment, normativeVersion, 0, normativeContent, uuid()]))[0].r;
      const finalizeId = uuid();
      const finalized = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5) r',
        [normativeDraft.id, Number(normativeDraft.version), finalizeId, 'fixture-1.0', 'fixture-device']))[0].r;
      assert.equal(finalized.verdict, 'pass');
      assert.equal(finalized.traceability, 'traceable');
      assert.equal(finalized.scope, 'complete');
      assert.equal(finalized.idempotent, false);
      const repeated = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5) r',
        [normativeDraft.id, Number(normativeDraft.version), finalizeId, 'fixture-1.0', 'fixture-device']))[0].r;
      assert.equal(repeated.id, finalized.id);
      assert.equal(repeated.idempotent, true);
      const stored = (await q(`select v.veredicto_global,v.trazabilidad,v.alcance,v.motor_version,
        p.error_max_abs::text,p.valor_metrica::text,count(l.id)::int readings
        from public.verificaciones v join public.pruebas p on p.verificacion_id=v.id
        join public.lecturas l on l.prueba_id=p.id where v.id=$1 and p.tipo='linearity'
        group by v.id,p.id`, [finalized.id]))[0];
      assert.deepEqual(stored, {
        veredicto_global: 'pass', trazabilidad: 'traceable', alcance: 'complete', motor_version: 'ivmet-internal-1.0.0',
        error_max_abs: '0.200000000', valor_metrica: '0.200000000', readings: 5,
      });
      const schedule = (await read('equipment', { equipmentId: equipment })).schedule;
      assert.equal(schedule.length, 2);
      assert.ok(schedule.every(item => item.lastTraceableAt));
      await assert.rejects(q("update public.verificaciones set observaciones='alterada' where id=$1", [finalized.id]), /permission denied/);
      await db.exec('reset role');
      await assert.rejects(q("update public.verificaciones set observaciones='alterada' where id=$1", [finalized.id]), /ACCEPTED_EVIDENCE_IS_IMMUTABLE/);
      await identity(operator);
      await assert.rejects(q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5)',
        [normativeDraft.id, Number(normativeDraft.version), uuid(), 'fixture-1.0', 'fixture-device']), /FINALIZATION_CONFLICT/);

      const partialContent = {
        ...normativeContent,
        certificates: [certificate],
        tests: [
          {
            id: normativeTrial.id, omitted: false, reason: '',
            readings: normativeTrial.points.map((p, index) => ({
              pointId: p.id, indication: ['1', '26', '51', '76', '101'][index], zero: '',
            })),
          },
          { id: repeatabilityTrial.id, omitted: true, reason: 'Sin carga suficiente', readings: [] },
        ],
      };
      const partialDraft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r',
        [uuid(), equipment, normativeVersion, 0, partialContent, uuid()]))[0].r;
      const partial = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5) r',
        [partialDraft.id, Number(partialDraft.version), uuid(), 'fixture-1.0', 'fixture-device']))[0].r;
      assert.equal(partial.verdict, 'fail');
      assert.equal(partial.traceability, 'non_traceable');
      assert.equal(partial.scope, 'partial');
      assert.equal(partial.alertCreated, true);
      const privateAlert = (await q(`select a.tipo,a.visibilidad_metrica,
        count(*) filter(where p.estado_ejecucion='executed')::int executed,
        count(*) filter(where p.estado_ejecucion='omitted')::int omitted
        from public.alertas a join public.pruebas p on p.verificacion_id=a.verificacion_id
        where a.verificacion_id=$1 group by a.id`, [partial.id]))[0];
      assert.deepEqual(privateAlert, {
        tipo: 'FAILED_NON_TRACEABLE', visibilidad_metrica: 'PRIVATE', executed: 1, omitted: 1,
      });
      await identity('', 'service_role');
      assert.equal((await q(`select count(*)::int n from private.sync_outbox
        where aggregate_type in ('public.verificaciones','public.pruebas','public.lecturas') and not privacy_blocked`))[0].n, 0);
      await identity(operator);
    });
    await t.test('revocar planta o licencia corta el acceso real, no solo la interfaz', async () => {
      await identity('', 'service_role');
      await q('update public.usuario_plantas set activa=false where usuario_id=$1', [operator]);
      await identity(operator);
      assert.equal((await read('drafts')).total, 0);
      await assert.rejects(save(content, 3, uuid()), /DRAFT_NOT_ACCESSIBLE/);
      await assert.rejects(customer('area.save',{plantId:plant,name:'Sin permiso',active:true}),/PLANT_SCOPE_INVALID/);
      await identity('', 'service_role');
      await q('update public.perfiles set debe_cambiar_password=true where id=$1', [operator]);
      await identity(operator);
      assert.equal((await read('session')).access.reason, 'PASSWORD_CHANGE_REQUIRED');
      await assert.rejects(read('bootstrap'), /MOBILE_ACCESS_DENIED/);
      await assert.rejects(setup('patterns'), /MOBILE_ACCESS_DENIED/);
    });
  } finally { await db.close(); }
});

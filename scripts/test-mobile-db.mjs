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
    await q(`insert into public.equipo_rangos(equipo_id,numero_rango,unidad,capacidad_max,division_escala,source_hash)
      values($1,1,'kg',100,0.1,repeat('a',64)),($2,1,'kg',100,0.1,repeat('b',64))`, [equipment,hiddenEquipment]);
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
    // El jefe de calidad asigna las balanzas a cada operador; la de la planta
    // ajena no se vuelve visible por estar asignada.
    await q('insert into public.usuario_equipos(usuario_id,equipo_id) values($1,$2),($1,$3)', [operator, equipment, hiddenEquipment]);
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
      assert.equal(boot.plants[0].equipmentCount, 1);
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
      assert.equal((await read('equipment',{equipmentId:equipment})).customerUpdatePending,false);
      await identity(quality);
      await assert.rejects(q('select public.ivmet_customer_read($1,$2)', ['share-preview',{id:equipment}]), /NO_EQUIPMENT_CORRECTIONS/);
      await identity('', 'service_role');
      await q("update public.equipos set cod_interno='MASTER-01' where id=$1",[equipment]);
      await identity(operator);
      assert.equal((await read('instruments')).items[0].cod_interno,'MASTER-01');
      await identity('', 'service_role');
      await q('update public.equipos set cod_interno=null where id=$1',[equipment]);
      await identity(operator);
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
    const configureChecks = async (equipmentId, configuration, request = uuid()) =>
      (await q('select public.ivmet_customer_configure_checks($1,$2,$3) r', [equipmentId,configuration,request]))[0].r;
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
      assert.equal(detail.customerUpdatePending,true);
      const completeList=await read('instruments',{search:'producción norte'});
      assert.equal(completeList.total,1);
      assert.equal(completeList.items[0].cod_interno,'CLI-01');
      assert.equal(completeList.items[0].departamento,'Producción Norte');
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
      assert.equal((await read('equipment',{equipmentId:equipment})).customerUpdatePending,false);
      await customer('equipment.validate',{...validation,version:'2',data:{...equipmentData,serie:'CAMBIO-NO-COMPARTIDO'}});
      assert.equal((await read('equipment',{equipmentId:equipment})).customerUpdatePending,true);
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
    await t.test('configuración guiada finaliza evidencia inmutable, trazable e idempotente', async () => {
      const loads = ['0', '25', '50', '75', '100'];
      const guidedConfiguration = { tests: [{
        type: 'linearity', frequencyDays: '30', tolerance: '0.5', loads,
      }, {
        type: 'repeatability', frequencyDays: '15', tolerance: '0.5', load: '50', repetitions: '5',
      }] };
      await assert.rejects(customer('plan.save', {}), /LEGACY_PLAN_MANAGEMENT_DISABLED/);
      await assert.rejects(setup('plans'), /LEGACY_PLAN_MANAGEMENT_DISABLED/);
      await assert.rejects(configureChecks(equipment, guidedConfiguration), /QUALITY_MANAGER_REQUIRED/);
      await identity(quality);
      const validCertificate = await customer('certificate.create', {
        patternId: pattern,
        number: 'CERT-VIGENTE',
        lab: 'Laboratorio trazable',
        calibratedOn: (await q("select (current_date-interval '1 day')::date::text d"))[0].d,
        expiresOn: (await q("select (current_date+interval '1 year')::date::text d"))[0].d,
      });
      const configurationRequest = uuid();
      const normative = await configureChecks(equipment, guidedConfiguration, configurationRequest);
      assert.deepEqual(await configureChecks(equipment, guidedConfiguration, configurationRequest), normative);
      await assert.rejects(configureChecks(equipment, {
        tests: [{ type: 'linearity', frequencyDays: '30', tolerance: '0.6', loads }],
      }, configurationRequest), /IDEMPOTENCY_CONFLICT/);
      const normativeVersion = normative.configurationId;
      assert.equal(normative.state, 'PUBLISHED');
      assert.equal((await q('select count(*)::int n from public.equipo_planes where equipo_id=$1 and vigente_hasta is null',[equipment]))[0].n,1);
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

      // Sin señal: se midió hace una hora con un teléfono que atrasa 90 s, y
      // la configuración cambió mientras tanto. Llega ahora.
      const ago = seconds => new Date(Date.now() - seconds * 1000).toISOString();
      await identity(quality);
      const changed = await configureChecks(equipment, {
        tests: [{ type: 'linearity', frequencyDays: '30', tolerance: '0.6', loads }],
      });
      assert.notEqual(changed.configurationId, normativeVersion);
      await identity(operator);
      await assert.rejects(q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6) r',
        [uuid(), equipment, normativeVersion, 0, normativeContent, uuid()]), /PLAN_NOT_ASSIGNED/,
        'en línea, la configuración retirada ya no se usa');
      const offlineDraft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6,$7) r',
        [uuid(), equipment, normativeVersion, 0, normativeContent, uuid(), ago(2 * 3600)]))[0].r;
      const measured = ago(3600 + 90);
      const offline = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5,$6,$7) r',
        [offlineDraft.id, Number(offlineDraft.version), uuid(), 'fixture-1.0', 'fixture-device', measured, ago(90)]))[0].r;
      assert.equal(offline.verdict, 'pass');
      assert.equal(offline.traceability, 'traceable');
      const times = (await q('select realizado_at,recibido_at from public.verificaciones where id=$1', [offline.id]))[0];
      assert.ok(Math.abs(times.realizado_at.getTime() - (Date.now() - 3600 * 1000)) < 5000,
        'la hora de medición se corrige con el desfase del reloj');
      assert.ok(times.recibido_at > times.realizado_at);
      const detail = await read('verification', { id: offline.id });
      assert.equal(new Date(detail.offlineCapture.deviceMeasuredAt).getTime(), new Date(measured).getTime());
      assert.ok(Math.abs(detail.offlineCapture.clockSkewSeconds - 90) <= 3);
      assert.equal((await read('verification', { id: finalized.id })).offlineCapture, null);

      // Un reloj adelantado no fecha la medición después de su llegada.
      const aheadDraft = (await q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6,$7) r',
        [uuid(), equipment, changed.configurationId, 0, {
          ...normativeContent,
          tests: [{ ...normativeContent.tests[0], id: (await read('equipment', { equipmentId: equipment }))
            .plan.tests[0].id, readings: (await read('equipment', { equipmentId: equipment })).plan.tests[0].points
            .map((p, index) => ({ pointId: p.id, indication: indications[index], zero: '' })) }],
        }, uuid(), ago(60)]))[0].r;
      const ahead = (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3,$4,$5,$6) r',
        [aheadDraft.id, Number(aheadDraft.version), uuid(), 'fixture-1.0', 'fixture-device', ago(-3600)]))[0].r;
      const aheadTimes = (await q('select realizado_at,recibido_at from public.verificaciones where id=$1', [ahead.id]))[0];
      assert.ok(aheadTimes.realizado_at <= aheadTimes.recibido_at || aheadTimes.realizado_at - aheadTimes.recibido_at < 1000);
      await assert.rejects(q('select public.ivmet_mobile_save_draft($1,$2,$3,$4,$5,$6,$7)',
        [uuid(), equipment, changed.configurationId, 0, normativeContent, uuid(), ago(-3 * 86400)]), /INVALID_CAPTURE_TIME/);
    });
    await t.test('cargas flexibles: cálculo real, grupos independientes, sustitución y recuperación', async () => {
      await identity(quality);
      const configurationRequest = uuid();
      const obsoleteLoads = { tests: [
        { type: 'linearity', frequencyDays: '30', tolerance: '0.5', loads: ['1','2','3','4','5'] },
        { type: 'repeatability', frequencyDays: '30', tolerance: '0.5', load: '99', repetitions: '10' },
        { type: 'eccentricity', frequencyDays: '30', tolerance: '0.5', load: '99', positions: '3' },
      ] };
      const loadFree = { tests: [
        { type: 'linearity', frequencyDays: '30', tolerance: '0.5' },
        { type: 'repeatability', frequencyDays: '30', tolerance: '0.5' },
        { type: 'eccentricity', frequencyDays: '30', tolerance: '0.5' },
      ] };
      const configured = await configureChecks(equipment, obsoleteLoads, configurationRequest);
      assert.deepEqual(await configureChecks(equipment, loadFree, configurationRequest), configured,
        'obsolete load fields do not participate in configuration or its idempotency hash');
      const cert = await customer('certificate.create', {
        patternId: pattern, number: 'CERT-FLEXIBLE', lab: 'Laboratorio',
        calibratedOn: today, expiresOn: endsOn,
      });
      await identity(operator);
      const bundle = await read('equipment', { equipmentId: equipment });
      assert.equal(bundle.plan.captureVersion, 2);
      assert.equal(bundle.plan.captureEngineVersion, 'ivmet-internal-2.0.0');
      const trialOf = type => bundle.plan.tests.find(t => t.type === type);
      const setupOf = (extra = {}) => ({ source: 'process', description: 'Sacos de producto, masa asignada', notes: '',
        platform: 'square', indicatorPosition: 'front', groupCount: 1, measurementCount: 3, pointCount: 5,
        loadingMethod: 'none', substitutionMethod: 'none', ...extra });
      const row = (pointId, slot, load, indication, group = 1) => ({ pointId, slot, group, load, indication, zero: '' });
      const lin = trialOf('linearity'), rep = trialOf('repeatability'), ecc = trialOf('eccentricity');
      assert.deepEqual(lin.points.map(p => Number(p.load)), [0,25,50,75,100]);
      assert.ok(rep.points.every(p => Number(p.load) === 50));
      assert.ok(ecc.points.every(p => Math.abs(Number(p.load) - 33.333333333) < 1e-9));
      const contentV2 = { captureVersion: 2, certificates: [cert.id], temperature: '', humidity: '', observations: '', tests: [
        { id: lin.id, omitted: false, reason: '', setup: setupOf({ pointCount: 2 }),
          readings: [row(lin.points[0].id, 1, '12.123456789', '12.223456789'), row(uuid(), 2, '23', '23.2')],
          retainedReadings: [row(uuid(), 3, '24,', '-', 1)] },
        { id: rep.id, omitted: false, reason: '', setup: setupOf({ groupCount: 2 }),
          readings: [
            ...['10','10.1','9.9'].map((i,n) => row(rep.points[n].id,n+1,'10',i)),
            ...['80','80.2','79.8'].map((i,n) => row(uuid(),n+1,'80',i,2)),
          ], retainedReadings: [] },
        { id: ecc.id, omitted: false, reason: '', setup: setupOf(),
          readings: ['19.8','19.9','19.7','19.8','19.8'].map((i,n) => row(ecc.points[n].id,n+1,'20',i)), retainedReadings: [] },
      ] };
      const saveV2 = async payload => (await q('select public.ivmet_mobile_save_draft($1,$2,$3,0,$4,$5) r',
        [uuid(),equipment,configured.configurationId,payload,uuid()]))[0].r;
      const finalizeV2 = async draft => (await q('select public.ivmet_mobile_finalize_draft($1,$2,$3) r',
        [draft.id,Number(draft.version),uuid()]))[0].r;
      const saved = await saveV2(contentV2);
      const resumed = await read('draft', { id: saved.id });
      assert.deepEqual(resumed.payload, contentV2, 'raw inactive fields and all active loads survive a server round trip');
      const result = await finalizeV2(saved);
      assert.equal(result.verdict, 'pass');
      assert.equal(result.traceability, 'non_traceable', 'a valid certificate does not certify working loads');
      const evidence = await q(`select p.tipo,p.valor_metrica::text,p.media::text,p.evaluacion_snapshot,
        jsonb_agg(jsonb_build_object('load',l.carga_nominal::text,'error',l.error::text,'metadata',l.metadata) order by l.orden) readings
        from public.pruebas p join public.lecturas l on l.prueba_id=p.id where p.verificacion_id=$1 group by p.id`, [result.id]);
      const linearResult = evidence.find(e => e.tipo === 'linearity');
      assert.equal(linearResult.readings.length, 2, 'inactive readings never enter the evaluation');
      assert.equal(linearResult.readings[0].load, '12.123456789');
      assert.equal(linearResult.readings[0].error, '0.100000000', 'actual, not suggested, load is used');
      assert.equal(linearResult.readings[0].metadata.suggestedLoad, lin.points[0].load);
      const repeatResult = evidence.find(e => e.tipo === 'repeatability');
      assert.equal(repeatResult.valor_metrica, '0.200000000', 'maximum of within-group sample standard deviations');
      assert.equal(repeatResult.media, null, 'no meaningless average across different loads');
      assert.deepEqual(repeatResult.evaluacion_snapshot.groups.map(g => Number(g.mean)), [10,80]);
      assert.equal(evidence.find(e => e.tipo === 'eccentricity').valor_metrica, '0.100000000');
      const eccentricityDetail = (await read('verification', { id: result.id })).tests.find(t => t.tipo === 'eccentricity');
      assert.deepEqual(eccentricityDetail.evaluacion_snapshot.setup, setupOf(),
        'the PDF report draws the platform from the setup inside the evaluation snapshot');

      const substituted = structuredClone(contentV2);
      const linear = substituted.tests[0];
      linear.retainedReadings = [];
      linear.setup.pointCount = 3;
      linear.setup.substitutionMethod = 'method_1';
      linear.readings = [row(lin.points[0].id,1,'10','10.1'), row(lin.points[1].id,2,'20','20.2'),
        { ...row(uuid(),3,'99','35.1'), substitution: { referencePointId: lin.points[0].id, basePointId: lin.points[1].id, indication: '15.1' } }];
      linear.substitutionDraft = { referencePointId: lin.points[0].id, basePointId: lin.points[1].id, indication: '15,' };
      const pendingSubstitution = await saveV2(substituted);
      assert.deepEqual((await read('draft', { id: pendingSubstitution.id })).payload.tests[0].substitutionDraft, linear.substitutionDraft);
      await assert.rejects(finalizeV2(pendingSubstitution), /SUBSTITUTION_PENDING/);
      delete linear.substitutionDraft;
      const substitutedResult = await finalizeV2(await saveV2(substituted));
      const derived = (await q(`select l.carga_nominal::text,l.error::text,l.metadata from public.lecturas l
        join public.pruebas p on p.id=l.prueba_id where p.verificacion_id=$1 and p.tipo='linearity' and l.orden=3`, [substitutedResult.id]))[0];
      assert.equal(derived.carga_nominal, '35.000000000', 'server derives substitution load instead of trusting 99');
      assert.equal(derived.error, '0.100000000');
      assert.equal(derived.metadata.substitution.indication, '15.1');

      const invalid = structuredClone(contentV2);
      invalid.tests[1].setup.measurementCount = '3';
      await assert.rejects(saveV2(invalid), /INVALID_TEST_SETUP/);
      invalid.tests[1].setup.measurementCount = 3;
      invalid.tests[0].readings[0].pointId = rep.points[0].id;
      await assert.rejects(saveV2(invalid), /INVALID_POINT/);
      invalid.tests[0] = structuredClone(contentV2.tests[0]);
      invalid.tests[1].readings[1].load = '11';
      await assert.rejects(saveV2(invalid), /GROUP_LOAD_MISMATCH/);
      invalid.tests[1] = structuredClone(contentV2.tests[1]);
      invalid.tests[0].readings[1].load = '101';
      await assert.rejects(finalizeV2(await saveV2(invalid)), /LOAD_OUT_OF_CAPACITY/);
      invalid.tests[0].readings[1].load = '12.123456789';
      await assert.rejects(finalizeV2(await saveV2(invalid)), /DISTINCT_LOADS_REQUIRED/);
      invalid.tests[0] = structuredClone(substituted.tests[0]);
      invalid.tests[0].readings[2].substitution.basePointId = invalid.tests[0].readings[2].pointId;
      await assert.rejects(saveV2(invalid), /SUBSTITUTION_REFERENCE_REQUIRED/);
      invalid.tests[0] = structuredClone(contentV2.tests[0]);
      invalid.tests[2].setup.platform = 'triangular';
      await assert.rejects(saveV2(invalid), /INVALID_PLATFORM_POSITIONS/);

      const omitted = structuredClone(contentV2);
      omitted.tests[0].omitted = true;
      omitted.tests[0].reason = 'Sin producto disponible';
      omitted.tests[0].readings[0].indication = '12,';
      const omittedResult = await finalizeV2(await saveV2(omitted));
      assert.equal(omittedResult.scope, 'partial');
      const standards = structuredClone(contentV2);
      standards.tests.forEach(t => { t.setup.source = 'standard'; });
      assert.equal((await finalizeV2(await saveV2(standards))).traceability, 'traceable');
      standards.certificates = [];
      assert.equal((await finalizeV2(await saveV2(standards))).traceability, 'non_traceable');

      // The OIML reference must follow the actual load, including unit conversion.
      await identity('', 'service_role');
      const referencePlan = uuid(), referenceVersion = uuid(), referenceTrial = uuid(), referencePoint = uuid();
      await q('insert into public.planes(id,cliente_id,nombre) values($1,$2,$3)', [referencePlan,client,'Fixture OIML flexible']);
      await q('insert into public.plan_versiones(id,plan_id,version) values($1,$2,1)', [referenceVersion,referencePlan]);
      await q(`insert into public.plan_pruebas(id,plan_version_id,tipo,metodo_evaluacion,unidad,frecuencia_dias,fuente_tolerancia)
        values($1,$2,'linearity','absolute_error','g',30,'OIML_IN_SERVICE_REFERENCE')`, [referenceTrial,referenceVersion]);
      await q(`insert into public.plan_puntos(id,plan_prueba_id,orden,codigo,etiqueta,carga_nominal,tolerancia)
        values($1,$2,1,'P1','Sugerencia',10000,1)`, [referencePoint,referenceTrial]);
      await q("update public.equipos set clase='III' where id=$1", [equipment]);
      await q('update public.equipo_rangos set intervalo_verificacion=0.1 where equipo_id=$1', [equipment]);
      const limits = (await q(`select private.flexible_load_tolerance($1,$2,$3,10000)::float8 low,
        private.flexible_load_tolerance($1,$2,$3,80000)::float8 high`, [equipment,referenceTrial,referencePoint]))[0];
      assert.deepEqual(limits, { low: 100, high: 200 });
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

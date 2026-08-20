import { approvedProcedures, env } from '@core/config';
import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ApiError } from '@core/errors/api-error';
import { ConflictError, DatabaseError, ServiceUnavailableError, ValidationError } from '@core/errors';
import { writeAudit } from '@shared/audit/audit';
import { clientTenant } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';
import { logger } from '@shared/logger';
import { payloadHash } from '../domain/canonical-payload';
import { evaluateTest, type EngineReading, type EvaluationMethod } from '../domain/metrology-engine';
import { certificateIsTraceable, deriveScope } from '../domain/verification-policy';
import type { VerificationUpload } from '../presentation/dto/sync.dto';

type Row = Record<string, unknown>;
type TestUpload = VerificationUpload['tests'][number];

interface PlanPoint {
  id: string; group: number; order: number; code: string; label: string;
  nominalLoad: string; tolerance: string; metadata: unknown;
}
interface PlanTest {
  id: string; type: 'eccentricity' | 'repeatability' | 'linearity';
  method: EvaluationMethod; unit: string; points: PlanPoint[];
}

export interface SyncItemResult {
  clientUuid: string;
  status: 'accepted' | 'duplicate' | 'rejected';
  verificationId?: string;
  verdict?: string;
  traceability?: string;
  error?: { code: string; message: string; details?: unknown };
}

function parseMetadata(value: unknown): unknown {
  if (typeof value !== 'string' || !value) return null;
  try { return JSON.parse(value); } catch { return null; }
}

export class SyncService {
  async upload(items: VerificationUpload[], user: AuthenticatedUser): Promise<{ results: SyncItemResult[]; accepted: number; rejected: number }> {
    if (!env.IVMET_SYNC_ENABLED) {
      throw new ServiceUnavailableError('La sincronizacion IvMET esta deshabilitada hasta aprobar el procedimiento metrologico');
    }
    const results: SyncItemResult[] = [];
    for (const item of items) {
      try { results.push(await this.processOne(item, user)); }
      catch (error) {
        const apiError = error instanceof ApiError ? error : new DatabaseError('No se pudo procesar la verificacion', error);
        if (!apiError.isOperational) logger.error({ err: error, clientUuid: item.clientUuid, userId: user.id }, 'Fallo al sincronizar un elemento IvMET');
        results.push({ clientUuid: item.clientUuid, status: 'rejected', error: {
          code: apiError.code, message: apiError.message,
          details: apiError.isOperational ? apiError.details : undefined,
        } });
      }
    }
    return { results, accepted: results.filter((item) => item.status !== 'rejected').length, rejected: results.filter((item) => item.status === 'rejected').length };
  }

  private async processOne(item: VerificationUpload, user: AuthenticatedUser): Promise<SyncItemResult> {
    const tenant = clientTenant(user);
    const hash = payloadHash(item);
    const performedAt = new Date(item.performedAt);
    if (performedAt.getTime() > Date.now() + 5 * 60_000) {
      throw new ValidationError('performedAt no puede estar mas de cinco minutos en el futuro');
    }
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
    try {
      const previous = await transaction.request().input('uuid', sql.UniqueIdentifier, item.clientUuid)
        .input('tenantForDuplicate', sql.NVarChar(50), tenant).input('userForDuplicate', sql.UniqueIdentifier, user.id).query(`
        SELECT v.verificacion_id,v.payload_hash,v.veredicto_global,v.trazabilidad,
          CASE WHEN v.cliente_id=@tenantForDuplicate AND EXISTS (
            SELECT 1 FROM ivmet.usuario_plantas up WHERE up.usuario_id=@userForDuplicate
              AND up.cliente_id=v.cliente_id AND up.planta_id=v.planta_id AND up.activa=1
          ) THEN 1 ELSE 0 END AS authorized
        FROM ivmet.verificaciones v WITH (UPDLOCK,HOLDLOCK) WHERE v.client_uuid=@uuid
      `);
      const existing = previous.recordset[0] as Row | undefined;
      if (existing) {
        if (!existing.authorized) throw new ConflictError('El clientUuid no esta disponible');
        const existingHash = existing.payload_hash as Buffer;
        if (!Buffer.isBuffer(existingHash) || !existingHash.equals(hash)) throw new ConflictError('El clientUuid ya existe con contenido diferente');
        await transaction.commit();
        return { clientUuid: item.clientUuid, status: 'duplicate', verificationId: String(existing.verificacion_id), verdict: String(existing.veredicto_global), traceability: String(existing.trazabilidad) };
      }

      const equipmentResult = await transaction.request().input('code', sql.NVarChar(100), item.equipmentCode)
        .input('tenant', sql.NVarChar(50), tenant).input('userId', sql.UniqueIdentifier, user.id)
        .input('version', sql.UniqueIdentifier, item.planVersionId).input('performedAt', sql.DateTime2(3), performedAt).query(`
          SELECT e.cod_metrica,e.cliente_id,e.planta_id,e.area_id,ep.plan_version_id,
            (SELECT TOP 1 legacy.* FROM dbo.DATA_EQUIPOS legacy WHERE CONVERT(nvarchar(100),legacy.cod_metrica)=e.cod_metrica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS equipmentJson,
            (SELECT TOP 1 balance.* FROM dbo.DATA_EQUIPOS_BALANZAS balance WHERE CONVERT(nvarchar(100),balance.cod_metrica)=e.cod_metrica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS balanceJson
          FROM ivmet.equipos e JOIN ivmet.equipo_planes ep ON ep.cod_metrica=e.cod_metrica
          WHERE e.cod_metrica=@code AND e.cliente_id=@tenant AND e.habilitado=1
            AND EXISTS (SELECT 1 FROM ivmet.usuario_plantas up WHERE up.usuario_id=@userId AND up.cliente_id=e.cliente_id AND up.planta_id=e.planta_id AND up.activa=1)
            AND ep.plan_version_id=@version AND ep.vigente_desde<=@performedAt
            AND (ep.vigente_hasta IS NULL OR ep.vigente_hasta>@performedAt)
            AND EXISTS (SELECT 1 FROM ivmet.plan_versiones pv WHERE pv.plan_version_id=ep.plan_version_id AND pv.estado IN (N'PUBLICADO',N'RETIRADO'))
        `);
      const equipment = equipmentResult.recordset[0] as Row | undefined;
      if (!equipment) throw new ValidationError('Equipo, planta o version del plan no autorizados para la fecha indicada');

      const capturedBy = item.capturedByUserId ?? user.id;
      const capturer = await transaction.request().input('capturer', sql.UniqueIdentifier, capturedBy)
        .input('tenant', sql.NVarChar(50), tenant).input('plant', sql.NVarChar(50), String(equipment.planta_id)).query(`
          SELECT TOP 1 u.usuario_id FROM ivmet.usuarios u JOIN ivmet.usuario_plantas up ON up.usuario_id=u.usuario_id
          WHERE u.usuario_id=@capturer AND u.cliente_id=@tenant AND u.estado=N'ACTIVO' AND up.planta_id=@plant AND up.cliente_id=@tenant AND up.activa=1
        `);
      if (!capturer.recordset[0]) throw new ValidationError('El usuario de captura no estaba autorizado para la planta');

      const plan = await this.loadPlan(transaction, item.planVersionId);
      if (!approvedProcedures.has(String(plan.snapshot.procedimiento_referencia))) {
        throw new ValidationError('El procedimiento de esta version del plan aun no fue aprobado para sincronizacion productiva');
      }
      const uploads = new Map(item.tests.map((test) => [test.type, test]));
      if (uploads.size !== plan.tests.length || plan.tests.some((test) => !uploads.has(test.type))) {
        throw new ValidationError('Debe declarar cada prueba del plan como ejecutada u omitida');
      }

      let traceability: 'traceable' | 'non_traceable' = 'traceable';
      const standards: Array<Row> = [];
      for (const standard of item.standards) {
        const result = await transaction.request().input('pattern', sql.UniqueIdentifier, standard.patternId)
          .input('certificate', sql.UniqueIdentifier, standard.certificateId).input('tenant', sql.NVarChar(50), tenant)
          .input('plant', sql.NVarChar(50), String(equipment.planta_id)).query(`
            SELECT p.patron_id,p.codigo,p.descripcion,p.tipo,p.clase,p.unidad,CONVERT(varchar(50),p.capacidad) AS capacidad,
              c.certificado_id,c.numero,c.laboratorio,CONVERT(char(10),c.calibrado_el,23) AS calibrado_el,
              CONVERT(char(10),c.vence_el,23) AS vence_el,c.documento_referencia
            FROM ivmet.patrones p JOIN ivmet.patron_plantas pp ON pp.patron_id=p.patron_id
            JOIN ivmet.patron_certificados c ON c.patron_id=p.patron_id
            WHERE p.patron_id=@pattern AND c.certificado_id=@certificate AND p.cliente_id=@tenant
              AND pp.planta_id=@plant AND p.activo=1 AND c.estado=N'ACTIVO'
          `);
        const row = result.recordset[0] as Row | undefined;
        if (!row) throw new ValidationError('Patron o certificado no autorizado para la planta');
        if (!certificateIsTraceable(performedAt, String(row.calibrado_el), String(row.vence_el))) traceability = 'non_traceable';
        standards.push({ ...row, role: standard.role });
      }

      const scope = deriveScope(item.tests.map((test) => test.status));
      const testCalculations: Array<{ plan: PlanTest; upload: TestUpload; calculation?: ReturnType<typeof evaluateTest> }> = [];
      for (const planTest of plan.tests) {
        const upload = uploads.get(planTest.type)!;
        if (upload.status === 'omitted') {
          testCalculations.push({ plan: planTest, upload });
          continue;
        }
        const byPoint = new Map(upload.readings.map((reading) => [reading.pointId, reading]));
        if (byPoint.size !== planTest.points.length || planTest.points.some((point) => !byPoint.has(point.id))) {
          throw new ValidationError(`Las lecturas de ${planTest.type} no coinciden con los puntos del plan`);
        }
        const engineReadings: EngineReading[] = planTest.points.map((point) => {
          const reading = byPoint.get(point.id)!;
          return { pointId: point.id, group: point.group, order: point.order, code: point.code,
            label: point.label, nominalLoad: point.nominalLoad, tolerance: point.tolerance,
            indication: reading.indication, zeroReturn: reading.zeroReturn,
            metadata: reading.metadata ?? point.metadata };
        });
        try {
          testCalculations.push({ plan: planTest, upload, calculation: evaluateTest(planTest.method, engineReadings) });
        } catch (error) {
          if (error instanceof RangeError) throw new ValidationError(`Los resultados de ${planTest.type} exceden decimal(19,9)`);
          throw error;
        }
      }
      const globalVerdict = testCalculations.some((test) => test.calculation?.verdict === 'fail') ? 'fail' : 'pass';
      const equipmentSnapshot = `{"equipment":${typeof equipment.equipmentJson === 'string' ? equipment.equipmentJson : 'null'},` +
        `"weighing":${typeof equipment.balanceJson === 'string' ? equipment.balanceJson : 'null'},` +
        `"ivmet":${JSON.stringify({ code: item.equipmentCode, clientId: tenant, plantId: equipment.planta_id, areaId: equipment.area_id })}}`;
      const planSnapshot = JSON.stringify(plan.snapshot);
      const inserted = await transaction.request().input('uuid', sql.UniqueIdentifier, item.clientUuid)
        .input('hash', sql.VarBinary(32), hash).input('code', sql.NVarChar(100), item.equipmentCode)
        .input('tenant', sql.NVarChar(50), tenant).input('plant', sql.NVarChar(50), String(equipment.planta_id))
        .input('area', sql.UniqueIdentifier, equipment.area_id ?? null).input('version', sql.UniqueIdentifier, item.planVersionId)
        .input('capturer', sql.UniqueIdentifier, capturedBy).input('uploader', sql.UniqueIdentifier, user.id)
        .input('performedAt', sql.DateTime2(3), performedAt).input('scope', sql.NVarChar(20), scope)
        .input('verdict', sql.NVarChar(20), globalVerdict).input('traceability', sql.NVarChar(20), traceability)
        .input('temperature', sql.NVarChar(50), item.temperatureC ?? null)
        .input('humidity', sql.NVarChar(50), item.relativeHumidityPct ?? null)
        .input('observations', sql.NVarChar(2000), item.observations ?? null)
        .input('equipmentSnapshot', sql.NVarChar(sql.MAX), equipmentSnapshot)
        .input('planSnapshot', sql.NVarChar(sql.MAX), planSnapshot).input('appVersion', sql.NVarChar(50), item.appVersion ?? null)
        .input('device', sql.NVarChar(200), item.deviceId).query(`
          INSERT INTO ivmet.verificaciones
            (client_uuid,payload_hash,cod_metrica,cliente_id,planta_id,area_id,plan_version_id,capturado_por,subido_por,
             realizado_at,alcance,veredicto_global,trazabilidad,temperatura_c,humedad_relativa_pct,observaciones,
             equipo_snapshot_json,plan_snapshot_json,app_version,dispositivo_id)
          OUTPUT INSERTED.verificacion_id
          VALUES (@uuid,@hash,@code,@tenant,@plant,@area,@version,@capturer,@uploader,@performedAt,@scope,@verdict,
            @traceability,CONVERT(decimal(9,3),@temperature),CONVERT(decimal(9,3),@humidity),@observations,@equipmentSnapshot,@planSnapshot,@appVersion,@device)
        `);
      const verificationId = String(inserted.recordset[0]?.verificacion_id);
      for (const standard of standards) {
        await transaction.request().input('verification', sql.UniqueIdentifier, verificationId)
          .input('pattern', sql.UniqueIdentifier, standard.patron_id).input('certificate', sql.UniqueIdentifier, standard.certificado_id)
          .input('role', sql.NVarChar(30), standard.role).input('snapshot', sql.NVarChar(sql.MAX), JSON.stringify(standard)).query(`
            INSERT INTO ivmet.verificacion_patrones (verificacion_id,patron_id,certificado_id,rol,snapshot_json)
            VALUES (@verification,@pattern,@certificate,@role,@snapshot)
          `);
      }
      for (const test of testCalculations) {
        const calculation = test.calculation;
        const testResult = await transaction.request().input('verification', sql.UniqueIdentifier, verificationId)
          .input('planTest', sql.UniqueIdentifier, test.plan.id).input('type', sql.NVarChar(30), test.plan.type)
          .input('status', sql.NVarChar(20), test.upload.status)
          .input('reason', sql.NVarChar(1000), test.upload.status === 'omitted' ? test.upload.omissionReason : null)
          .input('method', sql.NVarChar(60), test.plan.method).input('unit', sql.NVarChar(20), test.plan.unit)
          .input('acceptance', sql.NVarChar(50), calculation?.metrics.acceptanceLimit ?? null)
          .input('verdict', sql.NVarChar(20), calculation?.verdict ?? null)
          .input('maxError', sql.NVarChar(50), calculation?.metrics.maximumAbsoluteError ?? null)
          .input('mean', sql.NVarChar(50), calculation?.metrics.mean ?? null)
          .input('stddev', sql.NVarChar(50), calculation?.metrics.sampleStandardDeviation ?? null)
          .input('range', sql.NVarChar(50), calculation?.metrics.range ?? null)
          .input('observations', sql.NVarChar(1000), test.upload.observations ?? null).query(`
            INSERT INTO ivmet.pruebas
              (verificacion_id,plan_prueba_id,tipo,estado_ejecucion,motivo_omision,metodo_evaluacion,unidad,tolerancia,
               veredicto,error_max_abs,media,desviacion_estandar,rango,observaciones)
            OUTPUT INSERTED.prueba_id VALUES (@verification,@planTest,@type,@status,@reason,@method,@unit,
              CONVERT(decimal(19,9),@acceptance),
              @verdict,CONVERT(decimal(19,9),@maxError),CONVERT(decimal(19,9),@mean),
              CONVERT(decimal(19,9),@stddev),CONVERT(decimal(19,9),@range),@observations)
          `);
        const testId = String(testResult.recordset[0]?.prueba_id);
        for (const reading of calculation?.readings ?? []) {
          await transaction.request().input('test', sql.UniqueIdentifier, testId).input('point', sql.UniqueIdentifier, reading.pointId)
            .input('group', sql.Int, reading.group).input('order', sql.Int, reading.order)
            .input('code', sql.NVarChar(100), reading.code).input('label', sql.NVarChar(200), reading.label)
            .input('load', sql.NVarChar(50), reading.nominalLoad).input('indication', sql.NVarChar(50), reading.indication)
            .input('zero', sql.NVarChar(50), reading.zeroReturn ?? null).input('error', sql.NVarChar(50), reading.error)
            .input('tolerance', sql.NVarChar(50), reading.tolerance).input('verdict', sql.NVarChar(20), reading.verdict)
            .input('metadata', sql.NVarChar(sql.MAX), reading.metadata ? JSON.stringify(reading.metadata) : null).query(`
              INSERT INTO ivmet.lecturas
                (prueba_id,plan_punto_id,grupo,orden,punto_codigo,etiqueta,carga_nominal,indicacion,retorno_cero,error,tolerancia,veredicto,metadata_json)
              VALUES (@test,@point,@group,@order,@code,@label,CONVERT(decimal(19,9),@load),
                CONVERT(decimal(19,9),@indication),CONVERT(decimal(19,9),@zero),
                CONVERT(decimal(19,9),@error),CONVERT(decimal(19,9),@tolerance),@verdict,@metadata)
            `);
        }
      }
      if (globalVerdict === 'fail' || traceability === 'non_traceable') {
        const type = globalVerdict === 'fail' && traceability === 'non_traceable' ? 'both' : globalVerdict === 'fail' ? 'test_failed' : 'non_traceable';
        const summary = type === 'both' ? 'Verificacion fuera de tolerancia y sin trazabilidad vigente' : type === 'test_failed' ? 'Verificacion fuera de tolerancia' : 'Verificacion registrada sin trazabilidad vigente';
        await transaction.request().input('verification', sql.UniqueIdentifier, verificationId)
          .input('tenant', sql.NVarChar(50), tenant).input('plant', sql.NVarChar(50), String(equipment.planta_id))
          .input('code', sql.NVarChar(100), item.equipmentCode).input('type', sql.NVarChar(30), type)
          .input('summary', sql.NVarChar(1000), summary).query(`
            INSERT INTO ivmet.alertas (verificacion_id,cliente_id,planta_id,cod_metrica,tipo,resumen)
            VALUES (@verification,@tenant,@plant,@code,@type,@summary)
          `);
      }
      await writeAudit(transaction.request(), { actor: user, entity: 'verificacion', entityId: verificationId, action: 'sync_accept', after: { clientUuid: item.clientUuid, verdict: globalVerdict, traceability, scope }, deviceId: item.deviceId });
      await transaction.commit();
      return { clientUuid: item.clientUuid, status: 'accepted', verificationId, verdict: globalVerdict, traceability };
    } catch (error) {
      await transaction.rollback();
      throw error;
    }
  }

  private async loadPlan(transaction: sql.Transaction, versionId: string): Promise<{ tests: PlanTest[]; snapshot: Row }> {
    const versionResult = await transaction.request().input('version', sql.UniqueIdentifier, versionId).query(`
      SELECT pv.plan_version_id,pv.version,pv.estado,pv.procedimiento_referencia,pv.notas,pv.publicado_at,
        p.plan_id,p.nombre,p.descripcion
      FROM ivmet.plan_versiones pv JOIN ivmet.planes p ON p.plan_id=pv.plan_id WHERE pv.plan_version_id=@version
    `);
    const version = versionResult.recordset[0] as Row | undefined;
    if (!version) throw new ValidationError('Version del plan no encontrada');
    const rows = await transaction.request().input('version', sql.UniqueIdentifier, versionId).query(`
      SELECT t.plan_prueba_id,t.tipo,t.metodo_evaluacion,t.unidad,t.frecuencia_dias,t.aviso_dias,t.metadata_json AS test_metadata,
        p.plan_punto_id,p.grupo,p.orden,p.codigo,p.etiqueta,CONVERT(varchar(50),p.carga_nominal) AS carga_nominal,
        CONVERT(varchar(50),p.tolerancia) AS tolerancia,p.posicion,p.direccion,p.metadata_json AS point_metadata
      FROM ivmet.plan_pruebas t JOIN ivmet.plan_puntos p ON p.plan_prueba_id=t.plan_prueba_id
      WHERE t.plan_version_id=@version ORDER BY t.tipo,p.orden
    `);
    const tests = new Map<string, PlanTest>();
    const snapshotTests = new Map<string, Row>();
    for (const row of rows.recordset as Row[]) {
      const id = String(row.plan_prueba_id);
      if (!tests.has(id)) {
        tests.set(id, { id, type: String(row.tipo) as PlanTest['type'], method: String(row.metodo_evaluacion) as EvaluationMethod, unit: String(row.unidad), points: [] });
        snapshotTests.set(id, { id, type: row.tipo, evaluationMethod: row.metodo_evaluacion, unit: row.unidad,
          frequencyDays: row.frecuencia_dias, warningDays: row.aviso_dias, metadata: parseMetadata(row.test_metadata), points: [] });
      }
      const point: PlanPoint = { id: String(row.plan_punto_id), group: Number(row.grupo), order: Number(row.orden),
        code: String(row.codigo), label: String(row.etiqueta), nominalLoad: String(row.carga_nominal),
        tolerance: String(row.tolerancia), metadata: parseMetadata(row.point_metadata) };
      tests.get(id)!.points.push(point);
      (snapshotTests.get(id)!.points as Row[]).push({ ...point, position: row.posicion, direction: row.direccion });
    }
    return { tests: [...tests.values()], snapshot: { ...version, tests: [...snapshotTests.values()] } };
  }
}

export const syncService = new SyncService();

import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ConflictError, NotFoundError } from '@core/errors';
import { writeAudit, type AuditEvent } from '@shared/audit/audit';
import { bindTenantAccess, plantAccessPredicate } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';

type Row = Record<string, unknown>;

function parseJson(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}

export interface VerificationDetail extends Row {
  standards: Row[];
  tests: Row[];
}

export class VerificationReportsService {
  private scopedWhere(user: AuthenticatedUser, alias: string): string {
    return user.empresaId
      ? plantAccessPredicate(alias)
      : `EXISTS (SELECT 1 FROM ivmet.alertas shared WHERE shared.verificacion_id=${alias}.verificacion_id AND shared.visibilidad_metrica=N'shared')`;
  }

  async list(user: AuthenticatedUser, query: { page: number; pageSize: number; equipmentCode?: string; plantId?: string; from?: string; to?: string }): Promise<{ items: Row[]; total: number; page: number; pageSize: number }> {
    const pool = await getSqlPool();
    let request = pool.request().input('code', sql.NVarChar(100), query.equipmentCode ?? null)
      .input('plant', sql.NVarChar(50), query.plantId ?? null)
      .input('from', sql.DateTime2(3), query.from ? new Date(query.from) : null)
      .input('to', sql.DateTime2(3), query.to ? new Date(query.to) : null)
      .input('offset', sql.Int, (query.page - 1) * query.pageSize).input('pageSize', sql.Int, query.pageSize);
    if (user.empresaId) request = bindTenantAccess(request, user);
    const result = await request.query(`
      SELECT COUNT(*) OVER() AS total,v.verificacion_id AS id,v.client_uuid AS clientUuid,
        v.cod_metrica AS equipmentCode,v.cliente_id AS clientId,v.planta_id AS plantId,
        v.realizado_at AS performedAt,v.recibido_at AS receivedAt,v.alcance AS scope,
        v.veredicto_global AS verdict,v.trazabilidad AS traceability,v.estado AS status,
        v.anulada_at AS annulledAt,v.motivo_anulacion AS annulmentReason,
        capture.nombre AS capturedBy,upload.nombre AS uploadedBy
      FROM ivmet.verificaciones v JOIN ivmet.usuarios capture ON capture.usuario_id=v.capturado_por
      JOIN ivmet.usuarios upload ON upload.usuario_id=v.subido_por
      WHERE ${this.scopedWhere(user, 'v')} AND (@code IS NULL OR v.cod_metrica=@code)
        AND (@plant IS NULL OR v.planta_id=@plant) AND (@from IS NULL OR v.realizado_at>=@from)
        AND (@to IS NULL OR v.realizado_at<=@to)
      ORDER BY v.realizado_at DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
    `);
    const rows = result.recordset as Row[];
    return { items: rows, total: Number(rows[0]?.total ?? 0), page: query.page, pageSize: query.pageSize };
  }

  async detail(user: AuthenticatedUser, id: string): Promise<VerificationDetail> {
    const pool = await getSqlPool();
    let request = pool.request().input('id', sql.UniqueIdentifier, id);
    if (user.empresaId) request = bindTenantAccess(request, user);
    const result = await request.query(`
      SELECT v.verificacion_id AS id,v.client_uuid AS clientUuid,v.cod_metrica AS equipmentCode,
        v.cliente_id AS clientId,v.planta_id AS plantId,v.area_id AS areaId,v.plan_version_id AS planVersionId,
        v.realizado_at AS performedAt,v.recibido_at AS receivedAt,v.alcance AS scope,
        v.veredicto_global AS verdict,v.trazabilidad AS traceability,
        CONVERT(varchar(50),v.temperatura_c) AS temperatureC,
        CONVERT(varchar(50),v.humedad_relativa_pct) AS relativeHumidityPct,v.observaciones AS observations,
        v.equipo_snapshot_json AS equipmentSnapshot,v.plan_snapshot_json AS planSnapshot,
        v.app_version AS appVersion,v.dispositivo_id AS deviceId,v.estado AS status,
        v.anulada_at AS annulledAt,v.motivo_anulacion AS annulmentReason,
        capture.usuario_id AS capturedById,capture.nombre AS capturedBy,
        upload.usuario_id AS uploadedById,upload.nombre AS uploadedBy,
        annul.nombre AS annulledBy
      FROM ivmet.verificaciones v JOIN ivmet.usuarios capture ON capture.usuario_id=v.capturado_por
      JOIN ivmet.usuarios upload ON upload.usuario_id=v.subido_por
      LEFT JOIN ivmet.usuarios annul ON annul.usuario_id=v.anulada_por
      WHERE v.verificacion_id=@id AND ${this.scopedWhere(user, 'v')}
    `);
    const row = result.recordset[0] as Row | undefined;
    if (!row) throw new NotFoundError('Verificacion no encontrada o no compartida');
    const standards = await pool.request().input('id', sql.UniqueIdentifier, id).query(`
      SELECT patron_id AS patternId,certificado_id AS certificateId,rol AS role,snapshot_json AS snapshot
      FROM ivmet.verificacion_patrones WHERE verificacion_id=@id ORDER BY rol
    `);
    const testRows = await pool.request().input('id', sql.UniqueIdentifier, id).query(`
      SELECT t.prueba_id AS testId,t.plan_prueba_id AS planTestId,t.tipo AS type,t.estado_ejecucion AS executionStatus,
        t.motivo_omision AS omissionReason,t.metodo_evaluacion AS evaluationMethod,t.unidad AS unit,
        t.veredicto AS verdict,CONVERT(varchar(50),t.tolerancia) AS acceptanceLimit,
        CONVERT(varchar(50),t.error_max_abs) AS maximumAbsoluteError,
        CONVERT(varchar(50),t.media) AS mean,CONVERT(varchar(50),t.desviacion_estandar) AS sampleStandardDeviation,
        CONVERT(varchar(50),t.rango) AS [range],t.observaciones AS observations,
        l.lectura_id AS readingId,l.plan_punto_id AS pointId,l.grupo AS [group],l.orden AS [order],
        l.punto_codigo AS pointCode,l.etiqueta AS label,CONVERT(varchar(50),l.carga_nominal) AS nominalLoad,
        CONVERT(varchar(50),l.indicacion) AS indication,CONVERT(varchar(50),l.retorno_cero) AS zeroReturn,
        CONVERT(varchar(50),l.error) AS error,CONVERT(varchar(50),l.tolerancia) AS tolerance,
        l.veredicto AS readingVerdict,l.metadata_json AS readingMetadata
      FROM ivmet.pruebas t LEFT JOIN ivmet.lecturas l ON l.prueba_id=t.prueba_id
      WHERE t.verificacion_id=@id ORDER BY t.tipo,l.orden
    `);
    const tests = new Map<string, Row>();
    for (const testRow of testRows.recordset as Row[]) {
      const testId = String(testRow.testId);
      if (!tests.has(testId)) tests.set(testId, {
        id: testId, planTestId: testRow.planTestId, type: testRow.type, executionStatus: testRow.executionStatus,
        omissionReason: testRow.omissionReason, evaluationMethod: testRow.evaluationMethod, unit: testRow.unit,
        verdict: testRow.verdict, metrics: { acceptanceLimit: testRow.acceptanceLimit, maximumAbsoluteError: testRow.maximumAbsoluteError,
          mean: testRow.mean, sampleStandardDeviation: testRow.sampleStandardDeviation, range: testRow.range },
        observations: testRow.observations, readings: [],
      });
      if (testRow.readingId) (tests.get(testId)!.readings as Row[]).push({
        id: testRow.readingId, pointId: testRow.pointId, group: testRow.group, order: testRow.order,
        pointCode: testRow.pointCode, label: testRow.label, nominalLoad: testRow.nominalLoad,
        indication: testRow.indication, zeroReturn: testRow.zeroReturn, error: testRow.error,
        tolerance: testRow.tolerance, verdict: testRow.readingVerdict, metadata: parseJson(testRow.readingMetadata),
      });
    }
    return { ...row, equipmentSnapshot: parseJson(row.equipmentSnapshot), planSnapshot: parseJson(row.planSnapshot),
      standards: (standards.recordset as Row[]).map((standard) => ({ ...standard, snapshot: parseJson(standard.snapshot) })),
      tests: [...tests.values()] } as VerificationDetail;
  }

  async annul(user: AuthenticatedUser, id: string, reason: string, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      const request = bindTenantAccess(transaction.request(), user).input('id', sql.UniqueIdentifier, id)
        .input('reason', sql.NVarChar(1000), reason);
      const result = await request.query(`
        UPDATE v SET estado=N'ANULADA',anulada_at=SYSUTCDATETIME(),anulada_por=@userId,motivo_anulacion=@reason
        FROM ivmet.verificaciones v WHERE v.verificacion_id=@id AND v.estado=N'ACTIVA' AND ${plantAccessPredicate('v')};
        SELECT @@ROWCOUNT AS affected;
      `);
      if (!Number(result.recordset[0]?.affected)) throw new ConflictError('La verificacion no existe, ya esta anulada o no esta autorizada');
      await transaction.request().input('id', sql.UniqueIdentifier, id).query(`
        UPDATE ivmet.alertas SET estado_cliente=N'archived' WHERE verificacion_id=@id
      `);
      await writeAudit(transaction.request(), { ...metadata, actor: user, entity: 'verificacion', entityId: id, action: 'annul', after: { reason } });
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      if (error instanceof ConflictError) throw error;
      throw error;
    }
  }
}

export const verificationReportsService = new VerificationReportsService();

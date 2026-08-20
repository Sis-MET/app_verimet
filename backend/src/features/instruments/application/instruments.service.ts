import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { NotFoundError } from '@core/errors';
import { bindTenantAccess, plantAccessPredicate } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';

type Row = Record<string, unknown>;

function parseJson(value: unknown): unknown {
  if (typeof value !== 'string' || !value) return null;
  try { return JSON.parse(value); } catch { return null; }
}

function mapEquipment(row: Row): Row {
  return {
    code: String(row.code), clientId: String(row.clientId), plantId: String(row.plantId),
    plantName: String(row.plantName), areaId: row.areaId ? String(row.areaId) : null,
    areaName: row.areaName ? String(row.areaName) : null, enabled: Boolean(row.enabled),
    configurationStatus: String(row.configurationStatus),
    technical: { equipment: parseJson(row.equipmentJson), weighing: parseJson(row.balanceJson) },
    activePlanVersionId: row.planVersionId ? String(row.planVersionId) : null,
    lastVerificationAt: row.lastVerificationAt ?? null,
    lastVerdict: row.lastVerdict ?? null,
  };
}

export class InstrumentsService {
  async list(user: AuthenticatedUser, filters: { page: number; pageSize: number; plantId?: string; areaId?: string; search?: string }): Promise<{ items: Row[]; page: number; pageSize: number; total: number }> {
    const pool = await getSqlPool();
    const request = bindTenantAccess(pool.request(), user)
      .input('plantId', sql.NVarChar(50), filters.plantId ?? null)
      .input('areaId', sql.UniqueIdentifier, filters.areaId ?? null)
      .input('search', sql.NVarChar(100), filters.search ? `%${filters.search}%` : null)
      .input('offset', sql.Int, (filters.page - 1) * filters.pageSize)
      .input('pageSize', sql.Int, filters.pageSize);
    const result = await request.query(`
      SELECT COUNT(*) OVER() AS total,
        e.cod_metrica AS code, e.cliente_id AS clientId, e.planta_id AS plantId,
        COALESCE(CONVERT(nvarchar(200), p.planta), e.planta_id) AS plantName,
        e.area_id AS areaId, a.nombre AS areaName, e.habilitado AS enabled,e.estado_configuracion AS configurationStatus,
        ep.plan_version_id AS planVersionId,
        lastv.realizado_at AS lastVerificationAt, lastv.veredicto_global AS lastVerdict,
        (SELECT TOP 1 legacy.* FROM dbo.DATA_EQUIPOS legacy
          WHERE CONVERT(nvarchar(100), legacy.cod_metrica)=e.cod_metrica FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS equipmentJson,
        (SELECT TOP 1 balance.* FROM dbo.DATA_EQUIPOS_BALANZAS balance
          WHERE CONVERT(nvarchar(100), balance.cod_metrica)=e.cod_metrica FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS balanceJson
      FROM ivmet.equipos e
      LEFT JOIN ivmet.areas a ON a.area_id=e.area_id
      LEFT JOIN dbo.DATA_PLANTAS p ON CONVERT(nvarchar(50),p.planta_id)=e.planta_id
      OUTER APPLY (
        SELECT TOP 1 plan_version_id FROM ivmet.equipo_planes
        WHERE cod_metrica=e.cod_metrica AND vigente_desde<=SYSUTCDATETIME()
          AND (vigente_hasta IS NULL OR vigente_hasta>SYSUTCDATETIME())
        ORDER BY vigente_desde DESC
      ) ep
      OUTER APPLY (
        SELECT TOP 1 realizado_at, veredicto_global FROM ivmet.verificaciones
        WHERE cod_metrica=e.cod_metrica AND estado=N'ACTIVA'
        ORDER BY realizado_at DESC
      ) lastv
      WHERE ${plantAccessPredicate('e')} AND e.habilitado=1
        AND (@plantId IS NULL OR e.planta_id=@plantId)
        AND (@areaId IS NULL OR e.area_id=@areaId)
        AND (@search IS NULL OR e.cod_metrica LIKE @search OR a.nombre LIKE @search)
      ORDER BY COALESCE(a.nombre,N''), e.cod_metrica
      OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
    `);
    const rows = result.recordset as Row[];
    return { items: rows.map(mapEquipment), page: filters.page, pageSize: filters.pageSize, total: Number(rows[0]?.total ?? 0) };
  }

  async detail(user: AuthenticatedUser, code: string): Promise<Row> {
    const pool = await getSqlPool();
    const result = await bindTenantAccess(pool.request(), user).input('code', sql.NVarChar(100), code).query(`
      SELECT e.cod_metrica AS code, e.cliente_id AS clientId, e.planta_id AS plantId,
        COALESCE(CONVERT(nvarchar(200),p.planta),e.planta_id) AS plantName,
        e.area_id AS areaId, a.nombre AS areaName, e.habilitado AS enabled,e.estado_configuracion AS configurationStatus,
        ep.plan_version_id AS planVersionId, lastv.realizado_at AS lastVerificationAt,
        lastv.veredicto_global AS lastVerdict,
        (SELECT TOP 1 legacy.* FROM dbo.DATA_EQUIPOS legacy WHERE CONVERT(nvarchar(100),legacy.cod_metrica)=e.cod_metrica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS equipmentJson,
        (SELECT TOP 1 balance.* FROM dbo.DATA_EQUIPOS_BALANZAS balance WHERE CONVERT(nvarchar(100),balance.cod_metrica)=e.cod_metrica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS balanceJson
      FROM ivmet.equipos e
      LEFT JOIN ivmet.areas a ON a.area_id=e.area_id
      LEFT JOIN dbo.DATA_PLANTAS p ON CONVERT(nvarchar(50),p.planta_id)=e.planta_id
      OUTER APPLY (SELECT TOP 1 plan_version_id FROM ivmet.equipo_planes WHERE cod_metrica=e.cod_metrica AND vigente_desde<=SYSUTCDATETIME() AND (vigente_hasta IS NULL OR vigente_hasta>SYSUTCDATETIME()) ORDER BY vigente_desde DESC) ep
      OUTER APPLY (SELECT TOP 1 realizado_at,veredicto_global FROM ivmet.verificaciones WHERE cod_metrica=e.cod_metrica AND estado=N'ACTIVA' ORDER BY realizado_at DESC) lastv
      WHERE e.cod_metrica=@code AND ${plantAccessPredicate('e')} AND e.habilitado=1
    `);
    const row = result.recordset[0] as Row | undefined;
    if (!row) throw new NotFoundError('Instrumento no encontrado o fuera de su alcance');
    const equipment = mapEquipment(row);
    equipment.plan = row.planVersionId ? await this.getPlanSnapshot(String(row.planVersionId)) : null;
    equipment.dueTests = await this.getDueTests(user, code);
    return equipment;
  }

  async history(user: AuthenticatedUser, code: string, page: number, pageSize: number): Promise<{ items: Row[]; page: number; pageSize: number; total: number }> {
    const pool = await getSqlPool();
    const result = await bindTenantAccess(pool.request(), user).input('code', sql.NVarChar(100), code)
      .input('offset', sql.Int, (page - 1) * pageSize).input('pageSize', sql.Int, pageSize).query(`
        SELECT COUNT(*) OVER() AS total, v.verificacion_id AS id, v.client_uuid AS clientUuid,
          v.realizado_at AS performedAt, v.recibido_at AS receivedAt, v.alcance AS scope,
          v.veredicto_global AS verdict, v.trazabilidad AS traceability, v.estado AS status,
          u.nombre AS capturedBy
        FROM ivmet.verificaciones v
        JOIN ivmet.usuarios u ON u.usuario_id=v.capturado_por
        WHERE v.cod_metrica=@code AND ${plantAccessPredicate('v')}
        ORDER BY v.realizado_at DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
      `);
    const rows = result.recordset as Row[];
    return { items: rows, page, pageSize, total: Number(rows[0]?.total ?? 0) };
  }

  async getPlanSnapshot(versionId: string): Promise<Row | null> {
    const pool = await getSqlPool();
    const versions = await pool.request().input('id', sql.UniqueIdentifier, versionId).query(`
      SELECT pv.plan_version_id AS id,pv.version,pv.estado AS status,pv.procedimiento_referencia AS procedureReference,
        pv.publicado_at AS publishedAt,p.plan_id AS planId,p.nombre AS name,p.descripcion AS description
      FROM ivmet.plan_versiones pv JOIN ivmet.planes p ON p.plan_id=pv.plan_id WHERE pv.plan_version_id=@id
    `);
    const version = versions.recordset[0] as Row | undefined;
    if (!version) return null;
    const tests = await pool.request().input('id', sql.UniqueIdentifier, versionId).query(`
      SELECT pp.plan_prueba_id AS id,pp.tipo AS type,pp.metodo_evaluacion AS evaluationMethod,
        pp.unidad AS unit,pp.frecuencia_dias AS frequencyDays,pp.aviso_dias AS warningDays,
        pp.metadata_json AS metadataJson,p.plan_punto_id AS pointId,p.grupo AS [group],p.orden AS [order],
        p.codigo AS code,p.etiqueta AS label,CONVERT(varchar(50),p.carga_nominal) AS nominalLoad,
        CONVERT(varchar(50),p.tolerancia) AS tolerance,p.posicion AS position,p.direccion AS direction,
        p.metadata_json AS pointMetadataJson
      FROM ivmet.plan_pruebas pp JOIN ivmet.plan_puntos p ON p.plan_prueba_id=pp.plan_prueba_id
      WHERE pp.plan_version_id=@id ORDER BY pp.tipo,p.orden
    `);
    const grouped = new Map<string, Row>();
    for (const row of tests.recordset as Row[]) {
      const testId = String(row.id);
      let test = grouped.get(testId);
      if (!test) {
        test = { id: testId, type: row.type, evaluationMethod: row.evaluationMethod, unit: row.unit,
          frequencyDays: row.frequencyDays, warningDays: row.warningDays, metadata: parseJson(row.metadataJson), points: [] };
        grouped.set(testId, test);
      }
      (test.points as Row[]).push({ id: row.pointId, group: row.group, order: row.order, code: row.code,
        label: row.label, nominalLoad: row.nominalLoad, tolerance: row.tolerance, position: row.position,
        direction: row.direction, metadata: parseJson(row.pointMetadataJson) });
    }
    return { ...version, tests: [...grouped.values()] };
  }

  private async getDueTests(user: AuthenticatedUser, code: string): Promise<Row[]> {
    const pool = await getSqlPool();
    const result = await bindTenantAccess(pool.request(), user).input('code', sql.NVarChar(100), code).query(`
      SELECT pp.tipo AS type, pp.frecuencia_dias AS frequencyDays, pp.aviso_dias AS warningDays,
        last_ok.lastPerformedAt,
        CASE WHEN last_ok.lastPerformedAt IS NULL THEN NULL ELSE DATEADD(DAY,pp.frecuencia_dias,last_ok.lastPerformedAt) END AS dueAt
      FROM ivmet.equipos e JOIN ivmet.equipo_planes ep ON ep.cod_metrica=e.cod_metrica
      JOIN ivmet.plan_pruebas pp ON pp.plan_version_id=ep.plan_version_id
      OUTER APPLY (
        SELECT MAX(v.realizado_at) AS lastPerformedAt FROM ivmet.verificaciones v
        JOIN ivmet.pruebas t ON t.verificacion_id=v.verificacion_id
        WHERE v.cod_metrica=e.cod_metrica AND v.estado=N'ACTIVA' AND v.trazabilidad=N'traceable'
          AND t.tipo=pp.tipo AND t.estado_ejecucion=N'performed'
      ) last_ok
      WHERE e.cod_metrica=@code AND ${plantAccessPredicate('e')}
        AND ep.vigente_desde<=SYSUTCDATETIME() AND (ep.vigente_hasta IS NULL OR ep.vigente_hasta>SYSUTCDATETIME())
    `);
    return result.recordset as Row[];
  }
}

export const instrumentsService = new InstrumentsService();

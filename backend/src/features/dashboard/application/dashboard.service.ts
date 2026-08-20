import { getSqlPool } from '@core/database/sql-server-pool';
import { bindTenantAccess, plantAccessPredicate } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';

type Row = Record<string, unknown>;

export class DashboardService {
  async get(user: AuthenticatedUser): Promise<Record<string, unknown>> {
    if (!user.empresaId) return this.getMetricaDashboard();
    const pool = await getSqlPool();
    const park = await bindTenantAccess(pool.request(), user).query(`
      WITH scoped AS (
        SELECT e.cod_metrica,e.area_id,lastv.veredicto_global,lastv.trazabilidad
        FROM ivmet.equipos e
        OUTER APPLY (SELECT TOP 1 v.veredicto_global,v.trazabilidad FROM ivmet.verificaciones v
          WHERE v.cod_metrica=e.cod_metrica AND v.estado=N'ACTIVA' ORDER BY v.realizado_at DESC) lastv
        WHERE e.habilitado=1 AND ${plantAccessPredicate('e')}
      )
      SELECT COUNT(*) AS equipmentCount,COUNT(DISTINCT area_id) AS areaCount,
        SUM(CASE WHEN veredicto_global=N'pass' AND trazabilidad=N'traceable' THEN 1 ELSE 0 END) AS compliantCount,
        SUM(CASE WHEN veredicto_global IS NULL THEN 1 ELSE 0 END) AS pendingCount,
        SUM(CASE WHEN veredicto_global=N'fail' AND trazabilidad=N'traceable' THEN 1 ELSE 0 END) AS nonCompliantCount,
        SUM(CASE WHEN trazabilidad=N'non_traceable' THEN 1 ELSE 0 END) AS observedCount
      FROM scoped
    `);
    const alerts = await bindTenantAccess(pool.request(), user).query(`
      SELECT TOP 20 a.alerta_id AS id,a.cod_metrica AS equipmentCode,a.tipo AS type,
        a.resumen AS detail,a.estado_cliente AS clientStatus,a.visibilidad_metrica AS metricaVisibility,
        a.estado_metrica AS metricaStatus,a.creado_at AS createdAt
      FROM ivmet.alertas a WHERE ${plantAccessPredicate('a')} AND a.estado_cliente=N'open'
      ORDER BY a.creado_at DESC
    `);
    const due = await bindTenantAccess(pool.request(), user).query(`
      SELECT TOP 30 e.cod_metrica AS equipmentCode,a.nombre AS areaName,pp.tipo AS testType,
        last_ok.lastPerformedAt,
        CASE WHEN last_ok.lastPerformedAt IS NULL THEN NULL ELSE DATEADD(DAY,pp.frecuencia_dias,last_ok.lastPerformedAt) END AS dueAt,
        pp.aviso_dias AS warningDays
      FROM ivmet.equipos e LEFT JOIN ivmet.areas a ON a.area_id=e.area_id
      JOIN ivmet.equipo_planes ep ON ep.cod_metrica=e.cod_metrica
      JOIN ivmet.plan_pruebas pp ON pp.plan_version_id=ep.plan_version_id
      OUTER APPLY (SELECT MAX(v.realizado_at) AS lastPerformedAt FROM ivmet.verificaciones v
        JOIN ivmet.pruebas t ON t.verificacion_id=v.verificacion_id
        WHERE v.cod_metrica=e.cod_metrica AND v.estado=N'ACTIVA' AND v.trazabilidad=N'traceable'
          AND t.tipo=pp.tipo AND t.estado_ejecucion=N'performed') last_ok
      WHERE e.habilitado=1 AND ${plantAccessPredicate('e')}
        AND ep.vigente_desde<=SYSUTCDATETIME() AND (ep.vigente_hasta IS NULL OR ep.vigente_hasta>SYSUTCDATETIME())
        AND (last_ok.lastPerformedAt IS NULL OR DATEADD(DAY,pp.frecuencia_dias-pp.aviso_dias,last_ok.lastPerformedAt)<=SYSUTCDATETIME())
      ORDER BY CASE WHEN last_ok.lastPerformedAt IS NULL THEN 0 ELSE 1 END,
        DATEADD(DAY,pp.frecuencia_dias,last_ok.lastPerformedAt)
    `);
    const recent = await bindTenantAccess(pool.request(), user).query(`
      SELECT TOP 20 v.verificacion_id AS id,v.cod_metrica AS equipmentCode,v.realizado_at AS performedAt,
        u.nombre AS responsible,v.veredicto_global AS verdict,v.trazabilidad AS traceability,v.alcance AS scope
      FROM ivmet.verificaciones v JOIN ivmet.usuarios u ON u.usuario_id=v.capturado_por
      WHERE ${plantAccessPredicate('v')} AND v.estado=N'ACTIVA' ORDER BY v.realizado_at DESC
    `);
    const summary = (park.recordset[0] ?? {}) as Row;
    return {
      generatedAt: new Date().toISOString(),
      summary: {
        equipment: Number(summary.equipmentCount ?? 0), areas: Number(summary.areaCount ?? 0),
        compliant: Number(summary.compliantCount ?? 0), observed: Number(summary.observedCount ?? 0),
        nonCompliant: Number(summary.nonCompliantCount ?? 0), withoutVerification: Number(summary.pendingCount ?? 0),
      },
      alerts: alerts.recordset, dueTests: due.recordset, recentVerifications: recent.recordset,
      externalCalibrations: [],
    };
  }

  private async getMetricaDashboard(): Promise<Record<string, unknown>> {
    const pool = await getSqlPool();
    const result = await pool.request().query(`
      SELECT TOP 100 a.alerta_id AS id,a.cliente_id AS clientId,a.planta_id AS plantId,
        a.cod_metrica AS equipmentCode,a.tipo AS type,a.resumen AS detail,
        a.estado_metrica AS status,a.compartida_at AS sharedAt,a.creado_at AS createdAt
      FROM ivmet.alertas a WHERE a.visibilidad_metrica=N'shared'
      ORDER BY CASE a.estado_metrica WHEN N'pending' THEN 0 WHEN N'acknowledged' THEN 1 ELSE 2 END,a.compartida_at DESC
    `);
    const rows = result.recordset as Row[];
    return {
      generatedAt: new Date().toISOString(),
      summary: {
        sharedAlerts: rows.length,
        pending: rows.filter((row) => row.status === 'pending').length,
        acknowledged: rows.filter((row) => row.status === 'acknowledged').length,
        attended: rows.filter((row) => row.status === 'attended').length,
      },
      alerts: rows,
    };
  }
}

export const dashboardService = new DashboardService();

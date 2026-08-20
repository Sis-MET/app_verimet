import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ConflictError, NotFoundError } from '@core/errors';
import { writeAudit, type AuditEvent } from '@shared/audit/audit';
import { bindTenantAccess, plantAccessPredicate } from '@shared/security/access-control';
import type { AuthenticatedUser } from '@shared/types';

type Row = Record<string, unknown>;

export class AlertsService {
  async list(user: AuthenticatedUser, query: { page: number; pageSize: number; status?: string }): Promise<{ items: Row[]; total: number; page: number; pageSize: number }> {
    const pool = await getSqlPool();
    const offset = (query.page - 1) * query.pageSize;
    const request = pool.request().input('status', sql.NVarChar(30), query.status ?? null)
      .input('offset', sql.Int, offset).input('pageSize', sql.Int, query.pageSize);
    let where: string;
    if (user.empresaId) {
      bindTenantAccess(request, user);
      where = `${plantAccessPredicate('a')} AND (@status IS NULL OR a.estado_cliente=@status)`;
    } else {
      where = `a.visibilidad_metrica=N'shared' AND (@status IS NULL OR a.estado_metrica=@status)`;
    }
    const result = await request.query(`
      SELECT COUNT(*) OVER() AS total,a.alerta_id AS id,a.verificacion_id AS verificationId,
        a.cliente_id AS clientId,a.planta_id AS plantId,a.cod_metrica AS equipmentCode,
        a.tipo AS type,a.resumen AS summary,a.estado_cliente AS clientStatus,
        a.visibilidad_metrica AS metricaVisibility,a.compartida_at AS sharedAt,
        a.mensaje_compartido AS sharedMessage,a.estado_metrica AS metricaStatus,
        a.reconocida_at AS acknowledgedAt,a.atendida_at AS attendedAt,a.nota_atencion AS attendanceNote,
        a.creado_at AS createdAt
      FROM ivmet.alertas a WHERE ${where}
      ORDER BY a.creado_at DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
    `);
    const rows = result.recordset as Row[];
    return { items: rows, total: Number(rows[0]?.total ?? 0), page: query.page, pageSize: query.pageSize };
  }

  async share(alertId: string, message: string, user: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const result = await bindTenantAccess(pool.request(), user).input('id', sql.UniqueIdentifier, alertId)
      .input('message', sql.NVarChar(1000), message).query(`
        UPDATE a SET visibilidad_metrica=N'shared',compartida_at=SYSUTCDATETIME(),compartida_por=@userId,
          mensaje_compartido=@message,estado_metrica=N'pending'
        FROM ivmet.alertas a WHERE a.alerta_id=@id AND ${plantAccessPredicate('a')} AND a.visibilidad_metrica=N'private';
        SELECT @@ROWCOUNT AS affected;
      `);
    if (!Number(result.recordset[0]?.affected)) throw new ConflictError('La alerta no existe, no esta autorizada o ya fue compartida');
    await writeAudit(pool.request(), { ...metadata, actor: user, entity: 'alerta', entityId: alertId, action: 'share', after: { message } });
  }

  async archive(alertId: string, user: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const result = await bindTenantAccess(pool.request(), user).input('id', sql.UniqueIdentifier, alertId).query(`
      UPDATE a SET estado_cliente=N'archived' FROM ivmet.alertas a
      WHERE a.alerta_id=@id AND ${plantAccessPredicate('a')}; SELECT @@ROWCOUNT AS affected;
    `);
    if (!Number(result.recordset[0]?.affected)) throw new NotFoundError('Alerta no encontrada');
    await writeAudit(pool.request(), { ...metadata, actor: user, entity: 'alerta', entityId: alertId, action: 'archive' });
  }

  async acknowledge(alertId: string, user: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const result = await pool.request().input('id', sql.UniqueIdentifier, alertId).input('actor', sql.UniqueIdentifier, user.id).query(`
      UPDATE ivmet.alertas SET estado_metrica=N'acknowledged',reconocida_at=SYSUTCDATETIME(),reconocida_por=@actor
      WHERE alerta_id=@id AND visibilidad_metrica=N'shared' AND estado_metrica=N'pending'; SELECT @@ROWCOUNT AS affected;
    `);
    if (!Number(result.recordset[0]?.affected)) throw new ConflictError('La alerta no esta pendiente o no fue compartida');
    await writeAudit(pool.request(), { ...metadata, actor: user, entity: 'alerta', entityId: alertId, action: 'acknowledge' });
  }

  async attend(alertId: string, comment: string, user: AuthenticatedUser, metadata: Pick<AuditEvent, 'ip' | 'deviceId'>): Promise<void> {
    const pool = await getSqlPool();
    const result = await pool.request().input('id', sql.UniqueIdentifier, alertId).input('actor', sql.UniqueIdentifier, user.id)
      .input('comment', sql.NVarChar(1000), comment).query(`
        UPDATE ivmet.alertas SET estado_metrica=N'attended',atendida_at=SYSUTCDATETIME(),atendida_por=@actor,nota_atencion=@comment
        WHERE alerta_id=@id AND visibilidad_metrica=N'shared' AND estado_metrica IN (N'pending',N'acknowledged'); SELECT @@ROWCOUNT AS affected;
      `);
    if (!Number(result.recordset[0]?.affected)) throw new ConflictError('La alerta no fue compartida o ya esta atendida');
    await writeAudit(pool.request(), { ...metadata, actor: user, entity: 'alerta', entityId: alertId, action: 'attend', after: { comment } });
  }
}

export const alertsService = new AlertsService();

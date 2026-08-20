import type { Request as ExpressRequest } from 'express';
import type { Request as SqlRequest } from 'mssql';
import { sql } from '@core/database/sql-server-pool';
import type { AuthenticatedUser } from '@shared/types';

export interface AuditEvent {
  actor?: AuthenticatedUser;
  entity: string;
  entityId: string;
  action: string;
  before?: unknown;
  after?: unknown;
  ip?: string;
  deviceId?: string;
}

export async function writeAudit(request: SqlRequest, event: AuditEvent): Promise<void> {
  await request
    .input('auditActor', sql.UniqueIdentifier, event.actor?.id ?? null)
    .input('auditTenant', sql.NVarChar(50), event.actor?.empresaId ?? null)
    .input('auditEntity', sql.NVarChar(80), event.entity)
    .input('auditEntityId', sql.NVarChar(150), event.entityId)
    .input('auditAction', sql.NVarChar(80), event.action)
    .input('auditBefore', sql.NVarChar(sql.MAX), event.before === undefined ? null : JSON.stringify(event.before))
    .input('auditAfter', sql.NVarChar(sql.MAX), event.after === undefined ? null : JSON.stringify(event.after))
    .input('auditIp', sql.NVarChar(64), event.ip ?? null)
    .input('auditDevice', sql.NVarChar(200), event.deviceId ?? null)
    .query(`
      INSERT INTO ivmet.auditoria
        (actor_id, cliente_id, entidad, entidad_id, accion, antes_json,
         despues_json, ip, dispositivo_id)
      VALUES
        (@auditActor, @auditTenant, @auditEntity, @auditEntityId, @auditAction,
         @auditBefore, @auditAfter, @auditIp, @auditDevice)
    `);
}

export function auditRequestMetadata(req: ExpressRequest): Pick<AuditEvent, 'ip' | 'deviceId'> {
  return {
    ip: req.ip || req.socket.remoteAddress || undefined,
    deviceId: typeof req.headers['x-device-id'] === 'string' ? req.headers['x-device-id'] : undefined,
  };
}

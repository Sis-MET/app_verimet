import type { Request } from 'express';
import type { Request as SqlRequest } from 'mssql';
import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ForbiddenError, UnauthorizedError } from '@core/errors';
import type { AuthenticatedUser } from '@shared/types';

export function authenticatedUser(req: Request): AuthenticatedUser {
  if (!req.user) throw new UnauthorizedError();
  return req.user;
}

export function clientTenant(user: AuthenticatedUser): string {
  if (!user.empresaId) throw new ForbiddenError('Esta operacion requiere un usuario de cliente');
  return user.empresaId;
}

export async function assertPlantAccess(user: AuthenticatedUser, plantId: string): Promise<void> {
  const tenant = clientTenant(user);
  const pool = await getSqlPool();
  const result = await pool
    .request()
    .input('userId', sql.UniqueIdentifier, user.id)
    .input('tenant', sql.NVarChar(50), tenant)
    .input('plantId', sql.NVarChar(50), plantId)
    .query(`
      SELECT TOP 1 1 AS allowed
      FROM ivmet.usuario_plantas
      WHERE usuario_id = @userId AND cliente_id = @tenant AND planta_id = @plantId AND activa=1
    `);
  if (!result.recordset[0]) throw new ForbiddenError('La planta no esta asignada al usuario');
}

export function plantAccessPredicate(alias: string): string {
  return `${alias}.cliente_id = @tenant AND EXISTS (
    SELECT 1 FROM ivmet.usuario_plantas access
    WHERE access.usuario_id = @userId
      AND access.cliente_id = ${alias}.cliente_id
      AND access.planta_id = ${alias}.planta_id
      AND access.activa = 1
  )`;
}

export function bindTenantAccess(
  request: SqlRequest,
  user: AuthenticatedUser,
): SqlRequest {
  return request
    .input('userId', sql.UniqueIdentifier, user.id)
    .input('tenant', sql.NVarChar(50), clientTenant(user));
}

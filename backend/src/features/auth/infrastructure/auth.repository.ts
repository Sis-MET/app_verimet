import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { DatabaseError, UnauthorizedError } from '@core/errors';
import type { StoredUser, UserProfile } from '../domain/auth.types';
import type { UserRole } from '@shared/types';

type Row = Record<string, unknown>;

function mapUser(row: Row): StoredUser {
  return {
    id: String(row.usuario_id),
    username: String(row.usuario),
    normalizedUsername: String(row.usuario_normalizado),
    name: String(row.nombre),
    email: row.email === null ? null : String(row.email),
    passwordHash: String(row.password_hash),
    role: String(row.rol) as UserRole,
    empresaId: row.cliente_id === null ? null : String(row.cliente_id),
    status: String(row.estado) as StoredUser['status'],
    mustChangePassword: Boolean(row.debe_cambiar_password),
    failedAttempts: Number(row.intentos_fallidos),
    lockedUntil: row.bloqueado_hasta ? new Date(String(row.bloqueado_hasta)) : null,
    tokenVersion: Number(row.token_version),
  };
}

export class AuthRepository {
  async findByNormalizedUsername(normalizedUsername: string): Promise<StoredUser | null> {
    const pool = await getSqlPool();
    const result = await pool
      .request()
      .input('username', sql.NVarChar(100), normalizedUsername)
      .query(`
        SELECT TOP 1 usuario_id, usuario, usuario_normalizado, nombre, email,
          password_hash, rol, cliente_id, estado, debe_cambiar_password,
          intentos_fallidos, bloqueado_hasta, token_version
        FROM ivmet.usuarios
        WHERE usuario_normalizado = @username
      `);
    const row = result.recordset[0] as Row | undefined;
    return row ? mapUser(row) : null;
  }

  async findById(id: string): Promise<StoredUser | null> {
    const pool = await getSqlPool();
    const result = await pool
      .request()
      .input('id', sql.UniqueIdentifier, id)
      .query(`
        SELECT TOP 1 usuario_id, usuario, usuario_normalizado, nombre, email,
          password_hash, rol, cliente_id, estado, debe_cambiar_password,
          intentos_fallidos, bloqueado_hasta, token_version
        FROM ivmet.usuarios WHERE usuario_id = @id
      `);
    const row = result.recordset[0] as Row | undefined;
    return row ? mapUser(row) : null;
  }

  async recordFailedAttempt(userId: string): Promise<void> {
    const pool = await getSqlPool();
    await pool
      .request()
      .input('id', sql.UniqueIdentifier, userId)
      .query(`
        DECLARE @cambio TABLE (usuario_id uniqueidentifier,intentos int,bloqueado_hasta datetime2(3));
        UPDATE ivmet.usuarios
        SET intentos_fallidos = intentos_fallidos + 1,
            bloqueado_hasta = CASE
              WHEN intentos_fallidos + 1 >= 5 THEN DATEADD(MINUTE, 15, SYSUTCDATETIME())
              ELSE bloqueado_hasta
            END,
            actualizado_at = SYSUTCDATETIME()
        OUTPUT INSERTED.usuario_id,INSERTED.intentos_fallidos,INSERTED.bloqueado_hasta
          INTO @cambio(usuario_id,intentos,bloqueado_hasta)
        WHERE usuario_id = @id;
        INSERT INTO ivmet.auditoria (actor_id,cliente_id,entidad,entidad_id,accion,despues_json)
        SELECT u.usuario_id,u.cliente_id,N'usuario',CONVERT(nvarchar(150),u.usuario_id),N'account_lock',
          (SELECT c.intentos AS failedAttempts,c.bloqueado_hasta AS lockedUntil FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
        FROM @cambio c JOIN ivmet.usuarios u ON u.usuario_id=c.usuario_id WHERE c.intentos=5;
      `);
  }

  async recordSuccessfulLogin(userId: string, ip?: string, deviceId?: string): Promise<void> {
    const pool = await getSqlPool();
    await pool
      .request()
      .input('id', sql.UniqueIdentifier, userId)
      .input('ip', sql.NVarChar(64), ip ?? null)
      .input('device', sql.NVarChar(200), deviceId ?? null)
      .query(`
        UPDATE ivmet.usuarios
        SET intentos_fallidos = 0, bloqueado_hasta = NULL,
            ultimo_acceso_at = SYSUTCDATETIME(), actualizado_at = SYSUTCDATETIME()
        WHERE usuario_id = @id;
        INSERT INTO ivmet.auditoria (actor_id,cliente_id,entidad,entidad_id,accion,ip,dispositivo_id)
        SELECT usuario_id,cliente_id,N'sesion',CONVERT(nvarchar(150),usuario_id),
          CASE WHEN rol LIKE N'metrica_%' THEN N'admin_login' ELSE N'login' END,@ip,@device
        FROM ivmet.usuarios WHERE usuario_id=@id
      `);
  }

  async createRefreshSession(input: {
    userId: string;
    tokenHash: Buffer;
    deviceId: string;
    deviceName?: string;
    expiresAt: Date;
    ip?: string;
  }): Promise<string> {
    const pool = await getSqlPool();
    const result = await pool
      .request()
      .input('userId', sql.UniqueIdentifier, input.userId)
      .input('tokenHash', sql.VarBinary(32), input.tokenHash)
      .input('deviceId', sql.NVarChar(200), input.deviceId)
      .input('deviceName', sql.NVarChar(200), input.deviceName ?? null)
      .input('expiresAt', sql.DateTime2(3), input.expiresAt)
      .input('ip', sql.NVarChar(64), input.ip ?? null)
      .query(`
        INSERT INTO ivmet.sesiones_refresh
          (usuario_id, token_hash, dispositivo_id, dispositivo_nombre, expira_at, ip_creacion)
        OUTPUT INSERTED.sesion_id
        VALUES (@userId, @tokenHash, @deviceId, @deviceName, @expiresAt, @ip)
      `);
    return String(result.recordset[0]?.sesion_id);
  }

  async rotateRefreshSession(input: {
    oldHash: Buffer;
    newHash: Buffer;
    deviceId: string;
    deviceName?: string;
    expiresAt: Date;
    ip?: string;
  }): Promise<StoredUser> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
    try {
      const currentResult = await transaction.request()
        .input('hash', sql.VarBinary(32), input.oldHash)
        .input('deviceId', sql.NVarChar(200), input.deviceId)
        .query(`
          SELECT s.sesion_id, s.usuario_id, s.dispositivo_id, s.expira_at,
            s.revocado_at, u.usuario, u.usuario_normalizado, u.nombre, u.email,
            u.password_hash, u.rol, u.cliente_id, u.estado,
            u.debe_cambiar_password, u.intentos_fallidos,
            u.bloqueado_hasta, u.token_version
          FROM ivmet.sesiones_refresh s WITH (UPDLOCK, HOLDLOCK)
          JOIN ivmet.usuarios u ON u.usuario_id = s.usuario_id
          WHERE s.token_hash = @hash AND s.dispositivo_id = @deviceId
        `);
      const row = currentResult.recordset[0] as Row | undefined;
      if (!row || row.revocado_at || new Date(String(row.expira_at)) <= new Date()) {
        throw new UnauthorizedError('Refresh token invalido, vencido o revocado');
      }
      const user = mapUser(row);
      if (user.status !== 'ACTIVO') throw new UnauthorizedError('Usuario inactivo');

      const inserted = await transaction.request()
        .input('userId', sql.UniqueIdentifier, user.id)
        .input('newHash', sql.VarBinary(32), input.newHash)
        .input('deviceId', sql.NVarChar(200), input.deviceId)
        .input('deviceName', sql.NVarChar(200), input.deviceName ?? null)
        .input('expiresAt', sql.DateTime2(3), input.expiresAt)
        .input('ip', sql.NVarChar(64), input.ip ?? null)
        .query(`
          INSERT INTO ivmet.sesiones_refresh
            (usuario_id, token_hash, dispositivo_id, dispositivo_nombre, expira_at, ip_creacion)
          OUTPUT INSERTED.sesion_id
          VALUES (@userId, @newHash, @deviceId, @deviceName, @expiresAt, @ip)
        `);
      const replacementId = String(inserted.recordset[0]?.sesion_id);
      await transaction.request()
        .input('oldHash', sql.VarBinary(32), input.oldHash)
        .input('replacementId', sql.UniqueIdentifier, replacementId)
        .query(`
          UPDATE ivmet.sesiones_refresh
          SET revocado_at = SYSUTCDATETIME(), reemplazado_por = @replacementId,
              ultimo_uso_at = SYSUTCDATETIME()
          WHERE token_hash = @oldHash AND revocado_at IS NULL
        `);
      await transaction.commit();
      return user;
    } catch (error) {
      await transaction.rollback();
      if (error instanceof UnauthorizedError) throw error;
      throw new DatabaseError('No se pudo rotar la sesion', error);
    }
  }

  async revokeRefreshSession(tokenHash: Buffer): Promise<void> {
    const pool = await getSqlPool();
    await pool
      .request()
      .input('hash', sql.VarBinary(32), tokenHash)
      .query(`
        DECLARE @revocados TABLE (usuario_id uniqueidentifier);
        UPDATE ivmet.sesiones_refresh
        SET revocado_at = COALESCE(revocado_at, SYSUTCDATETIME())
        OUTPUT INSERTED.usuario_id INTO @revocados(usuario_id)
        WHERE token_hash = @hash AND revocado_at IS NULL;
        INSERT INTO ivmet.auditoria (actor_id,cliente_id,entidad,entidad_id,accion)
        SELECT DISTINCT u.usuario_id,u.cliente_id,N'sesion',CONVERT(nvarchar(150),u.usuario_id),N'logout'
        FROM @revocados r JOIN ivmet.usuarios u ON u.usuario_id=r.usuario_id
      `);
  }

  async changePassword(userId: string, passwordHash: string): Promise<void> {
    const pool = await getSqlPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      await transaction.request()
        .input('id', sql.UniqueIdentifier, userId)
        .input('hash', sql.NVarChar(255), passwordHash)
        .query(`
          UPDATE ivmet.usuarios
          SET password_hash = @hash, debe_cambiar_password = 0,
              token_version = token_version + 1, actualizado_at = SYSUTCDATETIME()
          WHERE usuario_id = @id
        `);
      await transaction.request().input('id', sql.UniqueIdentifier, userId).query(`
        INSERT INTO ivmet.auditoria (actor_id,cliente_id,entidad,entidad_id,accion)
        SELECT usuario_id,cliente_id,N'usuario',CONVERT(nvarchar(150),usuario_id),N'password_change'
        FROM ivmet.usuarios WHERE usuario_id=@id
      `);
      await transaction.request()
        .input('id', sql.UniqueIdentifier, userId)
        .query(`
          UPDATE ivmet.sesiones_refresh
          SET revocado_at = COALESCE(revocado_at, SYSUTCDATETIME())
          WHERE usuario_id = @id
        `);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new DatabaseError('No se pudo cambiar la contrasena', error);
    }
  }

  async getProfile(userId: string): Promise<UserProfile> {
    const user = await this.findById(userId);
    if (!user) throw new UnauthorizedError('Usuario no encontrado');
    const pool = await getSqlPool();
    let empresa: UserProfile['empresa'] = null;
    if (user.empresaId) {
      const companyResult = await pool
        .request()
        .input('clienteId', sql.NVarChar(50), user.empresaId)
        .query(`
          SELECT TOP 1 CONVERT(nvarchar(50), cliente_id) AS id,
            COALESCE(cliente, razonsocial, CONVERT(nvarchar(50), cliente_id)) AS nombre
          FROM dbo.DATA_CLIENTES
          WHERE CONVERT(nvarchar(50), cliente_id) = @clienteId
        `);
      const row = companyResult.recordset[0] as Row | undefined;
      empresa = row ? { id: String(row.id), name: String(row.nombre) } : { id: user.empresaId, name: user.empresaId };
    }
    const plantsResult = await pool
      .request()
      .input('userId', sql.UniqueIdentifier, user.id)
      .query(`
        SELECT up.planta_id AS id,
          COALESCE(CONVERT(nvarchar(100), p.codigo_planta), up.planta_id) AS codigo,
          COALESCE(CONVERT(nvarchar(200), p.planta), up.planta_id) AS nombre,
          CONVERT(nvarchar(500), p.dir) AS direccion
        FROM ivmet.usuario_plantas up
        LEFT JOIN dbo.DATA_PLANTAS p
          ON CONVERT(nvarchar(50), p.planta_id) = up.planta_id
        WHERE up.usuario_id = @userId AND up.activa=1
        ORDER BY nombre
      `);
    return {
      id: user.id,
      username: user.username,
      name: user.name,
      email: user.email,
      role: user.role,
      mustChangePassword: user.mustChangePassword,
      empresa,
      plants: (plantsResult.recordset as Row[]).map((row) => ({
        id: String(row.id),
        code: String(row.codigo),
        name: String(row.nombre),
        address: row.direccion === null ? null : String(row.direccion),
      })),
    };
  }
}

export const authRepository = new AuthRepository();

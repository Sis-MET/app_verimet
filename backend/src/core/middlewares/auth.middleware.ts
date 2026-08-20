import type { NextFunction, Request, RequestHandler, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '@core/config';
import { getSqlPool, sql } from '@core/database/sql-server-pool';
import { ForbiddenError, UnauthorizedError } from '@core/errors';
import type { AccessTokenPayload, AuthenticatedUser, UserRole } from '@shared/types';
import { isMetricaStaff } from '@shared/types';

function extractBearerToken(req: Request): string {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    throw new UnauthorizedError('Falta el header Authorization: Bearer <token>');
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) throw new UnauthorizedError('Token vacio');
  return token;
}

/**
 * Verifica el JWT y deja el usuario (con su empresa_id) en `req.user`.
 *
 * REGLA MULTI-TENANT: el `empresa_id` SIEMPRE sale del token, nunca del body,
 * query o params. Los casos de uso deben leerlo de `req.user.empresaId`.
 */
export const authenticate: RequestHandler = (req: Request, _res: Response, next: NextFunction) => {
  void authenticateRequest(req, next);
};

async function authenticateRequest(req: Request, next: NextFunction): Promise<void> {
  try {
    const token = extractBearerToken(req);
    const payload = jwt.verify(token, env.JWT_SECRET, {
      issuer: env.JWT_ISSUER,
      audience: env.JWT_AUDIENCE,
      algorithms: ['HS256'],
    }) as AccessTokenPayload;

    if (payload.type !== 'access') throw new UnauthorizedError('Tipo de token invalido');

    const pool = await getSqlPool();
    const result = await pool
      .request()
      .input('usuarioId', sql.UniqueIdentifier, payload.sub)
      .input('tokenVersion', sql.Int, payload.token_version)
      .query(`
        SELECT TOP 1 usuario_id, usuario, nombre, rol, cliente_id,
          debe_cambiar_password, token_version
        FROM ivmet.usuarios
        WHERE usuario_id = @usuarioId
          AND token_version = @tokenVersion
          AND estado = N'ACTIVO'
      `);
    const current = result.recordset[0] as Record<string, unknown> | undefined;
    if (!current) throw new UnauthorizedError('La sesion fue revocada o el usuario esta inactivo');

    const user: AuthenticatedUser = {
      id: String(current.usuario_id),
      username: String(current.usuario),
      name: String(current.nombre),
      role: String(current.rol) as UserRole,
      empresaId: current.cliente_id === null ? null : String(current.cliente_id),
      mustChangePassword: Boolean(current.debe_cambiar_password),
      tokenVersion: Number(current.token_version),
    };

    if (!isMetricaStaff(user) && !user.empresaId) {
      throw new UnauthorizedError('El token no contiene empresa_id para un usuario de cliente');
    }

    req.user = user;
    next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      next(new UnauthorizedError('Token expirado', { expiredAt: error.expiredAt }));
      return;
    }
    if (error instanceof jwt.JsonWebTokenError) {
      next(new UnauthorizedError('Token invalido'));
      return;
    }
    next(error);
  }
}

/** Restringe una ruta a los roles indicados. Usar despues de `authenticate`. */
export function requireRole(...roles: UserRole[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) {
      next(new UnauthorizedError());
      return;
    }
    if (!roles.includes(req.user.role)) {
      next(new ForbiddenError('Su rol no tiene acceso a este recurso'));
      return;
    }
    next();
  };
}

/** Atajo para rutas exclusivas de personal interno de Metrica (ej. dashboard global). */
export const requireMetricaStaff: RequestHandler = (req, _res, next) => {
  if (!req.user) {
    next(new UnauthorizedError());
    return;
  }
  if (!isMetricaStaff(req.user)) {
    next(new ForbiddenError('Recurso exclusivo de personal de Metrica'));
    return;
  }
  next();
};

/** Bloquea el resto de la API hasta cambiar una clave temporal. */
export const requirePasswordChanged: RequestHandler = (req, _res, next) => {
  if (!req.user) {
    next(new UnauthorizedError());
    return;
  }
  if (req.user.mustChangePassword) {
    next(new ForbiddenError('Debe cambiar la contrasena temporal antes de continuar'));
    return;
  }
  next();
};

/**
 * Devuelve el tenant que debe usarse en las queries del request actual.
 * Lanza si el usuario no tiene empresa asignada (evita queries sin filtro).
 */
export function requireTenant(req: Request): string {
  if (!req.user) throw new UnauthorizedError();
  if (!req.user.empresaId) {
    throw new ForbiddenError('El usuario no tiene una empresa asignada');
  }
  return req.user.empresaId;
}

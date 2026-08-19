import type { NextFunction, Request, RequestHandler, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '@core/config';
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
  try {
    const token = extractBearerToken(req);
    const payload = jwt.verify(token, env.JWT_SECRET) as AccessTokenPayload;

    const user: AuthenticatedUser = {
      id: payload.sub,
      email: payload.email,
      role: payload.role,
      empresaId: payload.empresa_id ?? null,
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
};

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

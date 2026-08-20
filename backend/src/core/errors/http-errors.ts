import { ApiError } from './api-error';

export class ValidationError extends ApiError {
  constructor(message = 'Datos de entrada invalidos', details?: unknown) {
    super(message, 400, 'VALIDATION_ERROR', details);
  }
}

export class UnauthorizedError extends ApiError {
  constructor(message = 'Credenciales invalidas o token ausente', details?: unknown) {
    super(message, 401, 'UNAUTHORIZED', details);
  }
}

export class ForbiddenError extends ApiError {
  constructor(message = 'No tiene permisos sobre este recurso', details?: unknown) {
    super(message, 403, 'FORBIDDEN', details);
  }
}

export class NotFoundError extends ApiError {
  constructor(message = 'Recurso no encontrado', details?: unknown) {
    super(message, 404, 'NOT_FOUND', details);
  }
}

export class ConflictError extends ApiError {
  constructor(message = 'El recurso ya existe o esta en un estado incompatible', details?: unknown) {
    super(message, 409, 'CONFLICT', details);
  }
}

export class TooManyRequestsError extends ApiError {
  constructor(message = 'Demasiados intentos; intente nuevamente mas tarde', details?: unknown) {
    super(message, 429, 'TOO_MANY_REQUESTS', details);
  }
}

export class ServiceUnavailableError extends ApiError {
  constructor(message = 'Servicio temporalmente no disponible', details?: unknown) {
    super(message, 503, 'SERVICE_UNAVAILABLE', details);
  }
}

export class DatabaseError extends ApiError {
  constructor(message = 'Error de base de datos', details?: unknown) {
    super(message, 500, 'DATABASE_ERROR', details, false);
  }
}

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

export class DatabaseError extends ApiError {
  constructor(message = 'Error de base de datos', details?: unknown) {
    super(message, 500, 'DATABASE_ERROR', details, false);
  }
}

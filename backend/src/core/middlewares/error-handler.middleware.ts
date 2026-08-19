import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';
import { ApiError, NotFoundError, ValidationError } from '@core/errors';
import { isProduction } from '@core/config';
import { logger } from '@shared/logger';

/** 404 para rutas no registradas. Va justo antes del error handler. */
export const notFoundHandler: RequestHandler = (req, _res, next) => {
  next(new NotFoundError(`Ruta no encontrada: ${req.method} ${req.originalUrl}`));
};

/** Error handler global: unico lugar donde se traduce un error a respuesta HTTP. */
export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  let apiError: ApiError;

  if (err instanceof ApiError) {
    apiError = err;
  } else if (err instanceof ZodError) {
    apiError = new ValidationError('Datos de entrada invalidos', err.issues);
  } else {
    apiError = new ApiError(
      isProduction ? 'Error interno del servidor' : String((err as Error)?.message ?? err),
      500,
      'INTERNAL_ERROR',
      undefined,
      false,
    );
  }

  const logPayload = {
    requestId: req.requestId,
    method: req.method,
    url: req.originalUrl,
    statusCode: apiError.statusCode,
    code: apiError.code,
    userId: req.user?.id,
    empresaId: req.user?.empresaId,
  };

  if (apiError.statusCode >= 500) {
    logger.error({ ...logPayload, err }, apiError.message);
  } else {
    logger.warn(logPayload, apiError.message);
  }

  res.status(apiError.statusCode).json(apiError.toJSON());
};

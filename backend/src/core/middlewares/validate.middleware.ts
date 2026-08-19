import type { RequestHandler } from 'express';
import type { ZodTypeAny } from 'zod';
import { ValidationError } from '@core/errors';

type ValidatableSource = 'body' | 'query' | 'params';

/**
 * Valida y normaliza una porcion del request con un schema zod.
 * Los schemas viven en `features/<feature>/presentation/dto/`.
 */
export function validate(schema: ZodTypeAny, source: ValidatableSource = 'body'): RequestHandler {
  return (req, _res, next) => {
    const result = schema.safeParse(req[source]);
    if (!result.success) {
      next(new ValidationError(`Error de validacion en ${source}`, result.error.issues));
      return;
    }
    // Se reemplaza por el valor parseado (con coerciones y defaults aplicados).
    req[source] = result.data;
    next();
  };
}

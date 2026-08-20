/**
 * Error base de la API. Todo error que el cliente deba ver como respuesta
 * controlada (4xx/5xx con cuerpo JSON) hereda de aca. Cualquier otro error
 * que llegue al error handler se trata como 500 sin filtrar detalles.
 */
export class ApiError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly details?: unknown;
  /** true = error esperado del dominio; false = bug/fallo no controlado. */
  public readonly isOperational: boolean;

  constructor(
    message: string,
    statusCode = 500,
    code = 'INTERNAL_ERROR',
    details?: unknown,
    isOperational = true,
  ) {
    super(message);
    this.name = new.target.name;
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, new.target);
  }

  toJSON() {
    return {
      error: {
        code: this.code,
        message: this.message,
        ...(this.isOperational && this.details !== undefined ? { details: this.details } : {}),
      },
    };
  }
}

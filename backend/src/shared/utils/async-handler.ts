import type { NextFunction, Request, RequestHandler, Response } from 'express';

/**
 * Envuelve un handler async para que cualquier throw/rejection llegue al
 * error handler global en vez de quedar como unhandled rejection.
 */
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    void fn(req, res, next).catch(next);
  };
}

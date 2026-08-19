import { randomUUID } from 'node:crypto';
import type { RequestHandler } from 'express';

/** Asigna un id de correlacion por request y lo expone en la respuesta. */
export const requestContext: RequestHandler = (req, res, next) => {
  const incoming = req.headers['x-request-id'];
  req.requestId = typeof incoming === 'string' && incoming ? incoming : randomUUID();
  res.setHeader('X-Request-Id', req.requestId);
  next();
};

import express, { type Express } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { corsOrigins, env } from '@core/config';
import { errorHandler, notFoundHandler, requestContext } from '@core/middlewares';
import { apiRouter } from './routes';

/**
 * Construye la instancia de Express con los middlewares globales.
 * No hace `listen()`: eso vive en server.ts (asi los tests pueden importar
 * la app sin levantar un puerto).
 */
export function createApp(): Express {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', true);

  app.use(helmet());
  app.use(cors({ origin: corsOrigins, credentials: true }));
  app.use(express.json({ limit: '5mb' })); // el batch de sync puede ser grande
  app.use(express.urlencoded({ extended: true }));
  app.use(requestContext);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', service: 'ivmet-api', env: env.NODE_ENV,
      ivmetEnabled: env.IVMET_ENABLED, syncEnabled: env.IVMET_SYNC_ENABLED,
      timestamp: new Date().toISOString() });
  });

  if (env.IVMET_ENABLED) app.use(env.API_PREFIX, apiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

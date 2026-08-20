import { Router, type RequestHandler } from 'express';
import type { ConnectionPool } from 'mssql';
import { env } from '@core/config';
import { configureSqlPool } from '@core/database/sql-server-pool';
import { apiRouter } from './routes';

/**
 * Adaptador para montar IvMET dentro del proceso Express corporativo:
 * `app.use('/api/ivmet/v1', createIvmetRouter({ sqlPool }))`.
 *
 * Si IVMET_ENABLED=false devuelve un router vacio. El pool inyectado pertenece
 * al host y nunca sera cerrado por IvMET.
 */
export function createIvmetRouter(options: { sqlPool?: ConnectionPool } = {}): RequestHandler {
  if (options.sqlPool) configureSqlPool(options.sqlPool);
  return env.IVMET_ENABLED ? apiRouter : Router();
}

export const ivmetEnabled = env.IVMET_ENABLED;

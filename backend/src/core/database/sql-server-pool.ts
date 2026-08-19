import sql from 'mssql';
import { env } from '@core/config';
import { logger } from '@shared/logger';
import { DatabaseError } from '@core/errors';

/**
 * Pool de conexiones `mssql` para los casos donde Prisma no alcanza:
 * stored procedures legados, queries con hints especificos, bulk insert
 * de resultados de sincronizacion, etc.
 */
const poolConfig: sql.config = {
  server: env.DB_HOST,
  port: env.DB_PORT,
  database: env.DB_NAME,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  options: {
    encrypt: env.DB_ENCRYPT,
    trustServerCertificate: env.DB_TRUST_SERVER_CERTIFICATE,
    enableArithAbort: true,
  },
  pool: { max: 10, min: 0, idleTimeoutMillis: 30_000 },
};

let pool: sql.ConnectionPool | undefined;

export async function getSqlPool(): Promise<sql.ConnectionPool> {
  if (pool?.connected) return pool;
  try {
    pool = await new sql.ConnectionPool(poolConfig).connect();
    logger.info({ host: env.DB_HOST, db: env.DB_NAME }, 'Pool mssql conectado');
    return pool;
  } catch (error) {
    throw new DatabaseError('No se pudo conectar al SQL Server de Metrica', error);
  }
}

export async function closeSqlPool(): Promise<void> {
  if (pool?.connected) {
    await pool.close();
    pool = undefined;
  }
}

export { sql };

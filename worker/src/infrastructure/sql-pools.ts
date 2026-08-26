import sql from 'mssql';
import type { SqlConnectionSettings } from '../config';

function poolConfig(settings: SqlConnectionSettings): sql.config {
  return {
    server: settings.host,
    port: settings.port,
    database: settings.database,
    user: settings.user,
    password: settings.password,
    options: {
      encrypt: settings.encrypt,
      trustServerCertificate: settings.trustServerCertificate,
      enableArithAbort: true,
      useUTC: true,
    },
    pool: {
      max: 5,
      min: 0,
      idleTimeoutMillis: 30_000,
    },
    connectionTimeout: 15_000,
    requestTimeout: 60_000,
  };
}

export class SqlPools {
  readonly dataMet: sql.ConnectionPool;
  readonly ivmet: sql.ConnectionPool;

  constructor(dataMetSettings: SqlConnectionSettings, ivmetSettings: SqlConnectionSettings) {
    this.dataMet = new sql.ConnectionPool(poolConfig(dataMetSettings));
    this.ivmet = new sql.ConnectionPool(poolConfig(ivmetSettings));
  }

  async connect(): Promise<void> {
    await Promise.all([this.dataMet.connect(), this.ivmet.connect()]);
  }

  async close(): Promise<void> {
    await Promise.allSettled([this.dataMet.close(), this.ivmet.close()]);
  }
}

export { sql };

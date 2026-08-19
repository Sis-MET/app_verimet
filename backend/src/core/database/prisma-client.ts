import { PrismaClient } from '@prisma/client';
import { env, isProduction } from '@core/config';
import { logger } from '@shared/logger';

/**
 * Cliente Prisma (provider = sqlserver). Es la via por defecto para acceder a
 * SQL Server desde los repositorios de infrastructure/.
 *
 * Para procedimientos almacenados legados de Metrica que Prisma no modela bien,
 * usar el pool de `mssql` en `sql-server-pool.ts`.
 */
declare global {
  var __ivmetPrisma__: PrismaClient | undefined;
}

export const prisma =
  global.__ivmetPrisma__ ??
  new PrismaClient({
    log: isProduction ? ['warn', 'error'] : ['query', 'warn', 'error'],
  });

if (!isProduction) global.__ivmetPrisma__ = prisma;

export async function connectPrisma(): Promise<void> {
  await prisma.$connect();
  logger.info({ db: env.DB_NAME }, 'Prisma conectado a SQL Server');
}

export async function disconnectPrisma(): Promise<void> {
  await prisma.$disconnect();
}

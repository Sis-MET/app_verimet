import { env } from '@core/config';
import { closeSqlPool } from '@core/database/sql-server-pool';
import { disconnectPrisma } from '@core/database/prisma-client';
import { logger } from '@shared/logger';
import { createApp } from './app';

const app = createApp();

const server = app.listen(env.PORT, () => {
  logger.info(
    { port: env.PORT, env: env.NODE_ENV, prefix: env.API_PREFIX },
    'IvMET API escuchando',
  );
});

async function shutdown(signal: string): Promise<void> {
  logger.info({ signal }, 'Cerrando IvMET API...');
  server.close(() => logger.info('Servidor HTTP cerrado'));
  await Promise.allSettled([closeSqlPool(), disconnectPrisma()]);
  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled rejection');
});

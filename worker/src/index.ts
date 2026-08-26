import { dataMetSqlSettings, env, ivmetSqlSettings } from './config';
import { safeError } from './core/canonical';
import { DataMetRepository } from './infrastructure/datamet.repository';
import { IvmetRepository } from './infrastructure/ivmet.repository';
import { SqlPools } from './infrastructure/sql-pools';
import { SupabaseGateway } from './infrastructure/supabase.gateway';
import { logger } from './logger';
import { CatalogSyncService } from './services/catalog-sync.service';
import { HealthService } from './services/health.service';
import { OutboxSyncService } from './services/outbox-sync.service';

type Command = 'health' | 'catalog' | 'outbox' | 'once' | 'daemon';

function parseCommand(value: string | undefined): Command {
  const command = value ?? 'daemon';
  if (!['health', 'catalog', 'outbox', 'once', 'daemon'].includes(command)) {
    throw new Error(`Comando invalido: ${command}`);
  }
  return command as Command;
}

function assertMutationsEnabled(): void {
  if (!env.WORKER_ENABLED) {
    throw new Error('WORKER_ENABLED=false: health esta disponible, pero la sincronizacion esta bloqueada');
  }
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main(): Promise<void> {
  const command = parseCommand(process.argv[2]);
  const pools = new SqlPools(dataMetSqlSettings, ivmetSqlSettings);
  await pools.connect();

  const dataMet = new DataMetRepository(pools.dataMet);
  const ivmet = new IvmetRepository(pools.ivmet);
  const supabase = new SupabaseGateway();
  const health = new HealthService(dataMet, ivmet, supabase);
  const catalog = new CatalogSyncService(dataMet, supabase, ivmet);
  const outbox = new OutboxSyncService(supabase, ivmet);

  try {
    const healthResult = await health.check();
    logger.info(healthResult, 'Conectividad del worker validada');

    if (command === 'health') return;
    assertMutationsEnabled();

    if (command === 'catalog') {
      await catalog.run();
      return;
    }
    if (command === 'outbox') {
      await outbox.run();
      return;
    }
    if (command === 'once') {
      await catalog.run();
      await outbox.run();
      return;
    }

    let stopping = false;
    const stop = (signal: string) => {
      stopping = true;
      logger.info({ signal }, 'Detencion solicitada; se cerrara al terminar el ciclo actual');
    };
    process.once('SIGINT', () => stop('SIGINT'));
    process.once('SIGTERM', () => stop('SIGTERM'));

    let lastCatalogAt = 0;
    while (!stopping) {
      const now = Date.now();
      if (now - lastCatalogAt >= env.WORKER_CATALOG_INTERVAL_SECONDS * 1000) {
        await catalog.run();
        lastCatalogAt = Date.now();
      }
      await outbox.run();
      if (!stopping) await wait(env.WORKER_OUTBOX_POLL_SECONDS * 1000);
    }
  } finally {
    await pools.close();
  }
}

main().catch((error) => {
  logger.fatal({ error: safeError(error) }, 'IvMET Worker termino con error');
  process.exitCode = 1;
});

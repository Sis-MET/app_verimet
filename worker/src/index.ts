import { dataMetSqlSettings, env, ivmetSqlSettings } from './config';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import {
  assertWorkerMode,
  runWorkerLoop,
  type WorkerCommand,
} from './core/runtime';
import { safeError } from './core/canonical';
import { DataMetRepository } from './infrastructure/datamet.repository';
import { IvmetRepository } from './infrastructure/ivmet.repository';
import { SqlPools } from './infrastructure/sql-pools';
import { SupabaseGateway } from './infrastructure/supabase.gateway';
import { logger } from './logger';
import { CatalogSyncService } from './services/catalog-sync.service';
import { HealthService } from './services/health.service';
import { OutboxSyncService } from './services/outbox-sync.service';

type Command = WorkerCommand;

function parseCommand(value: string | undefined): Command {
  const command = value ?? 'daemon';
  if (!['health', 'catalog', 'outbox', 'once', 'daemon'].includes(command)) {
    throw new Error(`Comando invalido: ${command}`);
  }
  return command as Command;
}

async function main(): Promise<void> {
  const command = parseCommand(process.argv[2]);
  const pools = new SqlPools(dataMetSqlSettings, ivmetSqlSettings);
  const dataMet = new DataMetRepository(pools.dataMet);
  const ivmet = new IvmetRepository(pools.ivmet);
  const supabase = new SupabaseGateway();
  const health = new HealthService(dataMet, ivmet, supabase);
  const catalog = new CatalogSyncService(dataMet, supabase, ivmet);
  const outbox = new OutboxSyncService(supabase, ivmet);
  const instanceId = randomUUID();
  const shutdown = new AbortController();
  const failures = new Set<string>();
  let blocked = false;
  const report = async (state: string) => {
    try {
      await supabase.reportWorker(instanceId, command, state);
    } catch (error) {
      logger.warn(
        { error: safeError(error) },
        'No se pudo publicar el estado del worker',
      );
    }
  };
  const stop = () => shutdown.abort();
  const pause = async (seconds: number) => {
    try {
      await delay(seconds * 1000, undefined, { signal: shutdown.signal });
    } catch (error) {
      if (!shutdown.signal.aborted) throw error;
    }
  };

  try {
    if (command !== 'health') {
      try {
        assertWorkerMode(
          command,
          env.WORKER_ENABLED,
          env.NODE_ENV === 'production',
          env.WORKER_SCOPE_ID,
        );
      } catch (error) {
        blocked = true;
        await report('BLOCKED');
        throw error;
      }
      await report('STARTING');
    }
    await pools.connect();
    const healthResult = await health.check();
    logger.info(
      {
        ...healthResult,
        enabled: env.WORKER_ENABLED,
        scopeFilter: env.WORKER_SCOPE_ID ?? null,
        automaticReady: env.WORKER_ENABLED && !env.WORKER_SCOPE_ID,
      },
      'Conectividad del worker validada',
    );

    if (command === 'health') return;

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

    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    // PM2 en Windows puede enviar el mensaje IPC en lugar de SIGINT.
    const onMessage = (message: unknown) => {
      if (message === 'shutdown') stop();
    };
    process.on('message', onMessage);
    const loop = (name: string, work: () => Promise<boolean>) =>
      runWorkerLoop({
        work,
        signal: shutdown.signal,
        pause,
        pollSeconds: env.WORKER_OUTBOX_POLL_SECONDS,
        onSuccess: () => {
          failures.delete(name);
        },
        onError: (error) => {
          failures.add(name);
          logger.error(
            { direction: name, error: safeError(error) },
            'Ciclo fallido; se reintentara automaticamente',
          );
        },
      });
    await report('ONLINE');
    process.send?.('ready');
    try {
      await Promise.all([
        loop('catalog', async () => {
          const results = await catalog.run();
          if (results.some((result) => result.status !== 'SUCCEEDED'))
            throw new Error('CATALOG_REQUIRES_ATTENTION');
          return results.length > 0;
        }),
        loop('outbox', async () => {
          const result = await outbox.run();
          if (result.status !== 'SUCCEEDED')
            throw new Error('OUTBOX_REQUIRES_ATTENTION');
          return result.processed >= env.WORKER_OUTBOX_BATCH_SIZE;
        }),
        loop('heartbeat', async () => {
          await report(failures.size ? 'DEGRADED' : 'ONLINE');
          return false;
        }),
      ]);
    } finally {
      process.off('message', onMessage);
    }
  } finally {
    shutdown.abort();
    process.off('SIGINT', stop);
    process.off('SIGTERM', stop);
    if (command !== 'health' && !blocked) await report('STOPPED');
    await pools.close();
  }
}

main().catch((error) => {
  logger.fatal({ error: safeError(error) }, 'IvMET Worker termino con error');
  process.exitCode = 1;
});

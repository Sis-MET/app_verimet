import { env } from '../config';
import { safeError } from '../core/canonical';
import { emptyCounts, runStatus, type SyncRunStatus } from '../domain/types';
import type { IvmetRepository } from '../infrastructure/ivmet.repository';
import type { SupabaseGateway } from '../infrastructure/supabase.gateway';
import { logger } from '../logger';

export class OutboxSyncService {
  private readonly leaseName = 'supabase_to_sql_ivmet';

  constructor(
    private readonly supabase: SupabaseGateway,
    private readonly ivmet: IvmetRepository,
  ) {}

  async run(): Promise<{ status: SyncRunStatus; processed: number }> {
    const acquired = await this.ivmet.tryAcquireLease(
      this.leaseName,
      env.WORKER_ID,
      env.WORKER_LEASE_SECONDS,
    );
    if (!acquired) {
      logger.info('Consumo de outbox omitido: otro worker conserva el lease');
      return { status: 'SUCCEEDED', processed: 0 };
    }

    const counts = emptyCounts();
    let supabaseRunId: string | null = null;
    let sqlRunId: string | null = null;
    let fatalError: string | null = null;

    try {
      supabaseRunId = await this.supabase.beginRun('SUPABASE_TO_SQL_IVMET', null, {
        batchSize: env.WORKER_OUTBOX_BATCH_SIZE,
      });
      sqlRunId = await this.ivmet.beginRun('SUPABASE_TO_SQL_IVMET', env.WORKER_ID, {
        supabaseRunId,
        batchSize: env.WORKER_OUTBOX_BATCH_SIZE,
      });

      const events = await this.supabase.claimOutbox(env.WORKER_OUTBOX_BATCH_SIZE);
      counts.scanned = events.length;

      for (const [index, event] of events.entries()) {
        await this.ivmet.renewLease(this.leaseName, env.WORKER_ID, env.WORKER_LEASE_SECONDS);
        try {
          const alreadyApplied = await this.ivmet.applyOutboxEvent(event, env.WORKER_ID);
          const acknowledged = await this.supabase.acknowledgeOutbox([event.eventId]);
          if (acknowledged !== 1) throw new Error(`OUTBOX_ACK_MISMATCH:${event.eventId}:${acknowledged}`);
          alreadyApplied ? (counts.unchanged += 1) : (counts.accepted += 1);
        } catch (error) {
          counts.rejected += 1;
          fatalError = safeError(error);
          const nextRetryAt = new Date(Date.now() + env.WORKER_RETRY_SECONDS * 1000);
          await this.ivmet
            .recordOutboxFailure({
              runId: sqlRunId,
              event,
              errorCode: 'OUTBOX_APPLY_FAILED',
              errorDetail: fatalError,
              nextRetryAt,
            })
            .catch((recordError) => {
              logger.error({ error: safeError(recordError) }, 'No se pudo registrar el fallo en SQL Server');
            });
          await this.supabase
            .failOutbox(event.eventId, fatalError, env.WORKER_RETRY_SECONDS)
            .catch((releaseError) => {
              logger.error({ error: safeError(releaseError) }, 'No se pudo devolver el evento fallido');
            });

          const remaining = events.slice(index + 1).map((item) => item.eventId);
          await this.supabase.releaseOutbox(remaining).catch((releaseError) => {
            logger.error({ error: safeError(releaseError) }, 'No se pudieron liberar eventos posteriores');
          });
          break;
        }
      }
    } catch (error) {
      fatalError = safeError(error);
      if (counts.scanned === 0) {
        counts.scanned = 1;
        counts.rejected = 1;
      }
      logger.error({ error: fatalError }, 'Fallo el consumo del outbox');
    } finally {
      await this.ivmet.releaseLease(this.leaseName, env.WORKER_ID).catch((error) => {
        logger.warn({ error: safeError(error) }, 'No se pudo liberar el lease del outbox');
      });
    }

    const status: SyncRunStatus = fatalError ? (counts.accepted + counts.unchanged > 0 ? 'PARTIAL' : 'FAILED') : runStatus(counts);
    if (supabaseRunId) {
      await this.supabase.finishRun(supabaseRunId, status, counts, fatalError).catch((error) => {
        logger.error({ error: safeError(error) }, 'No se pudo cerrar el run de outbox en Supabase');
      });
    }
    if (sqlRunId) {
      await this.ivmet.finishRun(sqlRunId, status, counts, fatalError).catch((error) => {
        logger.error({ error: safeError(error) }, 'No se pudo cerrar el run de outbox en SQL Server');
      });
    }

    logger.info({ status, counts }, 'Consumo de outbox finalizado');
    return { status, processed: counts.accepted + counts.unchanged };
  }
}

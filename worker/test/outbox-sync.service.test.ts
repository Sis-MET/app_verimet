import assert from 'node:assert/strict';
import test from 'node:test';
import type { OutboxEvent } from '../src/domain/types';

Object.assign(process.env, {
  NODE_ENV: 'test',
  LOG_LEVEL: 'fatal',
  WORKER_ID: 'ivmet-worker-test',
  WORKER_ENABLED: 'true',
  DATAMET_DB_HOST: 'localhost',
  DATAMET_DB_USER: 'test',
  DATAMET_DB_PASSWORD: 'test',
  IVMET_DB_HOST: 'localhost',
  IVMET_DB_USER: 'test',
  IVMET_DB_PASSWORD: 'test',
  SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'x'.repeat(64),
});

async function createService(supabase: object, ivmet: object) {
  const { OutboxSyncService } = await import(
    '../src/services/outbox-sync.service'
  );
  return new OutboxSyncService(supabase as never, ivmet as never);
}

function event(sequence: number): OutboxEvent {
  const suffix = String(sequence).padStart(12, '0');
  return {
    eventId: `00000000-0000-4000-8000-${suffix}`,
    sequence,
    aggregateType: 'public.clientes',
    aggregateKey: { id: `10000000-0000-4000-8000-${suffix}` },
    operation: 'I',
    payload: { id: `10000000-0000-4000-8000-${suffix}` },
    attempts: 1,
    createdAt: '2026-08-26T12:00:00.000Z',
  };
}

test('outbox acknowledges successful events in sequence', async () => {
  const applied: number[] = [];
  const acknowledged: string[] = [];
  const events = [event(1), event(2)];
  const ivmet = {
    tryAcquireLease: async () => true,
    beginRun: async () => '20000000-0000-4000-8000-000000000001',
    renewLease: async () => undefined,
    applyOutboxEvent: async (item: OutboxEvent) => {
      applied.push(item.sequence);
      return false;
    },
    recordOutboxFailure: async () => undefined,
    releaseLease: async () => undefined,
    finishRun: async () => undefined,
  };
  const supabase = {
    beginRun: async () => '30000000-0000-4000-8000-000000000001',
    claimOutbox: async () => events,
    acknowledgeOutbox: async (ids: string[]) => {
      acknowledged.push(...ids);
      return ids.length;
    },
    failOutbox: async () => undefined,
    releaseOutbox: async () => 0,
    finishRun: async () => undefined,
  };

  const service = await createService(supabase, ivmet);
  const result = await service.run();

  assert.deepEqual(applied, [1, 2]);
  assert.deepEqual(
    acknowledged,
    events.map((item) => item.eventId),
  );
  assert.deepEqual(result, { status: 'SUCCEEDED', processed: 2 });
});

test('outbox stops on first failure and releases later sequences', async () => {
  const events = [event(10), event(11), event(12)];
  const released: string[][] = [];
  const failed: string[] = [];
  const ivmet = {
    tryAcquireLease: async () => true,
    beginRun: async () => '20000000-0000-4000-8000-000000000002',
    renewLease: async () => undefined,
    applyOutboxEvent: async () => {
      throw new Error('projection failed');
    },
    recordOutboxFailure: async () => undefined,
    releaseLease: async () => undefined,
    finishRun: async () => undefined,
  };
  const supabase = {
    beginRun: async () => '30000000-0000-4000-8000-000000000002',
    claimOutbox: async () => events,
    acknowledgeOutbox: async () => 0,
    failOutbox: async (id: string) => {
      failed.push(id);
    },
    releaseOutbox: async (ids: string[]) => {
      released.push(ids);
      return ids.length;
    },
    finishRun: async () => undefined,
  };

  const service = await createService(supabase, ivmet);
  const result = await service.run();

  assert.deepEqual(failed, [events[0]!.eventId]);
  assert.deepEqual(released, [[events[1]!.eventId, events[2]!.eventId]]);
  assert.deepEqual(result, { status: 'FAILED', processed: 0 });
});

test('outbox vacío no genera miles de ejecuciones sin datos', async () => {
  let released = false;
  const service = await createService(
    {
      claimOutbox: async () => [],
      beginRun: async () => assert.fail('No debe crear un run vacío'),
    },
    {
      tryAcquireLease: async () => true,
      releaseLease: async () => {
        released = true;
      },
    },
  );
  assert.deepEqual(await service.run(), { status: 'SUCCEEDED', processed: 0 });
  assert.equal(released, true);
});

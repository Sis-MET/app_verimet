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

test('un agregado privado nunca llega a SQL Server ni a sus fallos', async () => {
  const item = {
    ...event(50),
    aggregateType: 'public.lecturas',
    payload: { secret: 'PRIVATE-READING' },
  };
  const service = await createService(
    {
      claimOutbox: async () => [item],
      beginRun: async () => 'run',
      failOutbox: async (_id: string, detail: string) =>
        assert.equal(detail, 'PRIVATE_OR_UNSUPPORTED_AGGREGATE'),
      releaseOutbox: async () => 0,
      finishRun: async () => undefined,
    },
    {
      tryAcquireLease: async () => true,
      renewLease: async () => undefined,
      releaseLease: async () => undefined,
      beginRun: async () => 'run',
      finishRun: async () => undefined,
      applyOutboxEvent: async () =>
        assert.fail('No exportar evidencia privada'),
      recordOutboxFailure: async () =>
        assert.fail('No exportar tampoco el payload de error'),
    },
  );
  assert.deepEqual(await service.run(), { status: 'FAILED', processed: 0 });
});
test('revalida un caso reclamado antes de retirarse; no entrega la instantánea vieja', async () => {
  const item = {
    ...event(51),
    aggregateType: 'public.casos_compartidos',
    payload: { snapshot: { secret: 'OLD' }, visibilidad: 'SHARED' },
  };
  const service = await createService(
    {
      claimOutbox: async () => [item],
      beginRun: async () => 'run',
      caseDelivery: async () => ({ snapshot: null, visibilidad: 'WITHDRAWN' }),
      acknowledgeOutbox: async () => 1,
      finishRun: async () => undefined,
    },
    {
      tryAcquireLease: async () => true,
      renewLease: async () => undefined,
      releaseLease: async () => undefined,
      beginRun: async () => 'run',
      finishRun: async () => undefined,
      applyOutboxEvent: async (e: OutboxEvent) => {
        assert.equal(e.payload.snapshot, null);
        assert.equal(e.payload.visibilidad, 'WITHDRAWN');
        return false;
      },
    },
  );
  assert.deepEqual(await service.run(), { status: 'SUCCEEDED', processed: 1 });
});

test('un reintento con consentimiento actualizado conserva el hash del evento original', async () => {
  const { IvmetRepository } = await import(
    '../src/infrastructure/ivmet.repository'
  );
  const bindings: Record<string, unknown> = {};
  const request = {
    input(name: string, _type: unknown, value: unknown) {
      bindings[name] = value;
      return this;
    },
    output() {
      return this;
    },
    execute: async () => ({ output: { already_applied: true } }),
  };
  const repository = new IvmetRepository({} as never);
  const record = Reflect.get(repository, 'recordAppliedEvent').bind(repository);
  const item = {
    ...event(52),
    aggregateType: 'public.casos_compartidos',
    sourcePayloadHash: 'a'.repeat(64),
    payload: { snapshot: { secret: 'OLD' } },
  };
  await record({ request: () => request }, item, 'fixture');
  assert.equal(bindings.payload_hash, 'a'.repeat(64));
  await record(
    { request: () => request },
    { ...item, payload: { snapshot: null, visibilidad: 'WITHDRAWN' } },
    'fixture',
  );
  assert.equal(bindings.payload_hash, 'a'.repeat(64));
  await assert.rejects(
    record(
      { request: () => request },
      { ...item, sourcePayloadHash: undefined },
      'fixture',
    ),
    /CASE_SOURCE_HASH_REQUIRED/,
  );
});

test('revalida una actualización del cliente antes de entregarla al espejo', async () => {
  const item = {...event(60), aggregateType:'public.actualizaciones_compartidas',
    payload:{snapshot:{serie:'PRIVATE-OLD'},visibilidad:'SHARED'}};
  const service = await createService({
    claimOutbox: async () => [item], beginRun: async () => 'run',
    equipmentUpdateDelivery: async () => ({snapshot:null,visibilidad:'WITHDRAWN'}),
    acknowledgeOutbox: async () => 1, finishRun: async () => undefined,
  }, {
    tryAcquireLease: async () => true, renewLease: async () => undefined,
    releaseLease: async () => undefined, beginRun: async () => 'run', finishRun: async () => undefined,
    applyOutboxEvent: async (e: OutboxEvent) => {
      assert.equal(e.payload.snapshot,null); assert.equal(e.payload.visibilidad,'WITHDRAWN'); return false;
    },
  });
  assert.deepEqual(await service.run(),{status:'SUCCEEDED',processed:1});
});

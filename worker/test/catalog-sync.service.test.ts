import assert from 'node:assert/strict';
import test from 'node:test';
import type { CatalogJob, SyncCounts } from '../src/domain/types';

Object.assign(process.env, {
  NODE_ENV: 'test',
  LOG_LEVEL: 'fatal',
  WORKER_ID: 'worker-test',
  WORKER_ENABLED: 'true',
  WORKER_SCOPE_ID: '',
  DATAMET_DB_HOST: 'localhost',
  DATAMET_DB_USER: 'test',
  DATAMET_DB_PASSWORD: 'test',
  IVMET_DB_HOST: 'localhost',
  IVMET_DB_USER: 'test',
  IVMET_DB_PASSWORD: 'test',
  SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'x'.repeat(64),
});
const job: CatalogJob = {
  scopeId: '00000000-0000-4000-8000-000000000001',
  legacyClientId: 103,
  legacyClientCode: '0103',
  supabaseClientId: null,
  status: 'REQUESTED',
  plantCodes: ['0103-11'],
  equipmentCodes: ['0103-11-001'],
  runId: '00000000-0000-4000-8000-000000000002',
  generation: '1',
};

async function fixture({
  failState = false,
  invalid = false,
  empty = false,
} = {}) {
  const { CatalogSyncService } = await import(
    '../src/services/catalog-sync.service'
  );
  const finished: Array<{ status: string; counts: SyncCounts }> = [];
  const quarantined: string[] = [];
  const supabase = {
    claimCatalogJob: async () => (empty ? null : job),
    renewCatalogJob: async () => {},
    upsertClient: async () => ({ id: 'client', changed: true }),
    upsertPlant: async () => ({ id: 'plant', changed: true }),
    upsertEquipment: async () => ({
      id: 'equipment',
      changed: true,
      rangeChanged: 0,
      rangeDeleted: 0,
      ranges: [],
    }),
    recordQuarantine: async (_id: string, record: { reasonCode: string }) => {
      quarantined.push(record.reasonCode);
    },
    finishCatalogJob: async (
      _job: unknown,
      _client: unknown,
      status: string,
      counts: SyncCounts,
    ) => {
      finished.push({ status, counts });
    },
  };
  const ivmet = {
    beginRun: async () => 'sql-run',
    upsertDataMetState: async () => {
      if (failState) throw new Error('state unavailable');
    },
    recordCatalogQuarantine: async () => {},
    finishRun: async () => {},
  };
  const dataMet = {
    readClient: async () => ({
      legacyClientId: 103,
      sourceHash: 'a'.repeat(64),
    }),
    readPlants: async (_id: number, codes: string[]) => {
      assert.deepEqual(codes, ['0103-11']);
      return [{ legacyCode: '0103-11', sourceHash: 'b'.repeat(64) }];
    },
    readEquipment: async (codes: string[]) => {
      assert.deepEqual(codes, ['0103-11-001']);
      return invalid
        ? []
        : [
            {
              sourceCode: '0103-11-001',
              equipment: {
                code: '0103-11-001',
                plantCode: '0103-11',
                legacyEquipmentId: 1,
                sourceHash: 'c'.repeat(64),
                warnings: [],
              },
            },
          ];
    },
  };
  return {
    service: new CatalogSyncService(
      dataMet as never,
      supabase as never,
      ivmet as never,
    ),
    finished,
    quarantined,
  };
}
test('consume una solicitud persistente con su alcance exacto y confirma al finalizar', async () => {
  const f = await fixture();
  await f.service.run();
  assert.equal(f.finished[0]?.status, 'SUCCEEDED');
  assert.deepEqual(f.finished[0]?.counts, {
    scanned: 3,
    accepted: 3,
    unchanged: 0,
    rejected: 0,
  });
});
test('un equipo inválido conserva el cliente importado y programa un resultado parcial', async () => {
  const f = await fixture({ invalid: true });
  await f.service.run();
  assert.equal(f.finished[0]?.status, 'PARTIAL');
  assert.deepEqual(f.quarantined, ['EQUIPMENT_NOT_FOUND']);
  assert.equal(f.finished[0]?.counts.rejected, 1);
});
test('una escritura de control fallida no cuenta la misma entidad como aceptada y rechazada', async () => {
  const f = await fixture({ failState: true });
  await f.service.run();
  assert.deepEqual(f.finished[0]?.counts, {
    scanned: 1,
    accepted: 0,
    unchanged: 0,
    rejected: 1,
  });
  assert.equal(f.finished[0]?.status, 'FAILED');
});
test('sin trabajos vencidos no crea ejecuciones ni importa catálogos', async () => {
  const f = await fixture({ empty: true });
  assert.deepEqual(await f.service.run(), []);
  assert.equal(f.finished.length, 0);
});

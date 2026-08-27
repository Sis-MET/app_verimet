import assert from 'node:assert/strict';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import {
  assertWorkerMode,
  keepLease,
  runWorkerLoop,
} from '../src/core/runtime';

test('producción exige habilitación explícita y procesa todos los alcances autorizados', () => {
  assert.doesNotThrow(() => assertWorkerMode('health', false, true, 'pilot'));
  assert.throws(
    () => assertWorkerMode('daemon', false, true),
    /WORKER_ENABLED/,
  );
  assert.throws(
    () => assertWorkerMode('daemon', true, true, 'pilot'),
    /WORKER_SCOPE_ID/,
  );
  assert.doesNotThrow(() => assertWorkerMode('daemon', true, true));
  assert.doesNotThrow(() => assertWorkerMode('catalog', true, true, 'pilot'));
});
test('la renovación se detiene sin solaparse y propaga pérdida de propiedad', async () => {
  let count = 0,
    active = 0,
    max = 0;
  let finished!: () => void;
  let deadline: ReturnType<typeof setTimeout>;
  const completion = new Promise<void>((resolve, reject) => {
    finished = resolve;
    deadline = setTimeout(
      () => reject(new Error('La renovación no finalizó')),
      3000,
    );
  });
  const lease = keepLease(async () => {
    count++;
    active++;
    max = Math.max(max, active);
    await delay(4);
    active--;
    if (count === 2) {
      finished();
      throw new Error('lost');
    }
  }, 2);
  try {
    await completion;
  } finally {
    clearTimeout(deadline!);
    await lease.stop();
  }
  assert.throws(lease.assertAlive, /lost/);
  const stopped = count;
  await delay(10);
  assert.equal(count, stopped);
  assert.equal(max, 1);
});
test('un fallo de catálogo no impide ejecutar outbox', async () => {
  const shutdown = new AbortController();
  let delivered = false;
  let errors = 0;
  const options = {
    signal: shutdown.signal,
    pause: async () => {
      await delay(1);
    },
    pollSeconds: 10,
    onSuccess: () => {},
    onError: () => {
      errors++;
    },
  };
  await Promise.all([
    runWorkerLoop({
      ...options,
      work: async () => {
        throw new Error('unavailable');
      },
    }),
    runWorkerLoop({
      ...options,
      work: async () => {
        await delay(5);
        delivered = true;
        shutdown.abort();
        return true;
      },
    }),
  ]);
  assert.equal(delivered, true);
  assert.ok(errors > 0);
});

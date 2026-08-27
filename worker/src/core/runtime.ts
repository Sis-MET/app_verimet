export type WorkerCommand = 'health' | 'catalog' | 'outbox' | 'once' | 'daemon';

export function assertWorkerMode(
  command: WorkerCommand,
  enabled: boolean,
  production: boolean,
  scopeId?: string,
): void {
  if (command === 'health') return;
  if (!enabled)
    throw new Error(
      'WORKER_ENABLED=false: solo health esta disponible. Habilita el worker en el servidor de despliegue.',
    );
  if (command === 'daemon' && production && scopeId) {
    throw new Error(
      'El daemon de produccion requiere WORKER_SCOPE_ID vacio: procesa todos los alcances autorizados, nunca todo DataMET.',
    );
  }
}

// Sin solapar renovaciones. El consumidor deja de trabajar si pierde propiedad.
export function keepLease(renew: () => Promise<void>, milliseconds: number) {
  let failure: unknown;
  let failed = false;
  let stopped = false;
  let pending: Promise<void> = Promise.resolve();
  let timer: ReturnType<typeof setTimeout>;
  const schedule = () => {
    timer = setTimeout(() => {
      pending = renew()
        .catch((error: unknown) => {
          failed = true;
          failure = error;
        })
        .finally(() => {
          if (!stopped && !failed) schedule();
        });
    }, milliseconds);
    timer.unref();
  };
  schedule();
  return {
    assertAlive() {
      if (failed) throw failure ?? new Error('LEASE_LOST');
    },
    async stop() {
      stopped = true;
      clearTimeout(timer);
      await pending;
    },
  };
}

// Un fallo de catálogo no detiene la entrega al espejo, ni viceversa.
export async function runWorkerLoop(options: {
  signal: AbortSignal;
  work: () => Promise<boolean>;
  pause: (seconds: number) => Promise<void>;
  onError: (error: unknown) => void;
  onSuccess: () => void;
  pollSeconds: number;
}): Promise<void> {
  while (!options.signal.aborted) {
    let more = false;
    try {
      more = await options.work();
      options.onSuccess();
    } catch (error) {
      options.onError(error);
    }
    if (!options.signal.aborted)
      await options.pause(more ? 0.1 : options.pollSeconds);
  }
}

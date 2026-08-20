/** Las tres pruebas de una verificacion intermedia. */
export const TEST_TYPES = ['eccentricity', 'repeatability', 'linearity'] as const;
export type TestType = (typeof TEST_TYPES)[number];

/** Resultado de una prueba frente a la tolerancia definida para el instrumento. */
export const TEST_VERDICTS = ['pass', 'fail'] as const;
export type TestVerdict = (typeof TEST_VERDICTS)[number];

/** Estado de un registro en la cola de sincronizacion offline-first. */
export const SYNC_STATUSES = ['pending', 'in_progress', 'synced', 'failed'] as const;
export type SyncStatus = (typeof SYNC_STATUSES)[number];

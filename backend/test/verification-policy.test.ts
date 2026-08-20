import assert from 'node:assert/strict';
import test from 'node:test';
import { certificateIsTraceable, deriveScope, nextDueAt } from '../src/features/sync/domain/verification-policy';

test('una omision justificada convierte el alcance en parcial', () => {
  assert.equal(deriveScope(['performed', 'omitted', 'performed']), 'partial');
  assert.equal(deriveScope(['performed', 'performed']), 'complete');
});

test('un certificado vencido en la fecha de medicion queda no trazable sin rechazar la fecha', () => {
  const measured = new Date('2026-08-20T12:00:00.000Z');
  assert.equal(certificateIsTraceable(measured, '2025-08-20', '2026-08-19'), false);
  assert.equal(certificateIsTraceable(measured, '2025-08-20', '2026-08-20'), true);
});

test('el proximo vencimiento se calcula por frecuencia desde la ultima ejecucion trazable', () => {
  assert.equal(nextDueAt(new Date('2026-01-01T00:00:00.000Z'), 30)?.toISOString(), '2026-01-31T00:00:00.000Z');
  assert.equal(nextDueAt(null, 30), null);
});

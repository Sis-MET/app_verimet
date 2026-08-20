import assert from 'node:assert/strict';
import test from 'node:test';
import { verificationPdfService } from '../src/features/verification-reports/application/verification-pdf.service';
import type { VerificationDetail } from '../src/features/verification-reports/application/verification-reports.service';

test('genera un PDF valido con alcance, omisiones, patrones y lecturas', async () => {
  const detail = {
    id: '00000000-0000-4000-8000-000000000001', equipmentCode: 'EQ-001', clientId: '10', plantId: '20',
    performedAt: new Date('2026-08-20T10:00:00.000Z'), receivedAt: new Date('2026-08-20T11:00:00.000Z'),
    scope: 'partial', verdict: 'pass', traceability: 'traceable', status: 'ACTIVA',
    planVersionId: '00000000-0000-4000-8000-000000000002', temperatureC: '23.000',
    relativeHumidityPct: '50.000', capturedBy: 'Operador', capturedById: 'u1', uploadedBy: 'Operador', uploadedById: 'u1',
    appVersion: '1.0.0', deviceId: 'phone', observations: null,
    equipmentSnapshot: { code: 'EQ-001' }, planSnapshot: { version: 1 },
    standards: [{ role: 'load', snapshot: { codigo: 'P-1', descripcion: 'Juego', numero: 'C-1', laboratorio: 'Lab', calibrado_el: '2026-01-01', vence_el: '2027-01-01' } }],
    tests: [
      { type: 'eccentricity', executionStatus: 'performed', evaluationMethod: 'absolute_error', verdict: 'pass', omissionReason: null,
        metrics: { maximumAbsoluteError: '0.010000000', mean: '10.000000000', sampleStandardDeviation: '0.000000000', range: '0.000000000' },
        readings: [{ order: 1, label: 'Centro', nominalLoad: '10.000000000', indication: '10.010000000', error: '0.010000000', tolerance: '0.020000000', verdict: 'pass' }] },
      { type: 'linearity', executionStatus: 'omitted', evaluationMethod: 'absolute_error', verdict: null, omissionReason: 'Equipo en proceso', metrics: {}, readings: [] },
    ],
  } as unknown as VerificationDetail;
  const pdf = await verificationPdfService.generate(detail);
  assert.equal(pdf.subarray(0, 5).toString('ascii'), '%PDF-');
  assert.ok(pdf.length > 1500);
  assert.match(pdf.subarray(-20).toString('ascii'), /%%EOF/);
});

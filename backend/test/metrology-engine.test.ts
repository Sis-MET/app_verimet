import assert from 'node:assert/strict';
import test from 'node:test';
import { evaluateTest, type EngineReading } from '../src/features/sync/domain/metrology-engine';

function reading(order: number, indication: string, tolerance = '0.500000000'): EngineReading {
  return {
    pointId: `00000000-0000-4000-8000-${String(order).padStart(12, '0')}`,
    group: 1, order, code: `P${order}`, label: `Punto ${order}`,
    nominalLoad: '10.000000000', indication, tolerance,
  };
}

test('absolute_error usa decimal exacto y no confia en un veredicto externo', () => {
  const result = evaluateTest('absolute_error', [reading(1, '10.200000000'), reading(2, '10.700000000')]);
  assert.equal(result.verdict, 'fail');
  assert.equal(result.readings[0]?.error, '0.200000000');
  assert.equal(result.readings[1]?.error, '0.700000000');
  assert.equal(result.metrics.maximumAbsoluteError, '0.700000000');
});

test('range compara el recorrido de indicaciones con el limite del plan', () => {
  const result = evaluateTest('range', [
    reading(1, '10.000000000', '0.300000000'),
    reading(2, '10.200000000', '0.300000000'),
    reading(3, '9.900000000', '0.300000000'),
  ]);
  assert.equal(result.metrics.range, '0.300000000');
  assert.equal(result.verdict, 'pass');
});

test('sample_standard_deviation usa n-1', () => {
  const result = evaluateTest('sample_standard_deviation', [
    reading(1, '10.000000000', '0.100000000'),
    reading(2, '10.100000000', '0.100000000'),
    reading(3, '9.900000000', '0.100000000'),
  ]);
  assert.equal(result.metrics.mean, '10.000000000');
  assert.equal(result.metrics.sampleStandardDeviation, '0.100000000');
  assert.equal(result.verdict, 'pass');
});

test('conserva el noveno decimal aun cerca del limite de decimal(19,9)', () => {
  const result = evaluateTest('absolute_error', [{
    ...reading(1, '9999999999.999999999', '0.000000001'),
    nominalLoad: '9999999999.999999998',
  }]);
  assert.equal(result.readings[0]?.error, '0.000000001');
  assert.equal(result.verdict, 'pass');
});

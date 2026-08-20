import assert from 'node:assert/strict';
import test from 'node:test';
import { canonicalPayloadJson, payloadHash } from '../src/features/sync/domain/canonical-payload';

test('el hash idempotente no depende del orden de las propiedades', () => {
  const left = { clientUuid: 'x', nested: { b: '2', a: '1' }, readings: [{ z: 2, a: 1 }] };
  const right = { readings: [{ a: 1, z: 2 }], nested: { a: '1', b: '2' }, clientUuid: 'x' };
  assert.equal(canonicalPayloadJson(left), canonicalPayloadJson(right));
  assert.equal(payloadHash(left).toString('hex'), payloadHash(right).toString('hex'));
});

test('el hash conserva el orden significativo de arreglos', () => {
  assert.notEqual(payloadHash({ readings: [1, 2] }).toString('hex'), payloadHash({ readings: [2, 1] }).toString('hex'));
});

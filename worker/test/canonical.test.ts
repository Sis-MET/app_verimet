import assert from 'node:assert/strict';
import test from 'node:test';
import { canonicalJson, sha256 } from '../src/core/canonical';
import {
  canonicalEquipmentCode,
  decimalString,
  isLegacyActive,
  plantCodeFromEquipment,
} from '../src/core/normalization';

test('canonical JSON and SHA-256 do not depend on object key order', () => {
  const left = { plant: '0001-01', values: { b: 2, a: 1 } };
  const right = { values: { a: 1, b: 2 }, plant: '0001-01' };

  assert.equal(canonicalJson(left), canonicalJson(right));
  assert.equal(sha256(left), sha256(right));
  assert.match(sha256(left), /^[0-9a-f]{64}$/);
});

test('legacy identifiers and decimals are normalized without losing decimal text', () => {
  assert.equal(canonicalEquipmentCode(' 0001-02-003 '), '0001-02-003');
  assert.equal(plantCodeFromEquipment('0001-02-003'), '0001-02');
  assert.equal(decimalString(' 1000.000000 '), '1000.000000');
  assert.equal(isLegacyActive(' activo '), true);
  assert.throws(() => canonicalEquipmentCode('1-2-3'), /cod_metrica invalido/);
  assert.throws(() => decimalString('1,25'), /Decimal legado invalido/);
});

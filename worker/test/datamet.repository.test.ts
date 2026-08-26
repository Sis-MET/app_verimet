import assert from 'node:assert/strict';
import type { ConnectionPool } from 'mssql';
import test from 'node:test';
import { DataMetRepository } from '../src/infrastructure/datamet.repository';

function equipmentRow(code: string, verificationInterval: string) {
  return {
    id: Number(code.slice(-3)),
    cod_metrica: code,
    cod_interno: null,
    instrumento: 'BALANZA',
    tipo_instrumento: null,
    marca: null,
    modelo: null,
    serie: null,
    estado: 'ACTIVO',
    ubicacion: null,
    categoria: 'STIL',
    unidad: 'kg',
    cap_max1: '100.00',
    d1: '1.00',
    e1: verificationInterval,
    dec1: 0,
    cap_max2: '0.00',
    d2: '0.00',
    e2: '0.00',
    dec2: 0,
    cap_max3: '0.00',
    d3: '0.00',
    e3: '0.00',
    dec3: 0,
    comunicacion: null,
    material: null,
    acceso: null,
    altura: null,
    n_celdas: null,
    tecnologia: null,
    proteccion: null,
    plataforma: null,
    clase: null,
    tipo_balanza: 'MESA',
    balance_cod_metrica: code,
  };
}

function repositoryWithRows(rows: ReturnType<typeof equipmentRow>[]): DataMetRepository {
  const request = {
    input() {
      return request;
    },
    async query() {
      return { recordset: rows };
    },
  };
  const pool = { request: () => request } as unknown as ConnectionPool;
  return new DataMetRepository(pool);
}

test('zero-filled unused legacy ranges do not require catalog review', async () => {
  const code = '0032-11-001';
  const [candidate] = await repositoryWithRows([equipmentRow(code, '1.00')])
    .readEquipment([code]);

  assert.ok(candidate?.equipment);
  assert.equal(candidate.equipment.catalogStatus, 'READY');
  assert.deepEqual(candidate.equipment.warnings, []);
  assert.equal(candidate.equipment.ranges.length, 1);
  assert.equal(candidate.equipment.ranges[0]?.verificationInterval, '1.00');
});

test('a zero verification interval is preserved as missing and requires review', async () => {
  const code = '0032-11-024';
  const [candidate] = await repositoryWithRows([equipmentRow(code, '0.00')])
    .readEquipment([code]);

  assert.ok(candidate?.equipment);
  assert.equal(candidate.equipment.catalogStatus, 'REQUIRES_REVIEW');
  assert.deepEqual(candidate.equipment.warnings, [`Intervalo e1 igual a cero para ${code}`]);
  assert.equal(candidate.equipment.ranges.length, 1);
  assert.equal(candidate.equipment.ranges[0]?.verificationInterval, null);
});

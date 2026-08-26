import type { ConnectionPool, IResult } from 'mssql';
import { sha256, type JsonValue } from '../core/canonical';
import {
  canonicalEquipmentCode,
  decimalString,
  isLegacyActive,
  optionalText,
  plantCodeFromEquipment,
  requiredText,
} from '../core/normalization';
import type {
  CatalogClient,
  CatalogEquipment,
  CatalogEquipmentRange,
  CatalogPlant,
} from '../domain/types';
import { sql } from './sql-pools';

type LegacyClientRow = {
  cliente_id: number;
  codigo_cliente: string;
  cliente: string | null;
  razonsocial: string | null;
  estado: string | null;
};

type LegacyPlantRow = {
  cliente_id: number;
  codigo_planta: string;
  planta_id: number | null;
  planta: string | null;
  dir: string | null;
  dep: string | null;
  dep_id: number | null;
  localidad: string | null;
  ubicacion: string | null;
  estado: string | null;
};

type LegacyEquipmentRow = {
  id: number;
  cod_metrica: string;
  cod_interno: string | null;
  instrumento: string | null;
  tipo_instrumento: string | null;
  marca: string | null;
  modelo: string | null;
  serie: string | null;
  estado: string | null;
  ubicacion: string | null;
  categoria: string | null;
  unidad: string | null;
  cap_max1: string | null;
  d1: string | null;
  e1: string | null;
  dec1: number | null;
  cap_max2: string | null;
  d2: string | null;
  e2: string | null;
  dec2: number | null;
  cap_max3: string | null;
  d3: string | null;
  e3: string | null;
  dec3: number | null;
  comunicacion: string | null;
  material: string | null;
  acceso: string | null;
  altura: string | null;
  n_celdas: number | null;
  tecnologia: string | null;
  proteccion: string | null;
  plataforma: string | null;
  clase: string | null;
  tipo_balanza: string | null;
  balance_cod_metrica: string | null;
};

export type EquipmentReadCandidate = {
  sourceCode: string;
  equipment: CatalogEquipment | null;
  error: string | null;
};

function asHashable(value: Record<string, unknown>): JsonValue {
  return value as JsonValue;
}

function clientFromRow(row: LegacyClientRow): CatalogClient {
  const base = {
    legacyClientId: row.cliente_id,
    code: requiredText(row.codigo_cliente, 'codigo_cliente'),
    name: optionalText(row.cliente),
    legalName: optionalText(row.razonsocial),
    legacyStatus: optionalText(row.estado),
    active: isLegacyActive(row.estado),
  };
  return { ...base, sourceHash: sha256(asHashable(base)) };
}

function plantFromRow(row: LegacyPlantRow): CatalogPlant {
  const base = {
    legacyClientId: row.cliente_id,
    legacyCode: requiredText(row.codigo_planta, 'codigo_planta'),
    legacyPlantNumber: row.planta_id,
    name: optionalText(row.planta),
    address: optionalText(row.dir),
    departmentCode: optionalText(row.dep),
    departmentId: row.dep_id,
    locality: optionalText(row.localidad),
    location: optionalText(row.ubicacion),
    legacyStatus: optionalText(row.estado),
    active: isLegacyActive(row.estado),
  };
  return { ...base, sourceHash: sha256(asHashable(base)) };
}

function rangeFromRow(
  equipmentCode: string,
  row: LegacyEquipmentRow,
  rangeNumber: 1 | 2 | 3,
): { range: CatalogEquipmentRange | null; warnings: string[] } {
  const capacity = decimalString(row[`cap_max${rangeNumber}`]);
  const division = decimalString(row[`d${rangeNumber}`]);
  const interval = decimalString(row[`e${rangeNumber}`]);
  const decimalPlaces = row[`dec${rangeNumber}`];

  const isUnusedPlaceholder = [capacity, division, interval]
    .every((value) => value === null || Number(value) === 0);
  if (isUnusedPlaceholder) return { range: null, warnings: [] };

  if (!capacity || !division) {
    throw new Error(`Rango ${rangeNumber} incompleto para ${equipmentCode}`);
  }
  if (Number(capacity) <= 0 || Number(division) <= 0) {
    throw new Error(`Rango ${rangeNumber} no positivo para ${equipmentCode}`);
  }
  if (interval !== null && Number(interval) < 0) {
    throw new Error(`Intervalo e${rangeNumber} negativo para ${equipmentCode}`);
  }
  if (decimalPlaces !== null && (decimalPlaces < 0 || decimalPlaces > 9)) {
    throw new Error(`Decimales fuera de rango para ${equipmentCode}`);
  }

  const warnings: string[] = [];
  const normalizedInterval = interval !== null && Number(interval) === 0 ? null : interval;
  if (interval !== null && normalizedInterval === null) {
    warnings.push(`Intervalo e${rangeNumber} igual a cero para ${equipmentCode}`);
  }

  const base = {
    equipmentCode,
    rangeNumber,
    unit: requiredText(row.unidad, `unidad de ${equipmentCode}`),
    maximumCapacity: capacity,
    scaleDivision: division,
    verificationInterval: normalizedInterval,
    decimalPlaces,
  };

  return {
    range: {
      rangeNumber: base.rangeNumber,
      unit: base.unit,
      maximumCapacity: base.maximumCapacity,
      scaleDivision: base.scaleDivision,
      verificationInterval: base.verificationInterval,
      decimalPlaces: base.decimalPlaces,
      sourceHash: sha256(asHashable(base)),
    },
    warnings,
  };
}

function equipmentFromRow(row: LegacyEquipmentRow): CatalogEquipment {
  const code = canonicalEquipmentCode(row.cod_metrica);
  const warnings: string[] = [];
  const ranges: CatalogEquipmentRange[] = [];

  if (!optionalText(row.balance_cod_metrica)) {
    warnings.push('MISSING_BALANCE_DETAIL');
  } else {
    for (const rangeNumber of [1, 2, 3] as const) {
      try {
        const parsed = rangeFromRow(code, row, rangeNumber);
        warnings.push(...parsed.warnings);
        if (parsed.range) ranges.push(parsed.range);
      } catch (error) {
        warnings.push(error instanceof Error ? error.message : String(error));
      }
    }
  }

  if (ranges.length === 0) warnings.push('NO_VALID_RANGES');

  const base = {
    legacyEquipmentId: row.id,
    code,
    plantCode: plantCodeFromEquipment(code),
    internalCode: optionalText(row.cod_interno),
    instrument: optionalText(row.instrumento),
    instrumentType: optionalText(row.tipo_instrumento),
    category: optionalText(row.categoria),
    balanceType: optionalText(row.tipo_balanza),
    brand: optionalText(row.marca),
    model: optionalText(row.modelo),
    serial: optionalText(row.serie),
    unit: optionalText(row.unidad),
    location: optionalText(row.ubicacion),
    communication: optionalText(row.comunicacion),
    material: optionalText(row.material),
    access: optionalText(row.acceso),
    height: optionalText(row.altura),
    cellCount: row.n_celdas,
    technology: optionalText(row.tecnologia),
    protection: optionalText(row.proteccion),
    platform: optionalText(row.plataforma),
    className: optionalText(row.clase),
    legacyStatus: optionalText(row.estado),
    catalogStatus: warnings.length === 0 ? ('READY' as const) : ('REQUIRES_REVIEW' as const),
    active: isLegacyActive(row.estado),
  };

  return {
    ...base,
    ranges,
    warnings,
    sourceHash: sha256(
      asHashable({
        ...base,
        ranges: ranges.map(({ sourceHash: _sourceHash, ...range }) => range),
      }),
    ),
  };
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

export class DataMetRepository {
  constructor(private readonly pool: ConnectionPool) {}

  async healthCheck(): Promise<{ database: string; canSelect: boolean; canUpdate: boolean }> {
    const result = await this.pool.request().query<{
      database_name: string;
      can_select: number;
      can_update: number;
    }>(`
      SELECT
        DB_NAME() AS database_name,
        CASE WHEN
          HAS_PERMS_BY_NAME(N'dbo.DATA_CLIENTES', N'OBJECT', N'SELECT') = 1
          AND HAS_PERMS_BY_NAME(N'dbo.DATA_PLANTAS', N'OBJECT', N'SELECT') = 1
          AND HAS_PERMS_BY_NAME(N'dbo.DATA_EQUIPOS', N'OBJECT', N'SELECT') = 1
          AND HAS_PERMS_BY_NAME(N'dbo.DATA_EQUIPOS_BALANZAS', N'OBJECT', N'SELECT') = 1
        THEN 1 ELSE 0 END AS can_select,
        CASE WHEN
          HAS_PERMS_BY_NAME(N'dbo.DATA_CLIENTES', N'OBJECT', N'UPDATE') = 1
          OR HAS_PERMS_BY_NAME(N'dbo.DATA_PLANTAS', N'OBJECT', N'UPDATE') = 1
          OR HAS_PERMS_BY_NAME(N'dbo.DATA_EQUIPOS', N'OBJECT', N'UPDATE') = 1
          OR HAS_PERMS_BY_NAME(N'dbo.DATA_EQUIPOS_BALANZAS', N'OBJECT', N'UPDATE') = 1
        THEN 1 ELSE 0 END AS can_update;
    `);
    const row = result.recordset[0];
    if (!row) throw new Error('DataMET no devolvio el resultado de permisos');
    return {
      database: row.database_name,
      canSelect: row.can_select === 1,
      canUpdate: row.can_update === 1,
    };
  }

  async readClient(legacyClientId: number, legacyCode: string): Promise<CatalogClient> {
    const result = await this.pool
      .request()
      .input('legacyClientId', sql.Int, legacyClientId)
      .input('legacyCode', sql.NVarChar(20), legacyCode)
      .query<LegacyClientRow>(`
        SELECT cliente_id, codigo_cliente, cliente, razonsocial, estado
        FROM dbo.DATA_CLIENTES
        WHERE cliente_id = @legacyClientId
          AND LTRIM(RTRIM(codigo_cliente)) = @legacyCode;
      `);

    if (result.recordset.length !== 1) {
      throw new Error(`CLIENT_NOT_UNIQUE:${legacyClientId}:${legacyCode}:${result.recordset.length}`);
    }
    return clientFromRow(result.recordset[0]!);
  }

  async readPlants(legacyClientId: number, plantCodes: string[]): Promise<CatalogPlant[]> {
    if (plantCodes.length === 0) return [];
    const rows: LegacyPlantRow[] = [];

    for (const codeChunk of chunks([...new Set(plantCodes)], 200)) {
      const request = this.pool.request().input('legacyClientId', sql.Int, legacyClientId);
      const parameters = codeChunk.map((code, index) => {
        const name = `plantCode${index}`;
        request.input(name, sql.NVarChar(50), code);
        return `@${name}`;
      });
      const result: IResult<LegacyPlantRow> = await request.query(`
        SELECT cliente_id, codigo_planta, planta_id, planta, dir, dep, dep_id,
               localidad, ubicacion, estado
        FROM dbo.DATA_PLANTAS
        WHERE cliente_id = @legacyClientId
          AND LTRIM(RTRIM(codigo_planta)) IN (${parameters.join(',')});
      `);
      rows.push(...result.recordset);
    }

    return rows.map(plantFromRow);
  }

  async readEquipment(equipmentCodes: string[]): Promise<EquipmentReadCandidate[]> {
    if (equipmentCodes.length === 0) return [];
    const rows: LegacyEquipmentRow[] = [];

    for (const codeChunk of chunks([...new Set(equipmentCodes)], 150)) {
      const request = this.pool.request();
      const parameters = codeChunk.map((code, index) => {
        const name = `equipmentCode${index}`;
        request.input(name, sql.NVarChar(12), code);
        return `@${name}`;
      });
      const result: IResult<LegacyEquipmentRow> = await request.query(`
        SELECT
          e.id,
          LTRIM(RTRIM(e.cod_metrica)) AS cod_metrica,
          e.cod_interno,
          e.instrumento,
          e.tipo_instrumento,
          e.marca,
          e.modelo,
          e.serie,
          e.estado,
          e.ubicacion,
          b.categoria,
          b.unidad,
          CONVERT(varchar(50), b.cap_max1) AS cap_max1,
          CONVERT(varchar(50), b.d1) AS d1,
          CONVERT(varchar(50), b.e1) AS e1,
          b.dec1,
          CONVERT(varchar(50), b.cap_max2) AS cap_max2,
          CONVERT(varchar(50), b.d2) AS d2,
          CONVERT(varchar(50), b.e2) AS e2,
          b.dec2,
          CONVERT(varchar(50), b.cap_max3) AS cap_max3,
          CONVERT(varchar(50), b.d3) AS d3,
          CONVERT(varchar(50), b.e3) AS e3,
          b.dec3,
          b.comunicacion,
          b.material,
          b.acceso,
          b.altura,
          b.n_celdas,
          b.tecnologia,
          b.proteccion,
          b.plataforma,
          b.clase,
          b.tipo AS tipo_balanza,
          b.cod_metrica AS balance_cod_metrica
        FROM dbo.DATA_EQUIPOS e
        LEFT JOIN dbo.DATA_EQUIPOS_BALANZAS b
          ON LTRIM(RTRIM(b.cod_metrica)) = LTRIM(RTRIM(e.cod_metrica))
        WHERE LTRIM(RTRIM(e.cod_metrica)) IN (${parameters.join(',')});
      `);
      rows.push(...result.recordset);
    }

    return rows.map((row) => {
      const sourceCode = optionalText(row.cod_metrica) ?? '<blank>';
      try {
        return { sourceCode, equipment: equipmentFromRow(row), error: null };
      } catch (error) {
        return {
          sourceCode,
          equipment: null,
          error: error instanceof Error ? error.message : String(error),
        };
      }
    });
  }
}

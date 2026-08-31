import type { JsonValue } from '../core/canonical';

export type SyncDirection = 'DATAMET_TO_SUPABASE' | 'SUPABASE_TO_SQL_IVMET';
export type SyncRunStatus = 'SUCCEEDED' | 'PARTIAL' | 'FAILED';
export type LegacyEntityType = 'CLIENT' | 'PLANT' | 'EQUIPMENT' | 'EQUIPMENT_RANGE';

export type SyncCounts = {
  scanned: number;
  accepted: number;
  unchanged: number;
  rejected: number;
};

export type CatalogScope = {
  scopeId: string;
  legacyClientId: number;
  legacyClientCode: string;
  supabaseClientId: string | null;
  status: 'REQUESTED' | 'ACTIVE';
  plantCodes: string[];
  equipmentCodes: string[];
};

export type CatalogJob = CatalogScope & { runId: string; generation: string };

export type CatalogClient = {
  legacyClientId: number;
  code: string;
  name: string | null;
  legalName: string | null;
  legacyStatus: string | null;
  active: boolean;
  sourceHash: string;
};

export type CatalogPlant = {
  legacyClientId: number;
  legacyCode: string;
  legacyPlantNumber: number | null;
  name: string | null;
  address: string | null;
  departmentCode: string | null;
  departmentId: number | null;
  locality: string | null;
  location: string | null;
  legacyStatus: string | null;
  active: boolean;
  sourceHash: string;
};

export type CatalogEquipmentRange = {
  rangeNumber: number;
  unit: string;
  maximumCapacity: string;
  scaleDivision: string;
  verificationInterval: string | null;
  decimalPlaces: number | null;
  sourceHash: string;
};

export type CatalogEquipment = {
  legacyEquipmentId: number;
  code: string;
  plantCode: string;
  internalCode: string | null;
  instrument: string | null;
  instrumentType: string | null;
  category: string | null;
  balanceType: string | null;
  brand: string | null;
  model: string | null;
  serial: string | null;
  unit: string | null;
  location: string | null;
  communication: string | null;
  material: string | null;
  access: string | null;
  height: string | null;
  cellCount: number | null;
  technology: string | null;
  protection: string | null;
  platform: string | null;
  className: string | null;
  legacyStatus: string | null;
  catalogStatus: 'READY' | 'REQUIRES_REVIEW';
  active: boolean;
  ranges: CatalogEquipmentRange[];
  warnings: string[];
  sourceHash: string;
};

export type QuarantineRecord = {
  entityType: LegacyEntityType;
  sourceKey: string;
  reasonCode: string;
  reasonDetail: string;
  safePayload: JsonValue;
  payloadHash: string;
};

export type OutboxEvent = {
  eventId: string;
  sequence: number;
  aggregateType: string;
  aggregateKey: Record<string, JsonValue>;
  operation: 'I' | 'U' | 'D';
  payload: Record<string, JsonValue>;
  /** Hash del evento original; la entrega de un caso puede actualizarse al retirar consentimiento. */
  sourcePayloadHash?: string;
  attempts: number;
  createdAt: string;
};

export function emptyCounts(): SyncCounts {
  return { scanned: 0, accepted: 0, unchanged: 0, rejected: 0 };
}

export function runStatus(counts: SyncCounts): SyncRunStatus {
  if (counts.rejected === 0) return 'SUCCEEDED';
  if (counts.accepted > 0 || counts.unchanged > 0) return 'PARTIAL';
  return 'FAILED';
}

import { env } from '../config';
import { safeError, sha256, type JsonValue } from '../core/canonical';
import type { CatalogScope, QuarantineRecord, SyncCounts } from '../domain/types';
import { emptyCounts, runStatus } from '../domain/types';
import type { DataMetRepository, EquipmentReadCandidate } from '../infrastructure/datamet.repository';
import type { IvmetRepository } from '../infrastructure/ivmet.repository';
import type { SupabaseGateway } from '../infrastructure/supabase.gateway';
import { logger } from '../logger';

type ScopeResult = {
  scopeId: string;
  counts: SyncCounts;
  status: ReturnType<typeof runStatus>;
};

function groupBy<T>(values: T[], key: (value: T) => string): Map<string, T[]> {
  const grouped = new Map<string, T[]>();
  for (const value of values) {
    const groupKey = key(value);
    grouped.set(groupKey, [...(grouped.get(groupKey) ?? []), value]);
  }
  return grouped;
}

export class CatalogSyncService {
  private readonly leaseName = 'datamet_to_supabase';

  constructor(
    private readonly dataMet: DataMetRepository,
    private readonly supabase: SupabaseGateway,
    private readonly ivmet: IvmetRepository,
  ) {}

  async run(): Promise<ScopeResult[]> {
    const acquired = await this.ivmet.tryAcquireLease(
      this.leaseName,
      env.WORKER_ID,
      env.WORKER_LEASE_SECONDS,
    );
    if (!acquired) {
      logger.info('Sincronizacion de catalogos omitida: otro worker conserva el lease');
      return [];
    }

    try {
      const scopes = await this.supabase.listScopes(env.WORKER_SCOPE_ID);
      const results: ScopeResult[] = [];
      for (const scope of scopes) {
        await this.ivmet.renewLease(this.leaseName, env.WORKER_ID, env.WORKER_LEASE_SECONDS);
        results.push(await this.syncScope(scope));
      }
      return results;
    } finally {
      await this.ivmet.releaseLease(this.leaseName, env.WORKER_ID).catch((error) => {
        logger.warn({ error: safeError(error) }, 'No se pudo liberar el lease de catalogos');
      });
    }
  }

  private async syncScope(scope: CatalogScope): Promise<ScopeResult> {
    const counts = emptyCounts();
    let supabaseRunId: string | null = null;
    let sqlRunId: string | null = null;
    let clientId: string | null = scope.supabaseClientId;
    let fatalError: string | null = null;

    try {
      supabaseRunId = await this.supabase.beginRun('DATAMET_TO_SUPABASE', scope.scopeId, {
        scopeId: scope.scopeId,
        legacyClientId: scope.legacyClientId,
        plantCount: scope.plantCodes.length,
        equipmentCount: scope.equipmentCodes.length,
      });
      sqlRunId = await this.ivmet.beginRun('DATAMET_TO_SUPABASE', env.WORKER_ID, {
        scopeId: scope.scopeId,
        supabaseRunId,
      });

      counts.scanned += 1;
      try {
        const client = await this.dataMet.readClient(scope.legacyClientId, scope.legacyClientCode);
        const outcome = await this.supabase.upsertClient(client, supabaseRunId);
        clientId = outcome.id;
        outcome.changed ? (counts.accepted += 1) : (counts.unchanged += 1);
        await this.ivmet.upsertDataMetState({
          entityType: 'CLIENT',
          sourceKey: String(client.legacyClientId),
          sourceHash: client.sourceHash,
          supabaseId: outcome.id,
          scopeId: scope.scopeId,
          runId: sqlRunId,
        });
      } catch (error) {
        counts.rejected += 1;
        await this.quarantine(supabaseRunId, sqlRunId, {
          entityType: 'CLIENT',
          sourceKey: `${scope.legacyClientId}:${scope.legacyClientCode}`,
          reasonCode: 'CLIENT_IMPORT_FAILED',
          reasonDetail: safeError(error),
          safePayload: {
            legacyClientId: scope.legacyClientId,
            legacyClientCode: scope.legacyClientCode,
          },
          payloadHash: sha256({
            legacyClientId: scope.legacyClientId,
            legacyClientCode: scope.legacyClientCode,
          }),
        });
        throw error;
      }

      if (scope.plantCodes.length === 0) {
        counts.scanned += 1;
        counts.rejected += 1;
        await this.quarantine(supabaseRunId, sqlRunId, this.scopeIssue(scope, 'SCOPE_WITHOUT_PLANTS'));
      }
      if (scope.equipmentCodes.length === 0) {
        counts.scanned += 1;
        counts.rejected += 1;
        await this.quarantine(supabaseRunId, sqlRunId, this.scopeIssue(scope, 'SCOPE_WITHOUT_EQUIPMENT'));
      }

      const plants = await this.dataMet.readPlants(scope.legacyClientId, scope.plantCodes);
      const plantsByCode = groupBy(plants, (plant) => plant.legacyCode);
      const plantIds = new Map<string, string>();

      for (const plantCode of scope.plantCodes) {
        counts.scanned += 1;
        const candidates = plantsByCode.get(plantCode) ?? [];
        if (candidates.length !== 1) {
          counts.rejected += 1;
          await this.quarantine(supabaseRunId, sqlRunId, {
            entityType: 'PLANT',
            sourceKey: `${scope.legacyClientId}:${plantCode}`,
            reasonCode: candidates.length === 0 ? 'PLANT_NOT_FOUND' : 'PLANT_AMBIGUOUS',
            reasonDetail: `Se encontraron ${candidates.length} filas para la planta seleccionada`,
            safePayload: { legacyClientId: scope.legacyClientId, plantCode },
            payloadHash: sha256({ legacyClientId: scope.legacyClientId, plantCode }),
          });
          continue;
        }

        const plant = candidates[0]!;
        try {
          const outcome = await this.supabase.upsertPlant(plant, clientId!, supabaseRunId);
          plantIds.set(plantCode, outcome.id);
          outcome.changed ? (counts.accepted += 1) : (counts.unchanged += 1);
          await this.ivmet.upsertDataMetState({
            entityType: 'PLANT',
            sourceKey: `${scope.legacyClientId}:${plantCode}`,
            sourceHash: plant.sourceHash,
            supabaseId: outcome.id,
            scopeId: scope.scopeId,
            runId: sqlRunId,
          });
        } catch (error) {
          counts.rejected += 1;
          await this.quarantine(supabaseRunId, sqlRunId, {
            entityType: 'PLANT',
            sourceKey: `${scope.legacyClientId}:${plantCode}`,
            reasonCode: 'PLANT_IMPORT_FAILED',
            reasonDetail: safeError(error),
            safePayload: { legacyClientId: scope.legacyClientId, plantCode },
            payloadHash: plant.sourceHash,
          });
        }
      }

      const equipmentCandidates = await this.dataMet.readEquipment(scope.equipmentCodes);
      const equipmentByCode = groupBy(equipmentCandidates, (candidate) => candidate.sourceCode);
      for (const equipmentCode of scope.equipmentCodes) {
        counts.scanned += 1;
        const candidates = equipmentByCode.get(equipmentCode) ?? [];
        await this.processEquipment(
          scope,
          equipmentCode,
          candidates,
          plantIds,
          clientId!,
          supabaseRunId,
          sqlRunId,
          counts,
        );
      }
    } catch (error) {
      fatalError = safeError(error);
      const classified = counts.accepted + counts.unchanged + counts.rejected;
      if (classified < counts.scanned) counts.rejected += counts.scanned - classified;
      if (counts.scanned === 0) {
        counts.scanned = 1;
        counts.rejected = 1;
      }
      logger.error({ scopeId: scope.scopeId, error: fatalError }, 'Fallo la sincronizacion del alcance');
    }

    const status = fatalError ? 'FAILED' : runStatus(counts);
    if (supabaseRunId) {
      await this.supabase.finishRun(supabaseRunId, status, counts, fatalError).catch((error) => {
        logger.error({ error: safeError(error), supabaseRunId }, 'No se pudo cerrar el run de Supabase');
      });
      await this.supabase
        .markScope(scope.scopeId, clientId, status === 'SUCCEEDED', fatalError ?? (status === 'PARTIAL' ? 'SYNC_PARTIAL' : null))
        .catch((error) => {
          logger.error({ error: safeError(error), scopeId: scope.scopeId }, 'No se pudo actualizar el alcance');
        });
    }
    if (sqlRunId) {
      await this.ivmet.finishRun(sqlRunId, status, counts, fatalError).catch((error) => {
        logger.error({ error: safeError(error), sqlRunId }, 'No se pudo cerrar el run de SQL Server');
      });
    }

    logger.info({ scopeId: scope.scopeId, status, counts }, 'Sincronizacion de alcance finalizada');
    return { scopeId: scope.scopeId, counts, status };
  }

  private async processEquipment(
    scope: CatalogScope,
    equipmentCode: string,
    candidates: EquipmentReadCandidate[],
    plantIds: Map<string, string>,
    clientId: string,
    supabaseRunId: string,
    sqlRunId: string,
    counts: SyncCounts,
  ): Promise<void> {
    if (candidates.length !== 1 || !candidates[0]?.equipment) {
      counts.rejected += 1;
      const reasonCode = candidates.length === 0
        ? 'EQUIPMENT_NOT_FOUND'
        : candidates.length > 1
          ? 'EQUIPMENT_AMBIGUOUS'
          : 'EQUIPMENT_INVALID';
      await this.quarantine(supabaseRunId, sqlRunId, {
        entityType: 'EQUIPMENT',
        sourceKey: equipmentCode,
        reasonCode,
        reasonDetail: candidates[0]?.error ?? `Se encontraron ${candidates.length} filas`,
        safePayload: { equipmentCode },
        payloadHash: sha256({ equipmentCode }),
      });
      return;
    }

    const equipment = candidates[0].equipment;
    const plantId = plantIds.get(equipment.plantCode);
    if (!plantId) {
      counts.rejected += 1;
      await this.quarantine(supabaseRunId, sqlRunId, {
        entityType: 'EQUIPMENT',
        sourceKey: equipmentCode,
        reasonCode: 'EQUIPMENT_PLANT_NOT_AVAILABLE',
        reasonDetail: `La planta ${equipment.plantCode} no fue seleccionada o no pudo importarse`,
        safePayload: { equipmentCode, plantCode: equipment.plantCode },
        payloadHash: equipment.sourceHash,
      });
      return;
    }

    try {
      const outcome = await this.supabase.upsertEquipment(
        equipment,
        clientId,
        plantId,
        supabaseRunId,
      );
      outcome.changed || outcome.rangeChanged > 0 || outcome.rangeDeleted > 0
        ? (counts.accepted += 1)
        : (counts.unchanged += 1);

      await this.ivmet.upsertDataMetState({
        entityType: 'EQUIPMENT',
        sourceKey: String(equipment.legacyEquipmentId),
        sourceHash: equipment.sourceHash,
        supabaseId: outcome.id,
        scopeId: scope.scopeId,
        runId: sqlRunId,
      });
      for (const range of outcome.ranges) {
        await this.ivmet.upsertDataMetState({
          entityType: 'EQUIPMENT_RANGE',
          sourceKey: `${equipment.code}:${range.rangeNumber}`,
          sourceHash: range.sourceHash,
          supabaseId: range.id,
          scopeId: scope.scopeId,
          runId: sqlRunId,
        });
      }

      if (equipment.warnings.length > 0) {
        await this.quarantine(supabaseRunId, sqlRunId, {
          entityType: 'EQUIPMENT',
          sourceKey: equipmentCode,
          reasonCode: 'EQUIPMENT_REQUIRES_REVIEW',
          reasonDetail: equipment.warnings.join('; '),
          safePayload: {
            equipmentCode,
            warnings: equipment.warnings,
          },
          payloadHash: equipment.sourceHash,
        });
      }
    } catch (error) {
      counts.rejected += 1;
      await this.quarantine(supabaseRunId, sqlRunId, {
        entityType: 'EQUIPMENT',
        sourceKey: equipmentCode,
        reasonCode: 'EQUIPMENT_IMPORT_FAILED',
        reasonDetail: safeError(error),
        safePayload: { equipmentCode, plantCode: equipment.plantCode },
        payloadHash: equipment.sourceHash,
      });
    }
  }

  private async quarantine(
    supabaseRunId: string,
    sqlRunId: string,
    record: QuarantineRecord,
  ): Promise<void> {
    await this.supabase.recordQuarantine(supabaseRunId, record);
    await this.ivmet.recordCatalogQuarantine(sqlRunId, record);
  }

  private scopeIssue(scope: CatalogScope, reasonCode: string): QuarantineRecord {
    const safePayload = {
      scopeId: scope.scopeId,
      legacyClientId: scope.legacyClientId,
      reasonCode,
    } satisfies Record<string, JsonValue>;
    return {
      entityType: 'CLIENT',
      sourceKey: `${scope.legacyClientId}:${scope.legacyClientCode}`,
      reasonCode,
      reasonDetail: reasonCode,
      safePayload,
      payloadHash: sha256(safePayload),
    };
  }
}

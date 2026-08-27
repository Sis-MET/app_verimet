import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { env } from '../config';
import type { JsonValue } from '../core/canonical';
import type {
  CatalogClient,
  CatalogEquipment,
  CatalogPlant,
  CatalogScope,
  CatalogJob,
  LegacyEntityType,
  OutboxEvent,
  QuarantineRecord,
  SyncCounts,
  SyncDirection,
  SyncRunStatus,
} from '../domain/types';

const scopeRowSchema = z.object({
  scope_id: z.string().uuid(),
  legacy_cliente_id: z.number().int(),
  legacy_codigo_cliente: z.string(),
  supabase_cliente_id: z.string().uuid().nullable(),
  scope_status: z.enum(['REQUESTED', 'ACTIVE']),
  plant_codes: z.array(z.string()),
  equipment_codes: z.array(z.string()),
});

const outboxRowSchema = z.object({
  event_id: z.string().uuid(),
  sequence: z.coerce.number().int().positive().safe(),
  aggregate_type: z.string().min(1),
  aggregate_key: z.record(z.unknown()),
  operation: z.enum(['I', 'U', 'D']),
  payload: z.record(z.unknown()),
  attempts: z.number().int().positive(),
  created_at: z.string(),
});

type ExistingCatalogRow = {
  id: string;
  source_hash: string;
  source_version?: number;
  cliente_id?: string;
  planta_id?: string;
  legacy_cliente_id?: number;
  legacy_equipo_id?: number;
};

export type UpsertOutcome = {
  id: string;
  changed: boolean;
};

export type EquipmentUpsertOutcome = UpsertOutcome & {
  rangeChanged: number;
  rangeUnchanged: number;
  rangeDeleted: number;
  ranges: Array<{ id: string; rangeNumber: number; sourceHash: string }>;
};

function ensureNoError(
  error: { message: string } | null,
  operation: string,
): void {
  if (error) throw new Error(`${operation}: ${error.message}`);
}

function asJsonRecord(
  value: Record<string, unknown>,
): Record<string, JsonValue> {
  return value as Record<string, JsonValue>;
}

export class SupabaseGateway {
  private readonly client: SupabaseClient;

  constructor(
    url = env.SUPABASE_URL,
    serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY,
  ) {
    this.client = createClient(url, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      global: {
        fetch: (input, init) =>
          fetch(input, { ...init, signal: AbortSignal.timeout(20_000) }),
        headers: {
          'X-IvMET-Worker': env.WORKER_ID,
        },
      },
    });
  }

  async healthCheck(): Promise<{
    reachable: boolean;
    scopes: number;
    contractVersion: number;
  }> {
    const { data, error } = await this.client.rpc('ivmet_worker_contract');
    ensureNoError(
      error,
      'Falta la migracion 202608270004_onboarding_queue o no se pudo comprobar el contrato',
    );
    if (data !== 2) throw new Error('WORKER_CONTRACT_MISMATCH');
    const scopes = await this.listScopes(env.WORKER_SCOPE_ID);
    return { reachable: true, scopes: scopes.length, contractVersion: data };
  }

  async reportWorker(
    instanceId: string,
    mode: string,
    state: string,
  ): Promise<void> {
    const { error } = await this.client.rpc('report_ivmet_worker', {
      worker_id: env.WORKER_ID,
      instance_id: instanceId,
      mode,
      state,
      target_scope_id: env.WORKER_SCOPE_ID ?? null,
      poll_seconds: env.WORKER_OUTBOX_POLL_SECONDS,
    });
    ensureNoError(error, 'No se pudo publicar disponibilidad del worker');
  }

  async claimCatalogJob(): Promise<CatalogJob | null> {
    const { data, error } = await this.client.rpc('claim_ivmet_catalog_job', {
      worker_id: env.WORKER_ID,
      target_scope_id: env.WORKER_SCOPE_ID ?? null,
      lease_seconds: env.WORKER_LEASE_SECONDS,
    });
    ensureNoError(error, 'No se pudo reclamar una incorporacion');
    if (!data) return null;
    const row = scopeRowSchema
      .extend({
        run_id: z.string().uuid(),
        generation: z.string().regex(/^\d+$/),
      })
      .parse(data);
    return {
      scopeId: row.scope_id,
      legacyClientId: row.legacy_cliente_id,
      legacyClientCode: row.legacy_codigo_cliente.trim(),
      supabaseClientId: row.supabase_cliente_id,
      status: row.scope_status,
      plantCodes: row.plant_codes,
      equipmentCodes: row.equipment_codes,
      runId: row.run_id,
      generation: row.generation,
    };
  }

  async renewCatalogJob(runId: string): Promise<void> {
    const { data, error } = await this.client.rpc('renew_ivmet_catalog_job', {
      target_run_id: runId,
      lease_seconds: env.WORKER_LEASE_SECONDS,
    });
    ensureNoError(error, 'No se pudo renovar la incorporacion');
    if (data !== true) throw new Error('CATALOG_LEASE_LOST');
  }

  async finishCatalogJob(
    job: CatalogJob,
    clientId: string | null,
    status: SyncRunStatus,
    counts: SyncCounts,
    detail: string | null,
  ): Promise<void> {
    const { data, error } = await this.client.rpc('finish_ivmet_catalog_job', {
      target_run_id: job.runId,
      target_client_id: clientId,
      final_status: status,
      scanned_count: counts.scanned,
      accepted_count: counts.accepted,
      unchanged_count: counts.unchanged,
      rejected_count: counts.rejected,
      error_message: detail,
      refresh_seconds: env.WORKER_CATALOG_INTERVAL_SECONDS,
      retry_seconds: env.WORKER_RETRY_SECONDS,
    });
    ensureNoError(error, 'No se pudo finalizar la incorporacion');
    if (data !== true) throw new Error('CATALOG_LEASE_LOST');
  }

  async listScopes(scopeId?: string): Promise<CatalogScope[]> {
    const { data, error } = await this.client.rpc(
      'list_ivmet_catalog_sync_scopes',
      {
        target_scope_id: scopeId ?? null,
      },
    );
    ensureNoError(error, 'No se pudieron leer los alcances de sincronizacion');

    return z
      .array(scopeRowSchema)
      .parse(data ?? [])
      .map((row) => ({
        scopeId: row.scope_id,
        legacyClientId: row.legacy_cliente_id,
        legacyClientCode: row.legacy_codigo_cliente.trim(),
        supabaseClientId: row.supabase_cliente_id,
        status: row.scope_status,
        plantCodes: row.plant_codes.map((code) => code.trim()),
        equipmentCodes: row.equipment_codes.map((code) => code.trim()),
      }));
  }

  async beginRun(
    direction: SyncDirection,
    scopeId: string | null,
    metadata: Record<string, JsonValue>,
  ): Promise<string> {
    const { data, error } = await this.client.rpc('begin_ivmet_sync_run', {
      direction,
      worker_id: env.WORKER_ID,
      target_scope_id: scopeId,
      run_metadata: metadata,
    });
    ensureNoError(error, 'No se pudo iniciar la ejecucion en Supabase');
    return z.string().uuid().parse(data);
  }

  async finishRun(
    runId: string,
    status: SyncRunStatus,
    counts: SyncCounts,
    errorMessage: string | null,
  ): Promise<void> {
    const { data, error } = await this.client.rpc('finish_ivmet_sync_run', {
      target_run_id: runId,
      final_status: status,
      scanned_count: counts.scanned,
      accepted_count: counts.accepted,
      unchanged_count: counts.unchanged,
      rejected_count: counts.rejected,
      error_message: errorMessage,
    });
    ensureNoError(error, 'No se pudo finalizar la ejecucion en Supabase');
    if (data !== true)
      throw new Error(`La ejecucion ${runId} ya estaba finalizada o no existe`);
  }

  async markScope(
    scopeId: string,
    clientId: string | null,
    successful: boolean,
    detail: string | null,
  ): Promise<void> {
    const { data, error } = await this.client.rpc(
      'mark_ivmet_catalog_sync_scope',
      {
        target_scope_id: scopeId,
        target_supabase_cliente_id: clientId,
        successful,
        detail,
      },
    );
    ensureNoError(error, 'No se pudo actualizar el alcance de sincronizacion');
    if (data !== true)
      throw new Error(`El alcance ${scopeId} no existe o no esta habilitado`);
  }

  async recordIdentity(
    runId: string,
    entityType: LegacyEntityType,
    legacyKey: string,
    supabaseId: string,
    sourceHash: string,
  ): Promise<void> {
    const { error } = await this.client.rpc('record_ivmet_legacy_identity', {
      target_run_id: runId,
      target_entity_type: entityType,
      target_legacy_key: legacyKey,
      target_supabase_id: supabaseId,
      target_source_hash: sourceHash,
    });
    ensureNoError(error, 'No se pudo registrar la identidad legada');
  }

  async recordQuarantine(
    runId: string,
    record: QuarantineRecord,
  ): Promise<void> {
    const { error } = await this.client.rpc('record_ivmet_sync_quarantine', {
      target_run_id: runId,
      target_entity_type: record.entityType,
      target_source_key: record.sourceKey,
      target_reason_code: record.reasonCode,
      target_reason_detail: record.reasonDetail,
      target_safe_payload: record.safePayload,
      target_payload_hash: record.payloadHash,
    });
    ensureNoError(error, 'No se pudo registrar la cuarentena');
  }

  async upsertClient(
    source: CatalogClient,
    runId: string,
  ): Promise<UpsertOutcome> {
    const { data: existingData, error: existingError } = await this.client
      .from('clientes')
      .select('id,legacy_cliente_id,source_hash,source_version')
      .eq('legacy_cliente_id', source.legacyClientId)
      .maybeSingle();
    ensureNoError(existingError, 'No se pudo consultar el cliente existente');
    const existing = existingData as ExistingCatalogRow | null;

    if (existing?.source_hash === source.sourceHash) {
      await this.recordIdentity(
        runId,
        'CLIENT',
        String(source.legacyClientId),
        existing.id,
        source.sourceHash,
      );
      return { id: existing.id, changed: false };
    }

    const { data, error } = await this.client
      .from('clientes')
      .upsert(
        {
          legacy_cliente_id: source.legacyClientId,
          codigo: source.code,
          nombre: source.name,
          razon_social: source.legalName,
          estado_legacy: source.legacyStatus,
          activo: source.active,
          source_version: (existing?.source_version ?? 0) + 1,
          source_hash: source.sourceHash,
          source_updated_at: null,
          synced_at: new Date().toISOString(),
          last_seen_run_id: runId,
        },
        { onConflict: 'legacy_cliente_id' },
      )
      .select('id')
      .single();
    ensureNoError(error, 'No se pudo guardar el cliente');
    const id = z.string().uuid().parse(data?.id);
    await this.recordIdentity(
      runId,
      'CLIENT',
      String(source.legacyClientId),
      id,
      source.sourceHash,
    );
    return { id, changed: true };
  }

  async upsertPlant(
    source: CatalogPlant,
    clientId: string,
    runId: string,
  ): Promise<UpsertOutcome> {
    const { data: existingData, error: existingError } = await this.client
      .from('plantas')
      .select('id,cliente_id,source_hash,source_version')
      .eq('legacy_codigo_planta', source.legacyCode)
      .maybeSingle();
    ensureNoError(existingError, 'No se pudo consultar la planta existente');
    const existing = existingData as ExistingCatalogRow | null;

    if (existing?.cliente_id && existing.cliente_id !== clientId) {
      throw new Error(`PLANT_SCOPE_CONFLICT:${source.legacyCode}`);
    }
    if (existing?.source_hash === source.sourceHash) {
      await this.recordIdentity(
        runId,
        'PLANT',
        `${source.legacyClientId}:${source.legacyCode}`,
        existing.id,
        source.sourceHash,
      );
      return { id: existing.id, changed: false };
    }

    const { data, error } = await this.client
      .from('plantas')
      .upsert(
        {
          cliente_id: clientId,
          legacy_codigo_planta: source.legacyCode,
          legacy_planta_numero: source.legacyPlantNumber,
          nombre: source.name,
          direccion: source.address,
          departamento_codigo: source.departmentCode,
          departamento_id: source.departmentId,
          localidad: source.locality,
          ubicacion: source.location,
          estado_legacy: source.legacyStatus,
          activo: source.active,
          source_version: (existing?.source_version ?? 0) + 1,
          source_hash: source.sourceHash,
          source_updated_at: null,
          synced_at: new Date().toISOString(),
          last_seen_run_id: runId,
        },
        { onConflict: 'legacy_codigo_planta' },
      )
      .select('id')
      .single();
    ensureNoError(error, 'No se pudo guardar la planta');
    const id = z.string().uuid().parse(data?.id);
    await this.recordIdentity(
      runId,
      'PLANT',
      `${source.legacyClientId}:${source.legacyCode}`,
      id,
      source.sourceHash,
    );
    return { id, changed: true };
  }

  async upsertEquipment(
    source: CatalogEquipment,
    clientId: string,
    plantId: string,
    runId: string,
  ): Promise<EquipmentUpsertOutcome> {
    const { data: existingData, error: existingError } = await this.client
      .from('equipos')
      .select(
        'id,cliente_id,planta_id,legacy_equipo_id,source_hash,source_version',
      )
      .eq('cod_metrica', source.code)
      .maybeSingle();
    ensureNoError(existingError, 'No se pudo consultar el equipo existente');
    const existing = existingData as ExistingCatalogRow | null;

    if (
      existing &&
      (existing.cliente_id !== clientId ||
        existing.planta_id !== plantId ||
        existing.legacy_equipo_id !== source.legacyEquipmentId)
    ) {
      throw new Error(`EQUIPMENT_SCOPE_CONFLICT:${source.code}`);
    }

    let equipmentId = existing?.id;
    let changed = false;

    if (!existing || existing.source_hash !== source.sourceHash) {
      const { data, error } = await this.client
        .from('equipos')
        .upsert(
          {
            cliente_id: clientId,
            planta_id: plantId,
            legacy_equipo_id: source.legacyEquipmentId,
            cod_metrica: source.code,
            cod_interno: source.internalCode,
            instrumento: source.instrument,
            tipo_instrumento: source.instrumentType,
            categoria: source.category,
            tipo_balanza: source.balanceType,
            marca: source.brand,
            modelo: source.model,
            serie: source.serial,
            unidad: source.unit,
            ubicacion: source.location,
            comunicacion: source.communication,
            material: source.material,
            acceso: source.access,
            altura: source.height,
            numero_celdas: source.cellCount,
            tecnologia: source.technology,
            proteccion: source.protection,
            plataforma: source.platform,
            clase: source.className,
            estado_legacy: source.legacyStatus,
            estado_catalogo: source.catalogStatus,
            activo: source.active,
            source_version: (existing?.source_version ?? 0) + 1,
            source_hash: source.sourceHash,
            source_updated_at: null,
            synced_at: new Date().toISOString(),
            last_seen_run_id: runId,
          },
          { onConflict: 'cod_metrica' },
        )
        .select('id')
        .single();
      ensureNoError(error, 'No se pudo guardar el equipo');
      equipmentId = z.string().uuid().parse(data?.id);
      changed = true;
    }

    if (!equipmentId)
      throw new Error(`No se resolvio el UUID del equipo ${source.code}`);
    await this.recordIdentity(
      runId,
      'EQUIPMENT',
      String(source.legacyEquipmentId),
      equipmentId,
      source.sourceHash,
    );

    const rangeResult = await this.syncRanges(source, equipmentId, runId);
    return { id: equipmentId, changed, ...rangeResult };
  }

  private async syncRanges(
    source: CatalogEquipment,
    equipmentId: string,
    runId: string,
  ): Promise<{
    rangeChanged: number;
    rangeUnchanged: number;
    rangeDeleted: number;
    ranges: Array<{ id: string; rangeNumber: number; sourceHash: string }>;
  }> {
    const { data: existingData, error: existingError } = await this.client
      .from('equipo_rangos')
      .select('id,numero_rango,source_hash')
      .eq('equipo_id', equipmentId);
    ensureNoError(
      existingError,
      'No se pudieron consultar los rangos existentes',
    );

    const existingByNumber = new Map<
      number,
      { id: string; source_hash: string }
    >(
      (
        (existingData ?? []) as Array<{
          id: string;
          numero_rango: number;
          source_hash: string;
        }>
      ).map((row) => [
        row.numero_rango,
        { id: row.id, source_hash: row.source_hash },
      ]),
    );
    let rangeChanged = 0;
    let rangeUnchanged = 0;
    const ranges: Array<{
      id: string;
      rangeNumber: number;
      sourceHash: string;
    }> = [];

    for (const range of source.ranges) {
      const existing = existingByNumber.get(range.rangeNumber);
      let rangeId = existing?.id;

      if (existing?.source_hash === range.sourceHash) {
        rangeUnchanged += 1;
      } else {
        const { data, error } = await this.client
          .from('equipo_rangos')
          .upsert(
            {
              equipo_id: equipmentId,
              numero_rango: range.rangeNumber,
              unidad: range.unit,
              capacidad_max: range.maximumCapacity,
              division_escala: range.scaleDivision,
              intervalo_verificacion: range.verificationInterval,
              cantidad_decimales: range.decimalPlaces,
              source_hash: range.sourceHash,
            },
            { onConflict: 'equipo_id,numero_rango' },
          )
          .select('id')
          .single();
        ensureNoError(error, 'No se pudo guardar el rango del equipo');
        rangeId = z.string().uuid().parse(data?.id);
        rangeChanged += 1;
      }

      if (!rangeId)
        throw new Error(
          `No se resolvio el rango ${source.code}:${range.rangeNumber}`,
        );
      await this.recordIdentity(
        runId,
        'EQUIPMENT_RANGE',
        `${source.code}:${range.rangeNumber}`,
        rangeId,
        range.sourceHash,
      );
      ranges.push({
        id: rangeId,
        rangeNumber: range.rangeNumber,
        sourceHash: range.sourceHash,
      });
      existingByNumber.delete(range.rangeNumber);
    }

    const staleRangeIds = [...existingByNumber.values()].map((row) => row.id);
    if (staleRangeIds.length > 0) {
      const { error } = await this.client
        .from('equipo_rangos')
        .delete()
        .in('id', staleRangeIds);
      ensureNoError(error, 'No se pudieron retirar los rangos obsoletos');
    }

    return {
      rangeChanged,
      rangeUnchanged,
      rangeDeleted: staleRangeIds.length,
      ranges,
    };
  }

  async claimOutbox(batchSize: number): Promise<OutboxEvent[]> {
    const { data, error } = await this.client.rpc('claim_ivmet_sync_outbox', {
      worker_id: env.WORKER_ID,
      batch_size: batchSize,
    });
    ensureNoError(error, 'No se pudo reclamar el outbox');
    return z
      .array(outboxRowSchema)
      .parse(data ?? [])
      .map((row) => ({
        eventId: row.event_id,
        sequence: row.sequence,
        aggregateType: row.aggregate_type,
        aggregateKey: asJsonRecord(row.aggregate_key),
        operation: row.operation,
        payload: asJsonRecord(row.payload),
        attempts: row.attempts,
        createdAt: row.created_at,
      }));
  }

  async acknowledgeOutbox(eventIds: string[]): Promise<number> {
    if (eventIds.length === 0) return 0;
    const { data, error } = await this.client.rpc('ack_ivmet_sync_outbox', {
      worker_id: env.WORKER_ID,
      event_ids: eventIds,
    });
    ensureNoError(error, 'No se pudo confirmar el outbox');
    return z.number().int().nonnegative().parse(data);
  }

  async failOutbox(
    eventId: string,
    message: string,
    retrySeconds: number,
  ): Promise<void> {
    const { data, error } = await this.client.rpc('fail_ivmet_sync_outbox', {
      worker_id: env.WORKER_ID,
      target_event_id: eventId,
      error_message: message,
      retry_after_seconds: retrySeconds,
    });
    ensureNoError(error, 'No se pudo liberar el evento fallido');
    if (data !== true)
      throw new Error(`El evento ${eventId} no pertenece al worker actual`);
  }

  async releaseOutbox(eventIds: string[], retrySeconds = 5): Promise<number> {
    if (eventIds.length === 0) return 0;
    const { data, error } = await this.client.rpc('release_ivmet_sync_outbox', {
      worker_id: env.WORKER_ID,
      event_ids: eventIds,
      retry_after_seconds: retrySeconds,
    });
    ensureNoError(error, 'No se pudieron liberar los eventos no procesados');
    return z.number().int().nonnegative().parse(data);
  }
}

import type { ConnectionPool, Request, Transaction } from 'mssql';
import { canonicalJson, sha256, type JsonValue } from '../core/canonical';
import type {
  LegacyEntityType,
  OutboxEvent,
  QuarantineRecord,
  SyncCounts,
  SyncDirection,
  SyncRunStatus,
} from '../domain/types';
import {
  mirrorSpecs,
  consentedAggregates,
  type MirrorColumn,
  type MirrorSpec,
} from './mirror-specs';
import { sql } from './sql-pools';

function quote(identifier: string): string {
  if (!/^[a-z_][a-z0-9_]*$/i.test(identifier)) {
    throw new Error(`Identificador SQL no permitido: ${identifier}`);
  }
  return `[${identifier}]`;
}

function jsonValue(value: unknown): JsonValue {
  return value as JsonValue;
}

function inputExpression(column: MirrorColumn, parameter: string): string {
  switch (column.type) {
    case 'uuid':
      return `TRY_CONVERT(uniqueidentifier, @${parameter})`;
    case 'int':
      return `TRY_CONVERT(int, @${parameter})`;
    case 'smallint':
      return `TRY_CONVERT(smallint, @${parameter})`;
    case 'bigint':
      return `TRY_CONVERT(bigint, @${parameter})`;
    case 'decimal':
      return `TRY_CONVERT(decimal(38,9), @${parameter})`;
    case 'bit':
      return `@${parameter}`;
    case 'date':
      return `TRY_CONVERT(date, @${parameter}, 23)`;
    case 'datetime':
      return `CONVERT(datetime2(3), SWITCHOFFSET(TRY_CONVERT(datetimeoffset, @${parameter}, 127), '+00:00'))`;
    case 'json':
    case 'text':
      return `@${parameter}`;
  }
}

function bindColumn(
  request: Request,
  parameter: string,
  column: MirrorColumn,
  rawValue: unknown,
): string {
  if (rawValue === undefined) {
    throw new Error(`El payload no contiene la columna ${column.source}`);
  }
  if (rawValue === null) {
    request.input(parameter, sql.NVarChar(sql.MAX), null);
    return inputExpression(column, parameter);
  }

  switch (column.type) {
    case 'bit':
      if (typeof rawValue !== 'boolean') {
        throw new Error(`${column.source} debe ser boolean`);
      }
      request.input(parameter, sql.Bit, rawValue);
      break;
    case 'json':
      request.input(
        parameter,
        sql.NVarChar(sql.MAX),
        canonicalJson(jsonValue(rawValue)),
      );
      break;
    default:
      request.input(parameter, sql.NVarChar(sql.MAX), String(rawValue));
  }
  return inputExpression(column, parameter);
}

function specFor(event: OutboxEvent): MirrorSpec {
  const spec = mirrorSpecs[event.aggregateType];
  if (!spec) throw new Error(`UNSUPPORTED_AGGREGATE:${event.aggregateType}`);
  return spec;
}

export class IvmetRepository {
  constructor(private readonly pool: ConnectionPool) {}

  async healthCheck(): Promise<{
    database: string;
    versions: number;
    canSelectMirror: boolean;
    canInsertMirror: boolean;
    canDeleteVerification: boolean;
    privacyReady: boolean;
    customerConfigurationReady: boolean;
  }> {
    const result = await this.pool.request().query<{
      database_name: string;
      versions: number;
      can_select: number;
      can_insert: number;
      can_delete_verification: number;
      privacy_ready: number;
      customer_configuration_ready: number;
    }>(`
      SELECT
        DB_NAME() AS database_name,
        (SELECT COUNT(*) FROM dbo.schema_versions WHERE version IN ('001','002','003','004','005','006')) AS versions,
        HAS_PERMS_BY_NAME(N'mirror.clientes', N'OBJECT', N'SELECT') AS can_select,
        HAS_PERMS_BY_NAME(N'mirror.clientes', N'OBJECT', N'INSERT') AS can_insert,
        HAS_PERMS_BY_NAME(N'mirror.verificaciones', N'OBJECT', N'DELETE') AS can_delete_verification,
        CASE WHEN EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='009')
          AND NOT EXISTS (SELECT 1 FROM (VALUES
            ('verificacion_borradores'),('verificaciones'),('verificacion_patrones'),('pruebas'),('lecturas'),('alertas'),('auditoria')
          ) evidence(table_name) CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) permissions(operation_name)
            WHERE COALESCE(HAS_PERMS_BY_NAME(N'mirror.'+evidence.table_name,N'OBJECT',permissions.operation_name),1)<>0)
          AND HAS_PERMS_BY_NAME(N'sync.failures',N'OBJECT',N'SELECT')=0
          AND HAS_PERMS_BY_NAME(N'mirror.casos_compartidos',N'OBJECT',N'INSERT')=1
          THEN 1 ELSE 0 END AS privacy_ready,
        CASE WHEN EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='011')
          AND HAS_PERMS_BY_NAME(N'mirror.actualizaciones_compartidas',N'OBJECT',N'INSERT')=1
          AND NOT EXISTS(SELECT 1 FROM (VALUES ('areas'),('equipos_ivmet'),('patrones'),('patron_plantas'),('patron_certificados'),
            ('planes'),('plan_versiones'),('plan_pruebas'),('plan_puntos'),('equipo_planes')) objects(table_name)
            CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) permissions(operation_name)
            WHERE COALESCE(HAS_PERMS_BY_NAME(N'mirror.'+objects.table_name,N'OBJECT',permissions.operation_name),1)<>0)
          THEN 1 ELSE 0 END AS customer_configuration_ready;
    `);
    const row = result.recordset[0];
    if (!row) throw new Error('IvMET no devolvio su estado');
    return {
      database: row.database_name,
      versions: row.versions,
      canSelectMirror: row.can_select === 1,
      canInsertMirror: row.can_insert === 1,
      canDeleteVerification: row.can_delete_verification === 1,
      privacyReady: row.privacy_ready === 1,
      customerConfigurationReady: row.customer_configuration_ready === 1,
    };
  }

  async tryAcquireLease(
    leaseName: string,
    ownerId: string,
    durationSeconds: number,
  ): Promise<boolean> {
    const result = await this.pool
      .request()
      .input('lease_name', sql.NVarChar(100), leaseName)
      .input('owner_id', sql.NVarChar(150), ownerId)
      .input('duration_seconds', sql.Int, durationSeconds)
      .output('acquired', sql.Bit)
      .execute('sync.try_acquire_lease');
    return result.output.acquired === true;
  }

  async renewLease(
    leaseName: string,
    ownerId: string,
    durationSeconds: number,
  ): Promise<void> {
    await this.pool
      .request()
      .input('lease_name', sql.NVarChar(100), leaseName)
      .input('owner_id', sql.NVarChar(150), ownerId)
      .input('duration_seconds', sql.Int, durationSeconds)
      .execute('sync.renew_lease');
  }

  async releaseLease(leaseName: string, ownerId: string): Promise<void> {
    await this.pool
      .request()
      .input('lease_name', sql.NVarChar(100), leaseName)
      .input('owner_id', sql.NVarChar(150), ownerId)
      .execute('sync.release_lease');
  }

  async beginRun(
    direction: SyncDirection,
    workerId: string,
    metadata: JsonValue,
  ): Promise<string> {
    const result = await this.pool
      .request()
      .input('direction', sql.VarChar(30), direction)
      .input('worker_id', sql.NVarChar(150), workerId)
      .input('metadata_json', sql.NVarChar(sql.MAX), canonicalJson(metadata))
      .output('run_id', sql.UniqueIdentifier)
      .execute('sync.begin_run');
    return String(result.output.run_id);
  }

  async finishRun(
    runId: string,
    status: SyncRunStatus,
    counts: SyncCounts,
    errorMessage: string | null,
  ): Promise<void> {
    await this.pool
      .request()
      .input('run_id', sql.UniqueIdentifier, runId)
      .input('status', sql.VarChar(20), status)
      .input('scanned_count', sql.Int, counts.scanned)
      .input('accepted_count', sql.Int, counts.accepted)
      .input('unchanged_count', sql.Int, counts.unchanged)
      .input('rejected_count', sql.Int, counts.rejected)
      .input('error', sql.NVarChar(4000), errorMessage)
      .execute('sync.finish_run');
  }

  async upsertDataMetState(input: {
    entityType: LegacyEntityType;
    sourceKey: string;
    sourceHash: string;
    supabaseId: string;
    scopeId: string;
    runId: string;
  }): Promise<void> {
    await this.pool
      .request()
      .input('entityType', sql.VarChar(30), input.entityType)
      .input('sourceKey', sql.NVarChar(150), input.sourceKey)
      .input('sourceHash', sql.Char(64), input.sourceHash)
      .input('supabaseId', sql.UniqueIdentifier, input.supabaseId)
      .input('scopeId', sql.UniqueIdentifier, input.scopeId)
      .input('runId', sql.UniqueIdentifier, input.runId).query(`
        UPDATE sync.datamet_entity_state WITH (UPDLOCK, HOLDLOCK)
        SET source_hash = @sourceHash,
            supabase_id = @supabaseId,
            scope_id = @scopeId,
            last_seen_at = SYSUTCDATETIME(),
            last_sent_at = SYSUTCDATETIME(),
            last_run_id = @runId,
            active = 1
        WHERE entity_type = @entityType AND source_key = @sourceKey;

        IF @@ROWCOUNT = 0
          INSERT INTO sync.datamet_entity_state
            (entity_type, source_key, source_hash, supabase_id, scope_id,
             first_seen_at, last_seen_at, last_sent_at, last_run_id, active)
          VALUES
            (@entityType, @sourceKey, @sourceHash, @supabaseId, @scopeId,
             SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), @runId, 1);
      `);
  }

  async recordCatalogQuarantine(
    runId: string,
    record: QuarantineRecord,
  ): Promise<void> {
    await this.pool
      .request()
      .input('runId', sql.UniqueIdentifier, runId)
      .input('entityType', sql.VarChar(30), record.entityType)
      .input('sourceKey', sql.NVarChar(150), record.sourceKey)
      .input('reasonCode', sql.NVarChar(100), record.reasonCode)
      .input('reasonDetail', sql.NVarChar(4000), record.reasonDetail)
      .input(
        'safePayload',
        sql.NVarChar(sql.MAX),
        canonicalJson(record.safePayload),
      )
      .input('payloadHash', sql.Char(64), record.payloadHash).query(`
        INSERT INTO sync.catalog_quarantine
          (run_id, entity_type, source_key, reason_code, reason_detail,
           safe_payload_json, payload_hash)
        VALUES
          (@runId, @entityType, @sourceKey, @reasonCode, @reasonDetail,
           @safePayload, @payloadHash);
      `);
  }

  async applyOutboxEvent(
    event: OutboxEvent,
    workerId: string,
  ): Promise<boolean> {
    const spec = specFor(event);
    if (spec.immutable && event.operation !== 'I') {
      throw new Error(
        `IMMUTABLE_AGGREGATE_OPERATION:${event.aggregateType}:${event.operation}`,
      );
    }

    const transaction = new sql.Transaction(this.pool);
    await transaction.begin(sql.ISOLATION_LEVEL.READ_COMMITTED);
    try {
      await this.applyProjection(transaction, spec, event);
      const alreadyApplied = await this.recordAppliedEvent(
        transaction,
        event,
        workerId,
      );
      await transaction.commit();
      return alreadyApplied;
    } catch (error) {
      await transaction.rollback().catch(() => undefined);
      throw error;
    }
  }

  private async applyProjection(
    transaction: Transaction,
    spec: MirrorSpec,
    event: OutboxEvent,
  ): Promise<void> {
    const request = transaction.request();
    request.input('eventSequence', sql.BigInt, String(event.sequence));

    if (event.operation === 'D') {
      const predicates = this.bindKeys(
        request,
        spec,
        event.aggregateKey,
        'key',
      );
      await request.query(`
        DELETE FROM mirror.${quote(spec.table)}
        WHERE ${predicates.join(' AND ')}
          AND source_event_sequence < @eventSequence;
      `);
      return;
    }

    const expressions = new Map<string, string>();
    for (const [index, column] of spec.columns.entries()) {
      expressions.set(
        column.target,
        bindColumn(
          request,
          `value${index}`,
          column,
          event.payload[column.source],
        ),
      );
    }
    const keyPredicates = spec.keys.map(
      (key) => `target.${quote(key)} = ${expressions.get(key)}`,
    );
    const insertColumns = [
      ...spec.columns.map((column) => quote(column.target)),
      '[source_event_sequence]',
      '[mirrored_at]',
    ];
    const insertValues = [
      ...spec.columns.map((column) => expressions.get(column.target)!),
      '@eventSequence',
      'SYSUTCDATETIME()',
    ];

    if (spec.immutable) {
      await request.query(`
        IF EXISTS (
          SELECT 1 FROM mirror.${quote(spec.table)} AS target WITH (UPDLOCK, HOLDLOCK)
          WHERE ${keyPredicates.join(' AND ')}
            AND target.source_event_sequence <> @eventSequence
        )
          THROW 53910, 'Conflicto sobre una proyeccion inmutable.', 1;

        IF NOT EXISTS (
          SELECT 1 FROM mirror.${quote(spec.table)} AS target WITH (UPDLOCK, HOLDLOCK)
          WHERE ${keyPredicates.join(' AND ')}
        )
          INSERT INTO mirror.${quote(spec.table)} (${insertColumns.join(', ')})
          VALUES (${insertValues.join(', ')});
      `);
      return;
    }

    const assignments = spec.columns
      .filter((column) => !spec.keys.includes(column.target))
      .map((column) =>
        consentedAggregates.has(event.aggregateType) &&
        ['snapshot_json', 'eventos_json'].includes(column.target)
          ? `${quote(column.target)} = CASE WHEN ${expressions.get('visibilidad')}='WITHDRAWN' THEN target.${quote(column.target)} ELSE ${expressions.get(column.target)} END`
          : `${quote(column.target)} = ${expressions.get(column.target)}`,
      );

    await request.query(`
      IF EXISTS (
        SELECT 1 FROM mirror.${quote(spec.table)} AS target WITH (UPDLOCK, HOLDLOCK)
        WHERE ${keyPredicates.join(' AND ')}
      )
      BEGIN
        UPDATE target
        SET ${assignments.join(', ')},
            [source_event_sequence] = CASE WHEN target.[source_event_sequence]>@eventSequence THEN target.[source_event_sequence] ELSE @eventSequence END,
            [mirrored_at] = SYSUTCDATETIME()
        FROM mirror.${quote(spec.table)} AS target
        WHERE ${keyPredicates.join(' AND ')}
          AND ${
            consentedAggregates.has(event.aggregateType)
              ? `(target.[source_row_version] < ${expressions.get('source_row_version')} OR (target.[source_row_version] = ${expressions.get('source_row_version')} AND target.[source_event_sequence] < @eventSequence))`
              : 'target.[source_event_sequence] < @eventSequence'
          };
      END
      ELSE
      BEGIN
        INSERT INTO mirror.${quote(spec.table)} (${insertColumns.join(', ')})
        VALUES (${insertValues.join(', ')});
      END;
    `);
  }

  private bindKeys(
    request: Request,
    spec: MirrorSpec,
    aggregateKey: Record<string, JsonValue>,
    prefix: string,
  ): string[] {
    return spec.keys.map((key, index) => {
      const column = spec.columns.find((candidate) => candidate.target === key);
      if (!column)
        throw new Error(`La clave ${key} no existe en ${spec.table}`);
      const value = aggregateKey[column.source];
      const expression = bindColumn(
        request,
        `${prefix}${index}`,
        column,
        value,
      );
      return `${quote(key)} = ${expression}`;
    });
  }

  private async recordAppliedEvent(
    transaction: Transaction,
    event: OutboxEvent,
    workerId: string,
  ): Promise<boolean> {
    if (
      consentedAggregates.has(event.aggregateType) &&
      !/^[0-9a-f]{64}$/.test(event.sourcePayloadHash || '')
    ) {
      throw new Error('CASE_SOURCE_HASH_REQUIRED');
    }
    const result = await transaction
      .request()
      .input('event_id', sql.UniqueIdentifier, event.eventId)
      .input('event_sequence', sql.BigInt, String(event.sequence))
      .input('aggregate_type', sql.NVarChar(128), event.aggregateType)
      .input(
        'aggregate_key_json',
        sql.NVarChar(1000),
        canonicalJson(event.aggregateKey),
      )
      .input('operation', sql.Char(1), event.operation)
      .input(
        'payload_hash',
        sql.Char(64),
        consentedAggregates.has(event.aggregateType)
          ? event.sourcePayloadHash
          : sha256(event.payload),
      )
      .input('source_created_at', sql.DateTime2(3), new Date(event.createdAt))
      .input('worker_id', sql.NVarChar(150), workerId)
      .input('worker_name', sql.NVarChar(100), 'supabase_to_sql_ivmet')
      .output('already_applied', sql.Bit)
      .execute('sync.record_applied_event');
    return result.output.already_applied === true;
  }

  async recordOutboxFailure(input: {
    runId: string;
    event: OutboxEvent;
    errorCode: string;
    errorDetail: string;
    nextRetryAt: Date | null;
  }): Promise<void> {
    await this.pool
      .request()
      .input('run_id', sql.UniqueIdentifier, input.runId)
      .input('event_id', sql.UniqueIdentifier, input.event.eventId)
      .input('event_sequence', sql.BigInt, String(input.event.sequence))
      .input('aggregate_type', sql.NVarChar(128), input.event.aggregateType)
      .input(
        'aggregate_key_json',
        sql.NVarChar(1000),
        canonicalJson(input.event.aggregateKey),
      )
      .input(
        'payload_json',
        sql.NVarChar(sql.MAX),
        canonicalJson(input.event.payload),
      )
      .input('error_code', sql.NVarChar(100), input.errorCode)
      .input('error_detail', sql.NVarChar(4000), input.errorDetail)
      .input('attempts', sql.Int, input.event.attempts)
      .input('next_retry_at', sql.DateTime2(3), input.nextRetryAt)
      .output('failure_id', sql.UniqueIdentifier)
      .execute('sync.record_failure');
  }
}

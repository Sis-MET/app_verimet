/*
  IvMET SQL Server - 002
  Control idempotente del worker y trazabilidad de DataMET/Supabase.
*/

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'sync') IS NULL
    THROW 53001, 'No existe el esquema sync. Ejecute 001_create_ivmet_database.sql.', 1;
GO

BEGIN TRANSACTION;

IF OBJECT_ID(N'sync.applied_events', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[applied_events] (
        [event_id] uniqueidentifier NOT NULL,
        [event_sequence] bigint NOT NULL,
        [aggregate_type] nvarchar(128) NOT NULL,
        [aggregate_key_json] nvarchar(1000) NOT NULL,
        [operation] char(1) NOT NULL,
        [payload_hash] char(64) NOT NULL,
        [source_created_at] datetime2(3) NOT NULL,
        [applied_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_applied_events_applied_at] DEFAULT SYSUTCDATETIME(),
        [worker_id] nvarchar(150) NOT NULL,
        CONSTRAINT [PK_applied_events] PRIMARY KEY ([event_id]),
        CONSTRAINT [UQ_applied_events_sequence] UNIQUE ([event_sequence]),
        CONSTRAINT [CK_applied_events_operation] CHECK ([operation] IN ('I', 'U', 'D')),
        CONSTRAINT [CK_applied_events_key_json] CHECK (ISJSON([aggregate_key_json]) = 1),
        CONSTRAINT [CK_applied_events_hash] CHECK (
            LEN([payload_hash]) = 64 AND [payload_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_applied_events_aggregate]
        ON [sync].[applied_events] ([aggregate_type], [applied_at] DESC);
END;

IF OBJECT_ID(N'sync.worker_state', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[worker_state] (
        [worker_name] nvarchar(100) NOT NULL,
        [checkpoint_sequence] bigint NOT NULL
            CONSTRAINT [DF_worker_state_checkpoint] DEFAULT 0,
        [last_success_at] datetime2(3) NULL,
        [last_error_at] datetime2(3) NULL,
        [last_error] nvarchar(4000) NULL,
        [updated_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_worker_state_updated_at] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_worker_state] PRIMARY KEY ([worker_name]),
        CONSTRAINT [CK_worker_state_checkpoint] CHECK ([checkpoint_sequence] >= 0)
    );
END;

IF OBJECT_ID(N'sync.runs', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[runs] (
        [run_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_sync_runs_id] DEFAULT NEWSEQUENTIALID(),
        [direction] varchar(30) NOT NULL,
        [worker_id] nvarchar(150) NOT NULL,
        [status] varchar(20) NOT NULL
            CONSTRAINT [DF_sync_runs_status] DEFAULT 'RUNNING',
        [started_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_sync_runs_started_at] DEFAULT SYSUTCDATETIME(),
        [finished_at] datetime2(3) NULL,
        [scanned_count] int NOT NULL CONSTRAINT [DF_sync_runs_scanned] DEFAULT 0,
        [accepted_count] int NOT NULL CONSTRAINT [DF_sync_runs_accepted] DEFAULT 0,
        [unchanged_count] int NOT NULL CONSTRAINT [DF_sync_runs_unchanged] DEFAULT 0,
        [rejected_count] int NOT NULL CONSTRAINT [DF_sync_runs_rejected] DEFAULT 0,
        [error] nvarchar(4000) NULL,
        [metadata_json] nvarchar(max) NULL,
        CONSTRAINT [PK_sync_runs] PRIMARY KEY ([run_id]),
        CONSTRAINT [CK_sync_runs_direction] CHECK (
            [direction] IN ('DATAMET_TO_SUPABASE', 'SUPABASE_TO_SQL_IVMET')
        ),
        CONSTRAINT [CK_sync_runs_status] CHECK (
            [status] IN ('RUNNING', 'SUCCEEDED', 'PARTIAL', 'FAILED')
        ),
        CONSTRAINT [CK_sync_runs_counts] CHECK (
            [scanned_count] >= 0 AND [accepted_count] >= 0
            AND [unchanged_count] >= 0 AND [rejected_count] >= 0
        ),
        CONSTRAINT [CK_sync_runs_metadata] CHECK (
            [metadata_json] IS NULL OR ISJSON([metadata_json]) = 1
        )
    );
    CREATE INDEX [IX_sync_runs_timeline]
        ON [sync].[runs] ([direction], [started_at] DESC);
END;

IF OBJECT_ID(N'sync.failures', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[failures] (
        [failure_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_sync_failures_id] DEFAULT NEWSEQUENTIALID(),
        [run_id] uniqueidentifier NULL,
        [event_id] uniqueidentifier NULL,
        [event_sequence] bigint NULL,
        [aggregate_type] nvarchar(128) NULL,
        [aggregate_key_json] nvarchar(1000) NULL,
        [payload_json] nvarchar(max) NULL,
        [error_code] nvarchar(100) NOT NULL,
        [error_detail] nvarchar(4000) NOT NULL,
        [attempts] int NOT NULL CONSTRAINT [DF_sync_failures_attempts] DEFAULT 1,
        [status] varchar(20) NOT NULL CONSTRAINT [DF_sync_failures_status] DEFAULT 'OPEN',
        [next_retry_at] datetime2(3) NULL,
        [resolved_at] datetime2(3) NULL,
        [resolution_note] nvarchar(2000) NULL,
        [created_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_sync_failures_created_at] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_sync_failures] PRIMARY KEY ([failure_id]),
        CONSTRAINT [FK_sync_failures_run] FOREIGN KEY ([run_id])
            REFERENCES [sync].[runs] ([run_id]),
        CONSTRAINT [CK_sync_failures_attempts] CHECK ([attempts] > 0),
        CONSTRAINT [CK_sync_failures_status] CHECK ([status] IN ('OPEN', 'RETRYING', 'RESOLVED', 'DEAD')),
        CONSTRAINT [CK_sync_failures_key_json] CHECK (
            [aggregate_key_json] IS NULL OR ISJSON([aggregate_key_json]) = 1
        ),
        CONSTRAINT [CK_sync_failures_payload_json] CHECK (
            [payload_json] IS NULL OR ISJSON([payload_json]) = 1
        )
    );
    CREATE INDEX [IX_sync_failures_open]
        ON [sync].[failures] ([status], [next_retry_at], [created_at]);
END;

IF OBJECT_ID(N'sync.datamet_entity_state', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[datamet_entity_state] (
        [entity_type] varchar(30) NOT NULL,
        [source_key] nvarchar(150) NOT NULL,
        [source_hash] char(64) NOT NULL,
        [supabase_id] uniqueidentifier NULL,
        [scope_id] uniqueidentifier NULL,
        [first_seen_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_datamet_state_first_seen] DEFAULT SYSUTCDATETIME(),
        [last_seen_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_datamet_state_last_seen] DEFAULT SYSUTCDATETIME(),
        [last_sent_at] datetime2(3) NULL,
        [last_run_id] uniqueidentifier NULL,
        [active] bit NOT NULL CONSTRAINT [DF_datamet_state_active] DEFAULT 1,
        CONSTRAINT [PK_datamet_entity_state] PRIMARY KEY ([entity_type], [source_key]),
        CONSTRAINT [FK_datamet_entity_state_run] FOREIGN KEY ([last_run_id])
            REFERENCES [sync].[runs] ([run_id]),
        CONSTRAINT [CK_datamet_entity_state_type] CHECK (
            [entity_type] IN ('CLIENT', 'PLANT', 'EQUIPMENT', 'EQUIPMENT_RANGE')
        ),
        CONSTRAINT [CK_datamet_entity_state_hash] CHECK (
            LEN([source_hash]) = 64 AND [source_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_datamet_entity_state_target]
        ON [sync].[datamet_entity_state] ([entity_type], [supabase_id]);
END;

IF OBJECT_ID(N'sync.catalog_quarantine', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[catalog_quarantine] (
        [quarantine_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_catalog_quarantine_id] DEFAULT NEWSEQUENTIALID(),
        [run_id] uniqueidentifier NOT NULL,
        [entity_type] varchar(30) NOT NULL,
        [source_key] nvarchar(150) NOT NULL,
        [reason_code] nvarchar(100) NOT NULL,
        [reason_detail] nvarchar(4000) NULL,
        [safe_payload_json] nvarchar(max) NULL,
        [payload_hash] char(64) NOT NULL,
        [status] varchar(20) NOT NULL
            CONSTRAINT [DF_catalog_quarantine_status] DEFAULT 'OPEN',
        [resolved_at] datetime2(3) NULL,
        [resolved_by] nvarchar(150) NULL,
        [resolution_note] nvarchar(2000) NULL,
        [created_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_catalog_quarantine_created] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_catalog_quarantine] PRIMARY KEY ([quarantine_id]),
        CONSTRAINT [FK_catalog_quarantine_run] FOREIGN KEY ([run_id])
            REFERENCES [sync].[runs] ([run_id]),
        CONSTRAINT [CK_catalog_quarantine_status] CHECK ([status] IN ('OPEN', 'RESOLVED', 'IGNORED')),
        CONSTRAINT [CK_catalog_quarantine_payload] CHECK (
            [safe_payload_json] IS NULL OR ISJSON([safe_payload_json]) = 1
        ),
        CONSTRAINT [CK_catalog_quarantine_hash] CHECK (
            LEN([payload_hash]) = 64 AND [payload_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_catalog_quarantine_open]
        ON [sync].[catalog_quarantine] ([status], [created_at] DESC)
        WHERE [status] = 'OPEN';
END;

IF OBJECT_ID(N'sync.worker_leases', N'U') IS NULL
BEGIN
    CREATE TABLE [sync].[worker_leases] (
        [lease_name] nvarchar(100) NOT NULL,
        [owner_id] nvarchar(150) NOT NULL,
        [acquired_at] datetime2(3) NOT NULL,
        [expires_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        CONSTRAINT [PK_worker_leases] PRIMARY KEY ([lease_name]),
        CONSTRAINT [CK_worker_leases_dates] CHECK ([expires_at] > [acquired_at])
    );
END;

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '002')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('002', N'Control de sincronizacion, eventos, cuarentena y leases');

COMMIT TRANSACTION;
GO

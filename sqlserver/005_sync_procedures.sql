/*
  IvMET SQL Server - 005
  Procedimientos de control para el worker DataMET <-> Supabase -> SQL IvMET.

  La aplicacion de un evento de outbox debe ejecutarse en una sola transaccion:
  1. upsert/delete logico de la tabla mirror correspondiente;
  2. EXEC sync.record_applied_event;
  3. COMMIT.
*/

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'sync.applied_events', N'U') IS NULL
    THROW 53500, 'Falta el control de sincronizacion. Ejecute 002_sync_control.sql.', 1;
GO

CREATE OR ALTER PROCEDURE [sync].[try_acquire_lease]
    @lease_name nvarchar(100),
    @owner_id nvarchar(150),
    @duration_seconds int = 120,
    @acquired bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@lease_name)), N'') IS NULL
        THROW 53501, 'lease_name es obligatorio.', 1;
    IF NULLIF(LTRIM(RTRIM(@owner_id)), N'') IS NULL
        THROW 53502, 'owner_id es obligatorio.', 1;
    IF @duration_seconds NOT BETWEEN 15 AND 3600
        THROW 53503, 'duration_seconds debe estar entre 15 y 3600.', 1;

    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @expires_at datetime2(3) = DATEADD(SECOND, @duration_seconds, @now);
    SET @acquired = 0;

    BEGIN TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM [sync].[worker_leases] WITH (UPDLOCK, HOLDLOCK)
        WHERE [lease_name] = @lease_name
    )
    BEGIN
        UPDATE [sync].[worker_leases]
        SET [owner_id] = @owner_id,
            [acquired_at] = @now,
            [expires_at] = @expires_at,
            [updated_at] = @now
        WHERE [lease_name] = @lease_name
          AND ([owner_id] = @owner_id OR [expires_at] <= @now);

        IF @@ROWCOUNT = 1 SET @acquired = 1;
    END
    ELSE
    BEGIN
        INSERT INTO [sync].[worker_leases]
            ([lease_name], [owner_id], [acquired_at], [expires_at], [updated_at])
        VALUES
            (@lease_name, @owner_id, @now, @expires_at, @now);

        SET @acquired = 1;
    END;

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [sync].[renew_lease]
    @lease_name nvarchar(100),
    @owner_id nvarchar(150),
    @duration_seconds int = 120
AS
BEGIN
    SET NOCOUNT ON;

    IF @duration_seconds NOT BETWEEN 15 AND 3600
        THROW 53504, 'duration_seconds debe estar entre 15 y 3600.', 1;

    DECLARE @now datetime2(3) = SYSUTCDATETIME();

    UPDATE [sync].[worker_leases]
    SET [expires_at] = DATEADD(SECOND, @duration_seconds, @now),
        [updated_at] = @now
    WHERE [lease_name] = @lease_name
      AND [owner_id] = @owner_id
      AND [expires_at] > @now;

    IF @@ROWCOUNT <> 1
        THROW 53505, 'El lease no existe, vencio o pertenece a otro worker.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [sync].[release_lease]
    @lease_name nvarchar(100),
    @owner_id nvarchar(150)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM [sync].[worker_leases]
    WHERE [lease_name] = @lease_name
      AND [owner_id] = @owner_id;
END;
GO

CREATE OR ALTER PROCEDURE [sync].[begin_run]
    @direction varchar(30),
    @worker_id nvarchar(150),
    @metadata_json nvarchar(max) = NULL,
    @run_id uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @direction NOT IN ('DATAMET_TO_SUPABASE', 'SUPABASE_TO_SQL_IVMET')
        THROW 53506, 'Direccion de sincronizacion invalida.', 1;
    IF NULLIF(LTRIM(RTRIM(@worker_id)), N'') IS NULL
        THROW 53507, 'worker_id es obligatorio.', 1;
    IF @metadata_json IS NOT NULL AND ISJSON(@metadata_json) <> 1
        THROW 53508, 'metadata_json no es JSON valido.', 1;

    SET @run_id = NEWID();

    INSERT INTO [sync].[runs]
        ([run_id], [direction], [worker_id], [status], [metadata_json])
    VALUES
        (@run_id, @direction, @worker_id, 'RUNNING', @metadata_json);
END;
GO

CREATE OR ALTER PROCEDURE [sync].[finish_run]
    @run_id uniqueidentifier,
    @status varchar(20),
    @scanned_count int,
    @accepted_count int,
    @unchanged_count int,
    @rejected_count int,
    @error nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @status NOT IN ('SUCCEEDED', 'PARTIAL', 'FAILED')
        THROW 53509, 'Estado final de ejecucion invalido.', 1;
    IF @scanned_count < 0 OR @accepted_count < 0
       OR @unchanged_count < 0 OR @rejected_count < 0
        THROW 53510, 'Los contadores no pueden ser negativos.', 1;
    IF @accepted_count + @unchanged_count + @rejected_count > @scanned_count
        THROW 53511, 'Los contadores procesados superan scanned_count.', 1;

    UPDATE [sync].[runs]
    SET [status] = @status,
        [finished_at] = SYSUTCDATETIME(),
        [scanned_count] = @scanned_count,
        [accepted_count] = @accepted_count,
        [unchanged_count] = @unchanged_count,
        [rejected_count] = @rejected_count,
        [error] = @error
    WHERE [run_id] = @run_id
      AND [status] = 'RUNNING';

    IF @@ROWCOUNT <> 1
        THROW 53512, 'La ejecucion no existe o ya fue finalizada.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [sync].[record_applied_event]
    @event_id uniqueidentifier,
    @event_sequence bigint,
    @aggregate_type nvarchar(128),
    @aggregate_key_json nvarchar(1000),
    @operation char(1),
    @payload_hash char(64),
    @source_created_at datetime2(3),
    @worker_id nvarchar(150),
    @worker_name nvarchar(100) = N'supabase_to_sql_ivmet',
    @already_applied bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @event_sequence <= 0
        THROW 53513, 'event_sequence debe ser positivo.', 1;
    IF @operation NOT IN ('I', 'U', 'D')
        THROW 53514, 'Operacion de outbox invalida.', 1;
    IF ISJSON(@aggregate_key_json) <> 1
        THROW 53515, 'aggregate_key_json no es JSON valido.', 1;
    IF LEN(@payload_hash) <> 64 OR @payload_hash LIKE '%[^0-9a-f]%'
        THROW 53516, 'payload_hash debe ser SHA-256 hexadecimal en minusculas.', 1;

    SET @already_applied = 0;

    IF EXISTS (SELECT 1 FROM [sync].[applied_events] WHERE [event_id] = @event_id)
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM [sync].[applied_events]
            WHERE [event_id] = @event_id
              AND [event_sequence] = @event_sequence
              AND [aggregate_type] = @aggregate_type
              AND [aggregate_key_json] = @aggregate_key_json
              AND [operation] = @operation
              AND [payload_hash] = @payload_hash
        )
            THROW 53517, 'El event_id ya existe con contenido diferente.', 1;

        SET @already_applied = 1;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM [sync].[applied_events]
        WHERE [event_sequence] = @event_sequence
          AND [event_id] <> @event_id
    )
        THROW 53518, 'event_sequence ya pertenece a otro evento.', 1;

    INSERT INTO [sync].[applied_events]
        ([event_id], [event_sequence], [aggregate_type], [aggregate_key_json],
         [operation], [payload_hash], [source_created_at], [worker_id])
    VALUES
        (@event_id, @event_sequence, @aggregate_type, @aggregate_key_json,
         @operation, @payload_hash, @source_created_at, @worker_id);

    UPDATE [sync].[worker_state] WITH (UPDLOCK, HOLDLOCK)
    SET [checkpoint_sequence] = CASE
            WHEN [checkpoint_sequence] < @event_sequence THEN @event_sequence
            ELSE [checkpoint_sequence]
        END,
        [last_success_at] = SYSUTCDATETIME(),
        [last_error] = NULL,
        [updated_at] = SYSUTCDATETIME()
    WHERE [worker_name] = @worker_name;

    IF @@ROWCOUNT = 0
        INSERT INTO [sync].[worker_state]
            ([worker_name], [checkpoint_sequence], [last_success_at], [updated_at])
        VALUES
            (@worker_name, @event_sequence, SYSUTCDATETIME(), SYSUTCDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [sync].[record_failure]
    @run_id uniqueidentifier = NULL,
    @event_id uniqueidentifier = NULL,
    @event_sequence bigint = NULL,
    @aggregate_type nvarchar(128) = NULL,
    @aggregate_key_json nvarchar(1000) = NULL,
    @payload_json nvarchar(max) = NULL,
    @error_code nvarchar(100),
    @error_detail nvarchar(4000),
    @attempts int = 1,
    @next_retry_at datetime2(3) = NULL,
    @failure_id uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @aggregate_key_json IS NOT NULL AND ISJSON(@aggregate_key_json) <> 1
        THROW 53519, 'aggregate_key_json no es JSON valido.', 1;
    IF @payload_json IS NOT NULL AND ISJSON(@payload_json) <> 1
        THROW 53520, 'payload_json no es JSON valido.', 1;
    IF @attempts <= 0
        THROW 53521, 'attempts debe ser positivo.', 1;

    SET @failure_id = NEWID();

    INSERT INTO [sync].[failures]
        ([failure_id], [run_id], [event_id], [event_sequence], [aggregate_type],
         [aggregate_key_json], [payload_json], [error_code], [error_detail],
         [attempts], [status], [next_retry_at])
    VALUES
        (@failure_id, @run_id, @event_id, @event_sequence, @aggregate_type,
         @aggregate_key_json, @payload_json, @error_code, @error_detail,
         @attempts, 'OPEN', @next_retry_at);
END;
GO

CREATE OR ALTER PROCEDURE [sync].[mark_worker_error]
    @worker_name nvarchar(100),
    @error nvarchar(4000)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [sync].[worker_state]
    SET [last_error_at] = SYSUTCDATETIME(),
        [last_error] = @error,
        [updated_at] = SYSUTCDATETIME()
    WHERE [worker_name] = @worker_name;

    IF @@ROWCOUNT = 0
        INSERT INTO [sync].[worker_state]
            ([worker_name], [checkpoint_sequence], [last_error_at], [last_error], [updated_at])
        VALUES
            (@worker_name, 0, SYSUTCDATETIME(), @error, SYSUTCDATETIME());
END;
GO

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '005')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('005', N'Procedimientos de control e idempotencia del worker');
GO

/*
  IvMET SQL Server - 008
  Validacion de solo lectura posterior al despliegue.
  Debe finalizar sin lanzar THROW y devolver cuatro juegos de resultados.
*/

USE [IvMET];
GO

SET NOCOUNT ON;

DECLARE @expected_versions TABLE ([version] varchar(20) PRIMARY KEY);
INSERT INTO @expected_versions ([version])
VALUES ('001'), ('002'), ('003'), ('004'), ('005'), ('006');

IF EXISTS (
    SELECT 1
    FROM @expected_versions expected
    LEFT JOIN [dbo].[schema_versions] actual
        ON actual.[version] = expected.[version]
    WHERE actual.[version] IS NULL
)
    THROW 53800, 'Faltan scripts de version 001-006.', 1;

DECLARE @expected_tables TABLE (
    [schema_name] sysname NOT NULL,
    [table_name] sysname NOT NULL,
    PRIMARY KEY ([schema_name], [table_name])
);

INSERT INTO @expected_tables ([schema_name], [table_name])
VALUES
    (N'sync', N'applied_events'),
    (N'sync', N'worker_state'),
    (N'sync', N'runs'),
    (N'sync', N'failures'),
    (N'sync', N'datamet_entity_state'),
    (N'sync', N'catalog_quarantine'),
    (N'sync', N'worker_leases'),
    (N'mirror', N'clientes'),
    (N'mirror', N'plantas'),
    (N'mirror', N'equipos'),
    (N'mirror', N'equipo_rangos'),
    (N'mirror', N'perfiles'),
    (N'mirror', N'usuario_plantas'),
    (N'mirror', N'planes_comerciales'),
    (N'mirror', N'precios_plan'),
    (N'mirror', N'contratos'),
    (N'mirror', N'suscripciones'),
    (N'mirror', N'facturas'),
    (N'mirror', N'pagos'),
    (N'mirror', N'suscripcion_cupos'),
    (N'mirror', N'licencias_usuario'),
    (N'mirror', N'eventos_licencia'),
    (N'mirror', N'areas'),
    (N'mirror', N'equipos_ivmet'),
    (N'mirror', N'patrones'),
    (N'mirror', N'patron_plantas'),
    (N'mirror', N'patron_certificados'),
    (N'mirror', N'planes'),
    (N'mirror', N'plan_versiones'),
    (N'mirror', N'plan_pruebas'),
    (N'mirror', N'plan_puntos'),
    (N'mirror', N'equipo_planes'),
    (N'mirror', N'verificacion_borradores'),
    (N'mirror', N'verificaciones'),
    (N'mirror', N'verificacion_patrones'),
    (N'mirror', N'pruebas'),
    (N'mirror', N'lecturas'),
    (N'mirror', N'alertas'),
    (N'mirror', N'auditoria');

IF EXISTS (
    SELECT 1
    FROM @expected_tables expected
    LEFT JOIN sys.schemas s ON s.[name] = expected.[schema_name]
    LEFT JOIN sys.tables t
        ON t.[schema_id] = s.[schema_id]
       AND t.[name] = expected.[table_name]
    WHERE t.[object_id] IS NULL
)
    THROW 53801, 'Faltan una o mas tablas requeridas en mirror/sync.', 1;

DECLARE @expected_procedures TABLE ([procedure_name] sysname PRIMARY KEY);
INSERT INTO @expected_procedures ([procedure_name])
VALUES
    (N'try_acquire_lease'),
    (N'renew_lease'),
    (N'release_lease'),
    (N'begin_run'),
    (N'finish_run'),
    (N'record_applied_event'),
    (N'record_failure'),
    (N'mark_worker_error');

IF EXISTS (
    SELECT 1
    FROM @expected_procedures expected
    LEFT JOIN sys.schemas s ON s.[name] = N'sync'
    LEFT JOIN sys.procedures p
        ON p.[schema_id] = s.[schema_id]
       AND p.[name] = expected.[procedure_name]
    WHERE p.[object_id] IS NULL
)
    THROW 53802, 'Faltan procedimientos requeridos en sync.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys fk
    INNER JOIN sys.tables t ON t.[object_id] = fk.[parent_object_id]
    INNER JOIN sys.schemas s ON s.[schema_id] = t.[schema_id]
    WHERE s.[name] IN (N'mirror', N'sync')
      AND (fk.[is_disabled] = 1 OR fk.[is_not_trusted] = 1)
)
    THROW 53803, 'Existe una clave foranea deshabilitada o no confiable.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.check_constraints ck
    INNER JOIN sys.tables t ON t.[object_id] = ck.[parent_object_id]
    INNER JOIN sys.schemas s ON s.[schema_id] = t.[schema_id]
    WHERE s.[name] IN (N'mirror', N'sync')
      AND (ck.[is_disabled] = 1 OR ck.[is_not_trusted] = 1)
)
    THROW 53804, 'Existe una restriccion CHECK deshabilitada o no confiable.', 1;

IF DATABASE_PRINCIPAL_ID(N'IvMETWorker') IS NULL
    THROW 53805, 'No existe el usuario IvMETWorker dentro de IvMET.', 1;

DECLARE @can_select_mirror int;
DECLARE @can_insert_mirror int;
DECLARE @can_delete_verification int;
DECLARE @can_alter_mirror int;

EXECUTE AS USER = N'IvMETWorker';
SELECT @can_select_mirror = HAS_PERMS_BY_NAME(N'mirror.clientes', N'OBJECT', N'SELECT');
SELECT @can_insert_mirror = HAS_PERMS_BY_NAME(N'mirror.clientes', N'OBJECT', N'INSERT');
SELECT @can_delete_verification = HAS_PERMS_BY_NAME(N'mirror.verificaciones', N'OBJECT', N'DELETE');
SELECT @can_alter_mirror = HAS_PERMS_BY_NAME(N'mirror', N'SCHEMA', N'ALTER');
REVERT;

IF @can_select_mirror <> 1 OR @can_insert_mirror <> 1
    THROW 53806, 'IvMETWorker no tiene los permisos de proyeccion esperados.', 1;
IF @can_delete_verification = 1
    THROW 53807, 'IvMETWorker no debe poder eliminar verificaciones.', 1;
IF @can_alter_mirror = 1
    THROW 53808, 'IvMETWorker no debe poder alterar el esquema mirror.', 1;

SELECT [version], [description], [applied_at], [applied_by]
FROM [dbo].[schema_versions]
ORDER BY [version];

SELECT
    s.[name] AS [schema_name],
    COUNT_BIG(*) AS [table_count]
FROM sys.tables t
INNER JOIN sys.schemas s ON s.[schema_id] = t.[schema_id]
WHERE s.[name] IN (N'mirror', N'sync')
GROUP BY s.[name]
ORDER BY s.[name];

SELECT
    SUM(CASE WHEN s.[name] = N'mirror' THEN 1 ELSE 0 END) AS [mirror_foreign_keys],
    SUM(CASE WHEN s.[name] = N'sync' THEN 1 ELSE 0 END) AS [sync_foreign_keys],
    SUM(CASE WHEN fk.[is_disabled] = 1 OR fk.[is_not_trusted] = 1 THEN 1 ELSE 0 END)
        AS [invalid_foreign_keys]
FROM sys.foreign_keys fk
INNER JOIN sys.tables t ON t.[object_id] = fk.[parent_object_id]
INNER JOIN sys.schemas s ON s.[schema_id] = t.[schema_id]
WHERE s.[name] IN (N'mirror', N'sync');

SELECT
    @can_select_mirror AS [worker_can_select_mirror],
    @can_insert_mirror AS [worker_can_insert_mirror],
    @can_delete_verification AS [worker_can_delete_verification],
    @can_alter_mirror AS [worker_can_alter_mirror],
    N'VALIDACION_IVMET_OK' AS [result];
GO

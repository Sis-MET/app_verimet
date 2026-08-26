/*
  IvMET SQL Server - 007
  Unico cambio permitido en DataMET: usuario y permisos SELECT para el worker.
  No crea, modifica ni elimina tablas o registros comerciales de DataMET.
*/

USE [DataMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SUSER_ID(N'IvMETWorker') IS NULL
    THROW 53700, 'No existe el login de servidor IvMETWorker.', 1;

IF OBJECT_ID(N'dbo.DATA_CLIENTES', N'U') IS NULL
    THROW 53701, 'No existe dbo.DATA_CLIENTES en DataMET.', 1;
IF OBJECT_ID(N'dbo.DATA_PLANTAS', N'U') IS NULL
    THROW 53702, 'No existe dbo.DATA_PLANTAS en DataMET.', 1;
IF OBJECT_ID(N'dbo.DATA_EQUIPOS', N'U') IS NULL
    THROW 53703, 'No existe dbo.DATA_EQUIPOS en DataMET.', 1;
IF OBJECT_ID(N'dbo.DATA_EQUIPOS_BALANZAS', N'U') IS NULL
    THROW 53704, 'No existe dbo.DATA_EQUIPOS_BALANZAS en DataMET.', 1;

BEGIN TRANSACTION;

IF DATABASE_PRINCIPAL_ID(N'IvMETWorker') IS NULL
    CREATE USER [IvMETWorker] FOR LOGIN [IvMETWorker] WITH DEFAULT_SCHEMA = [dbo];

GRANT CONNECT TO [IvMETWorker];
GRANT SELECT ON OBJECT::[dbo].[DATA_CLIENTES] TO [IvMETWorker];
GRANT SELECT ON OBJECT::[dbo].[DATA_PLANTAS] TO [IvMETWorker];
GRANT SELECT ON OBJECT::[dbo].[DATA_EQUIPOS] TO [IvMETWorker];
GRANT SELECT ON OBJECT::[dbo].[DATA_EQUIPOS_BALANZAS] TO [IvMETWorker];

DENY INSERT, UPDATE, DELETE, ALTER, CONTROL
    ON OBJECT::[dbo].[DATA_CLIENTES] TO [IvMETWorker];
DENY INSERT, UPDATE, DELETE, ALTER, CONTROL
    ON OBJECT::[dbo].[DATA_PLANTAS] TO [IvMETWorker];
DENY INSERT, UPDATE, DELETE, ALTER, CONTROL
    ON OBJECT::[dbo].[DATA_EQUIPOS] TO [IvMETWorker];
DENY INSERT, UPDATE, DELETE, ALTER, CONTROL
    ON OBJECT::[dbo].[DATA_EQUIPOS_BALANZAS] TO [IvMETWorker];

COMMIT TRANSACTION;
GO

EXECUTE AS USER = N'IvMETWorker';

SELECT
    OBJECT_SCHEMA_NAME(p.[major_id]) AS [schema_name],
    OBJECT_NAME(p.[major_id]) AS [table_name],
    p.[permission_name],
    p.[state_desc]
FROM sys.database_permissions p
WHERE p.[grantee_principal_id] = DATABASE_PRINCIPAL_ID(N'IvMETWorker')
  AND p.[major_id] IN (
      OBJECT_ID(N'dbo.DATA_CLIENTES'),
      OBJECT_ID(N'dbo.DATA_PLANTAS'),
      OBJECT_ID(N'dbo.DATA_EQUIPOS'),
      OBJECT_ID(N'dbo.DATA_EQUIPOS_BALANZAS')
  )
ORDER BY [table_name], p.[permission_name];

REVERT;
GO

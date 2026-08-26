/*
  IvMET SQL Server - 006
  Principio de minimo privilegio dentro de la base autonoma IvMET.

  Prerrequisito: un DBA debe crear el login de servidor [IvMETWorker] con una
  contrasena generada fuera del repositorio. Este archivo nunca crea secretos.
*/

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SUSER_ID(N'IvMETWorker') IS NULL
    THROW 53600, 'No existe el login IvMETWorker. Creelo en master con una contrasena segura antes de ejecutar este script.', 1;

BEGIN TRANSACTION;

IF DATABASE_PRINCIPAL_ID(N'IvMETWorker') IS NULL
    CREATE USER [IvMETWorker] FOR LOGIN [IvMETWorker] WITH DEFAULT_SCHEMA = [sync];

IF DATABASE_PRINCIPAL_ID(N'ivmet_worker_role') IS NULL
    CREATE ROLE [ivmet_worker_role] AUTHORIZATION [dbo];

IF DATABASE_PRINCIPAL_ID(N'ivmet_readonly_role') IS NULL
    CREATE ROLE [ivmet_readonly_role] AUTHORIZATION [dbo];

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals role_principal
        ON role_principal.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals member_principal
        ON member_principal.principal_id = drm.member_principal_id
    WHERE role_principal.[name] = N'ivmet_worker_role'
      AND member_principal.[name] = N'IvMETWorker'
)
    ALTER ROLE [ivmet_worker_role] ADD MEMBER [IvMETWorker];

GRANT CONNECT TO [IvMETWorker];
GRANT SELECT ON [dbo].[schema_versions] TO [ivmet_worker_role];

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[mirror] TO [ivmet_worker_role];

/* La evidencia aceptada no se borra; las anulaciones son UPDATE de verificaciones. */
DENY DELETE ON OBJECT::[mirror].[verificaciones] TO [ivmet_worker_role];
DENY UPDATE, DELETE ON OBJECT::[mirror].[verificacion_patrones] TO [ivmet_worker_role];
DENY UPDATE, DELETE ON OBJECT::[mirror].[pruebas] TO [ivmet_worker_role];
DENY UPDATE, DELETE ON OBJECT::[mirror].[lecturas] TO [ivmet_worker_role];
DENY UPDATE, DELETE ON OBJECT::[mirror].[auditoria] TO [ivmet_worker_role];

GRANT SELECT ON SCHEMA::[sync] TO [ivmet_worker_role];
GRANT INSERT, UPDATE ON OBJECT::[sync].[datamet_entity_state] TO [ivmet_worker_role];
GRANT INSERT, UPDATE ON OBJECT::[sync].[catalog_quarantine] TO [ivmet_worker_role];
GRANT EXECUTE ON SCHEMA::[sync] TO [ivmet_worker_role];

/* Los eventos aplicados y checkpoints se escriben exclusivamente por procedimientos. */
DENY INSERT, UPDATE, DELETE ON OBJECT::[sync].[applied_events] TO [ivmet_worker_role];
DENY INSERT, UPDATE, DELETE ON OBJECT::[sync].[worker_state] TO [ivmet_worker_role];
DENY INSERT, UPDATE, DELETE ON OBJECT::[sync].[runs] TO [ivmet_worker_role];
DENY INSERT, UPDATE, DELETE ON OBJECT::[sync].[failures] TO [ivmet_worker_role];
DENY INSERT, UPDATE, DELETE ON OBJECT::[sync].[worker_leases] TO [ivmet_worker_role];

DENY ALTER, TAKE OWNERSHIP ON SCHEMA::[mirror] TO [ivmet_worker_role];
DENY ALTER, TAKE OWNERSHIP ON SCHEMA::[sync] TO [ivmet_worker_role];

GRANT CONNECT TO [ivmet_readonly_role];
GRANT SELECT ON [dbo].[schema_versions] TO [ivmet_readonly_role];
GRANT SELECT ON SCHEMA::[mirror] TO [ivmet_readonly_role];
GRANT SELECT ON SCHEMA::[sync] TO [ivmet_readonly_role];

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '006')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('006', N'Roles y permisos de minimo privilegio para el worker');

COMMIT TRANSACTION;
GO

SELECT
    dp.[name] AS [principal],
    role_principal.[name] AS [database_role]
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm
    ON drm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals role_principal
    ON role_principal.principal_id = drm.role_principal_id
WHERE dp.[name] IN (N'IvMETWorker', N'ivmet_worker_role', N'ivmet_readonly_role')
ORDER BY dp.[name], role_principal.[name];
GO

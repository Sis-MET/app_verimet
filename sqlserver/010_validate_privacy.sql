/* Solo diagnóstico: no consulta ni devuelve resultados de pruebas. Ejecutar como DBA. */
USE [IvMET];
GO
SET NOCOUNT ON;
IF NOT EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='009')
    THROW 53921,'Falta 009_shared_cases_privacy.sql.',1;
EXECUTE AS USER='IvMETWorker';
SELECT HAS_PERMS_BY_NAME('mirror.verificaciones','OBJECT','SELECT') AS private_read,
       HAS_PERMS_BY_NAME('mirror.verificaciones','OBJECT','INSERT') AS private_write,
       HAS_PERMS_BY_NAME('mirror.auditoria','OBJECT','SELECT') AS private_audit_read,
       HAS_PERMS_BY_NAME('mirror.casos_compartidos','OBJECT','INSERT') AS shared_case_write,
       HAS_PERMS_BY_NAME('mirror.casos_compartidos','OBJECT','DELETE') AS shared_case_delete;
REVERT;
GO

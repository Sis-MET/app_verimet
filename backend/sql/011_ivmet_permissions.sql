/* Permisos minimos del usuario SQL que ejecuta servicemet-api. */

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'ivmet') IS NULL
    THROW 52100, 'No existe el esquema ivmet; ejecute 010_ivmet_schema.sql.', 1;
IF USER_ID(N'ServiceMET') IS NULL
    THROW 52101, 'No existe el usuario de base de datos ServiceMET.', 1;

BEGIN TRANSACTION;

GRANT SELECT, INSERT, UPDATE ON SCHEMA::[ivmet] TO [ServiceMET];
DENY DELETE ON SCHEMA::[ivmet] TO [ServiceMET];
DENY ALTER ON SCHEMA::[ivmet] TO [ServiceMET];
DENY UPDATE ON OBJECT::[ivmet].[auditoria] TO [ServiceMET];
DENY UPDATE ON OBJECT::[ivmet].[pruebas] TO [ServiceMET];
DENY UPDATE ON OBJECT::[ivmet].[lecturas] TO [ServiceMET];
DENY UPDATE ON OBJECT::[ivmet].[verificacion_patrones] TO [ServiceMET];

GRANT SELECT ON OBJECT::[dbo].[DATA_CLIENTES] TO [ServiceMET];
GRANT SELECT ON OBJECT::[dbo].[DATA_PLANTAS] TO [ServiceMET];
GRANT SELECT ON OBJECT::[dbo].[DATA_EQUIPOS] TO [ServiceMET];
GRANT SELECT ON OBJECT::[dbo].[DATA_EQUIPOS_BALANZAS] TO [ServiceMET];

COMMIT TRANSACTION;

EXECUTE AS USER = N'ServiceMET';
SELECT
    HAS_PERMS_BY_NAME(N'ivmet', N'SCHEMA', N'SELECT') AS [puede_leer],
    HAS_PERMS_BY_NAME(N'ivmet', N'SCHEMA', N'INSERT') AS [puede_insertar],
    HAS_PERMS_BY_NAME(N'ivmet', N'SCHEMA', N'UPDATE') AS [puede_actualizar],
    HAS_PERMS_BY_NAME(N'ivmet', N'SCHEMA', N'DELETE') AS [puede_eliminar];
REVERT;

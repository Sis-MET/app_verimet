/* Ejecutar como DBA en IvMET con ivmet-worker detenido.
   No modifica DataMET ni elimina información histórica. */
USE [IvMET];
GO
SET XACT_ABORT ON;
SET NOCOUNT ON;
IF NOT EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='009')
    THROW 53930, 'Ejecute primero 009_shared_cases_privacy.sql.', 1;
BEGIN TRANSACTION;
IF OBJECT_ID(N'mirror.actualizaciones_compartidas',N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[actualizaciones_compartidas] (
        [id] uniqueidentifier NOT NULL PRIMARY KEY,
        [equipo_id] uniqueidentifier NOT NULL REFERENCES mirror.equipos(id),
        [cliente_id] uniqueidentifier NOT NULL REFERENCES mirror.clientes(id),
        [planta_id] uniqueidentifier NOT NULL REFERENCES mirror.plantas(id),
        [autorizado_por] uniqueidentifier NOT NULL,
        [autorizado_at] datetime2(3) NOT NULL,
        [consentimiento_version] nvarchar(60) NOT NULL,
        [snapshot_json] nvarchar(max) NULL CHECK(snapshot_json IS NULL OR ISJSON(snapshot_json)=1),
        [snapshot_hash] varchar(64) NOT NULL,
        [mensaje] nvarchar(2000) NOT NULL,
        [visibilidad] varchar(20) NOT NULL CHECK(visibilidad IN ('SHARED','WITHDRAWN')),
        [retirado_at] datetime2(3) NULL,
        [estado] varchar(30) NOT NULL CHECK(estado IN ('NEW','REVIEWED')),
        [comentario] nvarchar(2000) NULL,
        [revisado_por] nvarchar(150) NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
    );
    CREATE INDEX actualizaciones_inbox_idx ON mirror.actualizaciones_compartidas(visibilidad,estado,autorizado_at);
    CREATE INDEX actualizaciones_scope_idx ON mirror.actualizaciones_compartidas(cliente_id,planta_id,equipo_id);
END;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.areas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.equipos_ivmet TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.patrones TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.patron_plantas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.patron_certificados TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.planes TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.plan_versiones TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.plan_pruebas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.plan_puntos TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.equipo_planes TO ivmet_worker_role,ivmet_readonly_role;
DENY DELETE ON OBJECT::mirror.actualizaciones_compartidas TO ivmet_worker_role;
DENY SELECT ON OBJECT::mirror.actualizaciones_compartidas TO ivmet_readonly_role;
IF NOT EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='011')
    INSERT INTO dbo.schema_versions(version,description) VALUES('011',N'Configuración privada del cliente y actualizaciones autorizadas');
COMMIT;
GO
CREATE OR ALTER VIEW mirror.actualizaciones_visibles AS
SELECT id,equipo_id,cliente_id,planta_id,autorizado_at,consentimiento_version,
  snapshot_hash,snapshot_json,mensaje,estado,comentario,revisado_por,updated_at
FROM mirror.actualizaciones_compartidas WHERE visibilidad='SHARED';
GO
GRANT SELECT ON OBJECT::mirror.actualizaciones_visibles TO ivmet_readonly_role;
GO

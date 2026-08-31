/* Ejecutar como DBA en IvMET, con ivmet-worker detenido. No modifica DataMET.
   Conserva la evidencia antigua; revoca su acceso y escritura operativos. */
USE [IvMET];
GO
SET XACT_ABORT ON;
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM dbo.schema_versions WHERE version='006')
    THROW 53920, 'Se requiere el esquema y permisos 001-006.', 1;
BEGIN TRANSACTION;
IF COL_LENGTH('mirror.plan_versiones','published_by_external') IS NULL
    ALTER TABLE [mirror].[plan_versiones] ADD [published_by_external] nvarchar(150) NULL;
IF COL_LENGTH('mirror.plan_versiones','retired_by_external') IS NULL
    ALTER TABLE [mirror].[plan_versiones] ADD [retired_by_external] nvarchar(150) NULL;
IF COL_LENGTH('mirror.plan_versiones','draft_revision') IS NULL
    ALTER TABLE [mirror].[plan_versiones] ADD [draft_revision] bigint NOT NULL CONSTRAINT DF_plan_draft_revision DEFAULT 1;
IF OBJECT_ID(N'mirror.casos_compartidos',N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[casos_compartidos] (
        [id] uniqueidentifier NOT NULL PRIMARY KEY,
        [codigo] nvarchar(40) NOT NULL UNIQUE,
        [alerta_id] uniqueidentifier NOT NULL,
        [verificacion_id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL REFERENCES mirror.clientes(id),
        [planta_id] uniqueidentifier NOT NULL REFERENCES mirror.plantas(id),
        [equipo_id] uniqueidentifier NOT NULL REFERENCES mirror.equipos(id),
        [autorizado_por] uniqueidentifier NOT NULL,
        [autorizado_at] datetime2(3) NOT NULL,
        [consentimiento_version] nvarchar(60) NOT NULL,
        [snapshot_hash] varchar(64) NOT NULL,
        [snapshot_json] nvarchar(max) NULL CHECK (snapshot_json IS NULL OR ISJSON(snapshot_json)=1),
        [eventos_json] nvarchar(max) NOT NULL CHECK (ISJSON(eventos_json)=1),
        [mensaje] nvarchar(2000) NOT NULL,
        [visibilidad] varchar(20) NOT NULL CHECK (visibilidad IN ('SHARED','WITHDRAWN')),
        [retirado_at] datetime2(3) NULL,
        [retirado_por] uniqueidentifier NULL,
        [motivo_retiro] nvarchar(2000) NULL,
        [estado] varchar(30) NOT NULL,
        [responsable] nvarchar(150) NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
    );
    CREATE INDEX casos_visibilidad_idx ON mirror.casos_compartidos(visibilidad,estado,created_at);
    CREATE INDEX casos_cliente_idx ON mirror.casos_compartidos(cliente_id,planta_id);
END;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.verificacion_borradores TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.verificaciones TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.verificacion_patrones TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.pruebas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.lecturas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.alertas TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT,INSERT,UPDATE,DELETE ON OBJECT::mirror.auditoria TO ivmet_worker_role,ivmet_readonly_role;
DENY SELECT ON OBJECT::sync.failures TO ivmet_worker_role,ivmet_readonly_role;
DENY DELETE ON OBJECT::mirror.casos_compartidos TO ivmet_worker_role;
DENY SELECT ON OBJECT::mirror.casos_compartidos TO ivmet_readonly_role;
IF NOT EXISTS(SELECT 1 FROM dbo.schema_versions WHERE version='009')
  INSERT INTO dbo.schema_versions(version,description) VALUES('009',N'Expedientes autorizados y aislamiento de evidencia privada');
COMMIT;
GO
CREATE OR ALTER VIEW mirror.casos_visibles AS
SELECT id,codigo,cliente_id,planta_id,equipo_id,autorizado_at,consentimiento_version,
  snapshot_hash,snapshot_json,eventos_json,mensaje,estado,responsable,created_at,updated_at
FROM mirror.casos_compartidos WHERE visibilidad='SHARED';
GO
GRANT SELECT ON OBJECT::mirror.casos_visibles TO ivmet_readonly_role;
GO

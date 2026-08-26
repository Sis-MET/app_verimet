/*
  IvMET SQL Server - 004
  Proyecciones tipadas de configuracion y evidencia metrologica de Supabase.
  No contiene contraseñas, refresh tokens ni secretos de Supabase Auth.
*/

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'mirror.equipos', N'U') IS NULL
    THROW 53200, 'Falta el catalogo espejo. Ejecute 003_mirror_catalog_commercial.sql.', 1;
GO

BEGIN TRANSACTION;

IF OBJECT_ID(N'mirror.areas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[areas] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [nombre] nvarchar(150) NOT NULL,
        [nombre_normalizado] nvarchar(150) NOT NULL,
        [activa] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_areas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_areas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_areas_nombre] UNIQUE ([cliente_id], [planta_id], [nombre_normalizado]),
        CONSTRAINT [FK_mirror_areas_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [FK_mirror_areas_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id])
    );
END;

IF OBJECT_ID(N'mirror.equipos_ivmet', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[equipos_ivmet] (
        [equipo_id] uniqueidentifier NOT NULL,
        [area_id] uniqueidentifier NULL,
        [habilitado] bit NOT NULL,
        [estado_configuracion] varchar(20) NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_equipos_ivmet_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_equipos_ivmet] PRIMARY KEY ([equipo_id]),
        CONSTRAINT [FK_mirror_equipos_ivmet_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [FK_mirror_equipos_ivmet_area] FOREIGN KEY ([area_id])
            REFERENCES [mirror].[areas] ([id]),
        CONSTRAINT [CK_mirror_equipos_ivmet_estado] CHECK (
            [estado_configuracion] IN ('PENDING', 'READY', 'SUSPENDED')
        )
    );
END;

IF OBJECT_ID(N'mirror.patrones', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[patrones] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [codigo] nvarchar(100) NOT NULL,
        [descripcion] nvarchar(300) NOT NULL,
        [tipo] nvarchar(50) NOT NULL,
        [clase] nvarchar(50) NULL,
        [unidad] nvarchar(20) NULL,
        [capacidad] decimal(19,9) NULL,
        [activo] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_patrones_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_patrones] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_patrones_codigo] UNIQUE ([cliente_id], [codigo]),
        CONSTRAINT [FK_mirror_patrones_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [CK_mirror_patrones_capacidad] CHECK ([capacidad] IS NULL OR [capacidad] > 0)
    );
END;

IF OBJECT_ID(N'mirror.patron_plantas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[patron_plantas] (
        [patron_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_patron_plantas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_patron_plantas] PRIMARY KEY ([patron_id], [planta_id]),
        CONSTRAINT [FK_mirror_patron_plantas_patron] FOREIGN KEY ([patron_id])
            REFERENCES [mirror].[patrones] ([id]),
        CONSTRAINT [FK_mirror_patron_plantas_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id])
    );
END;

IF OBJECT_ID(N'mirror.patron_certificados', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[patron_certificados] (
        [id] uniqueidentifier NOT NULL,
        [patron_id] uniqueidentifier NOT NULL,
        [numero] nvarchar(150) NOT NULL,
        [laboratorio] nvarchar(250) NOT NULL,
        [calibrado_el] date NOT NULL,
        [vence_el] date NOT NULL,
        [estado] varchar(20) NOT NULL,
        [archivo_path] nvarchar(1000) NULL,
        [archivo_hash] char(64) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_patron_certificados_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_patron_certificados] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_patron_certificados_numero] UNIQUE ([patron_id], [numero]),
        CONSTRAINT [FK_mirror_patron_certificados_patron] FOREIGN KEY ([patron_id])
            REFERENCES [mirror].[patrones] ([id]),
        CONSTRAINT [CK_mirror_patron_certificados_values] CHECK (
            [vence_el] >= [calibrado_el] AND [estado] IN ('ACTIVE', 'ANNULLED')
        )
    );
END;

IF OBJECT_ID(N'mirror.planes', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[planes] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NULL,
        [nombre] nvarchar(200) NOT NULL,
        [descripcion] nvarchar(max) NULL,
        [activo] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_planes_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_planes] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_planes_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id])
    );
    CREATE UNIQUE INDEX [UX_mirror_planes_global]
        ON [mirror].[planes] ([nombre]) WHERE [cliente_id] IS NULL;
    CREATE UNIQUE INDEX [UX_mirror_planes_cliente]
        ON [mirror].[planes] ([cliente_id], [nombre]) WHERE [cliente_id] IS NOT NULL;
END;

IF OBJECT_ID(N'mirror.plan_versiones', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[plan_versiones] (
        [id] uniqueidentifier NOT NULL,
        [plan_id] uniqueidentifier NOT NULL,
        [version] int NOT NULL,
        [estado] varchar(20) NOT NULL,
        [procedimiento_referencia] nvarchar(300) NULL,
        [notas] nvarchar(max) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [published_by] uniqueidentifier NULL,
        [published_at] datetime2(3) NULL,
        [retired_by] uniqueidentifier NULL,
        [retired_at] datetime2(3) NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_plan_versiones_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_plan_versiones] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_plan_versiones_numero] UNIQUE ([plan_id], [version]),
        CONSTRAINT [FK_mirror_plan_versiones_plan] FOREIGN KEY ([plan_id])
            REFERENCES [mirror].[planes] ([id]),
        CONSTRAINT [CK_mirror_plan_versiones_values] CHECK (
            [version] > 0 AND [estado] IN ('DRAFT', 'PUBLISHED', 'RETIRED')
        )
    );
END;

IF OBJECT_ID(N'mirror.plan_pruebas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[plan_pruebas] (
        [id] uniqueidentifier NOT NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [tipo] varchar(30) NOT NULL,
        [metodo_evaluacion] varchar(60) NOT NULL,
        [unidad] nvarchar(20) NOT NULL,
        [frecuencia_dias] int NOT NULL,
        [aviso_dias] int NOT NULL,
        [metadata_json] nvarchar(max) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_plan_pruebas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_plan_pruebas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_plan_pruebas_tipo] UNIQUE ([plan_version_id], [tipo]),
        CONSTRAINT [FK_mirror_plan_pruebas_version] FOREIGN KEY ([plan_version_id])
            REFERENCES [mirror].[plan_versiones] ([id]),
        CONSTRAINT [CK_mirror_plan_pruebas_values] CHECK (
            [tipo] IN ('eccentricity', 'repeatability', 'linearity')
            AND [metodo_evaluacion] IN ('absolute_error', 'range', 'sample_standard_deviation')
            AND [frecuencia_dias] > 0 AND [aviso_dias] >= 0
        ),
        CONSTRAINT [CK_mirror_plan_pruebas_json] CHECK (ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.plan_puntos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[plan_puntos] (
        [id] uniqueidentifier NOT NULL,
        [plan_prueba_id] uniqueidentifier NOT NULL,
        [grupo] int NOT NULL,
        [orden] int NOT NULL,
        [codigo] nvarchar(100) NOT NULL,
        [etiqueta] nvarchar(200) NOT NULL,
        [carga_nominal] decimal(19,9) NOT NULL,
        [tolerancia] decimal(19,9) NOT NULL,
        [posicion] nvarchar(100) NULL,
        [direccion] nvarchar(30) NULL,
        [metadata_json] nvarchar(max) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_plan_puntos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_plan_puntos] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_plan_puntos_orden] UNIQUE ([plan_prueba_id], [orden]),
        CONSTRAINT [UQ_mirror_plan_puntos_codigo] UNIQUE ([plan_prueba_id], [codigo]),
        CONSTRAINT [FK_mirror_plan_puntos_prueba] FOREIGN KEY ([plan_prueba_id])
            REFERENCES [mirror].[plan_pruebas] ([id]),
        CONSTRAINT [CK_mirror_plan_puntos_values] CHECK (
            [grupo] > 0 AND [orden] > 0 AND [carga_nominal] >= 0 AND [tolerancia] >= 0
        ),
        CONSTRAINT [CK_mirror_plan_puntos_json] CHECK (ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.equipo_planes', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[equipo_planes] (
        [id] uniqueidentifier NOT NULL,
        [equipo_id] uniqueidentifier NOT NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [vigente_desde] datetime2(3) NOT NULL,
        [vigente_hasta] datetime2(3) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_equipo_planes_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_equipo_planes] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_equipo_planes_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [FK_mirror_equipo_planes_version] FOREIGN KEY ([plan_version_id])
            REFERENCES [mirror].[plan_versiones] ([id]),
        CONSTRAINT [CK_mirror_equipo_planes_dates] CHECK (
            [vigente_hasta] IS NULL OR [vigente_hasta] > [vigente_desde]
        )
    );
    CREATE UNIQUE INDEX [UX_mirror_equipo_planes_vigente]
        ON [mirror].[equipo_planes] ([equipo_id]) WHERE [vigente_hasta] IS NULL;
END;

IF OBJECT_ID(N'mirror.verificacion_borradores', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[verificacion_borradores] (
        [id] uniqueidentifier NOT NULL,
        [request_uuid] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [area_id] uniqueidentifier NULL,
        [equipo_id] uniqueidentifier NOT NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [usuario_id] uniqueidentifier NOT NULL,
        [estado] varchar(20) NOT NULL,
        [paso_actual] nvarchar(30) NOT NULL,
        [payload_json] nvarchar(max) NOT NULL,
        [version] bigint NOT NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [expires_at] datetime2(3) NOT NULL,
        [finalized_at] datetime2(3) NULL,
        [verificacion_id] uniqueidentifier NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_verificacion_borradores_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_verificacion_borradores] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_verificacion_borradores_request] UNIQUE ([request_uuid]),
        CONSTRAINT [FK_mirror_verificacion_borradores_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [FK_mirror_verificacion_borradores_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id]),
        CONSTRAINT [FK_mirror_verificacion_borradores_area] FOREIGN KEY ([area_id])
            REFERENCES [mirror].[areas] ([id]),
        CONSTRAINT [FK_mirror_verificacion_borradores_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [FK_mirror_verificacion_borradores_plan] FOREIGN KEY ([plan_version_id])
            REFERENCES [mirror].[plan_versiones] ([id]),
        CONSTRAINT [FK_mirror_verificacion_borradores_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [CK_mirror_verificacion_borradores_estado] CHECK (
            [estado] IN ('DRAFT', 'FINALIZING', 'FINALIZED', 'ABANDONED', 'EXPIRED')
        ),
        CONSTRAINT [CK_mirror_verificacion_borradores_json] CHECK (ISJSON([payload_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.verificaciones', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[verificaciones] (
        [id] uniqueidentifier NOT NULL,
        [request_uuid] uniqueidentifier NOT NULL,
        [payload_hash] char(64) NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [area_id] uniqueidentifier NULL,
        [equipo_id] uniqueidentifier NOT NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [capturado_por] uniqueidentifier NOT NULL,
        [finalizado_por] uniqueidentifier NOT NULL,
        [realizado_at] datetime2(3) NOT NULL,
        [recibido_at] datetime2(3) NOT NULL,
        [alcance] varchar(20) NOT NULL,
        [veredicto_global] varchar(20) NULL,
        [trazabilidad] varchar(20) NOT NULL,
        [temperatura_c] decimal(9,3) NULL,
        [humedad_relativa_pct] decimal(9,3) NULL,
        [observaciones] nvarchar(max) NULL,
        [equipo_snapshot_json] nvarchar(max) NOT NULL,
        [plan_snapshot_json] nvarchar(max) NOT NULL,
        [app_version] nvarchar(50) NULL,
        [dispositivo_id] nvarchar(200) NULL,
        [estado] varchar(20) NOT NULL,
        [anulada_at] datetime2(3) NULL,
        [anulada_por] uniqueidentifier NULL,
        [motivo_anulacion] nvarchar(max) NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_verificaciones_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_verificaciones] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_verificaciones_request] UNIQUE ([request_uuid]),
        CONSTRAINT [FK_mirror_verificaciones_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_area] FOREIGN KEY ([area_id])
            REFERENCES [mirror].[areas] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_plan] FOREIGN KEY ([plan_version_id])
            REFERENCES [mirror].[plan_versiones] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_capturador] FOREIGN KEY ([capturado_por])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_finalizador] FOREIGN KEY ([finalizado_por])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [FK_mirror_verificaciones_anulador] FOREIGN KEY ([anulada_por])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [CK_mirror_verificaciones_values] CHECK (
            [alcance] IN ('complete', 'partial')
            AND ([veredicto_global] IS NULL OR [veredicto_global] IN ('pass', 'fail'))
            AND [trazabilidad] IN ('traceable', 'non_traceable')
            AND [estado] IN ('ACTIVE', 'ANNULLED')
            AND ([humedad_relativa_pct] IS NULL OR [humedad_relativa_pct] BETWEEN 0 AND 100)
        ),
        CONSTRAINT [CK_mirror_verificaciones_payload_hash] CHECK (
            LEN([payload_hash]) = 64 AND [payload_hash] NOT LIKE '%[^0-9a-f]%'
        ),
        CONSTRAINT [CK_mirror_verificaciones_equipo_json] CHECK (ISJSON([equipo_snapshot_json]) = 1),
        CONSTRAINT [CK_mirror_verificaciones_plan_json] CHECK (ISJSON([plan_snapshot_json]) = 1)
    );
    CREATE INDEX [IX_mirror_verificaciones_history]
        ON [mirror].[verificaciones] ([cliente_id], [planta_id], [equipo_id], [realizado_at] DESC);
END;

IF OBJECT_ID(N'mirror.verificacion_patrones', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[verificacion_patrones] (
        [verificacion_id] uniqueidentifier NOT NULL,
        [patron_id] uniqueidentifier NOT NULL,
        [certificado_id] uniqueidentifier NOT NULL,
        [rol] nvarchar(30) NOT NULL,
        [snapshot_json] nvarchar(max) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_verificacion_patrones_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_verificacion_patrones] PRIMARY KEY ([verificacion_id], [patron_id], [rol]),
        CONSTRAINT [FK_mirror_verificacion_patrones_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [mirror].[verificaciones] ([id]),
        CONSTRAINT [FK_mirror_verificacion_patrones_patron] FOREIGN KEY ([patron_id])
            REFERENCES [mirror].[patrones] ([id]),
        CONSTRAINT [FK_mirror_verificacion_patrones_certificado] FOREIGN KEY ([certificado_id])
            REFERENCES [mirror].[patron_certificados] ([id]),
        CONSTRAINT [CK_mirror_verificacion_patrones_json] CHECK (ISJSON([snapshot_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.pruebas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[pruebas] (
        [id] uniqueidentifier NOT NULL,
        [verificacion_id] uniqueidentifier NOT NULL,
        [plan_prueba_id] uniqueidentifier NOT NULL,
        [tipo] varchar(30) NOT NULL,
        [estado_ejecucion] varchar(20) NOT NULL,
        [motivo_omision] nvarchar(max) NULL,
        [metodo_evaluacion] varchar(60) NOT NULL,
        [unidad] nvarchar(20) NOT NULL,
        [tolerancia] decimal(19,9) NULL,
        [veredicto] varchar(20) NULL,
        [error_max_abs] decimal(19,9) NULL,
        [media] decimal(19,9) NULL,
        [desviacion_estandar] decimal(19,9) NULL,
        [rango] decimal(19,9) NULL,
        [observaciones] nvarchar(max) NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_pruebas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_pruebas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_pruebas_tipo] UNIQUE ([verificacion_id], [tipo]),
        CONSTRAINT [FK_mirror_pruebas_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [mirror].[verificaciones] ([id]),
        CONSTRAINT [FK_mirror_pruebas_plan] FOREIGN KEY ([plan_prueba_id])
            REFERENCES [mirror].[plan_pruebas] ([id]),
        CONSTRAINT [CK_mirror_pruebas_values] CHECK (
            [tipo] IN ('eccentricity', 'repeatability', 'linearity')
            AND [estado_ejecucion] IN ('executed', 'omitted')
            AND ([veredicto] IS NULL OR [veredicto] IN ('pass', 'fail'))
        )
    );
END;

IF OBJECT_ID(N'mirror.lecturas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[lecturas] (
        [id] uniqueidentifier NOT NULL,
        [prueba_id] uniqueidentifier NOT NULL,
        [plan_punto_id] uniqueidentifier NULL,
        [grupo] int NOT NULL,
        [orden] int NOT NULL,
        [punto_codigo] nvarchar(100) NOT NULL,
        [etiqueta] nvarchar(200) NOT NULL,
        [carga_nominal] decimal(19,9) NOT NULL,
        [indicacion] decimal(19,9) NOT NULL,
        [retorno_cero] decimal(19,9) NULL,
        [error] decimal(19,9) NOT NULL,
        [tolerancia] decimal(19,9) NOT NULL,
        [veredicto] varchar(20) NOT NULL,
        [metadata_json] nvarchar(max) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_lecturas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_lecturas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_lecturas_orden] UNIQUE ([prueba_id], [orden]),
        CONSTRAINT [FK_mirror_lecturas_prueba] FOREIGN KEY ([prueba_id])
            REFERENCES [mirror].[pruebas] ([id]),
        CONSTRAINT [FK_mirror_lecturas_punto] FOREIGN KEY ([plan_punto_id])
            REFERENCES [mirror].[plan_puntos] ([id]),
        CONSTRAINT [CK_mirror_lecturas_values] CHECK (
            [grupo] > 0 AND [orden] > 0 AND [tolerancia] >= 0
            AND [veredicto] IN ('pass', 'fail')
        ),
        CONSTRAINT [CK_mirror_lecturas_json] CHECK (ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.alertas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[alertas] (
        [id] uniqueidentifier NOT NULL,
        [verificacion_id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [equipo_id] uniqueidentifier NOT NULL,
        [tipo] varchar(30) NOT NULL,
        [resumen] nvarchar(max) NOT NULL,
        [estado_cliente] varchar(20) NOT NULL,
        [visibilidad_metrica] varchar(20) NOT NULL,
        [compartida_at] datetime2(3) NULL,
        [compartida_por] uniqueidentifier NULL,
        [mensaje_compartido] nvarchar(max) NULL,
        [estado_metrica] varchar(20) NOT NULL,
        [reconocida_at] datetime2(3) NULL,
        [reconocida_por] uniqueidentifier NULL,
        [atendida_at] datetime2(3) NULL,
        [atendida_por] uniqueidentifier NULL,
        [nota_atencion] nvarchar(max) NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_alertas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_alertas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_alertas_verificacion] UNIQUE ([verificacion_id]),
        CONSTRAINT [FK_mirror_alertas_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [mirror].[verificaciones] ([id]),
        CONSTRAINT [FK_mirror_alertas_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [FK_mirror_alertas_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id]),
        CONSTRAINT [FK_mirror_alertas_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [CK_mirror_alertas_values] CHECK (
            [estado_cliente] IN ('OPEN', 'CLOSED')
            AND [visibilidad_metrica] IN ('PRIVATE', 'SHARED')
            AND [estado_metrica] IN ('PENDING', 'ACKNOWLEDGED', 'ATTENDED')
        )
    );
END;

IF OBJECT_ID(N'mirror.auditoria', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[auditoria] (
        [id] uniqueidentifier NOT NULL,
        [actor_id] uniqueidentifier NULL,
        [actor_externo] nvarchar(150) NULL,
        [cliente_id] uniqueidentifier NULL,
        [entidad] nvarchar(80) NOT NULL,
        [entidad_id] nvarchar(150) NOT NULL,
        [accion] nvarchar(80) NOT NULL,
        [antes_json] nvarchar(max) NULL,
        [despues_json] nvarchar(max) NULL,
        [ip] varchar(45) NULL,
        [dispositivo_id] nvarchar(200) NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_auditoria_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_auditoria] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_auditoria_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [CK_mirror_auditoria_antes] CHECK (
            [antes_json] IS NULL OR ISJSON([antes_json]) = 1
        ),
        CONSTRAINT [CK_mirror_auditoria_despues] CHECK (
            [despues_json] IS NULL OR ISJSON([despues_json]) = 1
        )
    );
    CREATE INDEX [IX_mirror_auditoria_entidad]
        ON [mirror].[auditoria] ([entidad], [entidad_id], [created_at] DESC);
END;

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '004')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('004', N'Espejo tipado de configuracion y evidencia metrologica');

COMMIT TRANSACTION;
GO

/* La referencia circular borrador -> verificacion se agrega al final. */
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_mirror_verificacion_borradores_verificacion'
)
BEGIN
    ALTER TABLE [mirror].[verificacion_borradores] WITH CHECK
    ADD CONSTRAINT [FK_mirror_verificacion_borradores_verificacion]
        FOREIGN KEY ([verificacion_id]) REFERENCES [mirror].[verificaciones] ([id]);
END;
GO

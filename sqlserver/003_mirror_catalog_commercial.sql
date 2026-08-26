/*
  IvMET SQL Server - 003
  Proyecciones tipadas de catalogos, perfiles, contratos y licencias de
  Supabase. Los UUID de Supabase son las claves canonicas.
*/

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'mirror') IS NULL
    THROW 53100, 'No existe el esquema mirror. Ejecute 001_create_ivmet_database.sql.', 1;
GO

BEGIN TRANSACTION;

IF OBJECT_ID(N'mirror.clientes', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[clientes] (
        [id] uniqueidentifier NOT NULL,
        [legacy_cliente_id] int NOT NULL,
        [codigo] nvarchar(20) NOT NULL,
        [nombre] nvarchar(100) NULL,
        [razon_social] nvarchar(100) NULL,
        [estado_legacy] nvarchar(10) NULL,
        [activo] bit NOT NULL,
        [source_version] bigint NOT NULL,
        [source_hash] char(64) NOT NULL,
        [source_updated_at] datetime2(3) NULL,
        [synced_at] datetime2(3) NOT NULL,
        [last_seen_run_id] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_clientes_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_clientes] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_clientes_legacy] UNIQUE ([legacy_cliente_id]),
        CONSTRAINT [UQ_mirror_clientes_codigo] UNIQUE ([codigo]),
        CONSTRAINT [CK_mirror_clientes_hash] CHECK (
            LEN([source_hash]) = 64 AND [source_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_mirror_clientes_activos] ON [mirror].[clientes] ([activo], [codigo]);
END;

IF OBJECT_ID(N'mirror.plantas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[plantas] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [legacy_codigo_planta] nvarchar(50) NOT NULL,
        [legacy_planta_numero] int NULL,
        [nombre] nvarchar(100) NULL,
        [direccion] nvarchar(250) NULL,
        [departamento_codigo] nvarchar(10) NULL,
        [departamento_id] int NULL,
        [localidad] nvarchar(100) NULL,
        [ubicacion] nvarchar(100) NULL,
        [estado_legacy] nvarchar(10) NULL,
        [activo] bit NOT NULL,
        [source_version] bigint NOT NULL,
        [source_hash] char(64) NOT NULL,
        [source_updated_at] datetime2(3) NULL,
        [synced_at] datetime2(3) NOT NULL,
        [last_seen_run_id] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_plantas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_plantas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_plantas_legacy] UNIQUE ([legacy_codigo_planta]),
        CONSTRAINT [FK_mirror_plantas_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [CK_mirror_plantas_hash] CHECK (
            LEN([source_hash]) = 64 AND [source_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_mirror_plantas_cliente]
        ON [mirror].[plantas] ([cliente_id], [activo], [legacy_codigo_planta]);
END;

IF OBJECT_ID(N'mirror.equipos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[equipos] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [legacy_equipo_id] int NOT NULL,
        [cod_metrica] nvarchar(12) NOT NULL,
        [cod_interno] nvarchar(50) NULL,
        [instrumento] nvarchar(50) NULL,
        [tipo_instrumento] nvarchar(50) NULL,
        [categoria] nvarchar(20) NULL,
        [tipo_balanza] nvarchar(100) NULL,
        [marca] nvarchar(50) NULL,
        [modelo] nvarchar(50) NULL,
        [serie] nvarchar(70) NULL,
        [unidad] nvarchar(10) NULL,
        [ubicacion] nvarchar(200) NULL,
        [comunicacion] nvarchar(50) NULL,
        [material] nvarchar(50) NULL,
        [acceso] nvarchar(50) NULL,
        [altura] nvarchar(50) NULL,
        [numero_celdas] int NULL,
        [tecnologia] nvarchar(50) NULL,
        [proteccion] nvarchar(50) NULL,
        [plataforma] nvarchar(20) NULL,
        [clase] nvarchar(50) NULL,
        [estado_legacy] nvarchar(15) NULL,
        [estado_catalogo] varchar(30) NOT NULL,
        [activo] bit NOT NULL,
        [source_version] bigint NOT NULL,
        [source_hash] char(64) NOT NULL,
        [source_updated_at] datetime2(3) NULL,
        [synced_at] datetime2(3) NOT NULL,
        [last_seen_run_id] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_equipos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_equipos] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_equipos_legacy] UNIQUE ([legacy_equipo_id]),
        CONSTRAINT [UQ_mirror_equipos_codigo] UNIQUE ([cod_metrica]),
        CONSTRAINT [FK_mirror_equipos_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [FK_mirror_equipos_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id]),
        CONSTRAINT [CK_mirror_equipos_codigo] CHECK (
            [cod_metrica] LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9]'
        ),
        CONSTRAINT [CK_mirror_equipos_estado] CHECK (
            [estado_catalogo] IN ('READY', 'REQUIRES_REVIEW', 'QUARANTINED')
        ),
        CONSTRAINT [CK_mirror_equipos_hash] CHECK (
            LEN([source_hash]) = 64 AND [source_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
    CREATE INDEX [IX_mirror_equipos_scope]
        ON [mirror].[equipos] ([cliente_id], [planta_id], [activo], [estado_catalogo]);
END;

IF OBJECT_ID(N'mirror.equipo_rangos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[equipo_rangos] (
        [id] uniqueidentifier NOT NULL,
        [equipo_id] uniqueidentifier NOT NULL,
        [numero_rango] smallint NOT NULL,
        [unidad] nvarchar(10) NOT NULL,
        [capacidad_max] decimal(19,9) NOT NULL,
        [division_escala] decimal(19,9) NOT NULL,
        [intervalo_verificacion] decimal(19,9) NULL,
        [cantidad_decimales] smallint NULL,
        [source_hash] char(64) NOT NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_equipo_rangos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_equipo_rangos] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_equipo_rangos_numero] UNIQUE ([equipo_id], [numero_rango]),
        CONSTRAINT [FK_mirror_equipo_rangos_equipo] FOREIGN KEY ([equipo_id])
            REFERENCES [mirror].[equipos] ([id]),
        CONSTRAINT [CK_mirror_equipo_rangos_values] CHECK (
            [numero_rango] BETWEEN 1 AND 99 AND [capacidad_max] > 0 AND [division_escala] > 0
            AND ([intervalo_verificacion] IS NULL OR [intervalo_verificacion] > 0)
            AND ([cantidad_decimales] IS NULL OR [cantidad_decimales] BETWEEN 0 AND 9)
        ),
        CONSTRAINT [CK_mirror_equipo_rangos_hash] CHECK (
            LEN([source_hash]) = 64 AND [source_hash] NOT LIKE '%[^0-9a-f]%'
        )
    );
END;

IF OBJECT_ID(N'mirror.perfiles', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[perfiles] (
        [id] uniqueidentifier NOT NULL,
        [usuario] nvarchar(100) NOT NULL,
        [usuario_normalizado] nvarchar(100) NOT NULL,
        [nombre] nvarchar(200) NOT NULL,
        [rol] varchar(40) NOT NULL,
        [cliente_id] uniqueidentifier NULL,
        [activo] bit NOT NULL,
        [debe_cambiar_password] bit NOT NULL,
        [ultimo_acceso_at] datetime2(3) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_perfiles_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_perfiles] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_perfiles_usuario] UNIQUE ([usuario_normalizado]),
        CONSTRAINT [FK_mirror_perfiles_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [CK_mirror_perfiles_rol] CHECK ([rol] IN (
            'cliente_operador', 'cliente_jefe_calidad', 'metrica_tecnico', 'metrica_admin'
        ))
    );
    CREATE INDEX [IX_mirror_perfiles_cliente]
        ON [mirror].[perfiles] ([cliente_id], [activo], [rol]);
END;

IF OBJECT_ID(N'mirror.usuario_plantas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[usuario_plantas] (
        [usuario_id] uniqueidentifier NOT NULL,
        [planta_id] uniqueidentifier NOT NULL,
        [activa] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_usuario_plantas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_usuario_plantas] PRIMARY KEY ([usuario_id], [planta_id]),
        CONSTRAINT [FK_mirror_usuario_plantas_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [FK_mirror_usuario_plantas_planta] FOREIGN KEY ([planta_id])
            REFERENCES [mirror].[plantas] ([id])
    );
    CREATE INDEX [IX_mirror_usuario_plantas_planta]
        ON [mirror].[usuario_plantas] ([planta_id], [activa], [usuario_id]);
END;

IF OBJECT_ID(N'mirror.planes_comerciales', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[planes_comerciales] (
        [id] uniqueidentifier NOT NULL,
        [codigo] nvarchar(50) NOT NULL,
        [nombre] nvarchar(150) NOT NULL,
        [descripcion] nvarchar(max) NULL,
        [cuentas_incluidas] int NOT NULL,
        [dias_gracia] int NOT NULL,
        [caracteristicas_json] nvarchar(max) NOT NULL,
        [activo] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_planes_comerciales_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_planes_comerciales] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_planes_comerciales_codigo] UNIQUE ([codigo]),
        CONSTRAINT [CK_mirror_planes_comerciales_values] CHECK (
            [cuentas_incluidas] > 0 AND [dias_gracia] BETWEEN 0 AND 90
        ),
        CONSTRAINT [CK_mirror_planes_comerciales_json] CHECK (ISJSON([caracteristicas_json]) = 1)
    );
END;

IF OBJECT_ID(N'mirror.precios_plan', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[precios_plan] (
        [id] uniqueidentifier NOT NULL,
        [plan_id] uniqueidentifier NOT NULL,
        [periodicidad] varchar(10) NOT NULL,
        [moneda] char(3) NOT NULL,
        [importe] decimal(19,2) NOT NULL,
        [vigente_desde] date NOT NULL,
        [vigente_hasta] date NULL,
        [activo] bit NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_precios_plan_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_precios_plan] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_precios_plan_version] UNIQUE (
            [plan_id], [periodicidad], [moneda], [vigente_desde]
        ),
        CONSTRAINT [FK_mirror_precios_plan_plan] FOREIGN KEY ([plan_id])
            REFERENCES [mirror].[planes_comerciales] ([id]),
        CONSTRAINT [CK_mirror_precios_plan_values] CHECK (
            [periodicidad] IN ('MONTHLY', 'ANNUAL') AND [importe] >= 0
            AND ([vigente_hasta] IS NULL OR [vigente_hasta] >= [vigente_desde])
        )
    );
END;

IF OBJECT_ID(N'mirror.contratos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[contratos] (
        [id] uniqueidentifier NOT NULL,
        [cliente_id] uniqueidentifier NOT NULL,
        [numero_contrato] nvarchar(100) NOT NULL,
        [fecha_firma] date NULL,
        [vigente_desde] date NOT NULL,
        [vigente_hasta] date NULL,
        [estado] varchar(20) NOT NULL,
        [archivo_path] nvarchar(1000) NULL,
        [archivo_hash] char(64) NULL,
        [observaciones] nvarchar(max) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_contratos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_contratos] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_contratos_numero] UNIQUE ([numero_contrato]),
        CONSTRAINT [FK_mirror_contratos_cliente] FOREIGN KEY ([cliente_id])
            REFERENCES [mirror].[clientes] ([id]),
        CONSTRAINT [CK_mirror_contratos_estado] CHECK (
            [estado] IN ('DRAFT', 'ACTIVE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')
        ),
        CONSTRAINT [CK_mirror_contratos_dates] CHECK (
            [vigente_hasta] IS NULL OR [vigente_hasta] >= [vigente_desde]
        )
    );
    CREATE INDEX [IX_mirror_contratos_cliente]
        ON [mirror].[contratos] ([cliente_id], [estado], [vigente_hasta]);
END;

IF OBJECT_ID(N'mirror.suscripciones', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[suscripciones] (
        [id] uniqueidentifier NOT NULL,
        [contrato_id] uniqueidentifier NOT NULL,
        [plan_id] uniqueidentifier NOT NULL,
        [precio_plan_id] uniqueidentifier NULL,
        [periodicidad] varchar(10) NOT NULL,
        [inicio_periodo] datetime2(3) NOT NULL,
        [fin_periodo] datetime2(3) NOT NULL,
        [proximo_cobro] date NULL,
        [gracia_hasta] datetime2(3) NULL,
        [renovacion_automatica] bit NOT NULL,
        [estado] varchar(20) NOT NULL,
        [motivo_suspension] nvarchar(max) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_suscripciones_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_suscripciones] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_suscripciones_contrato] FOREIGN KEY ([contrato_id])
            REFERENCES [mirror].[contratos] ([id]),
        CONSTRAINT [FK_mirror_suscripciones_plan] FOREIGN KEY ([plan_id])
            REFERENCES [mirror].[planes_comerciales] ([id]),
        CONSTRAINT [FK_mirror_suscripciones_precio] FOREIGN KEY ([precio_plan_id])
            REFERENCES [mirror].[precios_plan] ([id]),
        CONSTRAINT [CK_mirror_suscripciones_values] CHECK (
            [periodicidad] IN ('MONTHLY', 'ANNUAL')
            AND [estado] IN ('PENDING', 'ACTIVE', 'PAST_DUE', 'GRACE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')
            AND [fin_periodo] > [inicio_periodo]
            AND ([gracia_hasta] IS NULL OR [gracia_hasta] >= [fin_periodo])
        )
    );
    CREATE INDEX [IX_mirror_suscripciones_contrato_estado]
        ON [mirror].[suscripciones] ([contrato_id], [estado], [fin_periodo]);
END;

IF OBJECT_ID(N'mirror.facturas', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[facturas] (
        [id] uniqueidentifier NOT NULL,
        [suscripcion_id] uniqueidentifier NOT NULL,
        [numero_factura] nvarchar(100) NOT NULL,
        [periodo_desde] date NOT NULL,
        [periodo_hasta] date NOT NULL,
        [fecha_emision] date NOT NULL,
        [fecha_vencimiento] date NOT NULL,
        [moneda] char(3) NOT NULL,
        [subtotal] decimal(19,2) NOT NULL,
        [impuestos] decimal(19,2) NOT NULL,
        [total] decimal(19,2) NOT NULL,
        [saldo] decimal(19,2) NOT NULL,
        [estado] varchar(20) NOT NULL,
        [referencia_externa] nvarchar(max) NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_facturas_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_facturas] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_mirror_facturas_numero] UNIQUE ([numero_factura]),
        CONSTRAINT [FK_mirror_facturas_suscripcion] FOREIGN KEY ([suscripcion_id])
            REFERENCES [mirror].[suscripciones] ([id]),
        CONSTRAINT [CK_mirror_facturas_estado] CHECK (
            [estado] IN ('PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'VOID')
        ),
        CONSTRAINT [CK_mirror_facturas_values] CHECK (
            [periodo_hasta] >= [periodo_desde] AND [fecha_vencimiento] >= [fecha_emision]
            AND [subtotal] >= 0 AND [impuestos] >= 0 AND [total] >= 0
            AND [saldo] >= 0 AND [saldo] <= [total]
        )
    );
END;

IF OBJECT_ID(N'mirror.pagos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[pagos] (
        [id] uniqueidentifier NOT NULL,
        [factura_id] uniqueidentifier NOT NULL,
        [fecha_pago] datetime2(3) NOT NULL,
        [importe] decimal(19,2) NOT NULL,
        [moneda] char(3) NOT NULL,
        [metodo] nvarchar(30) NOT NULL,
        [referencia] nvarchar(200) NULL,
        [estado] varchar(20) NOT NULL,
        [registrado_por] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_pagos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_pagos] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_pagos_factura] FOREIGN KEY ([factura_id])
            REFERENCES [mirror].[facturas] ([id]),
        CONSTRAINT [CK_mirror_pagos_values] CHECK (
            [importe] > 0 AND [estado] IN ('PENDING', 'CONFIRMED', 'REJECTED', 'REFUNDED')
        )
    );
END;

IF OBJECT_ID(N'mirror.suscripcion_cupos', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[suscripcion_cupos] (
        [id] uniqueidentifier NOT NULL,
        [suscripcion_id] uniqueidentifier NOT NULL,
        [tipo] varchar(20) NOT NULL,
        [cantidad] int NOT NULL,
        [factura_id] uniqueidentifier NULL,
        [vigente_desde] datetime2(3) NOT NULL,
        [vigente_hasta] datetime2(3) NULL,
        [estado] varchar(20) NOT NULL,
        [created_by] uniqueidentifier NULL,
        [created_at] datetime2(3) NOT NULL,
        [updated_at] datetime2(3) NOT NULL,
        [source_row_version] bigint NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_suscripcion_cupos_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_suscripcion_cupos] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_suscripcion_cupos_suscripcion] FOREIGN KEY ([suscripcion_id])
            REFERENCES [mirror].[suscripciones] ([id]),
        CONSTRAINT [FK_mirror_suscripcion_cupos_factura] FOREIGN KEY ([factura_id])
            REFERENCES [mirror].[facturas] ([id]),
        CONSTRAINT [CK_mirror_suscripcion_cupos_values] CHECK (
            [tipo] IN ('PLAN_BASE', 'ADDITIONAL') AND [cantidad] > 0
            AND [estado] IN ('PENDING', 'ACTIVE', 'REVOKED', 'EXPIRED')
            AND ([vigente_hasta] IS NULL OR [vigente_hasta] > [vigente_desde])
        )
    );
END;

IF OBJECT_ID(N'mirror.licencias_usuario', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[licencias_usuario] (
        [id] uniqueidentifier NOT NULL,
        [suscripcion_id] uniqueidentifier NOT NULL,
        [usuario_id] uniqueidentifier NOT NULL,
        [estado] varchar(20) NOT NULL,
        [asignada_at] datetime2(3) NOT NULL,
        [asignada_por] uniqueidentifier NULL,
        [revocada_at] datetime2(3) NULL,
        [revocada_por] uniqueidentifier NULL,
        [motivo_revocacion] nvarchar(max) NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_licencias_usuario_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_licencias_usuario] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_licencias_usuario_suscripcion] FOREIGN KEY ([suscripcion_id])
            REFERENCES [mirror].[suscripciones] ([id]),
        CONSTRAINT [FK_mirror_licencias_usuario_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [CK_mirror_licencias_usuario_estado] CHECK (
            [estado] IN ('ACTIVE', 'REVOKED', 'EXPIRED')
        )
    );
    CREATE UNIQUE INDEX [UX_mirror_licencias_usuario_activa]
        ON [mirror].[licencias_usuario] ([usuario_id]) WHERE [estado] = 'ACTIVE';
END;

IF OBJECT_ID(N'mirror.eventos_licencia', N'U') IS NULL
BEGIN
    CREATE TABLE [mirror].[eventos_licencia] (
        [id] uniqueidentifier NOT NULL,
        [usuario_id] uniqueidentifier NULL,
        [suscripcion_id] uniqueidentifier NULL,
        [contrato_id] uniqueidentifier NULL,
        [tipo_evento] nvarchar(50) NOT NULL,
        [estado_anterior_json] nvarchar(max) NULL,
        [estado_nuevo_json] nvarchar(max) NOT NULL,
        [actor_id] uniqueidentifier NULL,
        [actor_externo] nvarchar(150) NULL,
        [motivo] nvarchar(max) NULL,
        [created_at] datetime2(3) NOT NULL,
        [source_event_sequence] bigint NOT NULL,
        [mirrored_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_mirror_eventos_licencia_mirrored] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_mirror_eventos_licencia] PRIMARY KEY ([id]),
        CONSTRAINT [FK_mirror_eventos_licencia_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [mirror].[perfiles] ([id]),
        CONSTRAINT [FK_mirror_eventos_licencia_suscripcion] FOREIGN KEY ([suscripcion_id])
            REFERENCES [mirror].[suscripciones] ([id]),
        CONSTRAINT [FK_mirror_eventos_licencia_contrato] FOREIGN KEY ([contrato_id])
            REFERENCES [mirror].[contratos] ([id]),
        CONSTRAINT [CK_mirror_eventos_licencia_before] CHECK (
            [estado_anterior_json] IS NULL OR ISJSON([estado_anterior_json]) = 1
        ),
        CONSTRAINT [CK_mirror_eventos_licencia_after] CHECK (ISJSON([estado_nuevo_json]) = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '003')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('003', N'Espejo tipado de catalogos, perfiles, contratos y licencias');

COMMIT TRANSACTION;
GO

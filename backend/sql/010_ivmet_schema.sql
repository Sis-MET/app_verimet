/*
  Esquema aditivo de IvMET para SQL Server/DataMET.

  - No modifica tablas legadas.
  - No importa DATA_SERVICIOS_LEC.
  - Todas las bajas son logicas; la evidencia metrologica no se elimina.
  - Ejecutar primero sobre una copia validada de produccion.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.DATA_CLIENTES', N'U') IS NULL
    THROW 52001, 'No existe dbo.DATA_CLIENTES.', 1;
IF OBJECT_ID(N'dbo.DATA_PLANTAS', N'U') IS NULL
    THROW 52002, 'No existe dbo.DATA_PLANTAS.', 1;
IF OBJECT_ID(N'dbo.DATA_EQUIPOS', N'U') IS NULL
    THROW 52003, 'No existe dbo.DATA_EQUIPOS.', 1;
IF OBJECT_ID(N'dbo.DATA_EQUIPOS_BALANZAS', N'U') IS NULL
    THROW 52004, 'No existe dbo.DATA_EQUIPOS_BALANZAS.', 1;

IF COL_LENGTH(N'dbo.DATA_CLIENTES', N'cliente_id') IS NULL
    THROW 52005, 'Falta DATA_CLIENTES.cliente_id.', 1;
IF COL_LENGTH(N'dbo.DATA_PLANTAS', N'planta_id') IS NULL
    THROW 52006, 'Falta DATA_PLANTAS.planta_id.', 1;
IF COL_LENGTH(N'dbo.DATA_PLANTAS', N'cliente_id') IS NULL
    THROW 52007, 'Falta DATA_PLANTAS.cliente_id.', 1;
IF COL_LENGTH(N'dbo.DATA_EQUIPOS', N'cod_metrica') IS NULL
    THROW 52008, 'Falta DATA_EQUIPOS.cod_metrica.', 1;
IF COL_LENGTH(N'dbo.DATA_EQUIPOS_BALANZAS', N'cod_metrica') IS NULL
    THROW 52009, 'Falta DATA_EQUIPOS_BALANZAS.cod_metrica.', 1;

IF EXISTS (SELECT 1 FROM dbo.DATA_CLIENTES WHERE cliente_id IS NULL)
    THROW 52010, 'DATA_CLIENTES contiene cliente_id nulo.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_PLANTAS WHERE planta_id IS NULL OR cliente_id IS NULL)
    THROW 52011, 'DATA_PLANTAS contiene planta_id o cliente_id nulo.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_EQUIPOS WHERE cod_metrica IS NULL OR LTRIM(RTRIM(CONVERT(nvarchar(100),cod_metrica)))=N'')
    THROW 52012, 'DATA_EQUIPOS contiene cod_metrica nulo o vacio.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_EQUIPOS_BALANZAS WHERE cod_metrica IS NULL OR LTRIM(RTRIM(CONVERT(nvarchar(100),cod_metrica)))=N'')
    THROW 52013, 'DATA_EQUIPOS_BALANZAS contiene cod_metrica nulo o vacio.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_CLIENTES WHERE LEN(CONVERT(nvarchar(max),cliente_id))>50)
    THROW 52018, 'DATA_CLIENTES.cliente_id excede 50 caracteres canonicos.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_PLANTAS WHERE LEN(CONVERT(nvarchar(max),planta_id))>50 OR LEN(CONVERT(nvarchar(max),cliente_id))>50)
    THROW 52019, 'DATA_PLANTAS contiene un identificador que excede 50 caracteres canonicos.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_EQUIPOS WHERE LEN(CONVERT(nvarchar(max),cod_metrica))>100)
    THROW 52020, 'DATA_EQUIPOS.cod_metrica excede 100 caracteres canonicos.', 1;
IF EXISTS (SELECT 1 FROM dbo.DATA_EQUIPOS_BALANZAS WHERE LEN(CONVERT(nvarchar(max),cod_metrica))>100)
    THROW 52021, 'DATA_EQUIPOS_BALANZAS.cod_metrica excede 100 caracteres canonicos.', 1;
IF EXISTS (SELECT CONVERT(nvarchar(50),cliente_id) FROM dbo.DATA_CLIENTES GROUP BY CONVERT(nvarchar(50),cliente_id) HAVING COUNT(*)>1)
    THROW 52014, 'DATA_CLIENTES contiene cliente_id duplicado al convertirlo al identificador canonico.', 1;
IF EXISTS (SELECT CONVERT(nvarchar(50),planta_id) FROM dbo.DATA_PLANTAS GROUP BY CONVERT(nvarchar(50),planta_id) HAVING COUNT(*)>1)
    THROW 52015, 'DATA_PLANTAS contiene planta_id duplicado al convertirlo al identificador canonico.', 1;
IF EXISTS (SELECT CONVERT(nvarchar(100),cod_metrica) FROM dbo.DATA_EQUIPOS GROUP BY CONVERT(nvarchar(100),cod_metrica) HAVING COUNT(*)>1)
    THROW 52016, 'DATA_EQUIPOS contiene cod_metrica duplicado al convertirlo al identificador canonico.', 1;
IF EXISTS (SELECT CONVERT(nvarchar(100),cod_metrica) FROM dbo.DATA_EQUIPOS_BALANZAS GROUP BY CONVERT(nvarchar(100),cod_metrica) HAVING COUNT(*)>1)
    THROW 52017, 'DATA_EQUIPOS_BALANZAS contiene cod_metrica duplicado al convertirlo al identificador canonico.', 1;

/* Resultado de auditoria que debe conservarse con la evidencia del despliegue. */
SELECT OBJECT_SCHEMA_NAME(c.object_id) AS esquema,OBJECT_NAME(c.object_id) AS tabla,c.name AS columna,
       TYPE_NAME(c.user_type_id) AS tipo,c.max_length,c.precision,c.scale,c.is_nullable
FROM sys.columns c
WHERE c.object_id IN (OBJECT_ID(N'dbo.DATA_CLIENTES'),OBJECT_ID(N'dbo.DATA_PLANTAS'),
                      OBJECT_ID(N'dbo.DATA_EQUIPOS'),OBJECT_ID(N'dbo.DATA_EQUIPOS_BALANZAS'))
  AND c.name IN (N'cliente_id',N'planta_id',N'cod_metrica')
ORDER BY tabla,columna;

IF SCHEMA_ID(N'ivmet') IS NULL
    EXEC(N'CREATE SCHEMA [ivmet] AUTHORIZATION [dbo]');

BEGIN TRANSACTION;

IF OBJECT_ID(N'ivmet.usuarios', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[usuarios] (
        [usuario_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_id] DEFAULT NEWSEQUENTIALID(),
        [usuario] nvarchar(100) NOT NULL,
        [usuario_normalizado] nvarchar(100) NOT NULL,
        [nombre] nvarchar(200) NOT NULL,
        [email] nvarchar(254) NULL,
        [password_hash] nvarchar(255) NOT NULL,
        [rol] nvarchar(40) NOT NULL,
        [cliente_id] nvarchar(50) NULL,
        [estado] nvarchar(20) NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_estado] DEFAULT N'ACTIVO',
        [debe_cambiar_password] bit NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_cambio] DEFAULT 1,
        [intentos_fallidos] int NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_intentos] DEFAULT 0,
        [bloqueado_hasta] datetime2(3) NULL,
        [token_version] int NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_token_version] DEFAULT 1,
        [ultimo_acceso_at] datetime2(3) NULL,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_creado] DEFAULT SYSUTCDATETIME(),
        [actualizado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_usuarios_actualizado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NULL,
        [version_fila] rowversion NOT NULL,
        CONSTRAINT [PK_ivmet_usuarios] PRIMARY KEY ([usuario_id]),
        CONSTRAINT [UQ_ivmet_usuarios_normalizado] UNIQUE ([usuario_normalizado]),
        CONSTRAINT [CK_ivmet_usuarios_rol] CHECK ([rol] IN (
            N'cliente_operador', N'cliente_jefe_calidad',
            N'metrica_tecnico', N'metrica_admin'
        )),
        CONSTRAINT [CK_ivmet_usuarios_estado] CHECK ([estado] IN (N'ACTIVO', N'INACTIVO')),
        CONSTRAINT [CK_ivmet_usuarios_tenant] CHECK (
            ([rol] LIKE N'cliente_%' AND [cliente_id] IS NOT NULL) OR
            ([rol] LIKE N'metrica_%' AND [cliente_id] IS NULL)
        ),
        CONSTRAINT [CK_ivmet_usuarios_intentos] CHECK ([intentos_fallidos] >= 0),
        CONSTRAINT [FK_ivmet_usuarios_creado_por] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id])
    );
END;

IF OBJECT_ID(N'ivmet.usuario_plantas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[usuario_plantas] (
        [usuario_id] uniqueidentifier NOT NULL,
        [cliente_id] nvarchar(50) NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        [activa] bit NOT NULL CONSTRAINT [DF_ivmet_usuario_plantas_activa] DEFAULT 1,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_usuario_plantas_creado] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_ivmet_usuario_plantas] PRIMARY KEY ([usuario_id], [planta_id]),
        CONSTRAINT [FK_ivmet_usuario_plantas_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [ivmet].[usuarios]([usuario_id])
    );
    CREATE INDEX [IX_ivmet_usuario_plantas_tenant]
        ON [ivmet].[usuario_plantas]([cliente_id], [planta_id]);
END;

IF OBJECT_ID(N'ivmet.sesiones_refresh', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[sesiones_refresh] (
        [sesion_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_sesiones_id] DEFAULT NEWSEQUENTIALID(),
        [usuario_id] uniqueidentifier NOT NULL,
        [token_hash] binary(32) NOT NULL,
        [dispositivo_id] nvarchar(200) NOT NULL,
        [dispositivo_nombre] nvarchar(200) NULL,
        [expira_at] datetime2(3) NOT NULL,
        [revocado_at] datetime2(3) NULL,
        [reemplazado_por] uniqueidentifier NULL,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_sesiones_creado] DEFAULT SYSUTCDATETIME(),
        [ultimo_uso_at] datetime2(3) NULL,
        [ip_creacion] nvarchar(64) NULL,
        CONSTRAINT [PK_ivmet_sesiones_refresh] PRIMARY KEY ([sesion_id]),
        CONSTRAINT [UQ_ivmet_sesiones_token_hash] UNIQUE ([token_hash]),
        CONSTRAINT [FK_ivmet_sesiones_usuario] FOREIGN KEY ([usuario_id])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_sesiones_reemplazo] FOREIGN KEY ([reemplazado_por])
            REFERENCES [ivmet].[sesiones_refresh]([sesion_id])
    );
    CREATE INDEX [IX_ivmet_sesiones_usuario]
        ON [ivmet].[sesiones_refresh]([usuario_id], [revocado_at], [expira_at]);
END;

IF OBJECT_ID(N'ivmet.areas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[areas] (
        [area_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_areas_id] DEFAULT NEWSEQUENTIALID(),
        [cliente_id] nvarchar(50) NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        [nombre] nvarchar(150) NOT NULL,
        [nombre_normalizado] nvarchar(150) NOT NULL,
        [activa] bit NOT NULL CONSTRAINT [DF_ivmet_areas_activa] DEFAULT 1,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_areas_creado] DEFAULT SYSUTCDATETIME(),
        [actualizado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_areas_actualizado] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_ivmet_areas] PRIMARY KEY ([area_id]),
        CONSTRAINT [UQ_ivmet_areas_nombre] UNIQUE ([cliente_id], [planta_id], [nombre_normalizado])
    );
END;

IF OBJECT_ID(N'ivmet.equipos', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[equipos] (
        [cod_metrica] nvarchar(100) NOT NULL,
        [cliente_id] nvarchar(50) NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        [area_id] uniqueidentifier NULL,
        [estado_configuracion] nvarchar(20) NOT NULL
            CONSTRAINT [DF_ivmet_equipos_config] DEFAULT N'PENDIENTE',
        [habilitado] bit NOT NULL CONSTRAINT [DF_ivmet_equipos_habilitado] DEFAULT 1,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_equipos_creado] DEFAULT SYSUTCDATETIME(),
        [actualizado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_equipos_actualizado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        CONSTRAINT [PK_ivmet_equipos] PRIMARY KEY ([cod_metrica]),
        CONSTRAINT [FK_ivmet_equipos_area] FOREIGN KEY ([area_id])
            REFERENCES [ivmet].[areas]([area_id]),
        CONSTRAINT [FK_ivmet_equipos_usuario] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_equipos_config] CHECK ([estado_configuracion] IN (N'PENDIENTE',N'LISTO'))
    );
    CREATE INDEX [IX_ivmet_equipos_tenant]
        ON [ivmet].[equipos]([cliente_id], [planta_id], [habilitado]);
END;

IF OBJECT_ID(N'ivmet.patrones', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[patrones] (
        [patron_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_patrones_id] DEFAULT NEWSEQUENTIALID(),
        [cliente_id] nvarchar(50) NOT NULL,
        [codigo] nvarchar(100) NOT NULL,
        [descripcion] nvarchar(300) NOT NULL,
        [tipo] nvarchar(50) NOT NULL,
        [clase] nvarchar(50) NULL,
        [unidad] nvarchar(20) NULL,
        [capacidad] decimal(19,9) NULL,
        [activo] bit NOT NULL CONSTRAINT [DF_ivmet_patrones_activo] DEFAULT 1,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_patrones_creado] DEFAULT SYSUTCDATETIME(),
        [actualizado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_patrones_actualizado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        CONSTRAINT [PK_ivmet_patrones] PRIMARY KEY ([patron_id]),
        CONSTRAINT [UQ_ivmet_patrones_codigo] UNIQUE ([cliente_id], [codigo]),
        CONSTRAINT [FK_ivmet_patrones_usuario] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id])
    );
END;

IF OBJECT_ID(N'ivmet.patron_plantas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[patron_plantas] (
        [patron_id] uniqueidentifier NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        CONSTRAINT [PK_ivmet_patron_plantas] PRIMARY KEY ([patron_id], [planta_id]),
        CONSTRAINT [FK_ivmet_patron_plantas_patron] FOREIGN KEY ([patron_id])
            REFERENCES [ivmet].[patrones]([patron_id])
    );
END;

IF OBJECT_ID(N'ivmet.patron_certificados', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[patron_certificados] (
        [certificado_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_certificados_id] DEFAULT NEWSEQUENTIALID(),
        [patron_id] uniqueidentifier NOT NULL,
        [numero] nvarchar(150) NOT NULL,
        [laboratorio] nvarchar(250) NOT NULL,
        [calibrado_el] date NOT NULL,
        [vence_el] date NOT NULL,
        [documento_referencia] nvarchar(500) NULL,
        [estado] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_certificados_estado] DEFAULT N'ACTIVO',
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_certificados_creado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        CONSTRAINT [PK_ivmet_patron_certificados] PRIMARY KEY ([certificado_id]),
        CONSTRAINT [UQ_ivmet_certificados_numero] UNIQUE ([patron_id], [numero]),
        CONSTRAINT [FK_ivmet_certificados_patron] FOREIGN KEY ([patron_id])
            REFERENCES [ivmet].[patrones]([patron_id]),
        CONSTRAINT [FK_ivmet_certificados_usuario] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_certificados_fechas] CHECK ([vence_el] >= [calibrado_el]),
        CONSTRAINT [CK_ivmet_certificados_estado] CHECK ([estado] IN (N'ACTIVO', N'ANULADO'))
    );
END;

IF OBJECT_ID(N'ivmet.planes', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[planes] (
        [plan_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_planes_id] DEFAULT NEWSEQUENTIALID(),
        [nombre] nvarchar(200) NOT NULL,
        [descripcion] nvarchar(1000) NULL,
        [activo] bit NOT NULL CONSTRAINT [DF_ivmet_planes_activo] DEFAULT 1,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_planes_creado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        CONSTRAINT [PK_ivmet_planes] PRIMARY KEY ([plan_id]),
        CONSTRAINT [UQ_ivmet_planes_nombre] UNIQUE ([nombre]),
        CONSTRAINT [FK_ivmet_planes_usuario] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id])
    );
END;

IF OBJECT_ID(N'ivmet.plan_versiones', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[plan_versiones] (
        [plan_version_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_plan_versiones_id] DEFAULT NEWSEQUENTIALID(),
        [plan_id] uniqueidentifier NOT NULL,
        [version] int NOT NULL,
        [estado] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_plan_versiones_estado] DEFAULT N'BORRADOR',
        [procedimiento_referencia] nvarchar(300) NULL,
        [notas] nvarchar(1000) NULL,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_plan_versiones_creado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        [publicado_at] datetime2(3) NULL,
        [publicado_por] uniqueidentifier NULL,
        CONSTRAINT [PK_ivmet_plan_versiones] PRIMARY KEY ([plan_version_id]),
        CONSTRAINT [UQ_ivmet_plan_versiones_numero] UNIQUE ([plan_id], [version]),
        CONSTRAINT [FK_ivmet_plan_versiones_plan] FOREIGN KEY ([plan_id])
            REFERENCES [ivmet].[planes]([plan_id]),
        CONSTRAINT [FK_ivmet_plan_versiones_creador] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_plan_versiones_publicador] FOREIGN KEY ([publicado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_plan_versiones_estado] CHECK ([estado] IN (N'BORRADOR', N'PUBLICADO', N'RETIRADO')),
        CONSTRAINT [CK_ivmet_plan_versiones_version] CHECK ([version] > 0)
    );
END;

IF OBJECT_ID(N'ivmet.plan_pruebas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[plan_pruebas] (
        [plan_prueba_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_plan_pruebas_id] DEFAULT NEWSEQUENTIALID(),
        [plan_version_id] uniqueidentifier NOT NULL,
        [tipo] nvarchar(30) NOT NULL,
        [metodo_evaluacion] nvarchar(60) NOT NULL,
        [unidad] nvarchar(20) NOT NULL,
        [frecuencia_dias] int NOT NULL,
        [aviso_dias] int NOT NULL CONSTRAINT [DF_ivmet_plan_pruebas_aviso] DEFAULT 7,
        [metadata_json] nvarchar(max) NULL,
        CONSTRAINT [PK_ivmet_plan_pruebas] PRIMARY KEY ([plan_prueba_id]),
        CONSTRAINT [UQ_ivmet_plan_pruebas_tipo] UNIQUE ([plan_version_id], [tipo]),
        CONSTRAINT [FK_ivmet_plan_pruebas_version] FOREIGN KEY ([plan_version_id])
            REFERENCES [ivmet].[plan_versiones]([plan_version_id]),
        CONSTRAINT [CK_ivmet_plan_pruebas_tipo] CHECK ([tipo] IN (N'eccentricity', N'repeatability', N'linearity')),
        CONSTRAINT [CK_ivmet_plan_pruebas_metodo] CHECK ([metodo_evaluacion] IN (N'absolute_error',N'range',N'sample_standard_deviation')),
        CONSTRAINT [CK_ivmet_plan_pruebas_frecuencia] CHECK ([frecuencia_dias] > 0 AND [aviso_dias] >= 0),
        CONSTRAINT [CK_ivmet_plan_pruebas_metadata] CHECK ([metadata_json] IS NULL OR ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'ivmet.plan_puntos', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[plan_puntos] (
        [plan_punto_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_plan_puntos_id] DEFAULT NEWSEQUENTIALID(),
        [plan_prueba_id] uniqueidentifier NOT NULL,
        [grupo] int NOT NULL CONSTRAINT [DF_ivmet_plan_puntos_grupo] DEFAULT 1,
        [orden] int NOT NULL,
        [codigo] nvarchar(100) NOT NULL,
        [etiqueta] nvarchar(200) NOT NULL,
        [carga_nominal] decimal(19,9) NOT NULL,
        [tolerancia] decimal(19,9) NOT NULL,
        [posicion] nvarchar(100) NULL,
        [direccion] nvarchar(30) NULL,
        [metadata_json] nvarchar(max) NULL,
        CONSTRAINT [PK_ivmet_plan_puntos] PRIMARY KEY ([plan_punto_id]),
        CONSTRAINT [UQ_ivmet_plan_puntos_orden] UNIQUE ([plan_prueba_id], [orden]),
        CONSTRAINT [UQ_ivmet_plan_puntos_codigo] UNIQUE ([plan_prueba_id], [codigo]),
        CONSTRAINT [FK_ivmet_plan_puntos_prueba] FOREIGN KEY ([plan_prueba_id])
            REFERENCES [ivmet].[plan_pruebas]([plan_prueba_id]),
        CONSTRAINT [CK_ivmet_plan_puntos_valores] CHECK ([grupo] > 0 AND [orden] > 0 AND [tolerancia] >= 0),
        CONSTRAINT [CK_ivmet_plan_puntos_metadata] CHECK ([metadata_json] IS NULL OR ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'ivmet.equipo_planes', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[equipo_planes] (
        [equipo_plan_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_equipo_planes_id] DEFAULT NEWSEQUENTIALID(),
        [cod_metrica] nvarchar(100) NOT NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [vigente_desde] datetime2(3) NOT NULL,
        [vigente_hasta] datetime2(3) NULL,
        [creado_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_equipo_planes_creado] DEFAULT SYSUTCDATETIME(),
        [creado_por] uniqueidentifier NOT NULL,
        CONSTRAINT [PK_ivmet_equipo_planes] PRIMARY KEY ([equipo_plan_id]),
        CONSTRAINT [FK_ivmet_equipo_planes_equipo] FOREIGN KEY ([cod_metrica])
            REFERENCES [ivmet].[equipos]([cod_metrica]),
        CONSTRAINT [FK_ivmet_equipo_planes_version] FOREIGN KEY ([plan_version_id])
            REFERENCES [ivmet].[plan_versiones]([plan_version_id]),
        CONSTRAINT [FK_ivmet_equipo_planes_usuario] FOREIGN KEY ([creado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_equipo_planes_fechas] CHECK ([vigente_hasta] IS NULL OR [vigente_hasta] > [vigente_desde])
    );
    CREATE UNIQUE INDEX [UX_ivmet_equipo_planes_vigente]
        ON [ivmet].[equipo_planes]([cod_metrica]) WHERE [vigente_hasta] IS NULL;
    CREATE INDEX [IX_ivmet_equipo_planes_fechas]
        ON [ivmet].[equipo_planes]([cod_metrica], [vigente_desde], [vigente_hasta]);
END;

IF OBJECT_ID(N'ivmet.verificaciones', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[verificaciones] (
        [verificacion_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_verificaciones_id] DEFAULT NEWSEQUENTIALID(),
        [client_uuid] uniqueidentifier NOT NULL,
        [payload_hash] binary(32) NOT NULL,
        [cod_metrica] nvarchar(100) NOT NULL,
        [cliente_id] nvarchar(50) NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        [area_id] uniqueidentifier NULL,
        [plan_version_id] uniqueidentifier NOT NULL,
        [capturado_por] uniqueidentifier NOT NULL,
        [subido_por] uniqueidentifier NOT NULL,
        [realizado_at] datetime2(3) NOT NULL,
        [recibido_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_ivmet_verificaciones_recibido] DEFAULT SYSUTCDATETIME(),
        [alcance] nvarchar(20) NOT NULL,
        [veredicto_global] nvarchar(20) NULL,
        [trazabilidad] nvarchar(20) NOT NULL,
        [temperatura_c] decimal(9,3) NULL,
        [humedad_relativa_pct] decimal(9,3) NULL,
        [observaciones] nvarchar(2000) NULL,
        [equipo_snapshot_json] nvarchar(max) NOT NULL,
        [plan_snapshot_json] nvarchar(max) NOT NULL,
        [app_version] nvarchar(50) NULL,
        [dispositivo_id] nvarchar(200) NULL,
        [estado] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_verificaciones_estado] DEFAULT N'ACTIVA',
        [anulada_at] datetime2(3) NULL,
        [anulada_por] uniqueidentifier NULL,
        [motivo_anulacion] nvarchar(1000) NULL,
        CONSTRAINT [PK_ivmet_verificaciones] PRIMARY KEY ([verificacion_id]),
        CONSTRAINT [UQ_ivmet_verificaciones_uuid] UNIQUE ([client_uuid]),
        CONSTRAINT [FK_ivmet_verificaciones_equipo] FOREIGN KEY ([cod_metrica])
            REFERENCES [ivmet].[equipos]([cod_metrica]),
        CONSTRAINT [FK_ivmet_verificaciones_area] FOREIGN KEY ([area_id])
            REFERENCES [ivmet].[areas]([area_id]),
        CONSTRAINT [FK_ivmet_verificaciones_plan] FOREIGN KEY ([plan_version_id])
            REFERENCES [ivmet].[plan_versiones]([plan_version_id]),
        CONSTRAINT [FK_ivmet_verificaciones_capturador] FOREIGN KEY ([capturado_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_verificaciones_subidor] FOREIGN KEY ([subido_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_verificaciones_anulador] FOREIGN KEY ([anulada_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_verificaciones_alcance] CHECK ([alcance] IN (N'complete', N'partial')),
        CONSTRAINT [CK_ivmet_verificaciones_veredicto] CHECK ([veredicto_global] IS NULL OR [veredicto_global] IN (N'pass', N'fail')),
        CONSTRAINT [CK_ivmet_verificaciones_trazabilidad] CHECK ([trazabilidad] IN (N'traceable', N'non_traceable')),
        CONSTRAINT [CK_ivmet_verificaciones_estado] CHECK ([estado] IN (N'ACTIVA', N'ANULADA')),
        CONSTRAINT [CK_ivmet_verificaciones_humedad] CHECK ([humedad_relativa_pct] IS NULL OR ([humedad_relativa_pct] >= 0 AND [humedad_relativa_pct] <= 100)),
        CONSTRAINT [CK_ivmet_verificaciones_equipo_json] CHECK (ISJSON([equipo_snapshot_json]) = 1),
        CONSTRAINT [CK_ivmet_verificaciones_plan_json] CHECK (ISJSON([plan_snapshot_json]) = 1)
    );
    CREATE INDEX [IX_ivmet_verificaciones_historial]
        ON [ivmet].[verificaciones]([cliente_id], [planta_id], [cod_metrica], [realizado_at] DESC);
END;

IF OBJECT_ID(N'ivmet.verificacion_patrones', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[verificacion_patrones] (
        [verificacion_id] uniqueidentifier NOT NULL,
        [patron_id] uniqueidentifier NOT NULL,
        [certificado_id] uniqueidentifier NOT NULL,
        [rol] nvarchar(30) NOT NULL,
        [snapshot_json] nvarchar(max) NOT NULL,
        CONSTRAINT [PK_ivmet_verificacion_patrones] PRIMARY KEY ([verificacion_id], [patron_id], [rol]),
        CONSTRAINT [FK_ivmet_verificacion_patrones_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [ivmet].[verificaciones]([verificacion_id]),
        CONSTRAINT [FK_ivmet_verificacion_patrones_patron] FOREIGN KEY ([patron_id])
            REFERENCES [ivmet].[patrones]([patron_id]),
        CONSTRAINT [FK_ivmet_verificacion_patrones_certificado] FOREIGN KEY ([certificado_id])
            REFERENCES [ivmet].[patron_certificados]([certificado_id]),
        CONSTRAINT [CK_ivmet_verificacion_patrones_json] CHECK (ISJSON([snapshot_json]) = 1)
    );
END;

IF OBJECT_ID(N'ivmet.pruebas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[pruebas] (
        [prueba_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_pruebas_id] DEFAULT NEWSEQUENTIALID(),
        [verificacion_id] uniqueidentifier NOT NULL,
        [plan_prueba_id] uniqueidentifier NOT NULL,
        [tipo] nvarchar(30) NOT NULL,
        [estado_ejecucion] nvarchar(20) NOT NULL,
        [motivo_omision] nvarchar(1000) NULL,
        [metodo_evaluacion] nvarchar(60) NOT NULL,
        [unidad] nvarchar(20) NOT NULL,
        [tolerancia] decimal(19,9) NULL,
        [veredicto] nvarchar(20) NULL,
        [error_max_abs] decimal(19,9) NULL,
        [media] decimal(19,9) NULL,
        [desviacion_estandar] decimal(19,9) NULL,
        [rango] decimal(19,9) NULL,
        [observaciones] nvarchar(1000) NULL,
        CONSTRAINT [PK_ivmet_pruebas] PRIMARY KEY ([prueba_id]),
        CONSTRAINT [UQ_ivmet_pruebas_tipo] UNIQUE ([verificacion_id], [tipo]),
        CONSTRAINT [FK_ivmet_pruebas_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [ivmet].[verificaciones]([verificacion_id]),
        CONSTRAINT [FK_ivmet_pruebas_plan] FOREIGN KEY ([plan_prueba_id])
            REFERENCES [ivmet].[plan_pruebas]([plan_prueba_id]),
        CONSTRAINT [CK_ivmet_pruebas_tipo] CHECK ([tipo] IN (N'eccentricity', N'repeatability', N'linearity')),
        CONSTRAINT [CK_ivmet_pruebas_estado] CHECK ([estado_ejecucion] IN (N'performed', N'omitted')),
        CONSTRAINT [CK_ivmet_pruebas_veredicto] CHECK ([veredicto] IS NULL OR [veredicto] IN (N'pass', N'fail')),
        CONSTRAINT [CK_ivmet_pruebas_omision] CHECK (
            ([estado_ejecucion] = N'performed' AND [motivo_omision] IS NULL AND [veredicto] IS NOT NULL) OR
            ([estado_ejecucion] = N'omitted' AND LEN(LTRIM(RTRIM([motivo_omision]))) > 0 AND [veredicto] IS NULL)
        )
    );
END;

IF OBJECT_ID(N'ivmet.lecturas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[lecturas] (
        [lectura_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_lecturas_id] DEFAULT NEWSEQUENTIALID(),
        [prueba_id] uniqueidentifier NOT NULL,
        [plan_punto_id] uniqueidentifier NOT NULL,
        [grupo] int NOT NULL,
        [orden] int NOT NULL,
        [punto_codigo] nvarchar(100) NOT NULL,
        [etiqueta] nvarchar(200) NOT NULL,
        [carga_nominal] decimal(19,9) NOT NULL,
        [indicacion] decimal(19,9) NOT NULL,
        [retorno_cero] decimal(19,9) NULL,
        [error] decimal(19,9) NOT NULL,
        [tolerancia] decimal(19,9) NOT NULL,
        [veredicto] nvarchar(20) NOT NULL,
        [metadata_json] nvarchar(max) NULL,
        CONSTRAINT [PK_ivmet_lecturas] PRIMARY KEY ([lectura_id]),
        CONSTRAINT [UQ_ivmet_lecturas_orden] UNIQUE ([prueba_id], [orden]),
        CONSTRAINT [FK_ivmet_lecturas_prueba] FOREIGN KEY ([prueba_id])
            REFERENCES [ivmet].[pruebas]([prueba_id]),
        CONSTRAINT [FK_ivmet_lecturas_punto] FOREIGN KEY ([plan_punto_id])
            REFERENCES [ivmet].[plan_puntos]([plan_punto_id]),
        CONSTRAINT [CK_ivmet_lecturas_veredicto] CHECK ([veredicto] IN (N'pass', N'fail')),
        CONSTRAINT [CK_ivmet_lecturas_valores] CHECK ([grupo] > 0 AND [orden] > 0 AND [tolerancia] >= 0),
        CONSTRAINT [CK_ivmet_lecturas_metadata] CHECK ([metadata_json] IS NULL OR ISJSON([metadata_json]) = 1)
    );
END;

IF OBJECT_ID(N'ivmet.alertas', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[alertas] (
        [alerta_id] uniqueidentifier NOT NULL
            CONSTRAINT [DF_ivmet_alertas_id] DEFAULT NEWSEQUENTIALID(),
        [verificacion_id] uniqueidentifier NOT NULL,
        [cliente_id] nvarchar(50) NOT NULL,
        [planta_id] nvarchar(50) NOT NULL,
        [cod_metrica] nvarchar(100) NOT NULL,
        [tipo] nvarchar(30) NOT NULL,
        [resumen] nvarchar(1000) NOT NULL,
        [estado_cliente] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_alertas_cliente] DEFAULT N'open',
        [visibilidad_metrica] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_alertas_visibilidad] DEFAULT N'private',
        [compartida_at] datetime2(3) NULL,
        [compartida_por] uniqueidentifier NULL,
        [mensaje_compartido] nvarchar(1000) NULL,
        [estado_metrica] nvarchar(20) NOT NULL CONSTRAINT [DF_ivmet_alertas_metrica] DEFAULT N'not_shared',
        [reconocida_at] datetime2(3) NULL,
        [reconocida_por] uniqueidentifier NULL,
        [atendida_at] datetime2(3) NULL,
        [atendida_por] uniqueidentifier NULL,
        [nota_atencion] nvarchar(1000) NULL,
        [creado_at] datetime2(3) NOT NULL CONSTRAINT [DF_ivmet_alertas_creado] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_ivmet_alertas] PRIMARY KEY ([alerta_id]),
        CONSTRAINT [UQ_ivmet_alertas_verificacion] UNIQUE ([verificacion_id]),
        CONSTRAINT [FK_ivmet_alertas_verificacion] FOREIGN KEY ([verificacion_id])
            REFERENCES [ivmet].[verificaciones]([verificacion_id]),
        CONSTRAINT [FK_ivmet_alertas_compartidor] FOREIGN KEY ([compartida_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_alertas_reconocedor] FOREIGN KEY ([reconocida_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [FK_ivmet_alertas_atendedor] FOREIGN KEY ([atendida_por])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_alertas_tipo] CHECK ([tipo] IN (N'test_failed', N'non_traceable', N'both')),
        CONSTRAINT [CK_ivmet_alertas_cliente] CHECK ([estado_cliente] IN (N'open', N'archived')),
        CONSTRAINT [CK_ivmet_alertas_visibilidad] CHECK ([visibilidad_metrica] IN (N'private', N'shared')),
        CONSTRAINT [CK_ivmet_alertas_metrica] CHECK ([estado_metrica] IN (N'not_shared', N'pending', N'acknowledged', N'attended'))
    );
    CREATE INDEX [IX_ivmet_alertas_cliente]
        ON [ivmet].[alertas]([cliente_id], [planta_id], [estado_cliente], [creado_at] DESC);
    CREATE INDEX [IX_ivmet_alertas_metrica]
        ON [ivmet].[alertas]([visibilidad_metrica], [estado_metrica], [creado_at] DESC);
END;

IF OBJECT_ID(N'ivmet.auditoria', N'U') IS NULL
BEGIN
    CREATE TABLE [ivmet].[auditoria] (
        [auditoria_id] bigint IDENTITY(1,1) NOT NULL,
        [actor_id] uniqueidentifier NULL,
        [cliente_id] nvarchar(50) NULL,
        [entidad] nvarchar(80) NOT NULL,
        [entidad_id] nvarchar(150) NOT NULL,
        [accion] nvarchar(80) NOT NULL,
        [antes_json] nvarchar(max) NULL,
        [despues_json] nvarchar(max) NULL,
        [ip] nvarchar(64) NULL,
        [dispositivo_id] nvarchar(200) NULL,
        [creado_at] datetime2(3) NOT NULL CONSTRAINT [DF_ivmet_auditoria_creado] DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_ivmet_auditoria] PRIMARY KEY ([auditoria_id]),
        CONSTRAINT [FK_ivmet_auditoria_actor] FOREIGN KEY ([actor_id])
            REFERENCES [ivmet].[usuarios]([usuario_id]),
        CONSTRAINT [CK_ivmet_auditoria_antes] CHECK ([antes_json] IS NULL OR ISJSON([antes_json]) = 1),
        CONSTRAINT [CK_ivmet_auditoria_despues] CHECK ([despues_json] IS NULL OR ISJSON([despues_json]) = 1)
    );
    CREATE INDEX [IX_ivmet_auditoria_entidad]
        ON [ivmet].[auditoria]([entidad], [entidad_id], [creado_at] DESC);
END;

COMMIT TRANSACTION;

/* Una version publicada conserva para siempre su definicion y sus puntos. */
EXEC(N'
CREATE OR ALTER TRIGGER [ivmet].[TR_ivmet_plan_version_inmutable]
ON [ivmet].[plan_versiones]
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS (
    SELECT 1 FROM inserted i JOIN deleted d ON d.plan_version_id=i.plan_version_id
    WHERE d.estado=N''BORRADOR'' AND i.estado NOT IN (N''BORRADOR'',N''PUBLICADO'')
  ) THROW 52206, ''Un borrador solo puede permanecer borrador o publicarse.'', 1;
  IF EXISTS (
    SELECT 1 FROM inserted i JOIN deleted d ON d.plan_version_id=i.plan_version_id
    WHERE d.estado=N''BORRADOR'' AND i.estado=N''PUBLICADO'' AND (
      NULLIF(LTRIM(RTRIM(i.procedimiento_referencia)),N'''') IS NULL
      OR i.publicado_at IS NULL OR i.publicado_por IS NULL
      OR NOT EXISTS (SELECT 1 FROM ivmet.plan_pruebas t WHERE t.plan_version_id=i.plan_version_id)
      OR EXISTS (SELECT 1 FROM ivmet.plan_pruebas t WHERE t.plan_version_id=i.plan_version_id
        AND NOT EXISTS (SELECT 1 FROM ivmet.plan_puntos p WHERE p.plan_prueba_id=t.plan_prueba_id))
    )
  ) THROW 52207, ''No se puede publicar una version incompleta.'', 1;
  IF EXISTS (
    SELECT 1 FROM inserted i JOIN deleted d ON d.plan_version_id=i.plan_version_id
    WHERE d.estado IN (N''PUBLICADO'',N''RETIRADO'') AND NOT (
      d.estado=N''PUBLICADO'' AND i.estado=N''RETIRADO''
      AND i.plan_id=d.plan_id AND i.version=d.version
      AND ISNULL(i.procedimiento_referencia,N'''')=ISNULL(d.procedimiento_referencia,N'''')
      AND ISNULL(i.notas,N'''')=ISNULL(d.notas,N'''')
      AND i.creado_at=d.creado_at AND i.creado_por=d.creado_por
      AND ISNULL(i.publicado_at,''19000101'')=ISNULL(d.publicado_at,''19000101'')
      AND ISNULL(i.publicado_por,''00000000-0000-0000-0000-000000000000'')=ISNULL(d.publicado_por,''00000000-0000-0000-0000-000000000000'')
    )
  ) THROW 52201, ''Una version publicada es inmutable; solo puede retirarse.'', 1;
END');

EXEC(N'
CREATE OR ALTER TRIGGER [ivmet].[TR_ivmet_plan_pruebas_borrador]
ON [ivmet].[plan_pruebas]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS (SELECT 1 FROM inserted x JOIN ivmet.plan_versiones v ON v.plan_version_id=x.plan_version_id WHERE v.estado<>N''BORRADOR'')
    OR EXISTS (SELECT 1 FROM deleted x JOIN ivmet.plan_versiones v ON v.plan_version_id=x.plan_version_id WHERE v.estado<>N''BORRADOR'')
    THROW 52202, ''Las pruebas de una version publicada o retirada son inmutables.'', 1;
END');

EXEC(N'
CREATE OR ALTER TRIGGER [ivmet].[TR_ivmet_plan_puntos_borrador]
ON [ivmet].[plan_puntos]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS (SELECT 1 FROM inserted x JOIN ivmet.plan_pruebas p ON p.plan_prueba_id=x.plan_prueba_id JOIN ivmet.plan_versiones v ON v.plan_version_id=p.plan_version_id WHERE v.estado<>N''BORRADOR'')
    OR EXISTS (SELECT 1 FROM deleted x JOIN ivmet.plan_pruebas p ON p.plan_prueba_id=x.plan_prueba_id JOIN ivmet.plan_versiones v ON v.plan_version_id=p.plan_version_id WHERE v.estado<>N''BORRADOR'')
    THROW 52203, ''Los puntos de una version publicada o retirada son inmutables.'', 1;
END');

EXEC(N'
CREATE OR ALTER TRIGGER [ivmet].[TR_ivmet_verificacion_inmutable]
ON [ivmet].[verificaciones]
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;
  IF UPDATE(client_uuid) OR UPDATE(payload_hash) OR UPDATE(cod_metrica)
    OR UPDATE(cliente_id) OR UPDATE(planta_id) OR UPDATE(area_id)
    OR UPDATE(plan_version_id) OR UPDATE(capturado_por) OR UPDATE(subido_por)
    OR UPDATE(realizado_at) OR UPDATE(recibido_at) OR UPDATE(alcance)
    OR UPDATE(veredicto_global) OR UPDATE(trazabilidad) OR UPDATE(temperatura_c)
    OR UPDATE(humedad_relativa_pct) OR UPDATE(observaciones)
    OR UPDATE(equipo_snapshot_json) OR UPDATE(plan_snapshot_json)
    OR UPDATE(app_version) OR UPDATE(dispositivo_id)
    THROW 52204, ''La evidencia aceptada es inmutable.'', 1;
  IF EXISTS (
    SELECT 1 FROM inserted i JOIN deleted d ON d.verificacion_id=i.verificacion_id
    WHERE NOT (d.estado=N''ACTIVA'' AND i.estado=N''ANULADA''
      AND i.anulada_at IS NOT NULL AND i.anulada_por IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(i.motivo_anulacion)),N'''') IS NOT NULL)
  ) THROW 52205, ''La unica transicion permitida es anular con responsable y motivo.'', 1;
END');

SELECT [s].[name] AS [esquema], [t].[name] AS [tabla]
FROM [sys].[tables] AS [t]
JOIN [sys].[schemas] AS [s] ON [s].[schema_id] = [t].[schema_id]
WHERE [s].[name] = N'ivmet'
ORDER BY [t].[name];

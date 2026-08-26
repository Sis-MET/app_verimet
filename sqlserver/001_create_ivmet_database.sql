/*
  IvMET SQL Server - 001
  Crea la base corporativa independiente. Ejecutar conectado a master con una
  cuenta DBA. No crea ni modifica objetos en DataMET.
*/

USE [master];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @product_major_version int = TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion'));
IF @product_major_version IS NULL OR @product_major_version < 13
    THROW 52999, 'IvMET requiere SQL Server 2016 SP1 o superior.', 1;

IF DB_ID(N'IvMET') IS NULL
BEGIN
    PRINT N'Creando base [IvMET]...';
    CREATE DATABASE [IvMET];
END
ELSE
    PRINT N'La base [IvMET] ya existe; se conserva.';
GO

ALTER DATABASE [IvMET] SET AUTO_CLOSE OFF;
ALTER DATABASE [IvMET] SET AUTO_SHRINK OFF;
ALTER DATABASE [IvMET] SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE [IvMET] SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE [IvMET] SET READ_COMMITTED_SNAPSHOT ON;
IF (SELECT [compatibility_level] FROM sys.databases WHERE [name] = N'IvMET') < 130
    ALTER DATABASE [IvMET] SET COMPATIBILITY_LEVEL = 130;
GO

USE [IvMET];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'mirror') IS NULL
    EXEC(N'CREATE SCHEMA [mirror] AUTHORIZATION [dbo]');
IF SCHEMA_ID(N'sync') IS NULL
    EXEC(N'CREATE SCHEMA [sync] AUTHORIZATION [dbo]');
GO

IF OBJECT_ID(N'dbo.schema_versions', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[schema_versions] (
        [version] varchar(30) NOT NULL,
        [description] nvarchar(300) NOT NULL,
        [applied_at] datetime2(3) NOT NULL
            CONSTRAINT [DF_schema_versions_applied_at] DEFAULT SYSUTCDATETIME(),
        [applied_by] sysname NOT NULL
            CONSTRAINT [DF_schema_versions_applied_by] DEFAULT ORIGINAL_LOGIN(),
        CONSTRAINT [PK_schema_versions] PRIMARY KEY ([version])
    );
END;

IF NOT EXISTS (SELECT 1 FROM [dbo].[schema_versions] WHERE [version] = '001')
    INSERT INTO [dbo].[schema_versions] ([version], [description])
    VALUES ('001', N'Creacion de base IvMET y esquemas mirror/sync');
GO

SELECT
    DB_NAME() AS [database_name],
    d.compatibility_level,
    d.is_read_committed_snapshot_on,
    d.snapshot_isolation_state_desc,
    d.page_verify_option_desc
FROM sys.databases d
WHERE d.name = DB_NAME();
GO

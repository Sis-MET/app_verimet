# SQL Server corporativo: base `IvMET`

Estos son los scripts del paso 1 para preparar la nueva base corporativa. La
fuente principal de IvMET sigue siendo Supabase; SQL Server recibe una
proyeccion tipada y auditable. `DataMET` solo se consulta.

La entrega del 31/08/2026 deja de exportar evidencia y configuración privada.
Las tablas antiguas se conservan con acceso operativo denegado; solo se
proyectan casos y actualizaciones de balanzas autorizados.
Para actualizar una instalación existente usar la
[guía coordinada](../docs/customer-configuration-release.md), no repetir 001–008.

## Que crea cada script

| Orden | Archivo | Base afectada | Proposito |
| --- | --- | --- | --- |
| 1 | `001_create_ivmet_database.sql` | `master` / `IvMET` | Crea la base, opciones seguras y esquemas `mirror` y `sync`. |
| 2 | `002_sync_control.sql` | `IvMET` | Checkpoints, ejecuciones, fallos, cuarentena, leases y eventos idempotentes. |
| 3 | `003_mirror_catalog_commercial.sql` | `IvMET` | Espejo de clientes, plantas, equipos, usuarios, contratos, pagos y licencias. |
| 4 | `004_mirror_metrology.sql` | `IvMET` | Espejo de patrones, planes, verificaciones, lecturas, alertas y auditoria. |
| 5 | `005_sync_procedures.sql` | `IvMET` | Procedimientos transaccionales usados por el worker. |
| 6 | `006_permissions_ivmet.sql` | `IvMET` | Usuario y rol de minimo privilegio para el worker. |
| 7 | `007_datamet_read_permissions.sql` | `DataMET` | Solo crea el usuario y concede `SELECT` sobre cuatro tablas legadas. |
| 8 | `008_validate_ivmet.sql` | `IvMET` | Verifica versiones, tablas, constraints, procedimientos y permisos. |
| 9 | `009_shared_cases_privacy.sql` | `IvMET` | Proyección de casos consentidos, campos de versiones y aislamiento de evidencia antigua. |
| 10 | `010_validate_privacy.sql` | `IvMET` | Comprueba los permisos de privacidad sin consultar resultados. |
| 11 | `011_customer_configuration_privacy.sql` | `IvMET` | Espejo de fichas consentidas y denegación operativa de áreas, patrones y planes privados. |

Los archivos antiguos `backend/sql/010_ivmet_schema.sql` y
`backend/sql/011_ivmet_permissions.sql` pertenecen a la arquitectura anterior,
que intentaba montar IvMET dentro de `DataMET` y usar `ServiceMET`. **No deben
ejecutarse.**

## Antes de ejecutar

1. Hacer backup de `DataMET` y probar primero en una copia o ambiente de staging.
2. Ejecutar con una cuenta DBA desde SSMS o `sqlcmd`; los archivos contienen
   separadores `GO`.
3. Confirmar que la instancia sea SQL Server 2016 SP1 o superior. Se requiere
   compatibilidad 130 como minimo por las validaciones JSON.
4. Confirmar que las tablas legadas están en `dbo` y se llaman exactamente
   `DATA_CLIENTES`, `DATA_PLANTAS`, `DATA_EQUIPOS` y
   `DATA_EQUIPOS_BALANZAS`.
5. No guardar la contraseña SQL en Git, capturas, scripts ni historial de shell.

## Ejecucion exacta

### 1. Crear la base

Abrir y ejecutar `001_create_ivmet_database.sql` con una cuenta DBA.

### 2. Crear el login del worker

Generar una contraseña larga en el gestor de secretos y ejecutar manualmente,
reemplazando el marcador localmente:

```sql
USE [master];
GO
CREATE LOGIN [IvMETWorker]
WITH PASSWORD = N'REEMPLAZAR_EN_EL_MOMENTO_DE_EJECUTAR',
     CHECK_POLICY = ON,
     CHECK_EXPIRATION = OFF,
     DEFAULT_DATABASE = [IvMET];
GO
```

Si la politica de la empresa exige expiracion, puede activarse, pero la rotacion
debe coordinarse con el secreto del worker para evitar detener la sincronizacion.

### 3. Crear las tablas y procedimientos

Ejecutar, en este orden:

1. `002_sync_control.sql`
2. `003_mirror_catalog_commercial.sql`
3. `004_mirror_metrology.sql`
4. `005_sync_procedures.sql`
5. `006_permissions_ivmet.sql`
6. `007_datamet_read_permissions.sql`
7. `008_validate_ivmet.sql`

El último resultado de `008_validate_ivmet.sql` debe mostrar:

```text
worker_can_select_mirror       1
worker_can_insert_mirror       1
worker_can_delete_verification 0
worker_can_alter_mirror        0
result                         VALIDACION_IVMET_OK
```

## Alternativa con `sqlcmd`

Desde PowerShell, ajustando instancia y autenticacion:

```powershell
$sqlInstance = 'SERVIDOR\INSTANCIA'
$scriptRoot = 'C:\ruta\IvMET\sqlserver'

sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\001_create_ivmet_database.sql"
# Crear aqui el login IvMETWorker con SSMS o un canal seguro.
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\002_sync_control.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\003_mirror_catalog_commercial.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\004_mirror_metrology.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\005_sync_procedures.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\006_permissions_ivmet.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\007_datamet_read_permissions.sql"
sqlcmd -S $sqlInstance -E -b -i "$scriptRoot\008_validate_ivmet.sql"
```

`-b` hace que `sqlcmd` termine con error si cualquiera de los scripts falla. No
continues al siguiente archivo hasta corregir el error actual. Los valores
`datetime2(3)` del espejo deben escribirse siempre en UTC.

## Limites de este paso

Estos scripts preparan las bases y permisos. Todavia no copian datos ni ejecutan
la sincronizacion. El siguiente paso es implementar el worker, que seleccionara
en `DataMET` solamente el alcance contratado en RimMET y consumira el outbox de
Supabase en orden.

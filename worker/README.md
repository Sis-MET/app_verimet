# IvMET Worker

Proceso corporativo que sincroniza, sin conexiones entrantes hacia Metrica:

```text
DataMET (solo SELECT) -> Supabase (fuente principal) -> SQL Server IvMET (espejo)
```

El worker no pertenece a Flutter ni a una Edge Function. Debe ejecutarse dentro
de la red de Metrica, donde puede abrir conexiones salientes a Supabase y leer
las dos bases SQL Server.

## Protecciones incluidas

- [Guía vigente de producción](../docs/onboarding-production.md): sustituye el
  recorrido manual del piloto. Las altas normales se gestionan desde RimMET.
- `WORKER_ENABLED=false` bloquea la sincronización; `health` es estrictamente
  de lectura. Un arranque de daemon bloqueado puede publicar su estado operativo.
- Solo importa alcances registrados en `private.catalog_sync_scope`.
- Relaciona plantas por `cliente_id + codigo_planta`, nunca por `planta_id` solo.
- Relaciona `DATA_EQUIPOS_BALANZAS` por `cod_metrica`; su columna `id` no es fiable.
- Conserva decimales como texto hasta enviarlos a `numeric/decimal`.
- Compara SHA-256 antes de actualizar Supabase.
- Registra inconsistencias en cuarentena tanto en Supabase como en SQL `IvMET`.
- Procesa el outbox estrictamente por secuencia y en una transaccion por evento.
- Un evento repetido se reconoce por `event_id + hash`; no duplica evidencia.
- Un evento `DEAD` bloquea secuencias posteriores hasta intervención administrativa.
- La cola reclama cada alcance con lease renovable; recupera caídas y reintenta
  automáticamente con espera progresiva. Outbox conserva su lease global.
- El daemon de producción exige `WORKER_SCOPE_ID` vacío: todas las solicitudes
  autorizadas, nunca todos los datos maestros.

## 1. Aplicar el contrato Supabase

Aplicar todas las migraciones pendientes, incluida la versión de cola:

```text
supabase/migrations/202608270004_onboarding_queue.sql
```

Con una cuenta propietaria del proyecto:

```powershell
pnpm dlx supabase migration list
pnpm dlx supabase db push --linked --dry-run
pnpm dlx supabase db push --linked
pnpm dlx supabase db lint --linked --level warning
```

La migracion no expone las tablas `private`. Crea funciones de acceso limitadas
a `service_role`, recuperación de claims abandonados y bloqueo tras eventos
muertos.

## 2. Configurar secretos en el servidor

Desde `worker/`:

```powershell
if (-not (Test-Path -LiteralPath '.env')) { Copy-Item -LiteralPath '.env.example' -Destination '.env' }
```

Editar `.env` exclusivamente en el servidor. Se requieren:

- credenciales `IvMETWorker` para `DataMET` e `IvMET`;
- URL del proyecto Supabase;
- `service_role key` del proyecto;
- un identificador estable y unico para la maquina.

La `service_role key` nunca debe copiarse a Flutter, al navegador de RimMET,
capturas, Git ni logs. Solo el worker y el backend RimMET usan secretos privados.

Antes de continuar, `sqlserver/007_datamet_read_permissions.sql` debe haber sido
ejecutado dentro de `DataMET`; la validacion `008` solo comprueba la base
`IvMET` y no sustituye este permiso.

## 3. Validar sin modificar datos

Mantener inicialmente:

```dotenv
WORKER_ENABLED=false
```

Compilar y ejecutar el chequeo:

```powershell
pnpm install --frozen-lockfile
pnpm worker:build
pnpm worker:health
```

`health` exige simultaneamente:

- `SELECT` y ausencia de `UPDATE` sobre las cuatro tablas de `DataMET`;
- versiones SQL `001-006` y permisos seguros en `IvMET`;
- acceso a las funciones privadas del worker mediante `service_role`.

## 4. Referencia histórica: alcance piloto manual

RimMET ya permite incorporar y ampliar clientes. No usar SQL manual para las
altas de producción. El siguiente ejemplo documenta únicamente el piloto original:

```sql
insert into private.catalog_sync_scope (
  legacy_cliente_id,
  legacy_codigo_cliente,
  solicitado_por
) values (
  123,
  '0123',
  'PILOTO_MANUAL'
)
returning id;
```

Usar el UUID devuelto:

```sql
insert into private.catalog_sync_scope_plants (
  scope_id,
  legacy_codigo_planta,
  requested_by
) values
  ('UUID_DEL_SCOPE', '0123-01', 'PILOTO_MANUAL');

insert into private.catalog_sync_scope_equipments (
  scope_id,
  legacy_cod_metrica,
  requested_by
) values
  ('UUID_DEL_SCOPE', '0123-01-001', 'PILOTO_MANUAL');
```

Configurar temporalmente ese UUID en `WORKER_SCOPE_ID`. Así ninguna otra
solicitud puede entrar en el piloto por accidente.

## 5. Primera sincronizacion controlada

Cambiar únicamente cuando `health` sea satisfactorio:

```dotenv
WORKER_ENABLED=true
WORKER_SCOPE_ID=UUID_DEL_SCOPE
```

Ejecutar por separado:

```powershell
pnpm --filter @ivmet/worker sync:catalog
pnpm --filter @ivmet/worker sync:outbox
```

Revisar antes de continuar:

- `private.sync_runs` y `private.sync_quarantine` en Supabase;
- `sync.runs`, `sync.catalog_quarantine` y `sync.failures` en SQL `IvMET`;
- las filas del cliente piloto en `public.clientes/plantas/equipos`;
- las mismas filas en el esquema SQL `[mirror]`.

## 6. Ejecucion permanente

El repositorio incluye `ecosystem.config.cjs` para el PM2 corporativo:

```powershell
pnpm worker:build
pm2 start worker/ecosystem.config.cjs --only ivmet-worker
pm2 save
pm2 status ivmet-worker
```

Desde la raíz IvMET, cerrar el piloto y retirar `WORKER_SCOPE_ID` antes del daemon
de producción. Mantener `.env` fuera del repositorio y respaldar/rotar logs.
`pm2 save` no instala el inicio automático de Windows: completar la guía de
producción y verificar el reinicio del servidor bajo su cuenta de servicio.

## Comandos

| Comando | Funcion |
| --- | --- |
| `pnpm worker:health` | Verifica conectividad y permisos sin sincronizar. |
| `pnpm --filter @ivmet/worker sync:catalog` | Procesa un alcance vencido DataMET -> Supabase. |
| `pnpm --filter @ivmet/worker sync:outbox` | Ejecuta solo Supabase -> SQL IvMET. |
| `pnpm worker:once` | Procesa un alcance y un lote de outbox una vez (diagnóstico). |
| `pnpm --filter @ivmet/worker start` | Inicia el daemon. |
| `pnpm worker:test` | Ejecuta pruebas unitarias y de contratos. |

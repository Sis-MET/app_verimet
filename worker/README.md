# IvMET Worker

Proceso corporativo que sincroniza, sin conexiones entrantes hacia Metrica:

```text
DataMET (solo SELECT) -> Supabase (fuente principal) -> SQL Server IvMET (espejo)
```

El worker no pertenece a Flutter ni a una Edge Function. Debe ejecutarse dentro
de la red de Metrica, donde puede abrir conexiones salientes a Supabase y leer
las dos bases SQL Server.

## Protecciones incluidas

- `WORKER_ENABLED=false` bloquea toda mutacion y deja disponible solo `health`.
- Solo importa alcances registrados en `private.catalog_sync_scope`.
- Relaciona plantas por `cliente_id + codigo_planta`, nunca por `planta_id` solo.
- Relaciona `DATA_EQUIPOS_BALANZAS` por `cod_metrica`; su columna `id` no es fiable.
- Conserva decimales como texto hasta enviarlos a `numeric/decimal`.
- Compara SHA-256 antes de actualizar Supabase.
- Registra inconsistencias en cuarentena tanto en Supabase como en SQL `IvMET`.
- Procesa el outbox estrictamente por secuencia y en una transaccion por evento.
- Un evento repetido se reconoce por `event_id + hash`; no duplica evidencia.
- Un evento `DEAD` bloquea secuencias posteriores hasta intervención administrativa.
- Los leases evitan dos instancias activas del mismo flujo.

## 1. Aplicar el contrato Supabase

La migracion requerida es:

```text
supabase/migrations/202608260001_worker_contract.sql
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
Copy-Item -LiteralPath '.env.example' -Destination '.env'
```

Editar `.env` exclusivamente en el servidor. Se requieren:

- credenciales `IvMETWorker` para `DataMET` e `IvMET`;
- URL del proyecto Supabase;
- `service_role key` del proyecto;
- un identificador estable y unico para la maquina.

La `service_role key` nunca debe copiarse a Flutter, RimMET, capturas, Git ni
logs. El logger del worker redacta campos sensibles conocidos.

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

## 4. Crear el alcance piloto

Hasta que RimMET tenga la interfaz de gestion, un administrador puede registrar
un solo cliente desde el SQL Editor de Supabase. Sustituir los códigos por los
valores reales aprobados:

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
pm2 start ecosystem.config.cjs
pm2 save
pm2 status ivmet-worker
```

No se debe iniciar el daemon hasta cerrar el piloto y retirar o conservar
conscientemente `WORKER_SCOPE_ID`. El despliegue debe mantener `.env` fuera del
repositorio y respaldar los logs según la política de Metrica.

## Comandos

| Comando | Funcion |
| --- | --- |
| `pnpm worker:health` | Verifica conectividad y permisos sin sincronizar. |
| `pnpm --filter @ivmet/worker sync:catalog` | Ejecuta solo DataMET -> Supabase. |
| `pnpm --filter @ivmet/worker sync:outbox` | Ejecuta solo Supabase -> SQL IvMET. |
| `pnpm worker:once` | Ejecuta ambos sentidos una vez. |
| `pnpm --filter @ivmet/worker start` | Inicia el daemon. |
| `pnpm worker:test` | Ejecuta pruebas unitarias y de contratos. |

# Entrega administrativa de RimMET — 27 de agosto de 2026

El código de interfaz/API está en `C:\Users\jhona\RimMET`. Este repositorio
contiene su contrato transaccional de Supabase y las pruebas de base de datos.
No se modifica ServiceMET ni se despliega la antigua API de `IvMET/backend`.

## Migraciones nuevas

- `202608270001_admin_read.sql`: lecturas por cliente y tablas privadas de
  idempotencia. No concede lecturas administrativas a la app móvil.
- `202608270002_admin_actions.sql`: planes/tarifas, contratos, períodos, pagos,
  cupos, usuarios, licencias, áreas, patrones/certificados, habilitación de equipos,
  incorporación/ampliación selectiva. Refuerza la comprobación efectiva de cupos
  vigentes en la licencia. Conserva las tablas de evidencia y los catálogos.

Requieren las ocho migraciones anteriores, incluida
`202608260002_fix_worker_function_volatility.sql`. Son aditivas y no necesitan
una migración SQL Server: los cambios públicos usan el outbox y el espejo ya
existentes. `private.admin_requests` y los alias de Auth no se exportan como
datos comerciales al espejo.

## Aplicación

Desde una copia validada/proyecto de pruebas, con backup y CLI autenticada:

```powershell
Set-Location C:\Users\jhona\IvMET
pnpm install
pnpm db:test:admin
pnpm dlx supabase db push --linked --dry-run
pnpm dlx supabase db push --linked
pnpm dlx supabase db lint --linked --level warning
```

El usuario confirmó el 27/08 la aplicación de `202608270001` y `202608270002`
y un lint remoto sin errores, después de corregir la autenticación de la CLI.
No usar `migration repair` para simular la aplicación ni `db reset` sobre datos existentes.

**Migración aplicada por el usuario:** `202608270003_generated_plan_codes.sql` genera
códigos comerciales `PLAN-000001` mediante secuencia atómica y los hace
inmutables. Conserva códigos anteriores; la numeración puede tener saltos.
Aplicarla antes del backend/panel que deja de solicitar `code` en `plan.save`.
No necesita migración SQL Server: el código generado viaja por el outbox actual.
Esta migración se valida localmente; no se ejecuta contra Supabase desde la prueba.

**Nueva migración pendiente:** `202608270004_onboarding_queue.sql`. Añade cola
recuperable, detección de worker detenido/restringido, solicitudes dentro de
Clientes y reintento auditado. La puesta en producción completa se describe en
[onboarding-production.md](onboarding-production.md). No reinsertar el cliente
`0103`: su solicitud existente se conserva y queda encolada al aplicar la migración.

Después, reiniciar el backend de RimMET con `IVMET_ENABLED=true` y sus secretos
configurados, y cargar el frontend nuevo. El servidor RimMET usa HTTPS en
producción. El worker corporativo entrega el outbox en su siguiente ciclo; no
se activa ni ejecuta automáticamente desde los formularios.

## Validación

```powershell
pnpm db:test:admin
pnpm worker:test
pnpm worker:build
```

El test administrativo usa PostgreSQL embebido PGlite, con roles/Auth ficticios.
Carga todas las migraciones y comprueba aislamiento, pagos exactos/parciales,
idempotencia, versiones obsoletas, cupos, vencimientos, renovaciones, anulaciones,
patrones, alcance selectivo y denegación de las RPC al rol móvil. La única
adaptación de la pila de prueba es sustituir la extensión pgcrypto (no disponible
en ese runtime) por `gen_random_uuid` del motor; no se reimplementan las reglas
de negocio. Las pruebas unitarias del backend RimMET simulan Auth; falta la
prueba operativa de alta/login/cambio de contraseña con una cuenta de piloto
autorizada después del despliegue.

En RimMET, consultar `docs/ivmet-management.md` para el recorrido completo de
operación y el contrato HTTP. El primer recorrido real será EMBOL `0032`, planta
`0032-11`: plan y tarifa acordados → contrato firmado → pago verificado → usuarios
y plantas → licencias. No inventar importes, pagos ni credenciales productivas.

La gestión administrativa no publica planes metrológicos ni acepta resultados
definitivos. Sigue pendiente el procedimiento oficial y la validación del motor.
El rollback deshabilita el módulo de RimMET y conserva esquema/evidencia.

# Supabase IvMET

Supabase es la fuente principal de IvMET. DataMET conserva la autoridad sobre
los catalogos legados de clientes, plantas y balanzas; la nueva base SQL Server
`IvMET` sera un espejo corporativo alimentado desde la bandeja
`private.sync_outbox`.

La app movil es **online-only**. Guarda borradores en
`public.verificacion_borradores`; no existe una cola offline ni sincronizacion
por lotes desde el dispositivo.

## Orden de migraciones

1. `202608240001_foundation_catalog.sql`: catalogos selectivos y perfiles.
2. `202608240002_commercial_licensing.sql`: contratos, periodos, pagos, cupos y
   licencias por usuario.
3. `202608240003_metrology_online.sql`: planes, borradores, evidencia y alertas.
4. `202608240004_integration_outbox.sql`: alcance selectivo, cuarentena y outbox
   para el espejo SQL Server.
5. `202608240005_rls_and_workflows.sql`: aislamiento por cliente/planta/licencia
   y transiciones protegidas.
6. `202608240006_auth_contract.sql`: login por alias, estado de acceso y cierre
   seguro del cambio obligatorio de contraseña.
7. `202608260001_worker_contract.sql`: funciones privadas para el worker,
   recuperacion de claims abandonados y bloqueo estricto tras eventos muertos.

La operacion y los secretos del worker se documentan en
[`../worker/README.md`](../worker/README.md).

## Validacion local

Se requiere Docker Desktop o un runtime compatible con Docker:

```powershell
pnpm dlx supabase start
pnpm dlx supabase db reset
pnpm dlx supabase test db
```

Las funciones se verifican adicionalmente con Deno:

```powershell
pnpm dlx deno check --no-lock --config supabase/functions/ivmet-login/deno.json supabase/functions/ivmet-login/index.ts
pnpm dlx deno check --no-lock --config supabase/functions/ivmet-change-password/deno.json supabase/functions/ivmet-change-password/index.ts
```

## Proyecto remoto de desarrollo

No aplicar primero en produccion. Crear o elegir un proyecto Supabase de
desarrollo y ejecutar:

```powershell
pnpm dlx supabase login
pnpm dlx supabase link --project-ref <PROJECT_REF_DEV>
pnpm dlx supabase db push --dry-run
pnpm dlx supabase db push
pnpm dlx supabase functions deploy ivmet-login
pnpm dlx supabase functions deploy ivmet-change-password
```

Las claves secretas y `SUPABASE_SERVICE_ROLE_KEY` nunca se incluyen en Flutter,
RimMET ni Git. Las Edge Functions las reciben del entorno administrado por
Supabase.

## Bloqueo metrologico deliberado

Todavia no existe una funcion que acepte definitivamente una verificacion. El
motor debe implementarse despues de recibir el procedimiento oficial y sus
casos dorados aprobados por el metrologo. Hasta entonces solo se habilitan
borradores online; la evidencia final no tiene permisos de escritura desde la
app.

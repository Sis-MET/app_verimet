# Supabase IvMET

Supabase es la fuente principal de IvMET. DataMET conserva la autoridad sobre
los catalogos legados de clientes, plantas y balanzas; la nueva base SQL Server
`IvMET` sera un espejo corporativo alimentado desde la bandeja
`private.sync_outbox`.

Desde la entrega del 31/08/2026 el espejo **excluye resultados y configuración
privada**. Solo recibe expedientes o fichas concretas con consentimiento
explícito. Seguir la [guía de configuración y despliegue coordinado](../docs/customer-configuration-release.md)
antes de actualizar un servidor existente.

La app movil es **online-only**. Guarda borradores en
`public.verificacion_borradores`; no existe una cola offline ni sincronizacion
por lotes desde el dispositivo.

La primera entrega móvil usa la migración `202608280003_mobile_online_contract.sql`
y las funciones `ivmet-login` / `ivmet-change-password`.
Ver [activación de la app](../docs/mobile-online-release.md) y
[contrato móvil](../docs/mobile-online-api.md) y
[motor de comprobaciones internas](../docs/normative-metrology-engine.md).

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
8. `202608260002_fix_worker_function_volatility.sql`: volatilidad compatible con
   consultas de bloqueo del worker.
9. `202608270001_admin_read.sql`: lecturas administrativas por cliente para RimMET.
10. `202608270002_admin_actions.sql`: contratación, pagos, licencias, usuarios,
    configuración y ampliación del alcance, con auditoría/idempotencia.
11. `202608270003_generated_plan_codes.sql`: códigos de planes autogenerados e
    inmutables; conserva los códigos existentes. Aplicar antes del panel actualizado.
12. `202608270004_onboarding_queue.sql`: cola recuperable de incorporaciones,
    disponibilidad del worker y seguimiento inmediato en el directorio.
13. `202608280001_private_evidence_and_cases.sql`: bloqueo de exportación privada,
    expedientes consentidos, vista previa/confirmación y retirada.
14. `202608280002_management_operations.sql`: permisos internos, casos, borradores
    metrológicos, preparación/cobros/auditoría y contrato de worker versión 3.
15. `202608280003_mobile_online_contract.sql`: sesión, catálogos, borradores e
    historial para la aplicación online.
16. `202608280004_customer_configuration.sql`: áreas, patrones, certificados y
    planes administrados por el cliente; validación de balanzas, consentimiento
    de fichas y contrato del worker versión 4.
17. `202608310001_normative_metrology_engine.sql`: perfiles controlados,
    reglas de decisión, cálculo transaccional, finalización idempotente,
    vencimientos por prueba y evidencia inmutable de control interno.

`202609150001_customer_registered_equipment.sql` agrega las balanzas que
registra el cliente: privadas, fuera del espejo SQL Server y ocultas para
RimMET salvo envío autorizado. Ver
[Balanzas registradas por el cliente](../docs/customer-registered-equipment.md).

Para pasar del piloto a operación continua, seguir
[Incorporación automática en producción](../docs/onboarding-production.md).

La puesta en marcha de estas migraciones administrativas se documenta en
[la entrega de Gestión IvMET](../docs/rimmet-management-release.md).
Pruebas SQL administrativas aisladas, sin Docker ni claves: `pnpm db:test:admin`.

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
el navegador de RimMET ni Git. Solo el backend RimMET y el worker pueden
configurarlas en su entorno privado. Las Edge Functions las reciben del entorno
administrado por Supabase.

## Alcance metrológico

La función `ivmet_mobile_finalize_draft` acepta únicamente planes publicados
con un perfil controlado. Calcula en PostgreSQL y nunca confía en un resultado
enviado por la app. El alcance declarado es `INTERNAL_CHECK_ONLY`: no emite
certificados ni afirma acreditación. Toda nueva fórmula requiere versión de
motor y pruebas doradas, sin alterar resultados históricos.

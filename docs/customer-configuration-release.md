# Configuración del cliente y autorización de datos

Entrega del 31/08/2026. Esta guía sustituye, para esta actualización, las
instrucciones de contrato 3. No ejecuta despliegues automáticamente.

## Resultado funcional

- DataMET continúa siendo el catálogo maestro de clientes, plantas y balanzas,
  y el worker solo tiene permisos de lectura sobre sus cuatro tablas.
- Métrica habilita clientes, plantas, balanzas, contratos, licencias y usuarios
  desde RimMET. Ya no crea áreas, patrones ni planes metrológicos del cliente.
- El cliente administra en la app sus áreas por planta, patrones y certificados.
  El jefe de calidad configura las comprobaciones desde cada balanza; la app
  crea y asigna la versión interna automáticamente.
- `Ubicación` sugiere áreas ignorando mayúsculas, acentos y espacios repetidos.
  La sugerencia nunca altera automáticamente la ficha.
- Cada balanza debe validarse contra la revisión actual del catálogo antes de
  iniciar un borrador nuevo. Una actualización posterior de DataMET invalida la
  confirmación, pero conserva las correcciones privadas para volver a revisarlas.
- Las correcciones permanecen en Supabase. Solo el jefe de calidad puede abrir
  la vista previa, confirmar el snapshot exacto y autorizar una ficha concreta
  para Métrica. Los cambios posteriores requieren otra autorización.
- RimMET recibe una bandeja de actualizaciones autorizadas. Marcar una como
  revisada agrega un comentario visible al cliente, pero no escribe en DataMET.
- Configuraciones, patrones, certificados, áreas y resultados privados no se exportan a
  SQL Server. SQL `IvMET` recibe únicamente la actualización expresamente
  compartida y conserva el recibo histórico si después se retira el acceso.

Actualización: las migraciones `202608310001_normative_metrology_engine.sql` y
`202608310002_equipment_check_configuration.sql` incorporan el motor y la
configuración guiada por equipo. Su alcance y las validaciones previas al piloto se documentan en
[Motor metrológico](normative-metrology-engine.md).

## Componentes de la entrega

- Supabase: `202608280004_customer_configuration.sql`, motor
  `202608310001_normative_metrology_engine.sql` y configuración guiada
  `202608310002_equipment_check_configuration.sql`; contrato del worker 4.
- SQL Server `IvMET`: `011_customer_configuration_privacy.sql`.
- Worker: allowlist reducida, revalidación de autorizaciones y health de
  privacidad/configuración.
- Flutter: configuración del cliente, validación de balanzas, comprobaciones
  guiadas por equipo y consentimiento específico.
- RimMET: habilitación comercial/operativa y bandeja de actualizaciones; sin
  editor de áreas, patrones o planes metrológicos.

## Orden de despliegue

Hacer respaldo y validar primero en staging. Mantener Cronograma y ServiceMET
activos; la ventana coordinada afecta únicamente al worker y a Gestión IvMET.

### 1. Preparar artefactos sin desplegar

En el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:admin
pnpm db:test:operations
pnpm db:test:mobile
pnpm worker:test
pnpm worker:build

Set-Location '.\app'
flutter analyze
flutter test
flutter build apk --debug

Set-Location 'C:\Users\jhona\RimMET'
pnpm lint
pnpm test
pnpm --dir backend test
pnpm build
```

### 2. Detener solo el worker en el servidor

```powershell
pm2 stop ivmet-worker
pm2 list
```

No reiniciar `servicemet-api` ni ejecutar `pm2 restart all`.

### 3. Aplicar SQL 011 como DBA

En SSMS, seleccionar la base **IvMET**, no DataMET, y ejecutar
`sqlserver/011_customer_configuration_privacy.sql`. Debe registrar la versión
`011`, crear el espejo consentido y denegar al worker/lector el acceso a áreas,
patrones y planes antiguos. El script no modifica DataMET.

### 4. Aplicar migraciones pendientes de Supabase

Desde `C:\Users\jhona\IvMET` en el equipo de desarrollo:

```powershell
pnpm dlx supabase migration list
pnpm dlx supabase db push --linked --dry-run
pnpm dlx supabase db push --linked
pnpm dlx supabase db lint --linked --level warning
```

El dry-run debe mostrar únicamente las migraciones que aún no existan en el
proyecto enlazado; para esta entrega debe incluir
`202608310002_equipment_check_configuration.sql`. No usar `migration repair`
para simular que se aplicó. Tras el push, el contrato del worker continúa en 4.

### 5. Actualizar RimMET y la app

Publicar el `backend/dist` recién compilado y el backend actualizado de RimMET,
conservando `backend/.env`. Reiniciar solamente:

```powershell
pm2 restart cronomet-api --update-env
```

Distribuir la app únicamente después de configurar URL y clave pública de
Supabase. Nunca incorporar `service_role` al APK.

### 6. Actualizar y arrancar el worker

En `C:\Proyectos\IvMET`, conservar `worker/.env` y actualizar código/lockfiles:

```powershell
pnpm install --frozen-lockfile
pnpm worker:build
pnpm worker:health
```

El health debe mostrar `status=ok`, `supabase.contractVersion=4`,
`ivmet.customerConfigurationReady=true`, `ivmet.privacyReady=true`,
`enabled=true` y `automaticReady=true`. Si falta cualquiera, no iniciar.

```powershell
pm2 restart .\worker\ecosystem.config.cjs --only ivmet-worker --update-env
pm2 logs ivmet-worker --lines 40 --nostream
pm2 save
```

### 7. Piloto funcional

Con un cliente y una planta autorizados, comprobar: sugerencias por planta,
validación de ficha, cambio del catálogo, roles operador/jefe, configuración y
versionado interno por balanza, patrón/certificado, vista previa de la ficha compartida,
retirada del acceso y bandeja de RimMET. Confirmar en SQL `IvMET` que solo llegó
la actualización autorizada y que DataMET no cambió.

## Rollback

Detener el worker y ocultar Gestión IvMET/app si aparece una incompatibilidad.
No revertir permisos, no reactivar un worker de contrato 3 y no eliminar tablas,
recibos ni outbox. Corregir el código y reanudar desde health 4.

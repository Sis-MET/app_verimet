# IvMET

**Verificaciones intermedias de instrumentos de pesaje** — Metrica Ltda.

Monorepo con la app movil Flutter, el backend principal en Supabase y los
componentes de integracion con los servidores de Metrica. Permite a los
clientes ejecutar y registrar verificaciones intermedias de
**excentricidad**, **repetibilidad** y **linealidad** sobre sus balanzas, entre
calibraciones formales.

- Funciona **online-only**: la app requiere Internet y autoguarda borradores en
  Supabase. La captura también conserva un borrador local para recuperarse de
  cierres inesperados, con el paso y las lecturas pendientes.
- Es **multi-tenant**: cada cliente ve solo sus instrumentos y reportes.
- El personal de Métrica solo recibe las **alertas que el jefe de calidad
  comparte expresamente**, junto con su verificación y PDF.
- La app usa HTTPS hacia Supabase. Solo el worker corporativo accede a DataMET
  y a la base SQL Server `IvMET` desde la red de Metrica.
- Cualquier empresa crea su cuenta desde la app y empieza en el plan
  **Gratuito**, con límites de plantas, balanzas, usuarios y verificaciones;
  pide un plan superior desde la app y Métrica lo habilita en RimMET. Ver
  [docs/self-service-plans.md](docs/self-service-plans.md).
- Cada usuario puede eliminar su cuenta, y el jefe su empresa, desde la app o
  desde una página web; la evidencia se conserva sin datos personales. La app
  trae un manual de uso controlado. Ver
  [docs/account-deletion-and-manual.md](docs/account-deletion-and-manual.md).

---

## Estructura

```
IvMET/
├── app/                        App Flutter (proyecto Dart independiente)
├── backend/                    Backend SQL Server anterior, en transicion
├── supabase/                   Migraciones, RLS, tests y Edge Functions
├── sqlserver/                  Base corporativa IvMET y espejo tipado
├── worker/                     Sincronizacion corporativa bidireccional
├── packages/
│   └── shared-contracts/       Enums/DTOs compartidos + OpenAPI
├── docs/
│   ├── architecture.md         Screaming + Clean Architecture (leer primero)
│   ├── backend-implementation-roadmap.md
│   └── app-install-guide.md    Instalar/compilar la app
├── pnpm-workspace.yaml         packages: backend + worker + packages/*
├── package.json                scripts puente para ambos lados
└── .gitignore
```

`app/` **no** forma parte del workspace de pnpm: su gestor de paquetes es `pub`.
`backend`, `worker` y `packages/*` se instalan con `pnpm install` desde la raiz.

> El gestor de paquetes del lado JS es **pnpm**, no npm ni yarn. Esto no es una
> convencion, esta forzado: el script `preinstall` corre `only-allow pnpm` y
> aborta cualquier `npm install` o `yarn install`. El campo `packageManager`
> fija ademas la version, asi que con Corepack activo (`corepack enable`)
> todos usan la misma.

Antes de tocar codigo, leer [docs/architecture.md](docs/architecture.md): explica
por que las carpetas se llaman como se llaman y donde va cada archivo nuevo.

---

## Requisitos

| Herramienta | Version |
| --- | --- |
| Node.js | >= 20 (probado con 24.x) |
| pnpm | >= 10 (probado con 11.x) |
| Flutter | 3.44.x stable (Dart 3.12.x) |
| Supabase CLI | 2.115.x o compatible |
| Docker Desktop | requerido para la pila Supabase local |
| SQL Server | DataMET (solo lectura) + base nueva IvMET |

---

## Backend principal: Supabase

El orden de implementacion y los limites de cada sistema estan documentados en
[docs/backend-implementation-roadmap.md](docs/backend-implementation-roadmap.md).
Las instrucciones para validar y desplegar las migraciones estan en
[supabase/README.md](supabase/README.md).

La gestión comercial y de usuarios vive en el proyecto **RimMET**. Su entrega
administrativa, migraciones y pruebas están descritas en
[docs/rimmet-management-release.md](docs/rimmet-management-release.md).

La sincronizacion selectiva DataMET -> Supabase -> SQL Server `IvMET` se opera
segun [worker/README.md](worker/README.md). Arranca bloqueada con
`WORKER_ENABLED=false` y no abre conexiones entrantes hacia la red corporativa.

Validacion local, una vez instalado Docker Desktop:

```bash
pnpm dlx supabase start
pnpm dlx supabase db reset
pnpm dlx supabase test db
```

`backend/` conserva la implementacion SQL Server anterior durante la
transicion. No es el backend productivo nuevo y no debe desplegarse como una
segunda API movil.

## Workspace Node existente

Instalar dependencias de todo el workspace (desde la raiz):

```bash
pnpm install
```

pnpm bloquea los scripts de instalacion por defecto. Los de `prisma`,
`@prisma/engines`, `@prisma/client` y `bcrypt` estan habilitados en
`pnpm-workspace.yaml` (`allowBuilds`) porque descargan engines y el binding
nativo. Si alguna vez ves `ERR_PNPM_IGNORED_BUILDS`, es que aparecio una
dependencia nueva que necesita permiso: revisala antes de agregarla a esa lista.

Configurar el entorno:

```bash
cp backend/.env.example backend/.env
```

Completar `backend/.env` solo cuando se trabaje en las herramientas corporativas
que requieren SQL Server. Nunca incluir esas credenciales en Flutter o
Supabase.

Generar el cliente de Prisma (la base ya existe, se introspecciona):

```bash
pnpm --filter @ivmet/backend prisma:pull
```

```bash
pnpm --filter @ivmet/backend prisma:generate
```

Levantar en desarrollo (recarga en caliente con `ts-node-dev`):

```bash
pnpm backend:dev
```

Compilar y correr en produccion:

```bash
pnpm backend:build
```

```bash
pnpm backend:start
```

Verificar que responde:

```bash
curl http://localhost:3000/health
```

Otros scripts: `pnpm backend:lint`, `pnpm backend:test`.

---

## App (Flutter)

Instalar dependencias:

```bash
pnpm app:get
```

Generar el codigo de `freezed`, `json_serializable`, `riverpod_generator` y
`drift_dev` (los `*.g.dart` no se commitean):

```bash
pnpm app:gen
```

Correr en un dispositivo. La conexion con Supabase se incrusta al compilar desde
`app/config/supabase.local.json`, creado a partir de `supabase.example.json`:

```bash
pnpm app:run
```

Analizar y testear:

```bash
cd app && flutter analyze
```

```bash
pnpm app:test
```

Compilar el APK o el bundle de distribucion, con `app/config/supabase.prod.json`
y el keystore de IvMET:

```bash
pnpm app:apk
```

```bash
pnpm app:aab
```

Gradle detiene el build si falta la configuracion de Supabase o la firma. El
detalle esta en [docs/app-install-guide.md](docs/app-install-guide.md).

---

## Vocabulario

La app llama **verificación** a lo que hace, sin excepciones: se configuran
verificaciones por balanza, se inician, se finalizan y quedan registradas.

El sustantivo va calificado siempre que pueda confundirse. Lo que hace IvMET es
una **verificación intermedia**: interna, privada y entre calibraciones
formales. No es una **verificación legal** ni un certificado de calibración
acreditada, y los avisos de las pantallas y del informe se apoyan en ese
calificativo para distinguirlas.

Hubo un segundo termino, "comprobación interna", para el acto en curso. Se
retiró: dos palabras para lo mismo obligaban a elegir en cada texto nuevo, y la
distinción real —intermedia frente a legal— la carga el calificativo, no el
sustantivo.

## Separador decimal

Coma hacia la pantalla, punto hacia el servidor.

En planta se escribe con coma, pero el teclado del telefono ofrece el punto: la
entrada acepta los dos —`MeasurementFormat.parse`, `decimalError`— y todo lo
que se muestra sale con coma, incluidas las lecturas que el propio sistema
sugiere. Una lectura tecleada y una sugerida tienen que verse igual.

`normalizedDecimal` pone el punto justo antes de enviar, que es el formato que
espera Supabase. Un test lo fija: la misma lectura vale `45,123456789` en el
borrador y viaja como `44.999999999` en el payload.

La unica excepcion es `EvidenceTree`, la vista del expediente que se va a
enviar. Ahi los valores van crudos, tal y como salen, porque lo que se
consiente es exactamente eso.

---

## Features

La API organiza el dominio en estas features (`snake_case` en Dart,
`kebab-case` en TypeScript). La ultima columna dice donde vive cada una en la
app movil:

| Feature | Que resuelve | En la app |
| --- | --- | --- |
| `auth` | Supabase Auth, sesion, cambio obligatorio de contraseña, alta de empresas y recuperacion por correo. | `online/online_entry.dart`, `online/self_service_access.dart` |
| `instruments` | Balanzas del cliente: listado, detalle, estado. | `online/catalog_screen.dart` |
| `eccentricity_test` | Prueba de excentricidad. | `eccentricity_test/domain/` |
| `repeatability_test` | Prueba de repetibilidad. | `repeatability_test/domain/` |
| `linearity_test` | Prueba de linealidad. | `linearity_test/domain/` |
| `verification_reports` | Historial privado y expedientes compartidos. | `online/history_screen.dart`, `online/verification_report.dart` |
| `clients` | Empresas cliente (tenants), sucursales y areas; plantas y usuarios de las autoregistradas; plan, limites y solicitudes. | `online/customer_configuration.dart`, `online/company_plants.dart`, `online/company_users.dart`, `online/plan_screen.dart` |
| `dashboard` | Resumen operativo del cliente. La gestion interna vive en RimMET. | `online/workspace_screen.dart` |
| `sync` | Integracion servidor a servidor; no existe cola offline movil. | solo servidor |

La app movil **no** espeja esa division en carpetas: todo el flujo con sesion
vive en `app/lib/features/online/`, que habla con Supabase. Hubo un prototipo
que si la espejaba, con datos de demostracion y un cliente HTTP contra la API
antigua por VPN; se retiro al quedar sin ninguna ruta que lo alcanzara.

Lo unico que sobrevive de aquella division son los `domain/usecases/` de las
tres pruebas metrologicas. La app no evalua en el cliente —Supabase recalcula
al finalizar—, asi que se conservan, con sus tests, como especificacion
ejecutable de la matematica que el servidor debe replicar.

---

## Estado actual

La primera base Supabase ya define catalogos selectivos, contratos, licencias,
borradores online, configuraciones internas versionadas, evidencia inmutable, alertas privadas,
RLS y una outbox idempotente para el espejo SQL Server. El login por usuario y
el cambio obligatorio de contraseña estan implementados como Edge Functions.

La finalización de verificaciones intermedias está implementada en Supabase con
configuración guiada por balanza, perfiles internos versionados, trazabilidad,
vencimientos por prueba y casos dorados. Flutter captura borradores y solicita la finalización sin
calcular ni enviar veredictos. El alcance no es calibración acreditada ni
verificación legal. Ver
[docs/normative-metrology-engine.md](docs/normative-metrology-engine.md).

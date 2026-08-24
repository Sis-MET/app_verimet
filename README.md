# IvMET

**Verificaciones intermedias de instrumentos de pesaje** — Metrica Ltda.

Monorepo con la app movil Flutter, el backend principal en Supabase y los
componentes de integracion con los servidores de Metrica. Permite a los
clientes ejecutar y registrar pruebas de
**excentricidad**, **repetibilidad** y **linealidad** sobre sus balanzas, entre
calibraciones formales.

- Funciona **online-only**: la app requiere Internet y autoguarda borradores en
  Supabase.
- Es **multi-tenant**: cada cliente ve solo sus instrumentos y reportes.
- El personal de Métrica solo recibe las **alertas que el jefe de calidad
  comparte expresamente**, junto con su verificación y PDF.
- La app usa HTTPS hacia Supabase. Solo el worker corporativo accede a DataMET
  y a la base SQL Server `IvMET` desde la red de Metrica.

---

## Estructura

```
IvMET/
├── app/                        App Flutter (proyecto Dart independiente)
├── backend/                    Backend SQL Server anterior, en transicion
├── supabase/                   Migraciones, RLS, tests y Edge Functions
├── packages/
│   └── shared-contracts/       Enums/DTOs compartidos + OpenAPI
├── docs/
│   ├── architecture.md         Screaming + Clean Architecture (leer primero)
│   ├── backend-implementation-roadmap.md
│   └── app-install-guide.md    Instalar/compilar la app
├── pnpm-workspace.yaml         packages: backend + packages/*
├── package.json                scripts puente para ambos lados
└── .gitignore
```

`app/` **no** forma parte del workspace de pnpm: su gestor de paquetes es `pub`.
Solo `backend` y `packages/*` se instalan con `pnpm install` desde la raiz.

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

Correr en un dispositivo con la configuracion del proyecto Supabase de
desarrollo:

```bash
cd app && flutter run --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co --dart-define=SUPABASE_ANON_KEY=PUBLIC_KEY
```

Analizar y testear:

```bash
cd app && flutter analyze
```

```bash
pnpm app:test
```

El detalle de firma y build para Play Store esta en
[docs/app-install-guide.md](docs/app-install-guide.md).

---

## Features

Las mismas features existen en la app y en la API (`snake_case` en Dart,
`kebab-case` en TypeScript):

| Feature | Que resuelve |
| --- | --- |
| `auth` | Supabase Auth, sesion y cambio obligatorio de contraseña. |
| `instruments` | Balanzas del cliente: listado, detalle, estado. |
| `eccentricity_test` | Prueba de excentricidad. |
| `repeatability_test` | Prueba de repetibilidad. |
| `linearity_test` | Prueba de linealidad. |
| `verification_reports` | Reportes de verificacion intermedia y su PDF. |
| `clients` | Empresas cliente (tenants), sucursales y areas. |
| `dashboard` | Resumen operativo del cliente. La gestion interna vive en RimMET. |
| `sync` | Integracion servidor a servidor; no existe cola offline movil. |

---

## Estado actual

La primera base Supabase ya define catalogos selectivos, contratos, licencias,
borradores online, planes versionados, evidencia inmutable, alertas privadas,
RLS y una outbox idempotente para el espejo SQL Server. El login por usuario y
el cambio obligatorio de contraseña estan implementados como Edge Functions.

La finalizacion metrologica permanece deliberadamente bloqueada hasta recibir
el procedimiento oficial de Metrica y aprobar sus pruebas doradas. Flutter aun
contiene pantallas/datos demo y debe migrarse despues de estabilizar el contrato
Supabase.

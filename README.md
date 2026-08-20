# IvMET

**Verificaciones intermedias de instrumentos de pesaje** — Metrica Ltda.

Monorepo con la app movil (Flutter) y la API (Node.js + TypeScript + SQL Server)
que permiten a los clientes de Metrica ejecutar y registrar pruebas de
**excentricidad**, **repetibilidad** y **linealidad** sobre sus balanzas, entre
calibraciones formales.

- Funciona **offline-first**: se captura en planta sin señal y se sincroniza despues.
- Es **multi-tenant**: cada cliente ve solo sus instrumentos y reportes.
- El personal de Métrica solo recibe las **alertas que el jefe de calidad
  comparte expresamente**, junto con su verificación y PDF.
- El trafico va por la **VPN corporativa**; la app no gestiona el tunel.

---

## Estructura

```
IvMET/
├── app/                        App Flutter (proyecto Dart independiente)
├── backend/                    API Node.js + TypeScript (Express)
├── packages/
│   └── shared-contracts/       Enums/DTOs compartidos + OpenAPI
├── docs/
│   ├── architecture.md         Screaming + Clean Architecture (leer primero)
│   ├── vpn-install-guide.md    Instalar y conectar la VPN corporativa
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
| SQL Server | instancia de Metrica, alcanzable por VPN |

---

## Backend

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

Completar `backend/.env` con las credenciales de SQL Server y los secretos JWT.
**Requiere la VPN conectada** para llegar a la base.

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

Correr en un dispositivo con la VPN activa:

```bash
cd app && flutter run --dart-define=IVMET_API_BASE_URL=https://api.metrica.local
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
| `auth` | Login, refresh token, sesion. |
| `instruments` | Balanzas del cliente: listado, detalle, estado. |
| `eccentricity_test` | Prueba de excentricidad. |
| `repeatability_test` | Prueba de repetibilidad. |
| `linearity_test` | Prueba de linealidad. |
| `verification_reports` | Reportes de verificacion intermedia y su PDF. |
| `clients` | Empresas cliente (tenants), sucursales y areas. |
| `dashboard` | Vista interna de Metrica sobre todos los clientes. |
| `sync` | Cola offline-first e ingesta por lotes. |

---

## Estado actual

El backend IvMET incluye autenticación con refresh rotativo, aislamiento por
cliente/planta, bootstrap offline, catálogos y planes versionados, sincronización
idempotente, evidencia inmutable, alertas privadas/compartidas, anulación y PDF.
Las migraciones son aditivas y viven en `backend/sql/`.

Por seguridad las rutas y la sincronización se despliegan apagadas. No se debe
activar `IVMET_SYNC_ENABLED` hasta cargar el procedimiento oficial de Métrica y
aprobar sus pruebas doradas. El frontend conserva pantallas demo que deben pasar
a consumir los planes dinámicos entregados por `/api/ivmet/v1/bootstrap`.

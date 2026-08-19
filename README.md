# IvMET

**Verificaciones intermedias de instrumentos de pesaje** — Metrica Ltda.

Monorepo con la app movil (Flutter) y la API (Node.js + TypeScript + SQL Server)
que permiten a los clientes de Metrica ejecutar y registrar pruebas de
**excentricidad**, **repetibilidad** y **linealidad** sobre sus balanzas, entre
calibraciones formales.

- Funciona **offline-first**: se captura en planta sin señal y se sincroniza despues.
- Es **multi-tenant**: cada cliente ve solo sus instrumentos y reportes.
- El personal de Metrica tiene un **dashboard global** con el estado de todas
  las balanzas de todos los clientes.
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
├── package.json                npm workspaces: backend + packages/*
└── .gitignore
```

`app/` **no** forma parte de los workspaces npm: su gestor de paquetes es `pub`.
Solo `backend` y `packages/*` se instalan con `npm install` desde la raiz.

Antes de tocar codigo, leer [docs/architecture.md](docs/architecture.md): explica
por que las carpetas se llaman como se llaman y donde va cada archivo nuevo.

---

## Requisitos

| Herramienta | Version |
| --- | --- |
| Node.js | >= 20 (probado con 24.x) |
| npm | >= 10 |
| Flutter | 3.44.x stable (Dart 3.12.x) |
| SQL Server | instancia de Metrica, alcanzable por VPN |

---

## Backend

Instalar dependencias de todo el workspace (desde la raiz):

```bash
npm install
```

Configurar el entorno:

```bash
cp backend/.env.example backend/.env
```

Completar `backend/.env` con las credenciales de SQL Server y los secretos JWT.
**Requiere la VPN conectada** para llegar a la base.

Generar el cliente de Prisma (la base ya existe, se introspecciona):

```bash
npm run prisma:pull --workspace backend
```

```bash
npm run prisma:generate --workspace backend
```

Levantar en desarrollo (recarga en caliente con `ts-node-dev`):

```bash
npm run backend:dev
```

Compilar y correr en produccion:

```bash
npm run backend:build
```

```bash
npm run backend:start
```

Verificar que responde:

```bash
curl http://localhost:3000/health
```

Otros scripts: `npm run backend:lint`, `npm run backend:test`.

---

## App (Flutter)

Instalar dependencias:

```bash
npm run app:get
```

Generar el codigo de `freezed`, `json_serializable`, `riverpod_generator` y
`drift_dev` (los `*.g.dart` no se commitean):

```bash
npm run app:gen
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
npm run app:test
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

Scaffold de estructura y configuracion base. **Todavia no hay logica de
negocio**: sin calculos de las pruebas, sin endpoints reales y sin pantallas
definitivas. Lo que si esta listo y compila:

- Cliente Dio con interceptores de auth (placeholder de refresh), logging con
  redaccion de credenciales, y traduccion de errores.
- Jerarquia de `Failure` / `Result` en la app y de `ApiError` en la API.
- Middleware JWT con extraccion de `empresa_id` para el aislamiento multi-tenant.
- Router `go_router`, tema, almacenamiento seguro de tokens e inyeccion Riverpod.
- Express con helmet/cors/error handler, conexion Prisma + pool `mssql`.

Siguiente paso sugerido: implementar la feature `auth` completa (login +
refresh token) en ambos lados antes de tocar las features de calculo.

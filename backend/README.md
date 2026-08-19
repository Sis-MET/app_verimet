# IvMET — API

Backend Node.js + TypeScript (Express) sobre SQL Server. Forma parte del
monorepo IvMET: ver el [README raiz](../README.md).

Arquitectura y reglas de capas: [../docs/architecture.md](../docs/architecture.md).

## Puesta en marcha

```bash
cp .env.example .env
```

Completar `.env` con las credenciales de SQL Server y los secretos JWT. La base
esta detras de la VPN corporativa: hay que estar conectado antes de levantar.

```bash
pnpm dev
```

```bash
curl http://localhost:3000/health
```

## Scripts

| Script | Que hace |
| --- | --- |
| `pnpm dev` | `ts-node-dev` con recarga en caliente. |
| `pnpm build` | Compila a `dist/` y resuelve los alias de `tsconfig`. |
| `pnpm start` | Corre `dist/server.js`. |
| `pnpm typecheck` | `tsc --noEmit`. |
| `pnpm lint` | ESLint sobre `src/`. |
| `pnpm test` | Tests con el runner de Node. |
| `pnpm prisma:pull` | Introspecciona la base existente hacia `schema.prisma`. |
| `pnpm prisma:generate` | Genera el cliente tipado de Prisma. |

## Mapa de `src/`

| Ruta | Contenido |
| --- | --- |
| `server.ts` | Bootstrap: `listen()` y apagado ordenado. |
| `app.ts` | Instancia de Express y middlewares globales. |
| `routes.ts` | Unico lugar donde se montan los routers de cada feature. |
| `core/config/` | Validacion de variables de entorno con zod (fail fast). |
| `core/database/` | Cliente Prisma y pool `mssql` para stored procedures legados. |
| `core/middlewares/` | JWT + multi-tenant, validacion zod, error handler, request id. |
| `core/errors/` | `ApiError` y sus subclases. |
| `shared/` | Logger, tipos y utilidades transversales. |
| `features/` | Una carpeta por dominio: `domain/`, `application/`, `infrastructure/`, `presentation/`. |

## Alias de imports

`tsconfig.json` define `@core/*`, `@shared/*` y `@features/*`. En desarrollo los
resuelve `tsconfig-paths`; en el build, `tsc-alias`. Usar los alias para lo
transversal y rutas relativas dentro de una misma feature.

## Multi-tenant

`empresa_id` sale **siempre** del JWT (`req.user.empresaId`, helper
`requireTenant(req)`), nunca del body, query o params. Toda query que devuelva
instrumentos, pruebas o reportes debe filtrar por ese valor. La excepcion es el
personal interno de Metrica, y solo en rutas protegidas con `requireMetricaStaff`.

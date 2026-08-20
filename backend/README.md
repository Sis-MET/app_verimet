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
| `pnpm ivmet:create-admin` | Crea interactivamente el primer `metrica_admin`. |
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

Los `paths` se declaran relativos al `tsconfig.json` (`./src/core/*`) y **sin
`baseUrl`**: esa opcion quedo deprecada y deja de funcionar en TypeScript 7.
Por la misma razon el proyecto usa `module`/`moduleResolution` en `node16` y no
el viejo `node` (node10).

## Multi-tenant

El cliente sale **siempre** del usuario autenticado y cada consulta comprueba
ademas `ivmet.usuario_plantas`. Los IDs enviados por el móvil nunca amplían el
alcance. El personal de Métrica solo ve evidencia asociada a alertas que el
`cliente_jefe_calidad` haya compartido.

## Integración y despliegue

Las rutas públicas viven bajo `/api/ivmet/v1`. Para montar el módulo dentro del
proceso corporativo e inyectar su pool SQL Server existente se exporta
`createIvmetRouter` desde `src/ivmet.ts`. El procedimiento completo, migraciones,
banderas y rollback está en
[backend-ivmet-deployment.md](../docs/backend-ivmet-deployment.md).

La API completa se activa con `IVMET_ENABLED=true`. La ingesta se controla por
separado con `IVMET_SYNC_ENABLED=true` y debe permanecer apagada hasta que
Métrica apruebe el procedimiento y los casos dorados de cálculo.

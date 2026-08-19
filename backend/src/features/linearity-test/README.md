# Feature: `linearity-test`

Prueba de linealidad: barrido de cargas crecientes/decrecientes.

## Capas

| Carpeta | Responsabilidad | Puede depender de |
| --- | --- | --- |
| `domain/` | Entidades e interfaces de repositorio (puertos). Sin Express, sin Prisma, sin `mssql`. | nada |
| `application/` | Casos de uso. Orquestan entidades y puertos. | `domain/` |
| `infrastructure/` | Implementacion de los puertos contra SQL Server y servicios externos. | `domain/` |
| `presentation/` | Rutas Express, controllers y DTOs zod. | `application/`, `domain/` |

## Multi-tenant

Toda consulta que devuelva datos de un cliente debe recibir el `empresaId`
obtenido de `req.user.empresaId` (helper `requireTenant(req)`), nunca de
un parametro del request.

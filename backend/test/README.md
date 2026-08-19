# Tests de la API

La estructura espeja `src/features/`: cada feature tiene su carpeta y dentro
se testean sus capas (casos de uso de `application/` con repositorios en
memoria, validadores zod de `presentation/dto/`, y los repositorios de
`infrastructure/` contra una base de pruebas).

Runner: `node --test` (`pnpm --filter @ivmet/backend test`).

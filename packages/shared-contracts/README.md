# `@ivmet/shared-contracts`

Paquete opcional del monorepo. Sirve para que la API y (via OpenAPI) la app
Flutter no se desincronicen en:

- nombres de los tipos de prueba (`eccentricity`, `repeatability`, `linearity`),
- estados de la cola de sincronizacion,
- veredictos de una prueba.

`openapi/` guardara el contrato REST (`ivmet-api.yaml`) del que se puede
generar cliente Dart cuando los endpoints existan.

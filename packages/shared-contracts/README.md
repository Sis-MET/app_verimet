# `@ivmet/shared-contracts`

Paquete opcional del monorepo. Sirve para que la API y (via OpenAPI) la app
Flutter no se desincronicen en:

- nombres de los tipos de prueba (`eccentricity`, `repeatability`, `linearity`),
- estados de la cola de sincronizacion,
- veredictos de una prueba.

El contrato REST completo esta en `openapi/ivmet-v1.yaml` y es la fuente para
generar o validar el cliente Dart.

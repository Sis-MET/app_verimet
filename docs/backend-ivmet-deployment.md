# Despliegue de IvMET en la API corporativa (documento historico)

> **Obsoleto:** este documento describe la integracion anterior con ServiceMET.
> La arquitectura vigente usa Supabase como backend principal y una base SQL
> Server autonoma `IvMET`. Consulte
> [`sqlserver/README.md`](../sqlserver/README.md).

El código fuente de IvMET se mantiene en `IvMET/backend`. No requiere editar una
copia local de ServiceMET. En el servidor de la empresa se monta su router en el
mismo proceso Express y se reutiliza el pool `mssql` ya conectado.

## Montaje en el proceso existente

Compilar `@ivmet/backend` y cargar el adaptador sin ejecutar `server.js`:

```js
const { createIvmetRouter } = require('./ruta-a-ivmet/dist/ivmet.js');

app.use('/api/ivmet/v1', createIvmetRouter({ sqlPool: poolExistente }));
```

El adaptador no cierra un pool inyectado. Las rutas antiguas de ServiceMET no se
modifican; el puerto y TLS siguen perteneciendo al servidor corporativo.
`backend/src/app.ts` queda disponible para desarrollo local y monta el mismo
router bajo `API_PREFIX`.

## Secuencia segura

1. Crear una copia validada de DataMET y ejecutar `010_ivmet_schema.sql`.
2. Revisar el resultado de la auditoría de tablas/columnas legadas.
3. Ejecutar `011_ivmet_permissions.sql` con un administrador de base de datos.
4. Desplegar con `IVMET_ENABLED=false` e `IVMET_SYNC_ENABLED=false`.
5. Ejecutar `pnpm --dir backend ivmet:create-admin` en una consola privada.
6. Ejecutar typecheck, lint, tests y smoke tests contra la copia de DataMET.
7. Activar `IVMET_ENABLED=true` y ejecutar `pm2 reload servicemet-api`.
8. Crear el piloto de un cliente/una planta desde los endpoints `/admin`.
9. Solo después de aprobar el procedimiento oficial y sus pruebas doradas,
   registrar su identificador exacto en `IVMET_APPROVED_PROCEDURES`, activar
   `IVMET_SYNC_ENABLED=true` y ejecutar nuevamente
   `pm2 reload servicemet-api`.

Las variables `JWT_SECRET` y `JWT_REFRESH_SECRET` deben ser aleatorias,
diferentes y exclusivas de IvMET; `JWT_ISSUER=servicemet-api` y
`JWT_AUDIENCE=ivmet-mobile` impiden aceptar tokens de otras aplicaciones.

## Rollback

Cambiar `IVMET_ENABLED=false` y recargar el proceso retira las rutas IvMET sin
tocar las rutas existentes. No se revierte el esquema ni se borra evidencia. Si
el problema afecta solo a la ingesta, basta con `IVMET_SYNC_ENABLED=false`.

## Insumos pendientes antes de producción

- Procedimiento metrológico oficial y matriz de aceptación de Métrica.
- Casos dorados firmados/aprobados para cada método de evaluación.
- Validación de nombres y tipos reales en `DATA_CLIENTES`, `DATA_PLANTAS`,
  `DATA_EQUIPOS` y `DATA_EQUIPOS_BALANZAS` sobre la copia de producción.
- Prueba de integración/regresión en el servidor donde viven los tests actuales
  de ServiceMET; esos tests no están presentes en este repositorio.

El motor incluido cubre aritmética decimal y métodos parametrizados, pero la
bandera de sincronización evita considerarlos productivos sin esas aprobaciones.

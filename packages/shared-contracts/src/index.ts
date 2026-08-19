/**
 * Contratos compartidos de IvMET.
 *
 * Aca viven los tipos/enums que API y app deben interpretar igual
 * (tipos de prueba, estados de sincronizacion, veredictos). La app Flutter
 * no consume este paquete por npm: se mantiene alineada via la especificacion
 * OpenAPI de `openapi/` y sus propios `models` en `data/`.
 */
export * from './test-types';

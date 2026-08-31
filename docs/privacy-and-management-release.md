# Privacidad y operación interna IvMET

La entrega inicial de privacidad introdujo casos compartidos y bloqueó la
exportación masiva de evidencia privada. La arquitectura vigente amplía ese
aislamiento: áreas, patrones, certificados y planes metrológicos pertenecen al
cliente y se gestionan desde la app, no desde RimMET.

Para actualizar una instalación existente se debe usar la
[guía de configuración del cliente y contrato 4](customer-configuration-release.md).
Esa guía contiene el orden coordinado de SQL Server 011, Supabase
`202608280004`, RimMET, app y worker. No volver a desplegar un worker de contrato
3 después de aplicar esos permisos.

Principios que se mantienen:

- DataMET es de solo lectura para IvMET.
- Supabase es la fuente principal.
- resultados, borradores e historial permanecen privados;
- Métrica solo recibe expedientes o fichas autorizados explícitamente;
- retirar acceso no borra evidencia ni promete eliminar copias ya recibidas;
- ningún flujo cambia automáticamente el estado o los datos de DataMET.

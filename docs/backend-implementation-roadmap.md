# Ruta de implementacion del backend IvMET

## Principios que no cambian

- Supabase (Postgres, Auth, RLS, Storage y Edge Functions) es la fuente
  principal de IvMET.
- DataMET se consulta en modo solo lectura para clientes, plantas y equipos.
- Solo se importan clientes contratados y los elementos habilitados en RimMET.
- La base SQL Server nueva se llama `IvMET`; recibe un espejo, auditoria y
  resultados, pero no reemplaza ni modifica las tablas existentes de DataMET.
- RimMET administra contratos, pagos, cupos, usuarios y alcance de importacion.
- Flutter presta el servicio metrologico y requiere conexion a Internet.

## Secuencia de entrega

### 0. Proteger el trabajo existente

Crear commits de punto de control para los cambios actuales de Flutter y
RimMET antes de editar esos proyectos. Los cambios de Supabase pueden avanzar
de forma independiente.

### 1. Fundacion Supabase

Crear el proyecto de desarrollo, aplicar las migraciones, ejecutar pgTAP y
verificar que `anon` no tenga acceso. Este paso incluye catalogos selectivos,
licencias, borradores online, evidencia inmutable, alertas, outbox y RLS.

Resultado de salida: esquema reproducible y probado; ninguna tabla depende de
los identificadores defectuosos de DataMET como clave primaria propia.

### 2. Autenticacion y aprovisionamiento

Desplegar login por nombre de usuario, cambio obligatorio de contraseña y una
funcion administrativa para crear/desactivar cuentas desde RimMET. Supabase
Auth conserva contraseñas y sesiones; las tablas de negocio solo guardan
perfiles, asignaciones y licencias.

Resultado de salida: una cuenta sin licencia o fuera de periodo puede
autenticarse para conocer el motivo, pero RLS no le entrega datos operativos.

### 3. Base corporativa SQL Server `IvMET`

Crear el esquema espejo con UUID de Supabase como claves, tabla de eventos
aplicados e indices. El usuario del worker tendra lectura en DataMET y escritura
solo en la base nueva `IvMET`.

Los scripts ejecutables y su orden estan documentados en
[`sqlserver/README.md`](../sqlserver/README.md). Los scripts historicos que
creaban el esquema dentro de DataMET no se utilizan en esta arquitectura.

Resultado de salida: DataMET permanece intacta y cada evento Supabase puede
aplicarse de forma idempotente.

### 4. Worker bidireccional

Implementar un proceso saliente desde el servidor de Metrica:

1. Lee en RimMET/Supabase el alcance contratado.
2. Escanea en DataMET solo clientes, plantas y equipos habilitados.
3. Normaliza `cod_metrica`, unidades y rangos; compara hashes SHA-256.
4. Envia cambios permitidos a Supabase y pone inconsistencias en cuarentena.
5. Reclama eventos de `private.sync_outbox` y los aplica por secuencia en SQL
   Server `IvMET`.
6. Confirma o reintenta cada evento sin perderlo.

No se abren conexiones entrantes desde Internet hacia SQL Server.

La implementacion vive en [`worker/`](../worker/README.md). Arranca deshabilitada
por defecto, valida permisos antes de sincronizar y permite limitar el piloto a
un unico `WORKER_SCOPE_ID`.

### 5. Gestion IvMET en RimMET

Primero se endurece su autenticacion actual. Despues se agrega el tercer modulo
para contratos, mensualidades/anualidades, pagos, cupos, usuarios, plantas,
equipos, certificados, planes y cuarentena del worker.

### 6. Motor metrologico

Codificar el procedimiento oficial en una Edge Function transaccional. La app
envia cadenas decimales y un `requestUuid`; el servidor recalcula todos los
errores y veredictos, captura snapshots y genera alertas. No se acepta evidencia
productiva hasta aprobar las pruebas doradas de Metrica.

### 7. Flutter online

Reemplazar datos demo, Drift, cola offline y sincronizacion por lotes por:

- sesion nativa de Supabase;
- consultas protegidas por RLS;
- borrador remoto con version optimista y autoguardado;
- finalizacion idempotente mediante Edge Function;
- historial, alertas y PDF bajo demanda.

### 8. Piloto y produccion

Usar un proyecto de staging, un cliente y una planta. Verificar aislamiento,
vencimiento de licencia, caida de red, reintentos, cuarentena, espejo SQL y
restauracion. Solo entonces migrar a produccion.

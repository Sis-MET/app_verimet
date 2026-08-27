# Incorporación automática de clientes — despliegue

Esta entrega completa la incorporación administrativa, no el motor metrológico
ni la aplicación móvil. El procedimiento oficial de aceptación sigue siendo
un requisito independiente para habilitar resultados definitivos.

## Flujo de operación

1. El administrador de nivel 3 de RimMET selecciona un cliente y autoriza sus
   plantas/balanzas, dejando referencia del contrato/pago.
2. La solicitud aparece inmediatamente en **Clientes**, aunque el cliente aún
   no exista en el catálogo público de Supabase. No hay una segunda aprobación.
3. El worker permanente consulta la cola, reclama un único alcance y lo importa.
   No copia todos los clientes de DataMET: solo los alcances autorizados.
4. El seguimiento muestra pendiente, en curso, completo, parcial o fallido.
   Los errores se reintentan con espera progresiva; el administrador puede
   adelantar el reintento con motivo. No se ejecutan comandos desde el navegador.
5. Los cambios públicos se entregan al espejo SQL `IvMET` por el outbox existente.
   La importación no crea pagos, contratos, usuarios ni licencias automáticamente.

Las dos direcciones corren en bucles independientes. Una importación grande o
fallida no impide al otro bucle entregar cambios al espejo. El heartbeat sigue
publicándose durante una importación. Sin heartbeat reciente de un daemon, el
panel avisa que las solicitudes están guardadas pero el servicio no está disponible.

## 1. Preparación y pruebas

Respaldar Supabase y SQL `IvMET`. Validar primero en un proyecto de pruebas y
una copia de la base espejo. Detener **solo** el worker IvMET anterior antes de
aplicar esta versión; no mezclar el consumidor piloto con la nueva cola.
No detener ni modificar `servicemet-api`.

Desde la raíz de IvMET:

```powershell
pnpm install --frozen-lockfile
pnpm db:test:admin
pnpm worker:test
pnpm worker:build
pnpm dlx supabase db push --linked --dry-run
pnpm dlx supabase db push --linked
pnpm dlx supabase db lint --linked --level warning
```

La migración nueva es **202608270004_onboarding_queue.sql**. Las anteriores
001/002/003 del 27/08 ya fueron aplicadas por el usuario y no se reescriben.
Esta migración conserva solicitudes existentes, incluido `0103`, y las incorpora
a la cola. No necesita una migración SQL Server ni volver a incorporar al cliente.

Añade `private.catalog_jobs`, `private.worker_heartbeats`, índices y RPC de
servicio. Conserva la lógica comercial anterior detrás de funciones privadas;
clientes móviles no tienen permisos sobre estas operaciones. La cola y los
heartbeats son operativos, no forman parte del espejo público de 32 tablas.

## 2. Configuración única del servicio en el servidor

El worker debe estar en un equipo permanente de la red de Métrica, con acceso a
SQL Server y HTTPS saliente a Supabase. No basta con levantar el frontend de RimMET
ni ejecutar `worker:health`: ese comando solo verifica conectividad/permisos.

Conservar los secretos en `worker/.env`, fuera de Git. Configuración productiva:

```dotenv
NODE_ENV=production
WORKER_ID=ivmet-worker-metrica-01
WORKER_ENABLED=true
WORKER_SCOPE_ID=
WORKER_OUTBOX_POLL_SECONDS=10
WORKER_CATALOG_INTERVAL_SECONDS=300
WORKER_RETRY_SECONDS=60
WORKER_LEASE_SECONDS=300
```

`WORKER_SCOPE_ID` debe quedar vacío; el daemon de producción rechaza el filtro
piloto para que las incorporaciones de otros clientes no queden invisiblemente
excluidas. Cada máquina debe tener un `WORKER_ID` diferente. No cambiar las
credenciales DataMET de solo lectura ni conceder permisos nuevos de escritura.

```powershell
pnpm worker:health
```

Comprobar `contractVersion: 2`, `enabled: true`, `scopeFilter: null` y
`automaticReady: true`, además de los permisos seguros ya existentes. Health no
importa catálogos ni publica un heartbeat que simule un servicio permanente.

## 3. Arranque permanente con el PM2 corporativo

Desde la raíz del despliegue IvMET, para registrar el proceso por primera vez:

```powershell
pm2 start worker/ecosystem.config.cjs --only ivmet-worker
pm2 save
pm2 status ivmet-worker
pm2 logs ivmet-worker --lines 50
```

Para un proceso IvMET previamente registrado, después de detenerlo y actualizar
su código/configuración, usar `pm2 restart worker/ecosystem.config.cjs --only
ivmet-worker --update-env` en lugar de registrar un duplicado. Los comandos
operativos se ejecutan en el servidor, nunca por cada cliente ni desde el panel.

El archivo configura un proceso, reinicio con espera progresiva, señal de listo
y cierre por IPC para Windows. Los leases vencidos permiten recuperar una caída
forzada sin duplicar solicitudes. El proceso conserva un límite de memoria de
300 MB; revisar su consumo real y ajustar antes de ampliar la carga.

**Arranque de Windows:** `pm2 save` guarda la lista, pero no instala por sí solo
el arranque del sistema. El responsable del servidor debe integrar la cuenta de
servicio y la restauración de PM2 con el mecanismo corporativo de inicio de
Windows, y probar un reinicio sin sesión interactiva. No instalar otro daemon
paralelo. La documentación de [arranque de PM2](https://pm2.keymetrics.io/docs/usage/startup/)
separa la lista guardada del servicio de inicio. Windows permite registrar esa
acción con el [Programador de tareas](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask),
bajo una cuenta con acceso a la carpeta, los secretos y la red. Esa instalación
es responsabilidad del servidor y no se ejecutó en el equipo de desarrollo.

Aplicar la política corporativa de rotación/retención a los logs de PM2 y alertar
por proceso detenido, outbox `DEAD` o solicitudes fallidas recurrentes. No guardar
credenciales o payloads completos en logs. El gestor muestra solo códigos de
incidencia y claves del catálogo, no mensajes SQL internos ni snapshots privados.

## 4. Desplegar RimMET y verificar

En RimMET, publicar backend y frontend juntos, con las variables privadas
existentes (`IVMET_ENABLED=true` y claves de Supabase solo en backend):

```powershell
pnpm lint
pnpm test
pnpm --dir backend test
pnpm build
```

Reiniciar únicamente el backend RimMET mediante su mecanismo habitual y servir
el build actualizado. En **Gestión IvMET → Clientes**:

- El cliente `0103` debe aparecer sin una nueva solicitud.
- El indicador debe decir **Sincronización automática disponible**.
- Abrir su seguimiento y verificar sus dos plantas y las 50 balanzas autorizadas.
- Al finalizar, comprobar el cliente, plantas y equipos importados. Un equipo con
  datos técnicos pendientes permanece sin habilitar para uso metrológico.
- Comprobar que el outbox drene al espejo SQL `IvMET`; `DEAD` requiere investigar
  y corregir la causa, no saltarse eventos ni borrar evidencia.
- Probar una caída/reinicio del worker y una ampliación de alcance mientras
  procesa, primero en pruebas. Comprobar también el reinicio de Windows.

La latencia normal de detección de nuevas solicitudes es el intervalo de sondeo
(10 s por defecto) más la cola anterior y el tiempo de importación. Los alcances
ya completados se refrescan cada 300 s después de finalizar; fallos parciales o
totales se reprograman a 60, 120, 240… segundos, hasta una hora. La vista se
actualiza periódicamente sin desmontar los diálogos y pausa el sondeo al ocultarla.

## Recuperación y límites

- No borrar la solicitud para reintentar. Usar **Ver incorporación → Reintentar
  ahora** cuando haya fallado, o esperar la recuperación automática.
- Una ampliación incrementa una generación independiente de `row_version`.
  Terminar un intento antiguo no marca como importadas las nuevas selecciones.
- La reclamación/renovación/finalización usan `run_id`; un propietario vencido no
  puede cerrar el intento que lo reemplazó. La importación es al menos una vez,
  con upserts/hash; no es una transacción distribuida entre ambos servidores.
- Los motivos de autorización no se reemplazan por errores técnicos. Se conserva
  la auditoría, las incidencias y el resultado de cada intento.
- El botón de reintento no inicia un worker apagado. La disponibilidad depende de
  mantener el proceso del servidor activo, no del navegador del administrador.
- `catalog` y `once` procesan como máximo un alcance vencido por ejecución; son
  herramientas de diagnóstico. La operación normal usa exclusivamente el daemon.

Rollback: detener `ivmet-worker` y deshabilitar el gestor con su bandera si hace
falta. Conservar tablas/solicitudes/evidencia y la migración. No reactivar un worker
antiguo sobre la nueva cola; desplegar de nuevo una versión compatible corregida.

Las pruebas automatizadas usan PostgreSQL aislado y repositorios simulados. No se
aplicaron migraciones remotas ni se importaron los datos de `0103` durante el desarrollo.

Validación local de esta entrega: 22 pruebas PostgreSQL, 18 del worker, 18 del
backend RimMET y 50 del frontend aprobadas (108 en total). Compilaciones y lint
correctos. Se mantienen los avisos anteriores de Browserslist y tamaño del módulo
PDF. Con la skill de navegador se verificaron alta, recuperación de solicitud
existente, reintento, bandeja y servicio detenido; escritorio y modal de 390 px,
sin errores de consola y con bloqueo/restauración del scroll. No sustituye las
pruebas de conectividad, carga y reinicio en el servidor de despliegue.

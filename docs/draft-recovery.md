# Captura por pasos y recuperación de borradores

La pantalla activa de comprobación tiene cinco pasos fijos:

1. Juego de pesas patrón/certificados, temperatura y humedad relativa.
2. Excentricidad.
3. Repetibilidad.
4. Linealidad (clave interna `linearity`, evaluada mediante el error de cada indicación).
5. Resumen de condiciones, patrones, lecturas, omisiones y observaciones.

Una prueba no configurada se identifica en su paso y permite continuar. La
navegación hacia delante valida el paso; volver permite corregirlo. El resumen
muestra todas las lecturas y permite editar cada sección. Guardar y salir
conserva un borrador incompleto, accesible desde Mis borradores. La finalización
guarda primero y utiliza la evaluación existente del servidor.

## Persistencia

`DraftController` separa las cadenas crudas introducidas por el operador del
payload normalizado de la API. Cada cambio y selección inicia una escritura
local sin debounce: incluye paso, posición de desplazamiento, condiciones,
certificados, motivos y todas las lecturas. Un borrador tiene a lo sumo una
escritura en curso y una en espera: un cambio nuevo reemplaza el estado de la
que espera en lugar de encolar otra. La posición de desplazamiento viaja con la
siguiente escritura o se guarda 0,7 s después de dejar de desplazar; antes cada
píxel lanzaba una escritura (ver
[rendimiento de la captura](operator-agenda-and-schedules.md#rendimiento-de-la-captura)). Omitir una prueba
oculta sus lecturas pero las conserva para deshacer la omisión. También se
conservan textos transitorios como `-` o `10,`, que todavía no acepta el servidor.

En móvil, `SqliteDraftRecoveryStore` guarda un documento por servidor, cliente
y usuario en el directorio de soporte de la aplicación, usando SQLite WAL y
`synchronous=FULL`. Cada escritura actualiza atómicamente borradores y ruta
activa. SQLite confirma la escritura después de sincronizar el journal, según
su [documentación de durabilidad](https://sqlite.org/pragma.html#pragma_synchronous).
No contiene tokens ni el historial de evidencia final. Esta recuperación
introduce almacenamiento local de borradores, a diferencia de la captura
anterior, que mantenía los cambios pendientes únicamente en memoria.

La UI distingue guardando localmente, guardado local pendiente de envío y
guardado en el servidor. Ante fallo de almacenamiento no permite salir ni
avanzar y ofrece reintentar. La garantía aplica a escrituras confirmadas: borrar
los datos de la app, desinstalarla o perder físicamente el almacenamiento
elimina cualquier borrador aún no recibido por el servidor. La adaptación web
usa almacenamiento del navegador y depende de su disponibilidad y retención.

El autoguardado remoto espera 650 ms de inactividad. La captura original usa el
contrato v1; las [cargas flexibles](flexible-metrology-capture.md) requieren la
migración `202609030001_flexible_test_loads.sql` y el contrato de captura v2.
Si una entrada activa no es válida aún, queda localmente.
Un único envío activo serializa las versiones; la respuesta de un envío antiguo
no marca como guardadas las ediciones posteriores. Se conserva en disco el
cuerpo exacto y UUID antes de cada RPC. Un envío de resultado desconocido se
repite antes de enviar cambios nuevos, incluso tras reiniciar.

Se conserva también el UUID de finalización antes de solicitarla. Una respuesta
perdida deja el resumen bloqueado para cambios y permite confirmar el mismo
resultado mediante un reintento idempotente. Solo se retira la recuperación
después de confirmar el resultado. Un conflicto de versiones conserva la
captura local, detiene el autoguardado y permite consultar la versión del servidor;
no mezcla ni sobrescribe valores de otro dispositivo.

Al reabrir la app, `WorkspaceScreen` busca la comprobación activa del usuario.
La vista recuperada vuelve a consultar el equipo antes de exponer los datos.
El cierre de sesión conserva los borradores bajo su cuenta original. La app
sigue necesitando conexión y licencia válida para acceder, enviar y finalizar.

## Validación

`draft_recovery_test.dart` comprueba persistencia en disco con una conexión
SQLite nueva, aislamiento entre cuentas, entradas incompletas, omisiones,
escrituras concurrentes con el envío, respuestas perdidas, conflictos, fallos
locales y finalización idempotente. `mobile_flow_test.dart` destruye la pantalla
y la sesión y verifica que una entrada nueva a la app recupera automáticamente
el paso, lecturas parciales, condiciones y certificados. La validación de campo
incluye forzar el cierre en Android durante la captura y durante un envío.

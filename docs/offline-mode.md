# Trabajo sin conexión

IvMET trabaja sin señal. Registrarse, ingresar y administrar siguen exigiendo
internet; verificar y consultar, no. Al volver la conexión, lo capturado se
envía solo en segundo plano, como en WhatsApp, mientras la app sigue usable.

Decisiones tomadas con Métrica (09/10/2026):

| Tema | Decisión |
| --- | --- |
| Sincronizar | En segundo plano con la app abierta. No se bloquea la app; solo cerrar sesión con envíos pendientes. |
| Alcance | Verificar y consultar. Usuarios, plantas, plan, registrar o configurar balanzas, anular y compartir piden señal. |
| Resultado | Pendiente hasta sincronizar: lo calcula el servidor, no hay un segundo cálculo en el teléfono. |
| Plazo | 7 días sin validar la cuenta. Después la app pide señal; lo capturado no se pierde. |

## Por qué no se copian las tablas

La primera idea fue replicar en SQLite toda la estructura de Supabase. No se
hizo: obligaba a reescribir en el teléfono los permisos por planta y por
operador, los límites del plan, la agenda y el cálculo de la verificación, y
dos cálculos pueden discrepar. La app guarda en cambio **las mismas
respuestas que ya mostraba** y **las capturas con su diario de envíos**. El
servidor sigue decidiendo qué ve cada usuario y cuál es el resultado.

## Qué se puede hacer sin señal

- Inicio, Verificar (con búsqueda), la ficha de cada balanza con su
  configuración y sus pesas patrón, la agenda de este mes y el siguiente, el
  historial reciente, los borradores, Mi plan y el manual.
- Capturar una verificación y **finalizarla**: queda «Finalizada en el
  teléfono», bloqueada, con la hora en que se terminó.
- Una franja sobre toda la app dice «Sin conexión · datos del 09/10 10:22 ·
  1 por enviar». Lleva a **Por enviar** (también en Ajustes).

Lo que no está en la copia responde «Sin conexión, y esto no está en la copia
del teléfono». Lo que exige señal responde «Sin conexión. Esto necesita
internet…».

## Cómo está construido

### Copia del teléfono (`offline_copy.dart`)

- Vive en el mismo almacén SQLite de los borradores (`ivmet_draft_recovery`,
  WAL y `synchronous=FULL`), con claves `offline:v1|<cuenta>|<sección>|<filtros>`.
  La zona horaria no forma parte de la clave.
- `MobileSession.read(section, filters)`: con señal pide al servidor y guarda
  la respuesta; sin señal responde con la copia, marcada con
  `offlineCopySavedAt`. Se guardan `bootstrap`, `plan`, `instruments`,
  `equipment`, `agenda`, `history`, `drafts`, `draft` y `verification`; los
  formularios de administración y el equipo, no.
- **Descarga previa** (`MobileSession.prefetch`): con la app abierta y en línea,
  cada 15 minutos como mucho, el catálogo completo (páginas de 100, hasta
  2000 balanzas), la ficha de cada balanza (hasta 500, renovada cada 6 horas),
  la agenda de este mes y del siguiente, la primera página del historial y
  de los borradores y Mi plan. Sin señal, Verificar busca en el catálogo
  descargado con los mismos campos que el servidor.
- **Permiso de 7 días** (`OfflineGrant`): usuario, acceso, hora de validación
  y la hora más tardía de uso. Se renueva en cada validación en línea (cada
  30 s con la app abierta). No se alarga atrasando el reloj del teléfono.
- **Al cerrar sesión** se borran la copia y el permiso de esa cuenta; los
  borradores se conservan como antes. Si el servidor deshabilita la cuenta,
  le quita el cupo o rechaza la sesión, la copia también se borra.

### Sesión (`mobile_session.dart`)

- `online`: en `ready`, si el servidor responde. Una falla de red con un
  permiso vigente deja la app en `ready` sin conexión en lugar de ocultarla.
- Arranque en frío sin señal: con permiso vigente abre la app con la copia y
  retoma la captura activa. Sin permiso (vencido o nunca validado), solo
  quedan las capturas del teléfono, como antes.
- Al volver la señal (conectividad o la validación de cada 30 s) se valida la
  cuenta y la pantalla principal llama a `backgroundSync`.

### Capturas (`draft_controller.dart`, `capture_uploads.dart`)

- Cada captura guarda `startedAt`. Sin señal, «Finalizar» confirma con un
  texto propio y deja `queuedFinalize` (UUID de finalización) y `measuredAt`
  (hora del teléfono). La captura queda bloqueada.
- `CaptureUploads` recorre las capturas del teléfono, de la más antigua a la
  más nueva, con un `DraftController` sin pantalla: guarda el borrador
  (`started_at`) y finaliza (`measured_at`, `device_clock`). Usa los mismos
  UUID estables de siempre: un reintento nunca duplica.
- No toca una captura abierta en pantalla; esa la envía la propia pantalla
  al volver la señal. La pantalla espera a que termine la que se está
  enviando antes de abrirla.
- Un rechazo del servidor queda en `attention` (código, mensaje y hora): la
  franja se pone roja y no se reintenta en cada vuelta, sino cada 15 minutos o
  con «Enviar ahora». En la captura, «Corregir la captura» la vuelve editable
  y conserva la hora en que se midió.
- **Cerrar sesión** con verificaciones finalizadas sin enviar no se permite.
  **Eliminar la cuenta** tampoco: se descartarían.
- **Plan**: las capturas empezadas en el teléfono que el servidor no conoce
  ocupan su lugar del mes; sin señal no se empieza una más allá del límite.
  Si aun así el servidor la rechaza (dos teléfonos sin señal a la vez), queda
  en atención con «Tu plan ya usó las verificaciones de este mes».

### Servidor (`202610090002_offline_capture.sql`)

- `ivmet_mobile_save_draft(..., started_at)`: acepta la configuración que la
  balanza tenía en los 8 días previos a `started_at`, aunque el jefe de
  calidad la haya cambiado mientras el operador estaba sin señal.
- `ivmet_mobile_finalize_draft(..., measured_at, device_clock)`:
  `realizado_at` = hora del teléfono corregida por el desfase de su reloj al
  enviar, nunca posterior a la llegada. Los certificados se evalúan en esa
  fecha. `recibido_at` sigue siendo la llegada.
- `private.capturas_sin_conexion`: lo que mandó el teléfono (hora y desfase).
  `verification` lo devuelve como `offlineCapture`; el detalle y el informe
  PDF muestran «Captura sin conexión».
- Contrato: [API móvil](mobile-online-api.md#guardado-privado).

## Qué puede rechazar el servidor al sincronizar

| Caso | Qué pasa |
| --- | --- |
| La cuenta se desactivó o perdió su cupo mientras tanto | No se envía nada; al validar, la app vuelve al acceso y las capturas quedan en el teléfono bajo esa cuenta. |
| Le quitaron la balanza al operador | `EQUIPMENT_NOT_ACCESSIBLE`: queda en atención hasta que el jefe se la asigne. |
| Se anuló una pesa patrón usada | `CERTIFICATE_NOT_ACCESSIBLE`: «Corregir la captura» y quitar esa pesa (queda sin trazabilidad). |
| Se superó el límite del mes | `PLAN_LIMIT_VERIFICATIONS`: se reintenta solo; entra al mes siguiente o con un plan superior. |
| Otro teléfono cambió el mismo borrador | Conflicto, como en línea: «Ver datos del servidor». |

## Seguridad y privacidad

- La copia está en la carpeta privada de la app, que Android aísla de otras
  apps y protege con el cifrado del propio teléfono. No está cifrada aparte.
  Contiene datos de la empresa (balanzas, agenda, historial), no contraseñas
  ni tokens: los tokens siguen en el almacenamiento seguro.
- El plazo de 7 días limita lo que puede hacer sin señal una cuenta dada de
  baja o un teléfono perdido. El servidor revalida todo al recibirlo.

## NB/ISO/IEC 17025

Mejora RT-02 del [análisis](iso17025/analisis-ivmet.md): una verificación
hecha sin señal lleva la hora en que se midió y la de llegada, y queda
constancia de lo que informó el teléfono. Las capturas finalizadas en el
teléfono dependen del almacenamiento del dispositivo hasta enviarse: borrar
los datos de la app o perder el teléfono antes de sincronizar las pierde. Por
eso la franja y Por enviar las muestran siempre.

## Despliegue

No cambia SQL Server, el worker ni RimMET.

1. Validar:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:mobile
pnpm db:test:plans
pnpm db:test:admin
```

```powershell
Set-Location .\app
flutter analyze
flutter test
```

2. Aplicar la migración **antes** de publicar la app. El ensayo debe mostrar
   `202610090002_offline_capture.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

3. Compilar y distribuir la app (`pnpm app:aab`).

Una app anterior sigue funcionando con la migración: los parámetros nuevos son
opcionales. Una app nueva contra un servidor sin la migración falla al
guardar (`started_at` desconocido): por eso la migración va primero.

## Validación en el teléfono antes de publicar

- Entrar con señal, esperar un minuto en Inicio y abrir Verificar.
- Modo avión: la franja dice «Sin conexión». Abrir otra balanza (no visitada
  antes), su ficha y la agenda.
- Capturar y finalizar sin señal: «Finalizada en el teléfono». Ver Por enviar.
- Intentar cerrar sesión: no deja.
- Cerrar la app a la fuerza y abrirla sin señal: abre con la copia.
- Quitar el modo avión con la app abierta: «Enviando…», luego desaparece la
  franja. La verificación aparece en el historial con «Captura sin conexión».
- Con el reloj del teléfono adelantado una hora, repetir: la fecha de medición
  sale corregida.
- Sin abrir la app con señal durante 8 días (o adelantando el reloj 8 días):
  pide señal y conserva las capturas.

## Pendiente para otra entrega

- **Envío con la app cerrada** (Android WorkManager): hoy se envía con la app
  abierta.
- **Registrar y editar balanzas sin señal**.
- **Cifrar la copia** con SQLCipher si un cliente lo exige.

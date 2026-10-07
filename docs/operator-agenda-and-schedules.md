# Agenda, periodicidad y balanzas por operador

Entrega del 07/10/2026. Tres cambios que van juntos —qué balanza toca
verificar, cuándo y quién— y una corrección de rendimiento de la captura.

## Resultado funcional

### Periodicidad configurable

- El jefe de calidad elige la periodicidad de cada prueba en **Configurar
  verificaciones**, con un editor que muestra la regla en palabras y las
  próximas fechas antes de guardar.
- Accesos rápidos: diaria, días hábiles (lunes a viernes), semanal, quincenal,
  mensual, bimestral, trimestral, semestral y anual. Semanal y quincenal
  admiten varios días de la semana.
- **Personalizada**: cada N días, semanas (con los días elegidos), meses o
  años. En meses y años, un día fijo («el día 15», recortado al último día en
  los meses cortos) o un día de la semana («el primer lunes», «el último
  viernes»).
- **Cómo se cuenta**: *fechas fijas* desde una primera fecha (se mantienen
  aunque una verificación se atrase) o *desde la última* verificación
  realizada (cada verificación fija la siguiente).
- **Aviso previo** de 0 a 90 días: desde entonces la balanza aparece como
  próxima, y una verificación hecha en ese margen cuenta para esa fecha.
- Una regla puede aplicarse a todas las pruebas elegidas de un toque.
- Las configuraciones anteriores siguen valiendo: «cada N días» equivale a
  *desde la última*, con el aviso que ya tenían (la cuarta parte, hasta 30).

### Agenda

- Pestaña nueva **Agenda** en la barra: el mes con cuántas balanzas tocan cada
  día y el color de la más urgente; debajo, el detalle del día elegido.
- Arriba, las **atrasadas**: la fecha vigente venció sin verificación.
- Estados: programada, próxima, hoy, hecha, atrasada y no realizada (una
  fecha cuya ventana se cerró sin verificación).
- **Cuenta como hecha cualquier verificación finalizada**, con o sin pesas
  patrón: la trazabilidad sigue en el resultado, pero ya no condiciona el
  vencimiento. Antes solo una verificación trazable reiniciaba el plazo.
- El operador ve sus balanzas asignadas. El jefe de calidad ve las de sus
  plantas, quién tiene cada una y filtra por operador o por «sin operador».
- **Inicio** muestra «Hoy» (lo que falta verificar hoy, lo hecho y lo
  atrasado) en lugar del conteo de balanzas, que sigue en Verificar.

### Balanzas por operador

- Métrica sigue creando los usuarios y habilitándoles plantas en RimMET,
  dentro de los cupos del contrato. Ejemplo: un plan de 10 usuarios, 5 en una
  planta y 5 en otra; en cada una, 1 jefe de calidad y 4 operadores.
- El jefe de calidad asigna en **Plantas › Operadores** las balanzas de cada
  operador de su planta, con búsqueda y «marcar todas». Desde la ficha de una
  balanza, en **Operadores**, se eligen sus operadores. Una balanza puede tener
  varios.
- **Un operador sin asignaciones no ve ninguna balanza**: ni en Verificar, ni
  en la agenda, ni en los conteos. Tampoco puede abrir la ficha, guardar ni
  finalizar capturas de una balanza que no tiene. Conserva en su historial las
  verificaciones que capturó.
- Inicio y Plantas avisan al jefe de las balanzas sin operador.

> **Al desplegar, los operadores existentes dejan de ver balanzas hasta que el
> jefe de calidad se las asigne.** Fue la regla elegida. Hay que coordinarlo
> con cada cliente antes de publicar la app.

## Rendimiento de la captura

La captura se volvía lenta al empezar una verificación. No era el AppBar ni el
teclado numérico: era el autoguardado local.

- Cada píxel desplazado lanzaba una escritura completa del borrador en SQLite
  (`synchronous=FULL`, con su `fsync`), que además serializaba a JSON el
  equipo, el plan y los patrones. Al confirmarse, cada escritura redibujaba el
  paso entero con todos sus campos. Un desplazamiento de 40 cuadros generaba
  31 escrituras y otros tantos redibujados, que seguían llegando después de
  soltar la pantalla.
- Ahora la posición se guarda 0,7 s después de dejar de desplazar (o con la
  siguiente escritura). Las escrituras de un mismo borrador se funden: hay a
  lo sumo una en curso y una en espera con el estado más reciente, así que
  cada cambio sigue quedando en disco sin acumular cola.
- La línea «Guardado en este dispositivo…» escucha su propia señal y ya no
  reconstruye el paso. El payload, sus avisos y las expresiones regulares de
  cada lectura se calculan una vez por cambio, no en cada dibujo.
- La cabecera de pasos se plegaba y desplegaba en bucle cuando el contenido
  apenas desbordaba; ahora tiene umbrales distintos y una longitud mínima.

`test/online/draft_performance_test.dart` fija el comportamiento: 0
escrituras mientras se desplaza, 1 al detenerse. El teclado numérico y el
AppBar no cambian.

## Cómo está construido

- `public.usuario_equipos (usuario_id, equipo_id)`: asignaciones. Se escribe
  solo con `ivmet_customer_assign_equipment` (jefe de calidad, idempotente).
- `private.equipment_in_scope(equipo)`: el jefe ve todas las de sus plantas,
  el operador solo las asignadas. Lo aplican `private.customer_equipment`,
  `private.can_read_verification`, las políticas RLS de `equipos`,
  `equipo_rangos`, `equipos_ivmet` y `equipo_planes`, el catálogo, el
  historial, los conteos de `bootstrap` y el guardado y la finalización.
- `private.plan_test_schedules (plan_prueba_id, rule)`: la regla de cada
  prueba de una versión publicada. `frecuencia_dias` sigue obligatoria y se
  rellena con días aproximados para los consumidores anteriores.
- `private.schedule_next` y `schedule_previous` calculan las fechas fijas en
  forma cerrada (sin recorrer días). `private.equipment_schedule_status`
  sustituye la vigencia anterior y `private.equipment_agenda` da las fechas de
  un rango. La app replica las reglas en `check_schedule.dart` solo para la
  vista previa del editor; las dos implementaciones comparten casos de prueba.
- El día en planta lo decide el desfase horario del teléfono
  (`utcOffsetMinutes`); sin él, UTC−4.
- Contrato móvil en [API móvil](mobile-online-api.md#agenda-periodicidad-y-operadores).

## Despliegue

No cambia SQL Server, el worker ni su contrato. Las asignaciones y las reglas
son privadas del cliente y no se exportan. RimMET no cambia.

1. Validar en el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:mobile
pnpm db:test:admin
```

`pnpm db:test:mobile` incluye `scripts/test-operator-agenda-db.mjs`. Las dos
pruebas de `pnpm db:test:operations` que ya fallaban siguen igual; no dependen
de esta migración.

```powershell
Set-Location .\app
flutter analyze
flutter test
```

2. Acordar con cada cliente quién asigna las balanzas el día del cambio.
3. Aplicar la migración. El ensayo debe mostrar
   `202610070001_operator_scope_and_schedules.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

```powershell
pnpm dlx supabase db lint --linked --level warning
```

4. Compilar y distribuir la app (`pnpm app:apk` o `pnpm app:aab`).

Una app anterior sigue funcionando con la migración aplicada, con el alcance
por operador ya activo; no muestra la agenda ni el editor nuevo.

## Validación manual antes de distribuir

- Con un operador sin balanzas: Verificar vacío, aviso en Inicio y Agenda.
- Asignarle dos balanzas desde Plantas › Operadores y una desde la ficha de
  otra; comprobar que las ve y que otro operador no.
- Configurar una prueba semanal con dos días y otra mensual «el último
  viernes»; revisar las fechas en la agenda.
- Finalizar una verificación con cargas de trabajo y ver la fecha como hecha.
- En un teléfono de gama baja, desplazar la captura y escribir lecturas con el
  teclado propio: sin tirones ni guardado que siga después de soltar.

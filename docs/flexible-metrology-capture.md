# Captura metrológica flexible, basada en ServiceMET

Se revisaron las pantallas de `C:/Users/jhona/ServiceMET/lib/screens/calibracion/steps`
y su persistencia en `ServiceSessionProvider`. ServiceMET se usó como referencia;
no se modificó ese proyecto. El flujo de IvMET mantiene sus cinco pasos.

## Comparación de captura

| Prueba | ServiceMET | Incorporación en IvMET |
| --- | --- | --- |
| Excentricidad | `excentricidad_step.dart`: plataforma cuadrada, rectangular, circular o triangular; una carga editable; indicación y retorno por posición; indicador orientable. | Mismos tipos de plataforma y cantidades: cuadrada 5, rectangular 3/5, circular 4/5 y triangular 4. Esquema numerado con centro como referencia. La carga utilizada es común a todas las posiciones. |
| Repetibilidad | `repetibilidad_step.dart:19`: 1/2/3 cargas y 3/5/10 mediciones por carga; indicación, retorno y nota. | Mismas cantidades y captura por grupos. Una carga editable por grupo; desviación estándar muestral independiente para cada carga. |
| Linealidad | `linealidad_step.dart`: cargas editables, hasta 60 filas; aplicación sin método, ascenso con ceros o ascenso continuo; error indicación menos carga; asistente de sustitución. | Cargas sugeridas editables, 2–60 puntos activos, mismos descriptores de aplicación y sustitución, diferencias informativas y asistente con selección explícita de base/referencia. |

En ServiceMET, los cambios de carga pueden rellenar indicaciones automáticamente.
IvMET mantiene las indicaciones medidas independientes de las sugerencias y de
los cambios de carga. Reducir posiciones, grupos o repeticiones conserva las
filas retiradas, con sus identificadores y texto original, para recuperarlas al
aumentar la cantidad. No intervienen en el resultado mientras estén retiradas.

Cada prueba registra el origen: `standard` (pesas patrón), `process` (productos
o cargas de trabajo) o `mixed`, además de identificación y observaciones opcionales.
El valor inicial de la carga utilizada está vacío; **Usar sugerencia** es una
acción explícita. Las empresas pueden continuar sin seleccionar certificados.
Se conservan los límites de aceptación configurados; las cargas sugeridas no
limitan los valores que el operador puede declarar dentro de la capacidad.

## Evaluación

Los cálculos y veredictos definitivos permanecen en Supabase:

- Excentricidad: diferencia de cada indicación respecto de la posición central.
- Repetibilidad: media, desviación estándar muestral y rango por grupo. El
  veredicto de la prueba reúne los de los grupos; la métrica almacenada es la
  mayor desviación. Con varias cargas no se publica una media combinada.
- Linealidad: evalúa `indicación − carga utilizada`, conservando aparte la
  sugerencia del punto de configuración cuando existe.
- Sustitución: `errorReferencia = indicaciónReferencia − cargaReferencia`;
  `cargaSustituta = indicaciónSustituta − errorReferencia`;
  `cargaAcumulada = cargaBase + cargaSustituta`. Corresponde al cálculo de
  `linealidad_step.dart:902` en ServiceMET. Los nombres Método 1/2 allí son
  descriptores; no implementan fórmulas distintas. IvMET tampoco inventa una
  diferencia entre esas fórmulas. Las referencias deben ser filas anteriores.

Flutter usa aritmética decimal entera para la vista previa de sustitución y
recalcula sus dependencias sin alterar las indicaciones capturadas. Supabase
deriva otra vez la carga acumulada con `numeric`; no confía en la carga calculada
enviada por el cliente. El retorno a cero conserva su carácter opcional en IvMET
y no corrige automáticamente la indicación.

Los límites manuales se toman del punto configurado; los puntos adicionales
usan el menor límite de la prueba. Los límites OIML, cuando están configurados,
se calculan con la **carga utilizada**, la unidad y el intervalo del rango que
corresponde, no con la sugerencia original. No se calculan incertidumbre de
sustitución, histéresis ni correcciones de certificados en este cambio.

Productos, cargas mixtas o sustituciones producen evidencia `non_traceable`,
incluso si también se seleccionó un certificado vigente. Se conserva el
resultado interno y su alerta privada. Para origen `standard`, continúa la
evaluación existente de los certificados seleccionados. No se afirma que una
masa declarada de producto sea una masa certificada. No se incorporaron los
requisitos de fotografías ni la reutilización del servicio anterior de ServiceMET.

## Contrato y recuperación

La migración `202609030001_flexible_test_loads.sql` anuncia en el plan
`captureVersion: 2` y `captureEngineVersion: ivmet-internal-2.0.0`. Los borradores
anteriores mantienen su formato y cálculo original; no se convierten durante
la recuperación. La app sigue aceptando planes del servidor anterior.

El contenido v2 agrega `captureVersion: 2`. Cada prueba contiene:

```text
id, omitted, reason
setup: source, description, notes, platform, indicatorPosition,
       groupCount, measurementCount, pointCount, loadingMethod, substitutionMethod
readings: [{pointId, group, slot, load, indication, zero, substitution?}]
retainedReadings: [las filas temporalmente retiradas]
substitutionDraft?: {basePointId, referencePointId, indication}
```

Los identificadores de puntos nuevos son UUID estables de captura; la relación
con `plan_puntos` es opcional en la evidencia final. Las posiciones del grupo y
el orden se validan. No se aceptan puntos de otras pruebas ni campos de veredicto.
Las sugerencias no se aceptan como autoridad desde el cliente: se recuperan de
la configuración. Las cargas e indicaciones son cadenas decimales exactas.

Las filas retiradas y las de pruebas omitidas admiten texto incompleto y se
guardan también en Supabase. Un diálogo de sustitución a medio escribir se
conserva localmente y en el servidor; se reabre al recuperar ese paso. Finalizar
exige completar o descartar esa sustitución explícitamente. Se mantienen el
journal local, la serialización de envíos, los UUID idempotentes y la
[recuperación de pasos](draft-recovery.md).

## Activación y comprobación

Aplicar las migraciones pendientes en orden, incluida
`supabase/migrations/202609030001_flexible_test_loads.sql` y después
`supabase/migrations/202609030002_load_free_check_configuration.sql`, antes de
distribuir la app. La segunda elimina las cargas y cantidades de la configuración
del jefe de calidad; genera solo referencias internas desde la capacidad y
también ignora esos campos si los envía una app anterior. No se ha aplicado a un Supabase remoto desde esta tarea. La capacidad v2
se anuncia al volver a consultar una balanza; las capturas existentes siguen
su contrato original.

`pnpm db:test:mobile` verifica cargas reales distintas de las sugeridas,
decimales exactos, grupos independientes, sustituciones recalculadas, capacidad,
referencias inválidas, omisiones, trazabilidad y compatibilidad anterior.
`flutter test` incluye cambios de cargas en los tres formularios a 320 px,
recuperación tras cambiar cantidades, reinicio con diálogo parcial y resumen.
`flutter analyze` verifica la integración estática. Los tests no usan datos ni
servicios reales; la prueba de cierre forzado en un dispositivo Android queda
como comprobación de campo al distribuir la compilación.

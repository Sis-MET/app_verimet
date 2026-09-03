# Motor de comprobaciones metrológicas internas

## Alcance declarado

IvMET registra **comprobaciones internas** de instrumentos de pesaje no
automáticos. El resultado ayuda al cliente a vigilar su proceso entre
calibraciones, pero no constituye:

- un certificado de calibración;
- una calibración acreditada;
- una verificación legal del instrumento;
- una declaración emitida por Métrica sobre información que el cliente no haya
  decidido compartir.

La base guarda `INTERNAL_CHECK_ONLY` en la configuración interna, la
verificación y los snapshots.
Las pantallas repiten este alcance para evitar una interpretación incorrecta.

## Referencias controladas

- [OIML R 76-1:2006](https://www.oiml.org/en/files/pdf_r/r076-1-e06.pdf):
  errores máximos permitidos, excentricidad y disposiciones para básculas
  camioneras estáticas. OIML mantiene abierta una revisión de R 76:2006, por lo
  que cualquier nueva edición exige una nueva versión del motor y pruebas
  doradas; no se modifica silenciosamente un plan publicado.
- [EURAMET Calibration Guide No. 18, versión 4.0](https://www.euramet.org/publications-media-centre/calibration-guidelines/):
  estructura técnica de linealidad, repetibilidad y excentricidad para
  instrumentos de pesaje no automáticos.
- [ILAC G8:09/2019](https://ilac.org/publications-and-resources/ilac-guidance-series/):
  reglas de decisión y resultados no concluyentes cuando se usa banda de guarda.
- [ILAC P10:07/2020](https://ilac.org/publications-and-resources/ilac-policy-series/):
  trazabilidad metrológica de los patrones y sus certificados.
- [ILAC G24:2022](https://ilac.org/publications-and-resources/ilac-guidance-series/):
  revisión de intervalos. IvMET conserva la frecuencia decidida por el cliente y
  calcula fechas por prueba; no inventa una periodicidad universal.

Estas referencias orientan el control interno. No convierten a IvMET o al
cliente en laboratorio acreditado.

## Perfiles versión 1

| Perfil | Prueba | Evaluación del servidor |
| --- | --- | --- |
| Plataforma estática | Linealidad | `indicación - carga utilizada`; veredicto por valor absoluto. |
| Plataforma estática | Repetibilidad | Desviación estándar muestral de indicaciones a una misma carga. |
| Plataforma estática | Excentricidad | Diferencia de cada posición respecto de una lectura de referencia. |
| Báscula camionera estática | Linealidad | Igual que plataforma; puede usar MPE OIML en servicio como referencia. |
| Báscula camionera estática | Repetibilidad | Desviación estándar muestral a una misma carga. |
| Báscula camionera estática | Desplazamiento | Diferencia respecto de la referencia en posiciones inicio/centro/final. |

El código del motor es `ivmet-internal-1.0.0`. Desde la ficha de cada balanza,
el jefe de calidad elige las comprobaciones, su periodicidad e introduce los
errores permisibles. IvMET determina el perfil
por tipo de equipo y genera, publica y asigna una versión interna en una sola
transacción. El cliente no administra nombres, códigos, métodos ni estados de
planes y no puede enviar una fórmula arbitraria desde Flutter.

## Configuración guiada por balanza

La app presenta dos pasos: comprobaciones con su periodicidad y errores
permisibles con confirmación. No se configuran cargas ni cantidades de
mediciones. Supabase genera puntos de referencia internos desde la capacidad
para iniciar la captura, pero el operador declara allí las cargas realmente
utilizadas y el número de mediciones.

Las tablas de planes y versiones se conservan únicamente como mecanismo
interno para reproducir la configuración histórica de una verificación. Cada
cambio crea una versión inmutable y reemplaza de forma atómica la asignación
activa. Los RPC antiguos de creación, publicación y asignación manual están
deshabilitados.

## Límites y reglas de decisión

La configuración guiada versión 1 registra el límite como criterio del proceso
del cliente y aplica comparación directa. El motor conserva soporte interno
versionado para otras fuentes y reglas, pero no las ofrece en la app hasta que
exista un procedimiento aprobado que indique cuándo utilizarlas.

- Comparación directa: conforme cuando `|métrica| <= límite`.
- Banda de guarda: conforme cuando `|métrica| + U <= límite`; no conforme cuando
  `|métrica| - U > límite`; en la zona restante, no concluyente.

`U` es la incertidumbre expandida proporcionada y controlada por el cliente. La
versión 1 no estima incertidumbre de calibración ni corrige empuje del aire,
histéresis, redondeo de indicación o carga sustitutiva. Si el procedimiento del
cliente necesita esas magnitudes debe crearse una versión posterior del motor,
con revisión metrológica y nuevos casos dorados.

La extensión `ivmet-internal-2.0.0` incorpora cargas utilizadas distintas de
las sugerencias, grupos independientes y cálculo de cargas por sustitución
tomado de ServiceMET. El motor v1 permanece para capturas anteriores. La
extensión no propaga incertidumbre de sustitución ni amplía el alcance a una
calibración certificada. Ver [captura flexible](flexible-metrology-capture.md)
para fórmulas, procedencia de las cargas, persistencia y casos de prueba.

## Finalización y evidencia

1. El móvil guarda un borrador privado con números como cadenas decimales.
2. Al finalizar, Supabase vuelve a validar licencia, planta, equipo, versión de
   la configuración y certificados.
3. `private.evaluate_draft_payload` calcula todo antes de insertar la cabecera.
4. La verificación, pruebas y lecturas nacen con su resultado definitivo. Los
   triggers impiden editarlas o eliminarlas; solo existe anulación justificada.
5. El mismo UUID de finalización con el mismo contenido devuelve el resultado
   existente. Un uso diferente produce `FINALIZATION_CONFLICT`.
6. Un certificado vencido no descarta la captura: la marca no trazable, crea una
   alerta privada y no actualiza vencimientos.
7. Una verificación parcial guarda las omisiones justificadas y solo contiene
   lecturas de las pruebas ejecutadas.

El próximo vencimiento se deriva por tipo de prueba desde la última ejecución
trazable y no anulada. Un resultado no conforme cuenta como ejecución; una
prueba omitida no cuenta.

## Privacidad

Las tablas de evidencia siguen excluidas del outbox DataMET/SQL Server. Una
alerta nace `PRIVATE`. Solo el jefe de calidad puede compartir el snapshot de un
caso concreto; no se abre el historial completo a Métrica.

## Validación y cambio controlado

`pnpm db:test:mobile` aplica todas las migraciones en PostgreSQL desechable y
comprueba, entre otros casos:

- puntos frontera de MPE OIML clase III;
- comparación directa y banda de guarda;
- linealidad mediante el error de cada indicación y desviación estándar muestral;
- finalización trazable e idempotente;
- evidencia inmutable;
- prueba parcial, certificado vencido, resultado no conforme y alerta privada;
- ausencia de exportación de evidencia al worker.

Antes de un piloto productivo, el responsable metrológico de Métrica debe
revisar los límites elegidos por el cliente y aprobar por escrito ejemplos
representativos de sus tipos de equipo. Una modificación de fórmula se publica
como nueva versión de motor y nunca reevalúa evidencia histórica.

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

La base guarda `INTERNAL_CHECK_ONLY` en el plan, la verificación y los snapshots.
Las pantallas repiten este alcance para evitar una interpretación incorrecta.

## Referencias controladas

- [OIML R 76-1:2006](https://www.oiml.org/en/files/pdf_r/r076-1-e06.pdf):
  errores máximos permitidos, excentricidad y disposiciones para básculas
  camioneras estáticas. OIML mantiene abierta una revisión de R 76:2006, por lo
  que cualquier nueva edición exige una nueva versión del motor y pruebas
  doradas; no se modifica silenciosamente un plan publicado.
- [EURAMET Calibration Guide No. 18, versión 4.0](https://www.euramet.org/publications-media-centre/calibration-guidelines/):
  estructura técnica de error de indicación, repetibilidad y excentricidad para
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
| Plataforma estática | Error de indicación | `indicación - carga nominal`; veredicto por valor absoluto. |
| Plataforma estática | Repetibilidad | Desviación estándar muestral de indicaciones a una misma carga. |
| Plataforma estática | Excentricidad | Diferencia de cada posición respecto de una lectura de referencia. |
| Báscula camionera estática | Error de indicación | Igual que plataforma; puede usar MPE OIML en servicio como referencia. |
| Báscula camionera estática | Repetibilidad | Desviación estándar muestral a una misma carga. |
| Báscula camionera estática | Desplazamiento | Diferencia respecto de la referencia en posiciones inicio/centro/final. |

El código del motor es `ivmet-internal-1.0.0`. El jefe de calidad elige el
perfil, las pruebas incluidas, la frecuencia de cada prueba, las cargas, los
límites y su origen. No puede enviar una fórmula arbitraria desde Flutter.

## Límites y reglas de decisión

Los orígenes admitidos son proceso del cliente, fabricante, informe de
calibración y referencia OIML R 76 en servicio. Esta última solo aplica al error
de indicación y requiere clase e intervalo de verificación `e` en el catálogo
del equipo.

- Comparación directa: conforme cuando `|métrica| <= límite`.
- Banda de guarda: conforme cuando `|métrica| + U <= límite`; no conforme cuando
  `|métrica| - U > límite`; en la zona restante, no concluyente.

`U` es la incertidumbre expandida proporcionada y controlada por el cliente. La
versión 1 no estima incertidumbre de calibración ni corrige empuje del aire,
histéresis, redondeo de indicación o carga sustitutiva. Si el procedimiento del
cliente necesita esas magnitudes debe crearse una versión posterior del motor,
con revisión metrológica y nuevos casos dorados.

## Finalización y evidencia

1. El móvil guarda un borrador privado con números como cadenas decimales.
2. Al finalizar, Supabase vuelve a validar licencia, planta, equipo, versión del
   plan y certificados.
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
- error de indicación y desviación estándar muestral;
- finalización trazable e idempotente;
- evidencia inmutable;
- prueba parcial, certificado vencido, resultado no conforme y alerta privada;
- ausencia de exportación de evidencia al worker.

Antes de un piloto productivo, el responsable metrológico de Métrica debe
revisar los límites elegidos por el cliente y aprobar por escrito ejemplos
representativos de sus tipos de equipo. Una modificación de fórmula se publica
como nueva versión de motor y nunca reevalúa evidencia histórica.

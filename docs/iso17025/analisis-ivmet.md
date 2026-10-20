# Cumplimiento NB/ISO/IEC 17025 — IvMET 1.0.0+1 (sobre 45fe250, 2026-10-09)

Evaluación de las cláusulas **7.5** (registros técnicos), **7.11** (control de
los datos y gestión de la información) y **8.4** (control de registros) con el
mismo criterio y los mismos 38 ítems que se usaron en ServiceMET
(`ServiceMET/.claude/skills/iso17025-cumplimiento/references/checklist.md`).
Vale para el código de esta entrega: la app 1.0.0+1, Supabase hasta la
migración `202610090001_account_deletion.sql` y las Edge Functions actuales.

La NB/ISO/IEC 17025 es la adopción boliviana, idéntica, de la ISO/IEC
17025:2017. Los requisitos se parafrasean; el texto de la norma no se copia.

## 1. ¿IvMET debe cumplir la norma?

**No por la acreditación de Métrica, sí en tres casos concretos, y conviene
diseñarlo como si siempre aplicara.**

### Por qué no es obligatorio en general

- La 17025 se aplica a las **actividades de laboratorio** que Métrica tiene
  acreditadas ante la DTA-IBMETRO: sus calibraciones. Esas se registran en
  ServiceMET y DataMET, que sí forman parte de su sistema de gestión de la
  información (lo que la norma llama LIMS) y deben cumplir 7.5, 7.11 y 8.4.
- IvMET no produce resultados del laboratorio. Las verificaciones
  intermedias las hace **la empresa cliente**, con su personal, sus pesas y
  los límites de su proceso; la app lo declara en cada pantalla y en el informe
  («no es un certificado de calibración ni una verificación legal»). Métrica
  no usa esos resultados para emitir certificados.
- Lo que Métrica recibe de IvMET (casos compartidos, datos de balanzas que la
  empresa autoriza enviar) es información de clientes para preparar servicios,
  no registros técnicos de sus calibraciones. Le aplica la confidencialidad
  (4.2), no 7.5.

### Cuándo sí aplica

| Caso | Qué pasa | Quién responde |
|---|---|---|
| **A. Métrica usa IvMET para verificar sus propios equipos** (las balanzas o patrones del laboratorio, como control intermedio de 6.4.10) | Los registros de IvMET pasan a ser **registros técnicos del laboratorio** e IvMET, parte de su LIMS. 7.5, 7.11 y 8.4 son **obligatorios** y la DTA puede auditarlos. | Métrica, como laboratorio acreditado |
| **B. Un cliente acreditado** (laboratorio de ensayo o de calibración) usa IvMET para las verificaciones intermedias de sus balanzas | IvMET es parte del LIMS **del cliente**. Él debe demostrar 7.5, 7.11 y 8.4, y le pedirá a Métrica, como proveedor externo del sistema (7.11.4 y 6.6), evidencia de validación, integridad, respaldo y conservación. | El cliente, con evidencia que entrega Métrica |
| **C. Un cliente con ISO 9001, ISO 22000 o FSSC 22000** (por ejemplo, un embotellador) | No es la 17025, pero su control de equipos de seguimiento y medición (ISO 9001 7.1.5; ISO 22000 8.7) pide lo mismo en la práctica: registros conservados, atribuibles, sin alteración y disponibles para la auditoría. | El cliente |

**Pregunta para Métrica:** ¿el laboratorio usará IvMET con sus propias
balanzas o patrones (caso A)? Si la respuesta es sí, las brechas de riesgo
alto de la sección 4 deben cerrarse antes de ese uso.

### Recomendación

- Tratar 7.5, 7.11 y 8.4 como **requisitos de diseño** de IvMET: es lo que
  venden los casos B y C, y lo que exige el A. Casi todo ya está construido
  así (evidencia inmutable, anulación con motivo, aislamiento por empresa,
  cálculo en el servidor).
- **No** poner el tablero de cumplimiento dentro de la app: los usuarios de
  IvMET son clientes, no el sistema de gestión de Métrica. La matriz vive en
  este documento y la mantiene Métrica.
- **Sí** el manual de uso dentro de la app (7.11.5), que se agregó en esta
  entrega, y un paquete de evidencia para clientes acreditados (validación por
  versión, política de respaldo y conservación) cuando se cierren las brechas.

## 2. Resumen

De 38 ítems: **21 cumplen, 9 parciales, 3 no cumplen, 2 sin evidencia y 3 no
aplican** (con el trabajo sin conexión, CR-03 pasó a parcial y RT-02 bajó a
riesgo bajo; con los certificados desde la app, RT-06 pasó a cumple). Lo fuerte es la integridad del registro: una verificación nace
definitiva en el servidor, con quién capturó y finalizó, cuándo, con qué
equipo, configuración, patrones y versión de la app, y no se edita ni se
borra. Las brechas de riesgo alto son de operación, no de diseño: no hay
**respaldo y restauración probados** de la única copia de la evidencia, no hay
**registro de fallas del sistema** y no hay **registro de validación por
versión** (con dos pruebas que fallan desde hace semanas).

## 3. Matriz

Estados: `Cumple` · `Parcial` · `No cumple` · `No aplica` · `Sin evidencia`.
Cierre: **S**oftware, **P**rocedimiento o **A**mbos.

### RT: Registros técnicos (7.5)

| ID | Requisito | Estado | Evidencia | Brecha | Cierre | Riesgo |
|---|---|---|---|---|---|---|
| RT-01 | Identificación única, vinculada a la tarea y al ítem | Cumple | `verificaciones.id` UUID con `request_uuid`, `equipo_id`, `cliente_id`, `planta_id` (`supabase/migrations/202608240003_metrology_online.sql:224`); informe con el identificador | — | — | — |
| RT-02 | Fecha y hora al capturar | Parcial | `recibido_at` es la llegada. En línea, `realizado_at` es la hora del servidor al finalizar (`202608310001_normative_metrology_engine.sql:513,565`); sin señal, la hora del teléfono al finalizar, corregida por el desfase de su reloj, con constancia de lo informado (`private.capturas_sin_conexion`, `202610090002_offline_capture.sql:21,118`) | El inicio de la captura no pasa a la evidencia | S | Bajo |
| RT-03 | Responsable desde la sesión autenticada | Cumple | `capturado_por` = dueño del borrador y `finalizado_por` = `auth.uid()` (`202608310001…:565`); no hay campo editable | — | — | — |
| RT-04 | Quién revisa datos y resultados | No cumple | No existe una revisión por otra persona; el jefe de calidad solo puede anular | Para el caso A o B hace falta una revisión registrada | A | Medio |
| RT-05 | Información para repetir y estimar | Cumple | Copia del equipo y rangos (`equipo_snapshot`) y de la configuración (`plan_snapshot`), patrones con su certificado (`verificacion_patrones.snapshot`), temperatura, humedad, motor y regla de decisión (`202608240003…:233-246`) | — | — | — |
| RT-06 | Patrones vencidos advertidos o justificados | Cumple | El servidor marca `validAtMeasurement` y la trazabilidad (`202608310001…:572`); la captura avisa «Un certificado vencido no aporta trazabilidad»; Plantas › Patrones registra certificados, marca cada uno vigente, vencido o anulado y avisa del patrón sin certificado vigente (`202610200002_pattern_certificates.sql`, [certificados](../pattern-certificates.md)) | — | — | — |
| RT-07 | Observaciones originales; sugerencias confirmadas | Cumple | Las sugerencias se aplican solo con «Usar sugerencia» (`app/lib/features/online/flexible_trial_fields.dart:228`); el servidor guarda las lecturas tal como se enviaron | — | — | — |
| RT-08 | Modificación con anterior, nuevo, fecha, quién y motivo | Cumple | Lo finalizado no se modifica: corregir es anular con motivo (`annul_ivmet_verification`, `202608240005_rls_and_workflows.sql:580`) y registrar otra; las fichas de balanza suben versión y dejan auditoría | — | — | — |
| RT-09 | Sin sobrescritura silenciosa | Cumple | Guardado con `expected_version` y conflicto explícito; la app no pisa la versión del servidor («Ver datos del servidor») | — | — | — |
| RT-10 | Sin borrado físico; anulación con motivo | Cumple | Triggers `prevent_evidence_mutation` en pruebas, lecturas y patrones (`202608240003…:491-550`); la eliminación de cuenta conserva la evidencia (`202610090001_account_deletion.sql`) | — | — | — |
| RT-11 | Registro enviado no modificable sin control | Cumple | La verificación nace definitiva en el servidor; no hay edición posterior | — | — | — |
| RT-12 | Fotos y evidencias vinculadas | No aplica | IvMET no captura fotografías | — | — | — |
| RT-13 | Versión de la app en el registro | Cumple | `app_version` con la versión real (`app/lib/core/constants/app_config.dart:20`, `draft_controller.dart:622`); una prueba la ata a `pubspec.yaml`. Hasta esta entrega se enviaba un texto fijo | — | — | — |

### DI: Datos y gestión de la información (7.11)

| ID | Literal | Requisito | Estado | Evidencia | Brecha | Cierre | Riesgo |
|---|---|---|---|---|---|---|---|
| DI-01 | 7.11.1 | Acceso a los datos necesarios | Cumple | Todo vive en el servidor; sin señal la app consulta la copia descargada y captura y finaliza en el teléfono, y envía al volver la conexión (`docs/offline-mode.md`) | — | — | — |
| DI-02 | 7.11.2 | Registro de validación por versión | No cumple | Hay pruebas automáticas (base de datos, funciones y app) y casos dorados del cálculo (`scripts/test-mobile-db.mjs:29`) | No hay registro de validación por versión; `pnpm db:test:operations` tiene **dos pruebas fallando** que nadie justificó | A | Alto |
| DI-03 | 7.11.2 | Cambios autorizados y documentados | Parcial | Cada entrega tiene su documento con despliegue y validación (`docs/*.md`) y su historial en git | Falta quién autorizó cada liberación y cuándo entró en uso | P | Medio |
| DI-04 | 7.11.2 | Versión identificable y visible | Cumple | Ajustes › Versión de la app (`workspace_screen.dart:597`), informe PDF y cada verificación | — | — | — |
| DI-05 | 7.11.3 a | Cuentas individuales, sesión con vencimiento, cuentas inactivas bloqueadas | Cumple | Una cuenta por persona; JWT de 15 min con rotación (`supabase/config.toml:35-36`); el servidor revalida perfil y licencia en cada llamada (`private.mobile_require`, `202608280003_mobile_online_contract.sql:14`); sin señal, la app trabaja como mucho 7 días desde la última validación y no se alarga atrasando el reloj (`app/lib/features/online/offline_copy.dart:19,134`) | — | — | — |
| DI-06 | 7.11.3 a | Contraseñas con hash, nunca en logs | Cumple | Supabase Auth; las funciones no registran contraseñas ni las envían a la base (`scripts/test-self-service-auth.mjs`) | — | — | — |
| DI-07 | 7.11.3 b | Transporte protegido | Cumple | La app rechaza cualquier URL que no sea HTTPS (`mobile_api.dart:25`); Supabase con TLS | — | — | — |
| DI-08 | 7.11.3 b | Permisos mínimos; no se altera ni borra | Cumple | RLS por empresa y planta (`202608240005…:164`), escrituras solo por RPC, sin permisos REST de escritura para el móvil | — | — | — |
| DI-09 | 7.11.3 b | Protección contra la pérdida: respaldo y restauración probada | Sin evidencia | El espejo SQL Server recibe catálogos y contratos, **no** las verificaciones privadas: la única copia de la evidencia es Supabase | No se conoce el respaldo del proyecto (plan, frecuencia, PITR) ni hubo una restauración de prueba | A | Alto |
| DI-10 | 7.11.3 c | Entorno de operación especificado | Parcial | Android, internet y cuenta descritos en el manual («Antes de empezar»); compilación descrita en `docs/app-install-guide.md` | Falta la versión mínima de Android declarada al usuario | P | Bajo |
| DI-11 | 7.11.3 d | Integridad de tipos, decimales y fechas | Cumple | Decimales como cadenas exactas y `numeric(19,9)`; coma en pantalla y punto al enviar (`draft_controller.dart:13`); `timestamptz` | — | — | — |
| DI-12 | 7.11.3 e | Fallas del sistema registradas con acciones | No cumple | Los errores se muestran a quien usa la app; los de las funciones van al registro de Supabase | No hay registro de incidencias con acción inmediata y correctiva | A | Alto |
| DI-13 | 7.11.4 | Servicios externos identificados y controlados | Parcial | Supabase (base, Auth, funciones), Megalink (SMTP del código), Google Play (distribución) | No están documentados ni evaluados como proveedores (ubicación de los datos, acuerdos, respaldo) | P | Medio |
| DI-14 | 7.11.5 | Manual vigente, controlado y disponible | Parcial | Manual dentro de la app, sin conexión y exportable en PDF con bloque de control (`app/lib/features/online/user_manual_content.dart`); también desde el acceso | Falta código, revisión y aprobación de Calidad | P | Bajo |
| DI-15 | 7.11.6 | Cálculos con pruebas de referencia | Parcial | Casos dorados OIML R 76 y regla ILAC (`scripts/test-mobile-db.mjs:29`), pruebas de cargas flexibles y de los casos de uso de la app | Una de las pruebas que fallan es «configuración guiada, decimales exactos» | S | Medio |
| DI-16 | 7.11.6 | Transferencias verificadas | Cumple | El servidor recalcula al finalizar; guardado y finalización idempotentes con hash; el espejo usa outbox con hash e idempotencia | — | — | — |
| DI-17 | 7.11.6 | Exportar no altera los datos | Parcial | El PDF se arma con los datos del servidor y conserva decimales | Ninguna prueba compara el contenido del PDF con el registro | S | Bajo |

### CR: Control de registros (8.4)

| ID | Requisito | Estado | Evidencia | Brecha | Cierre | Riesgo |
|---|---|---|---|---|---|---|
| CR-01 | Legibles y recuperables | Cumple | Historial, detalle con el expediente completo e informe PDF | — | — | — |
| CR-02 | Archivos identificados | Cumple | `verificacion_<código>_<fecha>.pdf` y pie con identificador y procedencia | — | — | — |
| CR-03 | Almacenamiento protegido | Parcial | Servidor con RLS; en el teléfono, tokens en almacenamiento seguro y captura local y copia para trabajar sin señal en la carpeta privada de la app, borrada al cerrar sesión | Una verificación finalizada sin señal depende del teléfono hasta enviarse; la copia no está cifrada aparte | S | Bajo |
| CR-04 | Respaldo definido | Sin evidencia | — | Ver DI-09 | A | Alto |
| CR-05 | Retención definida y respetada | Parcial | La evidencia se conserva sin plazo y la eliminación de cuenta no la borra | No hay plazo de conservación definido ni comunicado a los clientes | P | Medio |
| CR-06 | Disposición controlada y registrada | Cumple | No hay borrado de evidencia; cada eliminación de cuenta o empresa deja constancia (`private.eliminaciones_cuenta`, `202610090001…:17`) | — | — | — |
| CR-07 | Acceso según confidencialidad | Cumple | Aislamiento por empresa y planta; Métrica solo ve lo que el cliente autoriza, con consentimiento y retiro | — | — | — |
| CR-08 | Fácilmente disponibles | Cumple | Historial por balanza y por empresa, con paginación | — | — | — |

### TX: Transversales

| ID | Requisito | Estado | Evidencia | Brecha | Cierre | Riesgo |
|---|---|---|---|---|---|---|
| TX-01 | Solo personal autorizado (6.2.6) | Cumple | Licencias y cupos, roles, plantas y balanzas por operador; desactivar corta el acceso al instante en línea, y el servidor rechaza lo que una cuenta desactivada capturó sin señal | — | — | — |
| TX-02 | Manual y procedimientos controlados (8.3) | Parcial | Bloque de control y historial de revisiones en el manual | Código y aprobación pendientes | P | Bajo |
| TX-03 | Falla que afectó resultados → trabajo no conforme (7.10) | No aplica | Lo decide la empresa cliente con su procedimiento; IvMET permite anular con motivo | — | — | — |
| TX-04 | Informes según 7.8 | No aplica | El informe declara que no es un certificado de calibración ni un informe de laboratorio | — | — | — |

## 4. Brechas priorizadas

### DI-09 y CR-04 — Respaldo y restauración (alto)

- **Qué falta:** el evaluador preguntará dónde están los respaldos y cuándo se
  probó una restauración. Las verificaciones privadas no van al espejo SQL
  Server: si se pierde el proyecto de Supabase, se pierde la evidencia.
- **Propuesta:** confirmar en el plan de Supabase los respaldos diarios y,
  si el caso A aplica, activar PITR; restaurar una vez en un proyecto de prueba
  y comparar recuentos de verificaciones, pruebas y lecturas; documentarlo en
  un procedimiento de respaldo con frecuencia, retención y responsable.
- **Demostración:** acta de la restauración de prueba con fecha y recuentos.

### DI-12 — Registro de fallas del sistema (alto)

- **Qué falta:** «¿Qué pasó la última vez que falló el sistema y qué se hizo?».
  Hoy queda en el registro de Supabase y en la memoria de quien lo atendió (por
  ejemplo, la falla del correo del código del 08/10).
- **Propuesta:** usar el Registro de fallas de RimMET también para IvMET, con
  origen, impacto en registros, acción inmediata, causa y acción correctiva; y,
  en una entrega posterior, reporte desde la app (versión, pantalla, mensaje).
- **Demostración:** la falla del 08/10 registrada y cerrada.

### DI-02, DI-03 y DI-15 — Validación por versión (alto)

- **Qué falta:** quién validó y autorizó la 1.0.0 y con qué pruebas; dos
  pruebas de `pnpm db:test:operations` fallan («configuración guiada,
  decimales exactos y plan interno inmutable» y «no exporta evidencia ni
  auditoría…»).
- **Propuesta:** corregir esas dos pruebas o justificar por escrito por qué no
  aplican; crear `docs/iso17025/validaciones/VAL-<versión>.md` con la plantilla
  de ServiceMET en cada liberación (pruebas, casos con valores de referencia,
  autorización y fecha de puesta en uso).

### RT-04 — Revisión de datos y resultados (medio)

- **Propuesta:** si el caso A o B aplica, agregar «Revisar» para el jefe de
  calidad en la verificación finalizada (quién y cuándo revisó, sin cambiar la
  evidencia). Mientras tanto, el procedimiento del cliente define quién revisa.

### RT-06 — Registrar certificados (resuelto)

- **Avance:** Plantas › Patrones vuelve a registrar certificados (número,
  laboratorio, fecha de calibración y vencimiento) y muestra si cada uno está
  vigente, vencido o anulado. El servidor rechaza números repetidos y fechas
  imposibles con motivos claros
  ([certificados de las pesas patrón](../pattern-certificates.md)).

### RT-02 — Hora de inicio de la captura (bajo)

- **Avance:** una verificación finalizada sin señal ya lleva la hora en que se
  midió y la de llegada, con constancia de lo que informó el teléfono
  ([trabajo sin conexión](../offline-mode.md)).
- **Propuesta:** copiar también al registro la hora en que se abrió la
  captura (el teléfono ya la envía como `started_at`) y mostrarla en el
  detalle y el informe.

### CR-03 — Verificaciones finalizadas en el teléfono (bajo)

- **Qué falta:** hasta que vuelve la señal, una verificación finalizada sin
  conexión solo está en el teléfono: borrar los datos de la app o perderlo la
  pierde. La franja de conexión y Por enviar la muestran siempre, y no se
  puede cerrar sesión ni eliminar la cuenta con envíos pendientes.
- **Propuesta:** instrucción de trabajo: conectarse al terminar la jornada en
  planta. Si un cliente lo exige, cifrar la copia (SQLCipher).

### CR-05 — Plazo de conservación (medio)

- **Propuesta:** Métrica define cuánto conserva la evidencia (por ejemplo, el
  plazo que exija su procedimiento o el que pidan los clientes acreditados) y
  qué pasa al vencer; se publica en las condiciones de uso.

### DI-13 — Proveedores externos (medio)

- **Propuesta:** ficha de cada proveedor (Supabase, Megalink, Google Play):
  qué datos procesa, dónde, con qué respaldo y qué acuerdo lo cubre.

## 5. Lo que depende de Métrica

- Si el laboratorio usará IvMET con sus propios equipos (caso A).
- Plazo de conservación de la evidencia y disposición al vencer.
- Respaldo del proyecto de Supabase: plan contratado, frecuencia, prueba de
  restauración y responsable.
- Quién autoriza cada versión antes de publicarla en Play Store.
- Código del manual en el sistema documental, revisión y aprobación.
- Registro de fallas de IvMET y su seguimiento.
- Revisión de las condiciones de uso (`ivmet-terms-v1`).

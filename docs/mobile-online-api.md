# Contrato móvil online v1

El móvil usa la URL de Supabase. No usa `/api/ivmet/v1` del backend antiguo.
Cabeceras: `apikey` pública, `Content-Type: application/json` y, salvo login,
`Authorization: Bearer <access token del usuario>`. Nunca service_role.

## Autenticación

- `POST /functions/v1/ivmet-login`: `{username,password}` →
  `{accessToken,refreshToken,expiresIn,tokenType,user,access}`.
- `POST /auth/v1/token?grant_type=refresh_token`: `{refresh_token}` → par
  rotado nativo de Supabase. El cliente serializa renovaciones concurrentes.
- `POST /auth/v1/logout?scope=local`: revocación de la sesión actual.
- `POST /functions/v1/ivmet-change-password`: `{password}` (12–200 caracteres)
  → `{changed,mustChangePassword}`. La sesión propia se valida con Auth.

## Lecturas

`POST /rest/v1/rpc/ivmet_mobile_read`: `{section,filters}`.

| section | Filtros | Respuesta |
| --- | --- | --- |
| session | ninguno | contractVersion=1, serverTime, user, access |
| bootstrap | ninguno | client, plants, areas, equipmentCount, openAlerts, engineVersion, finalizationEnabled |
| instruments | plantId?, areaId?, search?, page?, pageSize? | total, items |
| equipment | equipmentId | equipment, ranges, plan, patterns con certificados |
| history | equipmentId?, page?, pageSize? | total, items de verificaciones privadas |
| verification | id | verification, users, tests/readings, patterns, alert, cases/events |
| drafts | equipmentId?, page?, pageSize? | total, items de borradores propios no vencidos |
| draft | id | borrador propio, payload y context_snapshot |

Página inicial 1, tamaño 25, máximo 100. El servidor determina cliente y
plantas desde `auth.uid()`; los filtros nunca amplían permisos. `session` es
la única consulta disponible sin licencia activa, para mostrar el bloqueo.
Los roles internos no pueden consultar evidencia móvil.

## Guardado privado

`POST /rest/v1/rpc/ivmet_mobile_save_draft`:

```json
{
  "request_id": "UUID estable del borrador",
  "equipment_id": "UUID del equipo autorizado",
  "version_id": "UUID de la versión publicada asignada",
  "expected_version": "0",
  "save_id": "UUID estable de este intento de guardado",
  "content": {
    "temperature": "23.125",
    "humidity": "50",
    "observations": "",
    "certificates": [],
    "tests": [{
      "id": "UUID de plan_pruebas",
      "omitted": false,
      "reason": "",
      "readings": [{"pointId":"UUID de plan_puntos","indication":"0.123456789","zero":""}]
    }]
  }
}
```

Las cadenas explicativas de UUID del ejemplo deben sustituirse por UUID reales.
Todas las pruebas del plan deben estar presentes. Una prueba omitida exige
motivo y lecturas vacías. Los campos vacíos se permiten en borradores, pero
una lectura no vacía debe ser cadena decimal normalizada, máximo 10 enteros
y 9 decimales, sin exponentes ni separadores de miles. Condiciones: hasta 3
decimales, humedad entre 0 y 100. Máximo 256 KiB y 500 lecturas por prueba.

Respuesta: `{id,requestId,version,savedAt}`. Primera escritura con versión 0;
las siguientes requieren la versión devuelta. Repetir `save_id` con contenido
idéntico devuelve el resultado previo; cambiarlo con contenido diferente da
`IDEMPOTENCY_CONFLICT`. Un guardado desde una versión antigua da
`ROW_VERSION_CONFLICT`; reabrir el borrador, no sobrescribir a ciegas.
Cada llamada es una transacción. No hay sincronización offline ni lotes.

La versión retirada puede continuar en un borrador creado durante su asignación.
No se puede iniciar otro con una versión retirada. Los borradores caducan a los
30 días según el servidor. No se permite ampliarlo mediante REST.

## Finalización privada

La extensión de captura v2 se anuncia con `plan.captureVersion: 2` y
`plan.captureEngineVersion: ivmet-internal-2.0.0`. Mantiene las mismas RPC e
idempotencia y agrega cargas utilizadas, configuración por prueba, grupos y
filas retiradas al contenido del borrador. Las lecturas de pruebas omitidas se
conservan en v2 y quedan excluidas de la evaluación. Consultar el
[DTO y sus reglas](flexible-metrology-capture.md#contrato-y-recuperación).
El ejemplo de guardado anterior corresponde al protocolo v1, que continúa
admitiéndose para compatibilidad; no se cambia el protocolo de un borrador existente.

`POST /rest/v1/rpc/ivmet_mobile_finalize_draft`:

```json
{
  "draft_id": "UUID del borrador",
  "expected_version": "1",
  "finalize_id": "UUID estable del intento",
  "app_version_value": "ivmet-flutter-v1",
  "device_id_value": ""
}
```

Solo se habilita cuando el snapshot contiene un perfil controlado y el motor
`ivmet-internal-1.0.0`, o la capacidad de captura v2 indicada arriba. El servidor exige al menos una prueba completa, ignora
cualquier veredicto del cliente y calcula lecturas, métricas, veredictos,
trazabilidad, alerta y alcance en una transacción. Respuesta:
`{id,draftId,version,verdict,traceability,scope,alertCreated,idempotent}`.

Un certificado vencido produce `non_traceable` y alerta privada, no rechazo.
`inconclusive` es un resultado posible con banda de guarda. La evidencia se
inserta una vez y después es inmutable. Ver el
[contrato metrológico](normative-metrology-engine.md).

## Consentimiento y evidencia

Se reutilizan las RPC de privacidad existentes, exclusivas del jefe de calidad
autorizado y con licencia:

1. `preview_ivmet_alert_share({target_alert_id})` → snapshot, snapshotHash,
   alertVersion, consentVersion, notice. Mostrar el expediente completo.
2. `confirm_ivmet_alert_share({target_alert_id,expected_row_version,
   expected_snapshot_hash,share_message})` → id, codigo. Solo después de marcar
   el consentimiento. El servidor rechaza previews obsoletas.
3. `withdraw_ivmet_case({target_case_id,expected_row_version,reason})`.
4. `annul_ivmet_verification({target_verification_id,annulment_reason})`.

Ninguna operación comparte todo el historial ni habilita acceso general a
Métrica. La retirada conserva evidencia y no elimina copias entregadas.

## Errores y límites

Las RPC devuelven errores PostgREST con `message`: `MOBILE_ACCESS_DENIED`,
`EQUIPMENT_NOT_ACCESSIBLE`, `DRAFT_NOT_ACCESSIBLE`, `PLAN_NOT_ASSIGNED`,
`DRAFT_EXPIRED`, `ROW_VERSION_CONFLICT`, `IDEMPOTENCY_CONFLICT`,
`INVALID_DECIMAL_STRING`, `OMISSION_REASON_REQUIRED`, `INCOMPLETE_TEST`,
`ALL_TESTS_OMITTED`, `FINALIZATION_CONFLICT`, `DECISION_RULE_INVALID`, entre otros.
La app muestra mensajes controlados, no SQL ni cabeceras. Ante 401 intenta
una renovación; sin conexión protege la pantalla y permite revalidar.

No se aceptan campos de veredicto en el payload. `finalizationEnabled` proviene
del snapshot creado por el servidor; Flutter no puede activarlo.

## Configuración administrada por el cliente

`POST /rest/v1/rpc/ivmet_customer_read` recibe `{section,filters}`:

| section | Filtros principales | Uso |
| --- | --- | --- |
| `equipment` | `id` | Maestro, corrección privada, áreas y sugerencia. |
| `areas`, `area-suggestions` | `plantId`, paginación | Áreas de una planta y coincidencias de Ubicación. |
| `patterns` | `plantId`, paginación | Patrones y certificados históricos. |
| `share-preview` | `id` de equipo | Snapshot exacto y hash antes de autorizar. |
| `updates` | `id?`, paginación | Recibos de fichas compartidas y su estado. |

`POST /rest/v1/rpc/ivmet_customer_mutate` recibe
`{action,payload,request_id}`. `request_id` y el payload se mantienen idénticos
si la respuesta no pudo confirmarse.

Acciones del operador y jefe: `area.save`, `equipment.validate`,
`pattern.save`, `certificate.create`, `certificate.annul`. Son exclusivas del
jefe de calidad `update.share` y `update.withdraw`.

`POST /rest/v1/rpc/ivmet_customer_configure_checks` recibe
`{equipment_id,configuration,request_id}`. `configuration.tests` contiene las
comprobaciones seleccionadas, periodicidad y error permisible. El servidor
genera referencias internas desde la capacidad; cargas y cantidades antiguas
se ignoran porque se declaran al ejecutar. Luego elige el perfil, publica una
versión interna y la asigna a la balanza de forma atómica. Solo puede invocarlo el jefe
de calidad y requiere que la ficha esté validada y tenga rangos de medición.
Los contratos anteriores `plan.*`, `plans`, `plan` y `method-catalog` responden
`LEGACY_PLAN_MANAGEMENT_DISABLED`.

`equipment.validate` solo escribe el overlay del cliente y el área seleccionada;
no modifica la tabla maestra. `update.share` exige el hash mostrado por
`share-preview`, un mensaje y consentimiento explícito. Su snapshot contiene la
ficha de esa balanza, no resultados, configuraciones, patrones ni historial.

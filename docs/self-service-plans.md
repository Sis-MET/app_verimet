# Autoregistro de empresas y planes con límites

Entrega del 08/10/2026. IvMET deja de depender de que Métrica dé de alta a cada
cliente: cualquier empresa que instale la app desde Play Store crea su cuenta,
empieza en el plan **Gratuito** y, cuando sus límites le quedan cortos, pide un
plan superior desde la app. Métrica atiende la solicitud y cambia el plan en
RimMET. La app no muestra precios ni cobra.

Migración: `202610080001_self_service_plans.sql`. Edge Functions nuevas:
`ivmet-signup`, `ivmet-password-reset` e `ivmet-team-account`.

## Resultado funcional

### Crear la cuenta

- En el acceso, **Crear cuenta de empresa** abre un asistente de tres pasos:
  la empresa (nombre, primera planta, ciudad, país y teléfono), la cuenta de
  quien la registra (nombre, correo, contraseña de 12 caracteres o más y
  aceptación de las condiciones de uso) y el **código de 6 dígitos** que llega
  al correo. Al confirmarlo se entra directamente.
- Quien registra la empresa es su **jefe de calidad** y entra con su correo.
  El campo del acceso ahora dice **Usuario o correo**.
- Un correo que ya tiene cuenta no se registra dos veces: la app sugiere
  ingresar o recuperar la contraseña.
- **¿Olvidaste tu contraseña?** envía un código al correo y permite elegir una
  nueva. Solo sirve para cuentas cuyo usuario es su correo; las demás las
  restablece su jefe de calidad (o Métrica, en las empresas que gestiona).

### Plan Gratuito y planes superiores

La migración siembra tres planes. Sus límites y funciones se editan en RimMET y
rigen al instante para todas las empresas del plan:

| | Gratuito | Profesional | Empresa |
| --- | --- | --- | --- |
| Usuarios | 2 | 10 | 30 (ampliables con cupos) |
| Plantas | 1 | 3 | sin límite |
| Balanzas habilitadas | 5 | 50 | sin límite |
| Verificaciones por mes | 20 | sin límite | sin límite |
| Pesas patrón activas | 3 | sin límite | sin límite |
| Informe PDF | resumido | completo | completo |
| Periodicidad | predefinida | a medida | a medida |
| Vencimiento | ninguno | el contratado | el contratado |

- **Verificaciones por mes**: cuentan las finalizadas desde el día 1 (hora de
  Bolivia, UTC−4) más las capturas en curso. Se bloquea **empezar** una
  captura nueva; un borrador ya empezado siempre se puede seguir y finalizar.
- **Informe resumido**: identificación, condiciones, resumen de resultados y
  avisos legales. El completo agrega las lecturas de cada prueba, el croquis,
  los gráficos y la trazabilidad de las pesas patrón.
- **Periodicidad predefinida**: los accesos rápidos con fechas fijas (diaria,
  semanal, quincenal, mensual, bimestral, trimestral, semestral, anual).
  «Personalizada» y «Desde la última» muestran un candado.
- Las empresas que incorporó Métrica siguen con sus planes de siempre, que no
  traen límites: nada cambia para ellas.

### Cómo se nota el límite

- **Inicio** muestra al jefe de calidad una franja «Plan Gratuito · 4 de 5
  balanzas · Mejorar», con el recurso más usado.
- **Ajustes › Mi plan**: el uso de cada límite con su barra, las funciones
  incluidas, los planes que se ofrecen y la solicitud abierta.
- Al tocar algo que el plan no admite —registrar la sexta balanza, crear otra
  planta u otro usuario, empezar una captura con el mes completo, elegir una
  periodicidad a medida, pedir el informe completo— se abre un aviso que dice
  qué incluye el plan y ofrece **Solicitar plan superior**. Al operador se le
  indica que lo pida el jefe de calidad.
- La solicitud lleva el plan que interesa (o «asesoría»), el motivo, un mensaje
  y un teléfono opcional; Métrica recibe además el correo de la empresa. Hay
  una sola solicitud abierta por empresa y se puede cancelar desde ⋮.

### La empresa se gestiona sola

Solo en empresas autoregistradas (en las de Métrica sigue siendo RimMET):

- **Ajustes › Usuarios**: el jefe crea cuentas de operador o de jefe de calidad
  con usuario, plantas y una contraseña temporal que la app genera y muestra
  una sola vez para entregarla. Edita nombre, rol y plantas; desactivar una
  cuenta libera su cupo y conserva su historial; **Contraseña temporal** obliga
  a cambiarla en el próximo acceso. Nadie se quita su propio rol ni se
  desactiva a sí mismo.
- **Plantas › Nueva planta** y **⋮ › Editar planta** (nombre, ciudad,
  dirección). Desactivar exige que no tenga balanzas activas y que quede otra.
- Las balanzas se registran como hasta ahora (**Registrar balanza**), dentro
  del límite del plan.

### RimMET

- **Solicitudes de plan** (nueva entrada, con el número de abiertas): empresa,
  plan pedido, motivo, mensaje, contacto y estado. **Atender** la marca como
  contactada o la cierra (cambió de plan / no avanzó) con una nota interna.
- **Clientes**: las autoregistradas dicen «Registrada desde la app» y «Se
  gestiona desde la app», muestran su plan y avisan si pidieron uno superior.
- **Ficha › Contrato y pagos** arranca con **Plan y uso**: cada límite contra lo
  usado, las funciones, **Cambiar plan** y las solicitudes de la empresa. El
  banner muestra el correo, teléfono y ciudad con que se registró.
- **Cambiar plan** cambia límites, funciones y cuentas base sin cortar el
  acceso y cierra las solicitudes abiertas. Al salir del Gratuito (que no
  vence) pide el fin del período para que después se pueda renovar y cobrar
  con las facturas y pagos de siempre. Rechaza un plan con menos cuentas que
  las licencias activas.
- **Planes y tarifas**: cada plan muestra sus límites y funciones, y el
  formulario los edita (vacío = sin límite), junto con si se ofrece en la app,
  su orden, el resumen que ve el cliente y cuál es el plan de autoregistro.
  Solo puede haber uno de autoregistro activo; desactivarlo pausa las altas.

## Cómo está construido

- **Condiciones del plan** en `planes_comerciales.caracteristicas`:
  `{limits:{plants,equipment,monthlyVerifications,patterns}, features:{fullReport,
  customSchedules}, catalog:{visible,order,selfService,summary}}`. Ese JSON ya
  viaja al espejo SQL Server, así que el worker y SQL Server no cambian. Una
  restricción (`private.plan_terms_valid`) valida la forma; clave ausente o nula
  es sin límite o función incluida. Los usuarios los limitan los cupos de la
  suscripción, como antes.
- **Empresa autoregistrada**: `clientes.origen='AUTOREGISTRO'`, sin
  `legacy_cliente_id`, con código `IV000001` y plantas `IV000001-01`. Su
  contacto vive en `private.empresas_autoregistro`. El alta crea en una sola
  transacción cliente, planta, perfil, alias de login (el correo), contrato
  `IVMET-IV000001`, suscripción sin vencimiento (`fin_periodo='infinity'`),
  cupos y licencia.
- **Correo con código**: los registros públicos de Auth siguen cerrados.
  `ivmet-signup` crea la cuenta Auth con una contraseña de relleno que nadie
  conoce y pide a Auth un código (`signInWithOtp`, plantilla Magic Link). Al
  completar verifica el código, fija la contraseña elegida y llama a
  `ivmet_signup_complete`. Quien inició un alta con un correo ajeno no obtiene
  nada: sin el código no hay perfil ni acceso.
- **Límites en el servidor**: `ivmet_customer_mutate` (balanzas y patrones),
  `self_service_mutate` (plantas), `ivmet_team_account` y la restricción de
  cupos (usuarios), `ivmet_mobile_save_draft` (primer guardado de cada captura)
  e `ivmet_customer_configure_checks` (periodicidad). Un reintento de algo ya
  hecho devuelve su recibo aunque el plan esté lleno. El informe resumido se
  arma en la app; los datos completos siguen disponibles por la API.
- **Privacidad**: nada de una empresa autoregistrada llega al espejo SQL Server
  (trigger `sync_outbox_self_service`, igual que las balanzas registradas por el
  cliente). RimMET la ve por sus RPC.
- **Solicitudes**: `public.solicitudes_plan`, sin acceso REST; una abierta por
  empresa.
- Contratos: [API móvil](mobile-online-api.md#planes-autoregistro-y-solicitudes)
  y, en RimMET, `docs/ivmet-management.md`.

## Despliegue

No cambia SQL Server ni el worker.

1. Validar en el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:plans
pnpm db:test:admin
pnpm db:test:mobile
pnpm test:mobile-auth
```

`pnpm db:test:operations` mantiene sus dos fallos previos, ajenos a esta
entrega.

```powershell
Set-Location .\app
flutter analyze
flutter test
```

2. **Configurar el correo de Supabase** (Dashboard › Authentication), antes de
   publicar la app:
   - **SMTP propio** (Emails › SMTP Settings). El correo por defecto de
     Supabase solo llega a miembros del proyecto y tiene un tope muy bajo.
   - Plantilla **Magic Link** con el código: `{{ .Token }}`. Hay un modelo en
     `supabase/templates/codigo-ivmet.html` (asunto «Tu código de IvMET»).
   - Email OTP: 6 dígitos y vencimiento de 900 s; un envío por minuto por
     correo. Revisar el límite de correos por hora en Rate Limits.
   - **Allow new users to sign up** debe seguir **desactivado**: las cuentas
     las crea `ivmet-signup`.
3. Aplicar la migración. El ensayo debe mostrar
   `202610080001_self_service_plans.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

```powershell
pnpm dlx supabase db lint --linked --level warning
```

4. Desplegar las Edge Functions nuevas:

```powershell
pnpm dlx supabase functions deploy ivmet-signup ivmet-password-reset ivmet-team-account --no-verify-jwt
```

5. Publicar RimMET (backend y frontend juntos). Revisar en **Planes y tarifas**
   los tres planes sembrados, ajustar sus límites si hace falta y cargar las
   tarifas de Profesional y Empresa.
6. Compilar y distribuir la app (`pnpm app:aab`).

La migración va antes que RimMET y la app, y RimMET se publica junto con ella:
un RimMET anterior no sabe mostrar el período sin vencimiento del Gratuito y
falla al abrir la ficha de una empresa autoregistrada. Para las empresas de
Métrica sigue funcionando. Una app anterior no ofrece registrarse.

## Validación manual antes de publicar

- Registrar una empresa con un correo real: llega el código, al confirmarlo se
  entra en Inicio con la franja del plan Gratuito.
- Cerrar sesión y entrar con el correo; recuperar la contraseña con un código.
- Crear un operador desde Ajustes › Usuarios, entrar con él (pide cambiar la
  contraseña) y comprobar que ve solo lo asignado.
- Registrar 5 balanzas e intentar la sexta: aparece el aviso y la solicitud.
- Configurar una prueba e intentar «Personalizada»: candado.
- Generar el informe de una verificación: sale resumido.
- En RimMET, ver la solicitud, atenderla, cambiar el plan a Profesional con
  fin de período y comprobar en la app el nuevo plan y el informe completo.
- Confirmar en SQL Server `IvMET` que no llegó nada de la empresa y que el
  outbox no tiene eventos muertos.

## Decisiones abiertas

- **Política de pagos de Google Play.** Play exige su sistema de facturación
  para suscripciones de software vendidas dentro de la app y no permite
  dirigir a otros medios de pago. La app no muestra precios ni pagos y
  redacta la acción como solicitud de contacto, pero Google puede observarla.
  Si ocurre, la alternativa es Google Play Billing; el modelo de planes y
  límites no cambia, solo el canal del cambio de plan.
- **Condiciones de uso.** El texto de `self_service_access.dart`
  (`ivmet-terms-v1`) es un borrador redactado con lo que la app ya declara.
  Debe revisarlo quien corresponda en Métrica antes de publicar. Cambiar el
  texto de forma sustancial exige una versión nueva en la app, en
  `ivmet-signup` y en `ivmet_signup_complete`.
- **Conteo de balanzas en RimMET.** Las balanzas registradas por la empresa no
  aparecen en los listados ni en los conteos de RimMET; **Plan y uso** sí
  muestra cuántas hay habilitadas, porque es el límite que se vende. No
  muestra cuáles.
- **Fin de un plan pagado.** Si una empresa autoregistrada deja vencer un plan
  de pago, pierde el acceso igual que cualquier contrato (con gracia y
  suspensión). Para devolverla al Gratuito, **Cambiar plan** a Gratuito. Bajar
  sola al Gratuito queda para otra entrega.
- **Altas a medias.** Un alta que pidió el código y nunca lo confirmó deja una
  cuenta Auth sin perfil, que no sirve para entrar. Limpiarlas es una tarea
  periódica pendiente.
- **Eliminar la cuenta o la empresa**, que pide Google Play, está en
  [Eliminación de cuenta y manual](account-deletion-and-manual.md).

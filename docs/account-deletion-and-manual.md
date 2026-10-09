# Eliminación de cuenta, manual de uso y versión de la app

Tres cambios para publicar en Play Store y para el control de registros de la
NB/ISO/IEC 17025 (ver el [análisis](iso17025/analisis-ivmet.md)):

- **Eliminar la cuenta o la empresa**, desde la app y desde una página web. Es
  requisito de Google Play para toda app donde se crean cuentas.
- **Manual de uso** detallado dentro de la app, con copia controlada en PDF.
- **Versión real de la app** en Ajustes y en cada verificación.

## Eliminar la cuenta

### Desde la app

Ajustes › ⋮:

- **Eliminar mi cuenta**, para cualquier usuario.
- **Eliminar la empresa**, solo para el jefe de calidad de una empresa
  autoregistrada. Las empresas de Métrica se dan de baja en RimMET, por
  contrato; sus usuarios sí pueden eliminar su propia cuenta.

La pantalla dice qué se elimina y qué se conserva antes de confirmar, y pide la
contraseña y una casilla de «Entiendo». Al terminar, la app borra las capturas
locales, cierra la sesión y vuelve al acceso con el aviso.

El único jefe de calidad de una empresa autoregistrada no puede eliminar solo
su cuenta (`LAST_QUALITY_MANAGER`): primero nombra a otro jefe en Ajustes ›
Usuarios o elimina la empresa completa.

### Desde la web

`https://metrica.com.bo/ivmet/eliminar-cuenta` (fuente en
`web/eliminar-cuenta/`). Quien la pide se identifica con un código enviado a
su correo («Con mi correo», si su usuario es su correo) o con usuario y
contraseña, y elige su cuenta o la empresa. Es la dirección que se registra en
Play Console.

### Qué se elimina y qué se conserva

| | Cuenta | Empresa |
|---|---|---|
| Acceso: alias de login, licencia, asignaciones de plantas y balanzas | Se elimina | Se elimina, de todas las cuentas |
| Cuenta Auth | Bloqueada, con correo interno `deleted.<id>@users.ivmet.invalid`: el correo real queda libre | Igual, todas |
| Nombre, usuario, correo y teléfono | «Usuario eliminado» | «Usuario eliminado» y «Empresa eliminada»; se borra el contacto del alta |
| Capturas sin finalizar | Abandonadas | Abandonadas |
| Solicitudes de plan | Sin datos de contacto ni mensaje | Canceladas y sin contacto |
| Plan, contrato, cupos, plantas, balanzas | — | Cancelados o inactivos |
| Verificaciones finalizadas, pruebas, lecturas, patrones usados | **Se conservan**, firmadas por «Usuario eliminado» | **Se conservan**, sin el nombre de la empresa |
| Auditoría | Se conserva | Se conserva |

La evidencia metrológica de IvMET es inmutable y la empresa la necesita para
demostrar lo que se midió (7.5 y 8.4). Por eso no se borra: queda desvinculada
de las personas. Si la empresa no existe más, queda sin nombre.

### Constancia

Cada eliminación deja una fila en `private.eliminaciones_cuenta` (quién, cuenta
o empresa, app o web, qué cuentas, cuándo y cuándo se bloquearon en Auth), un
evento `ACCOUNT_DELETED` o `COMPANY_DELETED` en `auditoria` y un
`ACCOUNT_DELETED` por persona en `eventos_licencia`. Dos envíos simultáneos
de la misma eliminación dejan una sola constancia.

Si Auth falla después de anonimizar, la eliminación ya ocurrió (la cuenta no
entra a IvMET: no tiene alias, licencia ni perfil activo), pero la constancia
queda abierta (`auth_cerrado_at` vacío). La siguiente eliminación la
reintenta. Para revisar las abiertas:

```sql
select id, solicitado_at, alcance, usuarios
from private.eliminaciones_cuenta
where auth_cerrado_at is null
order by solicitado_at;
```

### Cómo está construido

- Migración `202610090001_account_deletion.sql`: `ivmet_account_delete`
  (anonimiza y deja la constancia), `ivmet_account_deletion_done` e
  `ivmet_account_deletions_pending`. Solo `service_role`.
- Edge Function `ivmet-account-delete`: identifica a quien la pide, llama a la
  base y bloquea las cuentas Auth. Contrato en la
  [API móvil](mobile-online-api.md#eliminar-la-cuenta).
- App: `account_deletion.dart` y el ⋮ de Ajustes.
- Web: `web/eliminar-cuenta/index.html` y `config.js`, que genera
  `pnpm web:eliminar-cuenta` desde `app/config/supabase.prod.json`. Lleva solo
  la URL y la clave publicable; el script rechaza una clave secreta. `config.js`
  no se versiona.

## Manual de uso

- Ajustes › Ayuda › **Manual de uso**, y en el acceso, **Manual de uso** (sin
  sesión). Funciona sin conexión.
- 22 secciones en seis grupos (empezar, preparar, verificar, registros, cuenta,
  ayuda), con buscador que ignora acentos, pasos que se marcan y la píldora
  «Siguiente: …». Usa los nombres reales de las pantallas y botones.
- ⋮ › **Exportar PDF**: copia con el bloque de control (código, revisión,
  fecha, aplica a, elaboró, revisó, aprobó), el historial de revisiones y un
  pie con el estado de aprobación.

Es un **documento controlado** (7.11.5 y 8.3). Sus datos de control están en
`ivmetUserManual.control` (`app/lib/features/online/user_manual_content.dart`):

- Mientras «Aprobó» empiece con `PENDIENTE`, la app y el PDF dicen
  «Pendiente de aprobación». Calidad asigna el código y aprueba; se cambian
  `code`, `reviewedBy`, `approvedBy` y la revisión pasa a `01`.
- Si cambia una pantalla, se actualiza su sección, sube la revisión y se agrega
  una línea a `history`.
- `test/online/user_manual_test.dart` falla si «Aplica a» no coincide con la
  versión menor de `pubspec.yaml`: subir a 1.1 obliga a revisar el manual.

## Versión de la app

`AppConfig.version` (`app/lib/core/constants/app_config.dart`) es la versión y
el build de `pubspec.yaml`. Se ve en Ajustes › Versión de la app y viaja en cada
verificación finalizada como `app_version` (`ivmet-flutter-1.0.0+1`). Antes se
enviaba un texto fijo (`ivmet-flutter-v1`), que no permitía saber con qué
versión se capturó un registro. Al subir la versión en `pubspec.yaml` hay que
cambiar también `AppConfig.version`; `test/core/app_version_test.dart` lo
exige.

## Despliegue

No cambia SQL Server, el worker ni RimMET.

1. Validar en el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:plans
pnpm db:test:admin
pnpm db:test:mobile
pnpm test:mobile-auth
```

```powershell
Set-Location .\app
flutter analyze
flutter test
```

2. Aplicar la migración. El ensayo debe mostrar
   `202610090001_account_deletion.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

3. Desplegar la función:

```powershell
pnpm dlx supabase functions deploy ivmet-account-delete --no-verify-jwt
```

4. Generar y publicar la página web:

```powershell
pnpm web:eliminar-cuenta
```

   Subir `web/eliminar-cuenta/index.html` y `config.js` a
   `https://metrica.com.bo/ivmet/eliminar-cuenta/`. Si la dirección es otra,
   cambiar `accountDeletionUrl` en `account_deletion.dart` y la sección
   «Eliminar la cuenta» del manual. La página llama a
   `<proyecto>.supabase.co/functions/v1/ivmet-account-delete` desde el
   navegador; la función ya responde CORS.

5. Play Console › Contenido de la app › **Seguridad de los datos**: declarar que
   las cuentas se pueden eliminar, con la URL del paso 4, y que se conservan
   registros técnicos sin datos personales por obligaciones de calidad de la
   empresa.
6. Compilar y distribuir la app (`pnpm app:aab`).

La migración y la función van antes que la app. Una app anterior no ofrece
eliminar la cuenta, pero la página web funciona igual para sus usuarios.

## Validación manual antes de publicar

- Con una empresa de prueba: crear un operador, entrar con él y eliminar su
  cuenta desde la app; ya no puede entrar y el jefe ve el cupo libre.
- Como único jefe, intentar «Eliminar mi cuenta»: aparece la alternativa.
- Desde la página web, «Con mi correo»: llega el código y se elimina la
  empresa. Registrar otra empresa con el mismo correo: funciona.
- Buscar en la base una verificación de la cuenta eliminada: sigue ahí,
  firmada por «Usuario eliminado».
- Consultar las constancias abiertas: ninguna.
- Exportar el manual en PDF y revisarlo con Calidad.

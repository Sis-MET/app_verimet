# Activación de la app IvMET online

## Qué incluye esta entrega

- Inicio con usuario asignado en RimMET, cambio obligatorio de contraseña,
  almacenamiento seguro del par de tokens y refresh serializado.
- Validación de licencia y rol en Supabase. Solo operador y jefe de calidad
  usan la app; los roles internos continúan en RimMET.
- Plantas y áreas autorizadas, balanzas habilitadas, búsqueda y paginación.
- Áreas sugeridas desde `Ubicación`, validación privada de la ficha y
  revalidación cuando cambia el catálogo maestro.
- Alta de áreas, patrones y certificados por el cliente; configuración guiada
  de las comprobaciones desde la ficha de cada balanza por el jefe de calidad.
- Vista previa y consentimiento específico para compartir con Métrica una
  actualización de balanza, sin incluir planes, patrones ni resultados.
- Ficha técnica y versión interna de la configuración; lecturas decimales como
  cadenas.
- Borradores privados en Supabase, reanudación, omisiones justificadas,
  condiciones ambientales y selección de patrones/certificados.
- Cargas sugeridas editables en todos los ensayos, origen de las cargas,
  grupos de repetibilidad y sustitución; recuperación de filas retiradas.
- Historial privado, anulación con motivo por el jefe de calidad, vista previa
  y consentimiento explícito para compartir un expediente; retirada del acceso.
- Perfiles controlados para plataformas y básculas camioneras estáticas,
  finalización transaccional, reglas de decisión y vencimientos por prueba.
- Tema claro/oscuro y barra inferior del diseño Industry existente. Se revisó
  visualmente con fixtures locales y se corrigió la paginación en ancho móvil.

La entrega crea comprobaciones internas finalizadas, pero no certificados de
calibración ni verificaciones legales. No modifica DataMET ni envía resultados
privados al worker. Solo un caso expresamente compartido por el jefe de calidad
queda disponible para Métrica. El PDF formal sigue fuera de esta entrega.

## 1. Validar en el equipo de desarrollo

Desde `C:\Users\jhona\IvMET`:

```powershell
pnpm db:test:admin
pnpm db:test:operations
pnpm db:test:mobile
pnpm test:mobile-auth
Set-Location .\app
flutter analyze
flutter test
```

Las pruebas SQL crean PostgreSQL desechable en memoria. No necesitan `.env`,
no leen DataMET y no se conectan a Supabase. Los fixtures no aprueban métodos
para producción. No deben insertarse en un cliente real.

## 2. Aplicar la migración nueva en Supabase

Desde la raíz del repositorio, no desde `app` ni desde SQL Server:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm dlx supabase db push --linked --dry-run
```

Para la captura flexible debe aparecer
`202609030002_load_free_check_configuration.sql`, después de
`202609030001_flexible_test_loads.sql` y cualquier migración anterior
pendiente. Aplicarlas en orden; requiere el motor normativo, la configuración
guiada y las correcciones posteriores de catálogo. Revisa el proyecto enlazado
antes de confirmar. La app activa la captura flexible al recibir la capacidad
v2 del servidor; los borradores anteriores conservan su formato original.

```powershell
pnpm dlx supabase db push --linked
```

```powershell
pnpm dlx supabase db lint --linked --level warning
```

La migración normativa es aditiva: no borra evidencia ni modifica DataMET. Los
resultados permanecen fuera del outbox. Requiere que las migraciones 003 y 004
ya estén aplicadas.

## 3. Desplegar las funciones de autenticación

```powershell
pnpm dlx supabase functions deploy ivmet-login --project-ref gdsiqryebdxwngnokmmm
```

```powershell
pnpm dlx supabase functions deploy ivmet-change-password --project-ref gdsiqryebdxwngnokmmm
```

La función de cambio de contraseña valida explícitamente el JWT con Auth y
comprueba el perfil activo. `verify_jwt=false` en su configuración evita que el
gateway antiguo rechace claves asimétricas; no elimina la autenticación del
handler. Actualiza la contraseña a través de Auth con el token del propio
usuario, no mediante una sesión ficticia ni dando permisos administrativos al
móvil. Si Auth cambia la contraseña pero falla la actualización del perfil,
se informa el fallo y se requiere revisión administrativa.

Los secretos de las funciones pertenecen a Supabase. No se copian al móvil.

## 4. Preparar una cuenta del piloto en RimMET

Comprobar que tenga contrato/licencia activos, cupo disponible, rol de cliente
y al menos una planta asignada. Para visualizar balanzas, deben estar habilitadas
y listas en Gestión IvMET. El cliente valida la ficha y el jefe de calidad usa
`Configurar comprobaciones` en esa balanza. IvMET publica y asigna la versión
interna automáticamente. Para capturar necesitan ambas condiciones. No insertar
una aprobación ficticia para saltar el bloqueo.
El código de acceso interno de RimMET no es la contraseña del usuario móvil.

## 5. Configurar y ejecutar Flutter

En `app/config/supabase.local.json` solo van URL y clave **pública** publishable
o anon, obtenidas en la configuración de API del proyecto. Nunca service_role,
sb_secret, contraseñas SQL ni el hash de acceso de RimMET. La clave pública
formará parte de la aplicación; la protección real son Auth, RLS y las RPC.

```powershell
Set-Location 'C:\Users\jhona\IvMET\app'
Copy-Item -LiteralPath '.\config\supabase.example.json' -Destination '.\config\supabase.local.json'
```

Editar la URL y la clave pública del archivo creado. No volver a copiar encima
si ya está configurado. Salvo la plantilla, los archivos de `config` están
excluidos de Git.

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.local.json
```

La app no lee `worker/.env` ni `backend/.env`, y tampoco el JSON al abrirse: la
configuración se incrusta al compilar. Gradle detiene la compilación de Android
si falta o si la clave no es pública; en otras plataformas la app muestra un
aviso y deshabilita el ingreso. No hay usuario ni contraseña precargados.

El APK o bundle del piloto se compila con `config/supabase.prod.json` y el
keystore de IvMET: ver [compilar para distribuir](app-install-guide.md#8-compilar-para-distribuir).

## Comportamiento online y privacidad

Se revalida el acceso cada 30 segundos, al volver al primer plano y al recuperar
conectividad. Cada RPC vuelve a comprobar licencia y plantas en PostgreSQL.
Mientras no se puede comprobar el acceso, la pantalla privada se oculta y no
acepta interacción. Las comprobaciones conservan cada cambio en un borrador
local y recuperan el paso activo al reiniciar, después de validar la sesión y
el acceso a la balanza. El resto de los formularios mantiene su comportamiento
online. La pérdida de acceso oculta la navegación privada; no elimina una
captura pendiente. Ver [recuperación de capturas](draft-recovery.md).

Logout elimina los tokens locales aunque no haya red. Si no puede confirmar
la revocación remota, lo indica. El access token emitido puede seguir siendo
válido hasta expirar; no se promete revocación instantánea de un JWT ya emitido.
Supabase documenta la [rotación de sesiones](https://supabase.com/docs/guides/auth/sessions)
y el [alcance del cierre de sesión](https://supabase.com/docs/guides/auth/signout).

Los borradores de comprobación se escriben en SQLite en el directorio privado
de soporte de la app. Están separados por servidor, cliente y usuario; la
recuperación se retira al confirmar la finalización. El historial no se guarda
localmente. Las lecturas se mantienen como cadenas y se validan en el servidor.
No se registran cuerpos HTTP o tokens.
Un borrador no es evidencia aceptada y puede estar incompleto. Sus certificados
se vuelven a validar al guardar; un certificado vencido se muestra claramente.
El snapshot de equipo y configuración queda ligado a la creación del borrador. Al
finalizar, el servidor recalcula los resultados; un certificado vencido produce
una alerta privada y no trazable. La evidencia final es inmutable.

## Validación manual antes de distribuir

Probar en Android físico el primer ingreso, cierre/reapertura, cambio de
contraseña, refresh tras expiración, licencia revocada, planta retirada,
modo avión, teclado decimal, dos dispositivos editando el mismo borrador,
caducidad, respuesta de guardado perdida, finalización repetida y certificado
vencido.
La compilación local y los tests sintéticos no sustituyen esa prueba contra
el proyecto enlazado. La versión iOS requiere macOS y firma; no se verifica
desde este equipo Windows.

## Servicios de esta actualización

No se modifica ni reinicia ServiceMET. El contrato 4 sí requiere detener y
actualizar `ivmet-worker`, aplicar SQL Server 011, publicar Supabase 004 y
actualizar RimMET/app de forma coordinada. Seguir el orden de
[configuración del cliente](customer-configuration-release.md); no iniciar un
worker de contrato 3 contra la nueva allowlist.

## Aprobación previa al piloto

Ejecutar `pnpm db:test:mobile` y conservar la revisión del responsable
metrológico sobre ejemplos representativos del cliente. Los perfiles actuales
son de control interno. Una necesidad de calibración acreditada, correcciones
avanzadas o una nueva edición normativa requiere otra versión del motor. El PDF
formal es el siguiente entregable y no debe presentarse como certificado.

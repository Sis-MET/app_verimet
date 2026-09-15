# Guia de instalacion de la app IvMET

Cubre dos publicos: el **operador del cliente** que solo quiere usar la app, y
el **desarrollador** que necesita compilarla y firmarla.

---

## Parte A — Para el operador (Android)

### 1. Requisitos

- Android 7.0 (API 24) o superior.
- Conexion a Internet por datos moviles o wifi. La app no usa VPN.
- Usuario y contraseña temporal entregados por Metrica Ltda.

### 2. Instalar

**Play Store (canal oficial)**

TODO(Metrica): pegar aca el enlace de Play Store cuando la ficha este publicada.

**Distribucion interna (previo a la publicacion)**

Mientras la app no este en Play Store, Metrica entrega un `.apk` firmado:

1. Descargar el archivo al telefono.
2. Android va a pedir permiso para "instalar apps desconocidas" para el
   navegador o gestor de archivos: aceptarlo.
3. Abrir el `.apk` e instalar.

Las versiones nuevas se instalan encima de la anterior. Si Android no deja
instalar una actualizacion, **no desinstalar la app**: avisar a Metrica.

### 3. Primer ingreso

1. Abrir **IvMET** con Internet.
2. Ingresar con el usuario y la contraseña temporal entregados por Metrica.
3. Definir una contraseña personal de al menos 12 caracteres.

La app la usan el operador y el jefe de calidad del cliente. Si indica que el
acceso cambio, pedir a Metrica que revise la licencia y las plantas asignadas.

### 4. Conexion y borradores

IvMET funciona online: necesita Internet para ingresar, guardar en el servidor
y finalizar. Durante una verificacion cada cambio se guarda tambien en el
telefono; si la app se cierra, al abrirla de nuevo recupera el paso y las
lecturas.

Borrar los datos de la app o desinstalarla elimina lo que todavia no llego al
servidor.

### 5. Permisos que pide la app

| Permiso | Para que |
| --- | --- |
| Internet | Conectarse con el servidor para ingresar, guardar y finalizar verificaciones. |

---

## Parte B — Para el desarrollador

### 1. Requisitos

| Herramienta | Version usada en el proyecto |
| --- | --- |
| Flutter SDK | 3.44.x (canal stable) |
| Dart SDK | 3.12.x (viene con Flutter) |
| Android Studio o VS Code | con los plugins de Flutter/Dart |
| Android SDK | plataforma 37 y build-tools |
| JDK | 17 |

Verificar el entorno:

```bash
flutter doctor -v
```

### 2. Preparar el proyecto

Desde la raiz del monorepo:

```bash
pnpm app:get
```

### 3. Generar el codigo (`build_runner`)

El proyecto usa `freezed`, `json_serializable`, `riverpod_generator` y
`drift_dev`. Los archivos `*.g.dart` / `*.freezed.dart` **no se commitean**
(ver `.gitignore`), asi que hay que generarlos:

```bash
pnpm app:gen
```

Durante el desarrollo conviene dejarlo en modo observador:

```bash
cd app && dart run build_runner watch --delete-conflicting-outputs
```

### 4. Configurar Supabase

La app recibe la URL y la clave publica de Supabase **al compilar**, no al
abrirse: `String.fromEnvironment` las incrusta en el binario. Por eso editar el
JSON no cambia un APK ya compilado.

| Archivo | Uso | En git |
| --- | --- | --- |
| `app/config/supabase.example.json` | Plantilla | Si |
| `app/config/supabase.local.json` | Desarrollo: `pnpm app:run` | No |
| `app/config/supabase.prod.json` | Distribucion: `pnpm app:apk` y `pnpm app:aab` | No |

Crear cada archivo desde la plantilla (PowerShell, desde `app/`):

```powershell
Copy-Item -LiteralPath '.\config\supabase.example.json' -Destination '.\config\supabase.local.json'
```

Completar `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` con los datos de API Keys
del proyecto en Supabase. Solo una clave publishable o anon: nunca
`service_role` ni `sb_secret`. La clave queda dentro del APK y cualquiera puede
extraerla; la proteccion real son Auth, RLS y las RPC.

Mientras exista un solo proyecto Supabase, `local` y `prod` apuntan al mismo. Si
produccion se separa, solo cambia `supabase.prod.json`.

Gradle detiene la compilacion de Android si falta la configuracion o si la
clave no es publica, con las mismas reglas que la app
(`app/android/app/build.gradle.kts`). Asi nunca se genera un APK que no deja
ingresar.

### 5. Correr la app

```bash
pnpm app:run
```

Los argumentos extra pasan a `flutter run`, por ejemplo
`pnpm app:run -d emulator-5554`.

Desde el IDE:

- **VS Code:** la configuracion `IvMET` de `.vscode/launch.json` ya pasa el
  archivo.
- **Android Studio:** agregar `--dart-define-from-file=config/supabase.local.json`
  en *Additional run args* de la configuracion de `main.dart`. Para generar APK
  o bundle usar los scripts, no el menu *Build > Flutter*.

### 6. Tests y analisis

```bash
cd app && flutter analyze
```

```bash
pnpm app:test
```

### 7. Firma de release (una sola vez)

Toda compilacion release se firma con el keystore de IvMET, y Gradle se detiene
si falta. Android solo instala una actualizacion firmada con la misma clave: si
la firma cambia hay que desinstalar, y eso borra los borradores guardados en el
telefono. Perder el keystore o sus contraseñas impide actualizar la app ya
instalada.

1. Crear una carpeta **fuera** del repo para el keystore:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\keys"
```

2. Generar el keystore. `keytool` viene con el JDK; en este equipo esta en
   `C:\Program Files\Java\jdk-17\bin`. Pide las contraseñas y los datos del
   certificado:

```powershell
& 'C:\Program Files\Java\jdk-17\bin\keytool.exe' -genkey -v -keystore "$env:USERPROFILE\keys\ivmet-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

3. Crear `app/android/key.properties` (ignorado por git):

```properties
storeFile=C:/Users/<usuario>/keys/ivmet-upload.jks
storePassword=<contraseña del keystore>
keyAlias=upload
keyPassword=<contraseña de la clave>
```

Usar `/` en la ruta: en un `.properties` la barra invertida es un caracter de
escape.

4. Guardar una copia del `.jks` y de las contraseñas en el gestor de
   contraseñas de Metrica.

### 8. Compilar para distribuir

Antes de cada entrega subir `version` en `app/pubspec.yaml`, por ejemplo de
`1.0.0+1` a `1.0.1+2`. El numero despues de `+` es el `versionCode`: Android no
instala encima una version con un numero menor y Play Store exige uno mayor en
cada subida.

APK para la distribucion interna:

```bash
pnpm app:apk
```

Queda en `app/build/app/outputs/flutter-apk/app-release.apk`.

Bundle para Play Store:

```bash
pnpm app:aab
```

Queda en `app/build/app/outputs/bundle/release/app-release.aab`.

No entregar builds debug: pesan cerca de 190 MB, corren mas lento y no llevan
la firma de IvMET.

### 9. Notas para Play Store

- La ficha debe aclarar que es una **app corporativa**: requiere credenciales
  entregadas por Metrica Ltda.
- Conviene publicarla como **prueba interna** o **distribucion privada** hasta
  tener el circuito de altas de usuarios resuelto.
- El `applicationId` es `bo.metrica.ivmet` y no debe cambiarse una vez
  publicado.
- Al activar *Play App Signing*, subir este mismo keystore como clave de firma
  de la app en lugar de dejar que Google genere una. Con otra clave, quien
  instalo el `.apk` interno no podria actualizar desde Play Store sin
  desinstalar.

# Guia de instalacion de la app IvMET

Cubre dos publicos: el **operador del cliente** que solo quiere usar la app, y
el **desarrollador** que necesita compilarla.

---

## Parte A — Para el operador (Android)

### 1. Requisitos

- Android 8.0 (API 26) o superior.
- Cliente de VPN corporativa ya instalado y funcionando: ver
  [vpn-install-guide.md](./vpn-install-guide.md).
- Usuario y contraseña de IvMET entregados por Metrica Ltda.

### 2. Instalar

**Play Store (canal oficial)**

TODO(Metrica): pegar aca el enlace de Play Store cuando la ficha este publicada.

**Distribucion interna (previo a la publicacion)**

Mientras la app no este en Play Store, Metrica entrega un `.apk` firmado o un
enlace de prueba interna. Para el `.apk`:

1. Descargar el archivo al telefono.
2. Android va a pedir permiso para "instalar apps desconocidas" para el
   navegador o gestor de archivos: aceptarlo.
3. Abrir el `.apk` e instalar.

### 3. Primer ingreso

1. **Conectar la VPN** (icono de llave o candado en la barra de estado).
2. Abrir **IvMET**.
3. Iniciar sesion con el usuario entregado por Metrica.
4. En el primer ingreso la app descarga la lista de instrumentos de su empresa;
   despues de eso funciona aunque se pierda la conexion.

### 4. Uso sin conexion

Las verificaciones se pueden ejecutar completas sin señal ni VPN. Quedan
marcadas como **pendientes de sincronizar** y se envian solas al reconectar.
No desinstalar la app con verificaciones pendientes: los datos se pierden.

### 5. Permisos que pide la app

| Permiso | Para que |
| --- | --- |
| Internet / estado de red | Enviar las verificaciones y detectar cuando hay conexion. |

---

## Parte B — Para el desarrollador

### 1. Requisitos

| Herramienta | Version usada en el proyecto |
| --- | --- |
| Flutter SDK | 3.44.x (canal stable) |
| Dart SDK | 3.12.x (viene con Flutter) |
| Android Studio o VS Code | con los plugins de Flutter/Dart |
| Android SDK | plataforma 34+ y build-tools |
| JDK | 17 |

Verificar el entorno:

```bash
flutter doctor -v
```

### 2. Preparar el proyecto

Desde la raiz del monorepo:

```bash
cd app && flutter pub get
```

### 3. Generar el codigo (`build_runner`)

El proyecto usa `freezed`, `json_serializable`, `riverpod_generator` y
`drift_dev`. Los archivos `*.g.dart` / `*.freezed.dart` **no se commitean**
(ver `.gitignore`), asi que hay que generarlos:

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

Durante el desarrollo conviene dejarlo en modo observador:

```bash
cd app && dart run build_runner watch --delete-conflicting-outputs
```

### 4. Correr la app

La URL de la API se inyecta en tiempo de compilacion, no esta hardcodeada:

```bash
cd app && flutter run --dart-define=IVMET_API_BASE_URL=https://api.metrica.local
```

Recordar tener la VPN levantada en la maquina o en el dispositivo.

Para apagar los logs de red:

```bash
cd app && flutter run --dart-define=IVMET_NETWORK_LOGS=false
```

### 5. Tests y analisis

```bash
cd app && flutter analyze
```

```bash
cd app && flutter test
```

### 6. Build de release para Play Store

1. Crear el keystore de firma (una sola vez, se guarda **fuera** del repo):

```bash
keytool -genkey -v -keystore ivmet-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Crear `app/android/key.properties` (ignorado por git) con `storePassword`,
   `keyPassword`, `keyAlias` y `storeFile`, y referenciarlo desde
   `android/app/build.gradle.kts`.

3. Generar el bundle:

```bash
cd app && flutter build appbundle --release --dart-define=IVMET_API_BASE_URL=https://api.metrica.local
```

El `.aab` queda en `app/build/app/outputs/bundle/release/`.

### 7. Notas para Play Store

- La ficha debe aclarar que es una **app corporativa**: requiere credenciales
  entregadas por Metrica Ltda y acceso a la red del cliente por VPN.
- Conviene publicarla como **prueba interna** o **distribucion privada** hasta
  tener el circuito de altas de usuarios resuelto.
- El `applicationId` es `bo.com.metrica.ivmet` y no debe cambiarse una vez
  publicado.

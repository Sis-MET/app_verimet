# Arquitectura de IvMET

> Lectura obligatoria antes de escribir la primera linea de codigo en este
> repositorio. Explica **por que** las carpetas se llaman como se llaman y
> **donde va cada archivo nuevo**.

## 1. Que es IvMET

Aplicacion comercial de **Metrica Ltda** para que sus clientes (Embol y otros)
realicen **verificaciones intermedias** de sus instrumentos de pesaje
(balanzas), entre calibraciones formales. Una verificacion se compone de tres
pruebas:

| Prueba | Que mide |
| --- | --- |
| **Excentricidad** | Efecto de la posicion de la carga sobre el receptor de carga. |
| **Repetibilidad** | Dispersion al repetir la misma carga varias veces. |
| **Linealidad** | Comportamiento del instrumento a lo largo de su rango. |

El operador captura las lecturas en el celular (con o sin señal), la app
calcula los resultados y los envia al servidor de Metrica. Los usuarios
internos de Metrica ven un **dashboard global** con el estado de las balanzas
de todos los clientes para decidir a quien ofrecerle soporte o calibracion.

## 2. Monorepo

```
IvMET/
├── app/                       Flutter (fuera del workspace pnpm, tiene su pubspec)
├── backend/                   API Node.js + TypeScript + SQL Server
├── packages/shared-contracts/ Enums/DTOs + OpenAPI compartidos
├── docs/
├── pnpm-workspace.yaml        packages: backend, packages/*
└── package.json               scripts puente para operar ambos lados
```

`app/` queda deliberadamente **fuera** del workspace de pnpm: su gestor de
paquetes es `pub`. Del lado JS el gestor es **pnpm** (fijado con el campo
`packageManager`), nunca npm ni yarn. La unica relacion entre app y backend es el
contrato HTTP (y, cuando exista, el OpenAPI de `packages/shared-contracts`).

## 3. Screaming Architecture

Al abrir `app/lib/features/` o `backend/src/features/` se debe entender **de
que trata el negocio**, no que framework se uso:

```
features/
├── auth
├── instruments
├── eccentricity_test      (app)  /  eccentricity-test      (api)
├── repeatability_test     (app)  /  repeatability-test     (api)
├── linearity_test         (app)  /  linearity-test         (api)
├── verification_reports   (app)  /  verification-reports   (api)
├── clients
├── dashboard
└── sync
```

Las mismas features existen de los dos lados: la app **consume** lo que la API
**expone**. La unica diferencia es la convencion de nombres del lenguaje:
`snake_case` en Dart, `kebab-case` en TypeScript.

**Regla:** una carpeta nueva de primer nivel dentro de `features/` solo se crea
si representa un concepto que el cliente nombraria en una reunion. `utils`,
`helpers` o `services` **no** son features: van a `core/` o `shared/`.

## 4. Clean Architecture por feature

La dependencia siempre apunta **hacia adentro**: nada en `domain/` conoce a
Express, Dio, Prisma, Drift ni a Flutter.

### 4.1 App (Flutter)

```
features/<feature>/
├── domain/
│   ├── entities/       Clases puras (sin json, sin dependencias externas)
│   ├── repositories/   Interfaces abstractas (puertos)
│   └── usecases/       Una clase por caso de uso: CalculateEccentricityUseCase
├── data/
│   ├── models/         DTOs con fromJson/toJson que mapean a las entities
│   ├── datasources/    remote_datasource.dart (dio) / local_datasource.dart (drift)
│   └── repositories/   *_repository_impl.dart: implementa el puerto de domain/
└── presentation/
    ├── screens/        Pantallas
    ├── widgets/        Widgets propios de la feature
    └── providers/      Riverpod: states + notifiers (controllers)
```

Direccion permitida de imports:

```
presentation  ->  domain          (usecases y entities)
data          ->  domain          (implementa sus interfaces)
domain        ->  (nada del proyecto)
```

`presentation` **no** debe importar de `data` directamente: pide el repositorio
por su interfaz de `domain/` y deja que la inyeccion (`app/di/`) provea la
implementacion concreta.

### 4.2 API (Node.js)

```
features/<feature>/
├── domain/
│   ├── entities/       Objetos de negocio puros
│   └── repositories/   Interfaces (puertos), sin Prisma ni mssql
├── application/        Casos de uso / servicios que orquestan domain + puertos
├── infrastructure/     Implementacion de los puertos contra SQL Server,
│                       hashing bcrypt, proveedor JWT, notificaciones
└── presentation/
    ├── <feature>.routes.ts    Rutas Express
    ├── *.controller.ts        Recibe req -> llama al usecase -> responde
    └── dto/                   Schemas zod de entrada/salida
```

Direccion permitida de imports:

```
presentation   ->  application, domain
application    ->  domain
infrastructure ->  domain
domain         ->  (nada del proyecto)
```

El **controller** no contiene reglas de negocio: valida (via el middleware
`validate`), llama al caso de uso y formatea la respuesta.

## 5. Multi-tenant (regla no negociable)

Cada cliente de Metrica es un **tenant** identificado por `empresa_id`.

- El `empresa_id` viaja **dentro del JWT** y se resuelve en
  `core/middlewares/auth.middleware.ts`, quedando en `req.user.empresaId`.
- **Toda** query que devuelva instrumentos, pruebas o reportes debe filtrar por
  ese valor. Usar el helper `requireTenant(req)`.
- **Nunca** confiar en un `empresaId` que venga del body, query o params: un
  operador de Embol no puede leer datos de otro cliente cambiando un parametro.
- Los usuarios internos de Metrica (`metrica_admin`, `metrica_tecnico`) son la
  unica excepcion, y solo a traves de rutas protegidas con `requireMetricaStaff`
  (feature `dashboard`).

## 6. Offline-first y `sync`

El operador puede estar en una planta sin cobertura y sin VPN.

1. La app guarda la verificacion en la base local (**Drift**) y encola un
   registro en la cola de sincronizacion con estado `pending`.
2. Cuando hay conectividad **y** VPN activa, la feature `sync` envia los lotes
   pendientes a `POST /api/v1/sync/...`.
3. El servidor responde con los ids definitivos y la app marca los registros
   como `synced`.

Se eligio **Drift** sobre `sqflite` justamente por la cola de sincronizacion:
queries tipadas en tiempo de compilacion evitan errores de estado al reintentar
envios. El id local es un UUID generado en el celular, para que un lote pueda
reenviarse sin duplicar (idempotencia por `client_uuid`).

## 7. Red y VPN

El SQL Server y la API de Metrica viven **detras de la VPN corporativa**
(WireGuard/OpenVPN). La app **no** gestiona el tunel: asume que el cliente VPN
del sistema operativo ya esta conectado y hace llamadas HTTPS normales. Ver
[vpn-install-guide.md](./vpn-install-guide.md).

Consecuencia de diseño: un fallo de red **no** es un bug de la app. Se mapea a
`NetworkFailure` y la UI debe sugerir revisar la conexion VPN, en vez de
mostrar un error generico.

## 8. Manejo de errores

Los dos lados usan la misma jerarquia conceptual:

| Situacion | App (`core/errors/failures.dart`) | API (`core/errors/`) |
| --- | --- | --- |
| Sin red / VPN caida / timeout | `NetworkFailure` | — |
| Error devuelto por el servidor | `ServerFailure` | `ApiError` (500) |
| Datos invalidos | `ValidationFailure` | `ValidationError` (400) |
| No autenticado / token vencido | `UnauthorizedFailure` | `UnauthorizedError` (401) |
| Sin permisos / otro tenant | `ForbiddenFailure` | `ForbiddenError` (403) |
| No existe | `NotFoundFailure` | `NotFoundError` (404) |
| Falla de base local | `CacheFailure` | `DatabaseError` (500) |

En la API, el **unico** lugar que traduce un error a respuesta HTTP es
`errorHandler`. En la app, los datasources lanzan excepciones y los
`repository_impl` las convierten en `Failure` dentro de un `Result`.

## 9. Como agregar una feature nueva

1. Elegir un nombre del **dominio**, no del framework.
2. Crear la carpeta en **ambos** lados con la misma semantica
   (`snake_case` en `app/lib/features/`, `kebab-case` en `backend/src/features/`).
3. API: entidad + puerto en `domain/`, caso de uso en `application/`,
   repositorio SQL Server en `infrastructure/`, ruta + DTO zod en
   `presentation/`, y montar el router en `backend/src/routes.ts`.
4. App: entidad + puerto + usecase en `domain/`, model + datasources +
   `repository_impl` en `data/`, providers y pantallas en `presentation/`, y
   registrar la ruta en `app/lib/app/router/`.
5. Espejar la carpeta en `test/` de cada lado.
6. Si aparece un enum que ambos lados deben interpretar igual, agregarlo a
   `packages/shared-contracts`.

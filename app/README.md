# IvMET — app Flutter

App móvil online para capturar verificaciones intermedias de instrumentos de pesaje.
Forma parte del monorepo IvMET: ver el [README raiz](../README.md).

La entrada activa usa **Supabase**, usuarios de cliente y licencias reales.
No utiliza VPN, la API Node antigua ni sincronización offline. Las pantallas
de demostración anteriores permanecen como referencia, sin rutas desde la app.

Guía vigente: [activación móvil online](../docs/mobile-online-release.md).
Contrato: [API móvil](../docs/mobile-online-api.md).

La app permite que el cliente administre áreas por planta, patrones,
certificados y planes metrológicos versionados. Cada balanza se valida contra
el catálogo importado; sus correcciones quedan privadas y solo el jefe de
calidad puede compartir una vista previa exacta con Métrica.

La captura recorre cinco pasos: pesas patrón y ambiente, excentricidad,
repetibilidad, linealidad y resumen. Guarda borradores privados y puede finalizar planes publicados con
un perfil controlado. Los cálculos se ejecutan otra vez en Supabase; Flutter no
envía veredictos. Los resultados son comprobaciones internas, no certificados
de calibración ni verificaciones legales. Ver
[motor metrológico](../docs/normative-metrology-engine.md).

Las cargas de configuración se muestran como sugerencias. En los tres ensayos
se registra la carga realmente utilizada, incluidas cargas de trabajo y
productos, con su origen. La captura admite plataformas y posiciones,
varias cargas de repetibilidad y puntos de indicación por sustitución.
Ver [captura flexible y comparación con ServiceMET](../docs/flexible-metrology-capture.md).

- Arquitectura y reglas de capas: [../docs/architecture.md](../docs/architecture.md)
- Instalar / compilar / firmar: [../docs/app-install-guide.md](../docs/app-install-guide.md)

## Atajos

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

```bash
flutter run --dart-define-from-file=config/supabase.local.json
```

## Mapa de `lib/`

| Carpeta | Contenido |
| --- | --- |
| `main.dart` | Entrada: `ProviderScope` + `IvmetApp`. |
| `app/` | Widget raiz, router (`go_router`) e inyeccion de dependencias. |
| `core/` | Red (Dio + interceptores), storage seguro, errores, constantes, utils. |
| `core/domain/` | Vocabulario compartido por varias features: veredictos, estados de cumplimiento y la lectura de balanza ya contrastada. Espeja `packages/shared-contracts`. |
| `shared/` | Tema y widgets reutilizables por varias features. |
| `features/` | Una carpeta por dominio, cada una con `domain/`, `data/`, `presentation/`. |

`features/online/` contiene el transporte Supabase, la sesión, configuración del
cliente y las pantallas activas. El transporte se inyecta con
`mobileApiProvider`; los tests usan un
adaptador HTTP sintético, nunca un proyecto remoto. Las features demo no
participan en este recorrido. La captura utiliza SQLite/Drift exclusivamente
para recuperar borradores en el móvil; la evidencia final y el historial
permanecen en Supabase. Ver [recuperación de capturas](../docs/draft-recovery.md).

## Sistema visual

La UI implementa el diseno "Industry" (acero sobre fondo tecnico): esquinas
rectas, hairline de 1 px en vez de sombras, tarjetas con marcas de registro de
plano y el acento reservado a lo activo. La unica excepcion consentida es la
barra de navegacion inferior, que si flota y es redondeada.

| Archivo | Papel |
| --- | --- |
| `shared/theme/app_colors.dart` | Tokens crudos, tal como los publica el design system. |
| `shared/theme/industry_palette.dart` | Roles de color (`divider`, `accentInk`, `fail`...) resueltos por brillo. La UI lee de aqui, nunca de `AppColors`. |
| `shared/theme/app_theme.dart` | `ThemeData` claro y oscuro: escala tipografica, botones, campos. |
| `shared/widgets/` | Componentes del sistema: `BlueprintCard`, `StatusTag`, `VerdictBadge`, `ProportionBar`, `ReadingsCapture`, `IndustryIconView`. |

Dos cosas pendientes de esta capa:

- **Tipografia.** El sistema pide Barlow Condensed y Barlow. Los `.ttf` todavia
  no estan empaquetados, asi que Flutter cae al fallback del dispositivo. Para
  cerrarlo: dejar los archivos en `app/fonts/` y declarar el bloque `fonts:` en
  `pubspec.yaml` con las familias `Barlow Condensed` y `Barlow`, que es como ya
  las nombra `AppFonts`.
- **Validación metrológica del piloto.** Los perfiles y casos automatizados ya
  están implementados. El responsable metrológico debe revisar los límites del
  cliente y firmar los ejemplos representativos antes de distribuir el piloto.

## Pruebas

`flutter analyze`, `flutter test` y, desde la raíz, `pnpm db:test:mobile`.
Las pruebas automatizadas evitan regresiones; no sustituyen la aprobación del
procedimiento concreto del cliente.

Revisión visual local sin red ni credenciales:

```powershell
flutter run -d web-server --web-port 8418 -t test/online/mobile_preview.dart
```

Solo admite debug. Usuario
ficticio `operador`, contraseña ficticia `fixture-password`. No usar este
entrypoint para distribuir la app.

# IvMET — app Flutter

App movil para ejecutar verificaciones intermedias de instrumentos de pesaje.
Forma parte del monorepo IvMET: ver el [README raiz](../README.md).

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
flutter run --dart-define=IVMET_API_BASE_URL=https://api.metrica.local
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

`presentation/` nunca importa de `data/`: depende de las interfaces de
`domain/repositories/` y la implementacion se inyecta desde `app/di/`.

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
- **Datos.** Las pantallas se alimentan de los `*_demo_data.dart` de cada
  feature, con el parque de referencia del diseno. Los providers ya exponen la
  forma definitiva, asi que conectar los repositorios reales no toca ninguna
  pantalla.

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
| `shared/` | Tema y widgets reutilizables por varias features. |
| `features/` | Una carpeta por dominio, cada una con `domain/`, `data/`, `presentation/`. |

`presentation/` nunca importa de `data/`: depende de las interfaces de
`domain/repositories/` y la implementacion se inyecta desde `app/di/`.

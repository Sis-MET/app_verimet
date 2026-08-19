# Feature: `clients`

Empresa cliente (tenant), sucursales y areas.

| Capa | Contenido | Puede importar |
| --- | --- | --- |
| `domain/` | `entities/`, `repositories/` (interfaces), `usecases/` | nada del proyecto |
| `data/` | `models/` (fromJson/toJson), `datasources/` (dio + drift), `repositories/` (impl) | `domain/` |
| `presentation/` | `screens/`, `widgets/`, `providers/` (Riverpod) | `domain/` |

`presentation/` nunca importa de `data/`: depende de la interfaz de
`domain/repositories/` y la implementacion se inyecta desde `app/di/`.

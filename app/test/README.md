# Tests de la app

La estructura espeja `lib/features/`: por cada feature, `domain/` (usecases
puros), `data/` (mapeo de models y repositorios con datasources falsos, con
`mocktail`) y `presentation/` (notifiers de Riverpod y widget tests).

Correr con `flutter test`.

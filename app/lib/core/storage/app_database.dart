/// Base de datos local (Drift) para el modo offline-first.
///
/// PLACEHOLDER: todavia no se declaran tablas. Cuando se implemente la
/// feature `sync`, aca van:
///
/// - las tablas espejo de lo que se captura en planta (instrumentos cacheados,
///   verificaciones, lecturas de cada prueba),
/// - la cola de sincronizacion (`sync_queue`) con `clientUuid`, `payload`,
///   `status` y `retryCount`.
///
/// Estructura esperada del archivo una vez implementado:
///
/// ```dart
/// import 'package:drift/drift.dart';
/// import 'package:drift_flutter/drift_flutter.dart';
///
/// part 'app_database.g.dart';
///
/// @DriftDatabase(tables: [SyncQueue, CachedInstruments])
/// class AppDatabase extends _$AppDatabase {
///   AppDatabase([QueryExecutor? executor])
///       : super(executor ?? driftDatabase(name: 'ivmet'));
///
///   @override
///   int get schemaVersion => 1;
/// }
/// ```
///
/// Tras escribirlo hay que correr:
/// `dart run build_runner build --delete-conflicting-outputs`
library;

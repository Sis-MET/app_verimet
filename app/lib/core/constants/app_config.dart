/// Configuracion por ambiente.
///
/// La conexion con Supabase (`SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`) se
/// declara en `features/online/mobile_api.dart`, que es quien la consume. Se
/// incrusta al compilar desde `config/`, no se lee al abrir la app:
///
/// ```
/// flutter run --dart-define-from-file=config/supabase.local.json
/// ```
///
/// El build de Android se detiene si falta (`android/app/build.gradle.kts`).
abstract final class AppConfig {
  static const String appName = 'IvMET';

  /// Versión y build de `pubspec.yaml`. Viaja en cada verificación
  /// finalizada (`app_version`) y se muestra en Ajustes: es la que permite
  /// saber con qué versión se capturó un registro (NB/ISO/IEC 17025 7.5 y
  /// 7.11.2). `test/core/app_version_test.dart` falla si no coincide con
  /// `pubspec.yaml`.
  static const String version = '1.0.0+1';
}

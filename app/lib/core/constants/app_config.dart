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
}

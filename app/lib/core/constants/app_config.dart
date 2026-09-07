/// Configuracion por ambiente.
///
/// La conexion con Supabase (`SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`) se
/// declara en `features/online/mobile_api.dart`, que es quien la consume:
///
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
///             --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave>
/// ```
abstract final class AppConfig {
  static const String appName = 'IvMET';
}

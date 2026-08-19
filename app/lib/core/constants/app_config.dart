/// Configuracion por ambiente.
///
/// Se inyecta en tiempo de compilacion para no hornear la IP interna de
/// Metrica en el binario de Play Store:
///
/// ```
/// flutter run --dart-define=IVMET_API_BASE_URL=https://api.metrica.local
/// ```
abstract final class AppConfig {
  static const String appName = 'IvMET';

  /// Host de la API. Solo alcanzable con la VPN corporativa activa.
  static const String apiBaseUrl = String.fromEnvironment(
    'IVMET_API_BASE_URL',
    defaultValue: 'https://api.metrica.local',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Log de request/response. Debe quedar en false para releases.
  static const bool enableNetworkLogs = bool.fromEnvironment(
    'IVMET_NETWORK_LOGS',
    defaultValue: true,
  );
}

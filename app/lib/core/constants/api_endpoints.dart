/// Rutas de la API de IvMET.
///
/// Se mantienen centralizadas para que ningun datasource arme URLs a mano.
/// Los paths son relativos a [AppConfig.apiBaseUrl].
abstract final class ApiEndpoints {
  static const String prefix = '/api/v1';

  // auth
  static const String login = '$prefix/auth/login';
  static const String refresh = '$prefix/auth/refresh';
  static const String logout = '$prefix/auth/logout';
  static const String me = '$prefix/auth/me';

  // instruments
  static const String instruments = '$prefix/instruments';
  static String instrumentById(String id) => '$instruments/$id';

  // pruebas
  static const String eccentricityTests = '$prefix/eccentricity-tests';
  static const String repeatabilityTests = '$prefix/repeatability-tests';
  static const String linearityTests = '$prefix/linearity-tests';

  // reportes / clientes / dashboard / sync
  static const String verificationReports = '$prefix/verification-reports';
  static const String clients = '$prefix/clients';
  static const String dashboard = '$prefix/dashboard';
  static const String sync = '$prefix/sync';
}

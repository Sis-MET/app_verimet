/// Rutas de la API de IvMET.
///
/// Se mantienen centralizadas para que ningun datasource arme URLs a mano.
/// Los paths son relativos a [AppConfig.apiBaseUrl].
abstract final class ApiEndpoints {
  static const String prefix = '/api/ivmet/v1';

  // auth
  static const String login = '$prefix/auth/login';
  static const String refresh = '$prefix/auth/refresh';
  static const String logout = '$prefix/auth/logout';
  static const String me = '$prefix/auth/me';
  static const String changePassword = '$prefix/auth/change-password';

  // datos offline dinamicos (plantas, instrumentos, planes y patrones)
  static const String bootstrap = '$prefix/bootstrap';

  // instruments
  static const String instruments = '$prefix/instruments';
  static String instrumentById(String id) => '$instruments/$id';

  // Las pruebas y sus puntos llegan dentro del plan versionado del bootstrap.
  static const String verifications = '$prefix/verifications';
  static String verificationById(String id) => '$verifications/$id';
  static String verificationPdf(String id) => '$verifications/$id/report.pdf';
  static const String alerts = '$prefix/alerts';
  static const String dashboard = '$prefix/dashboard';
  static const String syncVerifications = '$prefix/sync/verifications';
}

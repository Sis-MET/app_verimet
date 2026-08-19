/// Nombres y paths de las rutas de la app.
///
/// Se mantienen alineados con las features: una feature nueva agrega su path
/// aca y su `GoRoute` en `app_router.dart`.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String instruments = '/instruments';
  static const String instrumentDetail = '/instruments/:id';
  static const String eccentricityTest = '/instruments/:id/eccentricity';
  static const String repeatabilityTest = '/instruments/:id/repeatability';
  static const String linearityTest = '/instruments/:id/linearity';
  static const String verificationReports = '/reports';
  static const String dashboard = '/dashboard';
  static const String syncQueue = '/sync';
}

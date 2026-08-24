/// Nombres y paths de las rutas de la app.
///
/// Los paths estan en castellano porque coinciden con los cuatro apartados que
/// el operario ve en la barra inferior: leer la URL de un deep link tiene que
/// decir a que pantalla lleva.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';

  /// Inicio: estado del parque.
  static const String home = '/inicio';

  /// Asistente de verificacion intermedia (las tres pruebas).
  static const String verification = '/verificar';

  /// Areas del cliente, y sus dos niveles de detalle.
  static const String areas = '/areas';
  static const String areaPattern = '$areas/:area';
  static const String instrumentHistoryPattern = '$areaPattern/:codigo';

  static const String settings = '/ajustes';

  /// Equipos de un area. El nombre lleva tildes, asi que va codificado.
  static String areaDetail(String area) => '$areas/${Uri.encodeComponent(area)}';

  /// Ficha e historico de un equipo dentro de su area.
  static String instrumentHistory(String area, String codigo) =>
      '${areaDetail(area)}/${Uri.encodeComponent(codigo)}';
}

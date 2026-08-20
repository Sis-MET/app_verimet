/// Rol del usuario dentro del cliente.
///
/// Los tres roles ven exactamente las mismas pantallas: el rol cambia que
/// puede hacer, no que puede mirar. Fue una decision de diseno para no
/// mantener tres arboles de navegacion sobre el mismo dominio.
enum UserRole {
  /// Captura verificaciones en planta.
  operario('cliente_operador', 'Operario'),

  /// Ademas cierra verificaciones y da de baja equipos no conformes.
  jefeCalidad('cliente_jefe_calidad', 'Jefe de calidad'),

  /// Personal de Metrica: ve todas las empresas y registra correcciones.
  tecnicoMetrica('metrica_tecnico', 'Técnico de Métrica'),

  /// Administra usuarios, catálogos y planes metrológicos.
  administradorMetrica('metrica_admin', 'Administrador de Métrica');

  const UserRole(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static UserRole fromWire(String value) => UserRole.values.firstWhere(
        (role) => role.wireValue == value,
        orElse: () => throw ArgumentError.value(value, 'value', 'Rol IvMET desconocido'),
      );
}

/// Usuario con sesion abierta.
///
/// [empresaId] es la frontera multi-tenant: todo lo que la app muestra
/// pertenece a esa empresa y la API lo vuelve a verificar en cada request.
class SessionUser {
  const SessionUser({
    required this.id,
    required this.nombre,
    required this.email,
    required this.role,
    required this.empresaId,
    required this.empresaNombre,
  });

  final String id;
  final String nombre;
  final String? email;
  final UserRole role;
  /// Nulo para `metrica_tecnico` y `metrica_admin`.
  final String? empresaId;
  final String? empresaNombre;
}

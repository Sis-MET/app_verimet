/// Jerarquia de fallos del dominio.
///
/// Los datasources lanzan `Exception`s (ver `exceptions.dart`); los
/// `repository_impl` las traducen a un [Failure] para que `domain/` y
/// `presentation/` nunca vean detalles de Dio ni de la base local.
///
/// Todos los constructores usan parametros nombrados a proposito: en el punto
/// de uso queda explicito que se esta pasando (`message`, `cause`) sin tener
/// que recordar el orden.
sealed class Failure {
  const Failure({required this.message, this.cause});

  /// Mensaje apto para mostrarle al operador.
  final String message;

  /// Error original (Dio, drift, etc.). Solo para logs, nunca para la UI.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Sin conectividad, timeout o VPN corporativa caida.
///
/// Es el caso mas frecuente en planta: la UI deberia sugerir revisar la VPN y
/// recordar que el trabajo queda guardado localmente.
final class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'Sin conexion con el servidor de Metrica. Verifique la VPN.',
    super.cause,
  });
}

/// El servidor respondio con un error (5xx o un error no contemplado).
final class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    this.statusCode,
    this.code,
    super.cause,
  });

  final int? statusCode;

  /// Codigo de negocio devuelto por la API (ej. `VALIDATION_ERROR`).
  final String? code;
}

/// Fallo al leer o escribir la base local (drift) o el almacenamiento seguro.
final class CacheFailure extends Failure {
  const CacheFailure({
    super.message = 'No se pudo acceder a los datos guardados en el dispositivo.',
    super.cause,
  });
}

/// Datos invalidos, ya sea por validacion local o por un 400 de la API.
final class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    this.fieldErrors = const {},
    super.cause,
  });

  /// Errores por campo, listos para pintar en el formulario.
  final Map<String, String> fieldErrors;
}

/// Token ausente, invalido o expirado (401).
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({
    super.message = 'Su sesion expiro. Vuelva a iniciar sesion.',
    super.cause,
  });
}

/// El usuario existe pero no tiene permiso sobre el recurso (403).
///
/// Incluye el caso multi-tenant: intentar ver datos de otra empresa.
final class ForbiddenFailure extends Failure {
  const ForbiddenFailure({
    super.message = 'No tiene permisos para acceder a este recurso.',
    super.cause,
  });
}

/// El recurso no existe (404).
final class NotFoundFailure extends Failure {
  const NotFoundFailure({
    super.message = 'El recurso solicitado no existe.',
    super.cause,
  });
}

/// Fallo no contemplado. Si aparece seguido, hay que darle su propio tipo.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.message = 'Ocurrio un error inesperado.',
    super.cause,
  });
}

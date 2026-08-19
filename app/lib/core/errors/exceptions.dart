/// Excepciones que lanzan los datasources.
///
/// Solo viven entre `data/datasources/` y `data/repositories/`: al salir del
/// repositorio ya deben ser un `Failure`.
class ServerException implements Exception {
  const ServerException(this.message, {this.statusCode, this.code, this.details});

  final String message;
  final int? statusCode;
  final String? code;
  final Object? details;

  @override
  String toString() => 'ServerException($statusCode, $code): $message';
}

class NetworkException implements Exception {
  const NetworkException([this.message = 'Sin conexion']);
  final String message;

  @override
  String toString() => 'NetworkException: $message';
}

class CacheException implements Exception {
  const CacheException([this.message = 'Error de base local']);
  final String message;

  @override
  String toString() => 'CacheException: $message';
}

class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message = 'No autorizado']);
  final String message;

  @override
  String toString() => 'UnauthorizedException: $message';
}

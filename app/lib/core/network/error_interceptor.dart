import 'package:dio/dio.dart';

import '../errors/exceptions.dart';

/// Traduce respuestas y fallos de Dio a las excepciones de `core/errors/`.
///
/// Asi los datasources trabajan con excepciones propias y no con
/// `DioException`, y los `repository_impl` solo mapean excepcion -> `Failure`.
class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final status = response.statusCode ?? 0;

    // validateStatus deja pasar los 4xx para poder leer el cuerpo del error.
    if (status >= 400) {
      final body = response.data;
      final error = body is Map<String, dynamic> ? body['error'] : null;
      final asMap = error is Map<String, dynamic> ? error : const <String, dynamic>{};
      final message = asMap['message'] as String? ?? 'Error $status';

      final exception = status == 401
          ? UnauthorizedException(message)
          : ServerException(
              message,
              statusCode: status,
              code: asMap['code'] as String?,
              details: asMap['details'],
            );

      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: exception,
        ),
      );
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is ServerException || err.error is UnauthorizedException) {
      return handler.next(err);
    }

    final mapped = switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        const NetworkException('El servidor de Metrica no respondio a tiempo.'),
      DioExceptionType.connectionError || DioExceptionType.unknown =>
        const NetworkException('Sin conexion con el servidor. Verifique la VPN corporativa.'),
      DioExceptionType.badCertificate =>
        const NetworkException('El certificado del servidor no es valido.'),
      DioExceptionType.cancel => const NetworkException('Solicitud cancelada.'),
      DioExceptionType.badResponse => ServerException(
          'Respuesta invalida del servidor.',
          statusCode: err.response?.statusCode,
        ),
      // Cubre variantes futuras del enum de Dio sin romper la compilacion.
      _ => const NetworkException('No se pudo completar la solicitud.'),
    };

    handler.next(err.copyWith(error: mapped));
  }
}

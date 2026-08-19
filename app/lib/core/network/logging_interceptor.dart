import 'dart:developer' as developer;

import 'package:dio/dio.dart';

/// Log de trafico HTTP para desarrollo.
///
/// Nunca imprime el header `Authorization` ni el cuerpo de `/auth/*`, para no
/// dejar credenciales en el logcat de un dispositivo del cliente.
class LoggingInterceptor extends Interceptor {
  static const _redacted = '***';
  static const _sensitiveHeaders = {'authorization', 'cookie', 'set-cookie'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    developer.log(
      '--> ${options.method} ${options.uri}\n'
      'headers: ${_maskHeaders(options.headers)}\n'
      'body: ${_maskBody(options.path, options.data)}',
      name: 'ivmet.http',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    developer.log(
      '<-- ${response.statusCode} ${response.requestOptions.uri}',
      name: 'ivmet.http',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    developer.log(
      '<-- ERROR ${err.response?.statusCode ?? ''} ${err.requestOptions.uri}\n'
      '${err.type}: ${err.message}',
      name: 'ivmet.http',
      level: 1000,
    );
    handler.next(err);
  }

  Map<String, dynamic> _maskHeaders(Map<String, dynamic> headers) {
    return {
      for (final entry in headers.entries)
        entry.key:
            _sensitiveHeaders.contains(entry.key.toLowerCase()) ? _redacted : entry.value,
    };
  }

  Object? _maskBody(String path, Object? data) => path.contains('/auth/') ? _redacted : data;
}

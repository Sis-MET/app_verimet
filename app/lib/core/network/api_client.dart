import 'package:dio/dio.dart';

import '../constants/app_config.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';
import 'logging_interceptor.dart';

/// Cliente HTTP de IvMET.
///
/// Un solo [Dio] para toda la app, expuesto por Riverpod desde
/// `app/di/core_providers.dart`. Las llamadas salen por la VPN corporativa:
/// desde el punto de vista de la app son HTTPS normales, el tunel lo maneja
/// el cliente WireGuard/OpenVPN del sistema operativo.
class ApiClient {
  ApiClient({Dio? dio, AuthInterceptor? authInterceptor, String? baseUrl}) : dio = dio ?? Dio() {
    this.dio.options = BaseOptions(
          baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          sendTimeout: AppConfig.sendTimeout,
          responseType: ResponseType.json,
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json', 'X-Client': 'ivmet-mobile'},
          // La API responde los errores con cuerpo JSON: se dejan pasar para
          // que ErrorInterceptor los traduzca sin perder el detalle.
          validateStatus: (status) => status != null && status < 500,
        );

    // El orden importa: auth agrega el token, logging observa lo que sale,
    // error traduce lo que vuelve.
    if (authInterceptor != null) {
      this.dio.interceptors.add(authInterceptor);
    }
    if (AppConfig.enableNetworkLogs) {
      this.dio.interceptors.add(LoggingInterceptor());
    }
    this.dio.interceptors.add(ErrorInterceptor());
  }

  final Dio dio;

  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken}) =>
      dio.get<T>(path,
          queryParameters: queryParameters, options: options, cancelToken: cancelToken);

  Future<Response<T>> post<T>(String path,
          {Object? data,
          Map<String, dynamic>? queryParameters,
          Options? options,
          CancelToken? cancelToken}) =>
      dio.post<T>(path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken);

  Future<Response<T>> put<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) =>
      dio.put<T>(path, data: data, options: options, cancelToken: cancelToken);

  Future<Response<T>> patch<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) =>
      dio.patch<T>(path, data: data, options: options, cancelToken: cancelToken);

  Future<Response<T>> delete<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) =>
      dio.delete<T>(path, data: data, options: options, cancelToken: cancelToken);
}

import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../storage/token_storage.dart';

/// Agrega `Authorization: Bearer <token>` y coordina el refresh del token.
///
/// PLACEHOLDER: el refresh esta esbozado pero **no implementado**. Se completa
/// junto con la feature `auth` (ver docs/architecture.md).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  /// Rutas que no llevan token (evita mandar uno vencido al refrescar).
  static const _publicPaths = <String>{ApiEndpoints.login, ApiEndpoints.refresh};

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_publicPaths.any(options.path.contains)) {
      return handler.next(options);
    }

    final token = await _tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final isRefreshCall = err.requestOptions.path.contains(ApiEndpoints.refresh);

    if (!isUnauthorized || isRefreshCall) {
      return handler.next(err);
    }

    // TODO(IvMET-auth): al implementar la feature `auth`:
    //   1. leer el refresh token de TokenStorage,
    //   2. POST ApiEndpoints.refresh con un Dio limpio (sin este interceptor),
    //   3. guardar el nuevo par de tokens,
    //   4. reintentar err.requestOptions con el token nuevo,
    //   5. si el refresh falla -> limpiar tokens y navegar al login.
    // QueuedInterceptor serializa los requests, asi varias llamadas en paralelo
    // que reciban 401 no disparan N refreshes.
    handler.next(err);
  }
}

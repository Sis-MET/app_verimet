import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/api_client.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/network/network_info.dart';
import '../../core/storage/token_storage.dart';

/// Inyeccion de dependencias transversales.
///
/// Cada feature declara sus propios providers en
/// `features/<feature>/presentation/providers/` y toma de aca lo que necesite
/// (ApiClient, TokenStorage, NetworkInfo).
///
/// Estos son providers escritos a mano a proposito: son la raiz del grafo y no
/// se benefician de `riverpod_generator`. Los providers de feature si deberian
/// usar `@riverpod`.

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: SecureTokenStorage.androidOptions,
    iOptions: SecureTokenStorage.iosOptions,
  );
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage(ref.watch(secureStorageProvider));
});

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

final networkInfoProvider = Provider<NetworkInfo>((ref) {
  return NetworkInfoImpl(ref.watch(connectivityProvider));
});

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref.watch(tokenStorageProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(authInterceptor: ref.watch(authInterceptorProvider));
});

/// Dio crudo, por si algun datasource necesita opciones especiales.
/// Preferir [apiClientProvider].
final dioProvider = Provider<Dio>((ref) => ref.watch(apiClientProvider).dio);

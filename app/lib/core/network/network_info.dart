import 'package:connectivity_plus/connectivity_plus.dart';

/// Consulta de conectividad para el modo offline-first.
///
/// Tener red **no** garantiza llegar a la API de Metrica: hace falta la VPN
/// corporativa. Esto solo evita intentos obviamente inutiles; la verdad final
/// la da la respuesta HTTP.
abstract interface class NetworkInfo {
  Future<bool> get isConnected;
  Stream<bool> get onConnectivityChanged;
}

class NetworkInfoImpl implements NetworkInfo {
  NetworkInfoImpl(this._connectivity);

  final Connectivity _connectivity;

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> get isConnected async => _hasConnection(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged.map(_hasConnection);
}

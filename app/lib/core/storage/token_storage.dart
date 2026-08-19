import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';

/// Guarda el par de tokens JWT en el almacen seguro del sistema
/// (Keystore en Android, Keychain en iOS). Nunca en SharedPreferences.
abstract interface class TokenStorage {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// Android: los defaults de flutter_secure_storage 11 ya usan AES-GCM sobre
  /// Keystore. Solo se namespacea la clave para no chocar con otras apps.
  static const androidOptions = AndroidOptions(preferencesKeyPrefix: 'ivmet');

  /// iOS: el token debe seguir disponible tras un reinicio si el dispositivo
  /// ya fue desbloqueado una vez (el operador trabaja en planta, sin soporte).
  static const iosOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  @override
  Future<String?> readAccessToken() => _storage.read(key: StorageKeys.accessToken);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: StorageKeys.refreshToken);

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: StorageKeys.accessToken, value: accessToken);
    await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: StorageKeys.accessToken);
    await _storage.delete(key: StorageKeys.refreshToken);
    await _storage.delete(key: StorageKeys.userId);
    await _storage.delete(key: StorageKeys.empresaId);
  }
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';

/// Guarda el par de tokens JWT en el almacen seguro del sistema
/// (Keystore en Android, Keychain en iOS). Nunca en SharedPreferences.
abstract interface class TokenStorage {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();

  /// Dueno de los borradores locales de la ultima sesion validada.
  ///
  /// `MobileSession.recoveryOwner` se calcula con el usuario, que viene del
  /// servidor: sin senal no hay usuario y no se podria localizar en el disco lo
  /// que el operario ya escribio. Se guarda aqui, junto al token y con su misma
  /// vida: al cerrar sesion se borra, para que quien entre despues no vea los
  /// borradores del anterior.
  Future<String?> readRecoveryOwner();
  Future<void> saveRecoveryOwner(String owner);
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _sessionKey = 'ivmet.supabase.session.v1';

  Future<String?> _read(String field) async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)[field] as String?;
    } catch (_) {
      await clear();
      return null;
    }
  }

  /// Android: los defaults de flutter_secure_storage 11 ya usan AES-GCM sobre
  /// Keystore. Solo se namespacea la clave para no chocar con otras apps.
  static const androidOptions = AndroidOptions(preferencesKeyPrefix: 'ivmet');

  /// iOS: el token debe seguir disponible tras un reinicio si el dispositivo
  /// ya fue desbloqueado una vez (el operador trabaja en planta, sin soporte).
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  @override
  Future<String?> readAccessToken() => _read('access');

  @override
  Future<String?> readRefreshToken() => _read('refresh');

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    // Un registro evita pares mezclados durante la rotación del refresh.
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'access': accessToken, 'refresh': refreshToken}),
    );
  }

  @override
  Future<String?> readRecoveryOwner() =>
      _storage.read(key: StorageKeys.recoveryOwner);

  @override
  Future<void> saveRecoveryOwner(String owner) =>
      _storage.write(key: StorageKeys.recoveryOwner, value: owner);

  // Va en su propia clave y no en el registro de tokens: ese se reescribe
  // entero en cada rotacion del refresh, a proposito, para no mezclar pares.
  @override
  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: StorageKeys.recoveryOwner);
    await _storage.delete(key: StorageKeys.accessToken);
    await _storage.delete(key: StorageKeys.refreshToken);
    await _storage.delete(key: StorageKeys.userId);
    await _storage.delete(key: StorageKeys.empresaId);
  }
}

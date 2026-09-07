/// Claves usadas en `flutter_secure_storage`.
abstract final class StorageKeys {
  static const String accessToken = 'ivmet.access_token';
  static const String refreshToken = 'ivmet.refresh_token';
  static const String userId = 'ivmet.user_id';
  static const String empresaId = 'ivmet.empresa_id';

  /// Ultimo dueno de los borradores de este dispositivo. Ver
  /// `TokenStorage.readRecoveryOwner`.
  static const String recoveryOwner = 'ivmet.recovery_owner.v1';
}

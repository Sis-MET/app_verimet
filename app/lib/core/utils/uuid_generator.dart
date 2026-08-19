import 'package:uuid/uuid.dart';

/// Genera los identificadores locales de los registros creados offline.
///
/// El servidor usa este `clientUuid` como clave de idempotencia: si un lote se
/// reenvia porque se corto la VPN a mitad de camino, no se duplica nada.
abstract final class UuidGenerator {
  static const _uuid = Uuid();

  static String newId() => _uuid.v4();
}

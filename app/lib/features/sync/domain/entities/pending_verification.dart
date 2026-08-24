import '../../../../core/domain/test_verdict.dart';

/// Verificacion capturada en el dispositivo que todavia no llego al servidor.
///
/// Es la unidad de la cola offline-first: se guarda entera al cerrarla y se
/// reenvia hasta que la API la confirme. El `clientUuid` es lo que hace el
/// reenvio idempotente — sin el, un reintento crearia una verificacion
/// duplicada en el historico del equipo.
class PendingVerification {
  const PendingVerification({
    required this.clientUuid,
    required this.instrumentCode,
    required this.capturadaEl,
    required this.status,
    this.retryCount = 0,
  });

  final String clientUuid;
  final String instrumentCode;
  final String capturadaEl;
  final SyncStatus status;
  final int retryCount;

  PendingVerification copyWith({SyncStatus? status, int? retryCount}) {
    return PendingVerification(
      clientUuid: clientUuid,
      instrumentCode: instrumentCode,
      capturadaEl: capturadaEl,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

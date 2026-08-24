import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/test_verdict.dart';
import '../../domain/entities/pending_verification.dart';

/// Cola de verificaciones sin enviar.
///
/// DEMO: la cola real vive en la tabla `sync_queue` de Drift y la vacia un
/// worker en cuanto hay VPN. Este notifier ya expone la misma forma —
/// contador, lista de equipos y un envio manual — para que la UI no cambie
/// cuando se conecte la implementacion de verdad.
class SyncQueueNotifier extends Notifier<List<PendingVerification>> {
  @override
  List<PendingVerification> build() => const <PendingVerification>[
    PendingVerification(
      clientUuid: 'a5f1c0de-0001',
      instrumentCode: 'BAL-014',
      capturadaEl: 'hoy 08:14',
      status: SyncStatus.pending,
    ),
    PendingVerification(
      clientUuid: 'a5f1c0de-0002',
      instrumentCode: 'BAL-033',
      capturadaEl: 'hoy 09:02',
      status: SyncStatus.pending,
    ),
    PendingVerification(
      clientUuid: 'a5f1c0de-0003',
      instrumentCode: 'PRO-007',
      capturadaEl: 'ayer 16:40',
      status: SyncStatus.pending,
    ),
  ];

  /// Encola una verificacion recien cerrada. No intenta enviarla: quien la
  /// envia es el worker, cuando haya VPN.
  void enqueue(PendingVerification verification) {
    state = <PendingVerification>[...state, verification];
  }

  /// Intento manual de envio desde Ajustes.
  Future<void> sendAll() async {
    if (state.isEmpty) return;
    state = <PendingVerification>[
      for (final item in state) item.copyWith(status: SyncStatus.inProgress),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 900));
    state = const <PendingVerification>[];
  }
}

final syncQueueProvider = NotifierProvider<SyncQueueNotifier, List<PendingVerification>>(
  SyncQueueNotifier.new,
);

/// Cuantas verificaciones esperan envio. Lo usa la etiqueta de Inicio.
final pendingSyncCountProvider = Provider<int>((ref) => ref.watch(syncQueueProvider).length);

/// Codigos de los equipos en cola, para el detalle de Ajustes.
final pendingSyncCodesProvider = Provider<String>((ref) {
  return ref.watch(syncQueueProvider).map((item) => item.instrumentCode).join(', ');
});

/// Ultima sincronizacion completada con exito.
///
/// TODO(IvMET-sync): leerla de la tabla `sync_queue` en vez de fijarla.
final lastSyncLabelProvider = Provider<String>((ref) => 'hoy 09:42');

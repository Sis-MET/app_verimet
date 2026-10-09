import 'dart:async';

import 'package:flutter/foundation.dart';

import 'draft_controller.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';

/// Lo capturado en este teléfono que todavía no llegó al servidor.
///
/// Como en WhatsApp: cada captura queda en el teléfono y se envía sola, en
/// segundo plano y de la más antigua a la más nueva, cuando hay conexión. La
/// app sigue usable mientras tanto. Se usa el mismo [DraftController] de la
/// pantalla, sin pantalla: el mismo diario de envíos, los mismos
/// identificadores y los mismos reintentos, así que un envío repetido nunca
/// duplica una verificación.
class CaptureUploads extends ChangeNotifier {
  CaptureUploads(this.session);
  final MobileSession session;

  /// Capturas de este teléfono, tal como están en el disco.
  List<Json> items = const [];
  bool sending = false;

  /// Enviadas desde que se abrió la app.
  int sent = 0;
  bool _disposed = false;
  Future<void>? _running;
  bool _again = false;
  bool _force = false;

  /// Captura que se está enviando y pausas pedidas por la pantalla.
  String? _current;
  int _held = 0;
  Completer<void>? _released;
  Completer<void>? _itemDone;

  /// Un rechazo del servidor no se reintenta en cada vuelta: espera a que
  /// alguien lo revise o a este plazo.
  static const rest = Duration(minutes: 15);

  /// Finalizada en el teléfono y todavía sin resultado del servidor.
  static bool finishedOnPhone(Json capture) =>
      capture['queuedFinalize'] != null || capture['pendingFinalize'] != null;

  /// Finalizadas en el teléfono que esperan enviarse.
  int get waiting => items.where(finishedOnPhone).length;

  /// Rechazadas por el servidor: alguien tiene que revisarlas.
  int get attention => items.where((c) => c['attention'] != null).length;

  /// Empezadas en este teléfono que el servidor todavía no conoce. Ocupan su
  /// lugar del mes en el plan aunque aún no lo sepa el servidor.
  int get notOnServer => items.where((c) => c['draftId'] == null).length;

  String? get _owner {
    try {
      return session.recoveryOwner;
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final owner = _owner;
    if (owner == null) {
      if (items.isNotEmpty) {
        items = const [];
        _notify();
      }
      return;
    }
    try {
      items = await session.recovery.peek(owner);
    } catch (_) {
      return;
    }
    _notify();
  }

  void reset() {
    items = const [];
    sent = 0;
    _notify();
  }

  /// Envía lo pendiente. Con [force] reintenta también lo rechazado hace poco.
  Future<void> run({bool force = false}) {
    if (_running != null) {
      _again = true;
      _force = _force || force;
      return _running!;
    }
    final future = _run(force);
    _running = future;
    return future.whenComplete(() {
      _running = null;
      if (_again && !_disposed) {
        final again = _force;
        _again = false;
        _force = false;
        unawaited(run(force: again));
      }
    });
  }

  /// La pantalla abre una captura: espera a que termine la que se está
  /// enviando y no empieza otra hasta [release].
  Future<void> hold() async {
    _held++;
    _released ??= Completer<void>();
    final current = _itemDone;
    if (current != null) await current.future;
  }

  void release() {
    if (_held == 0) return;
    _held--;
    if (_held == 0) {
      _released?.complete();
      _released = null;
    }
  }

  bool _resting(Json capture) {
    final at = DateTime.tryParse(
      object(
            capture['attention'] ?? const <String, dynamic>{},
          )['at']?.toString() ??
          '',
    );
    return at != null && DateTime.now().difference(at) < rest;
  }

  Future<void> _run(bool force) async {
    await load();
    if (session.stage != SessionStage.ready || !session.online) return;
    final owner = _owner;
    if (owner == null) return;
    String order(Json c) =>
        (object(c['queuedFinalize'] ?? const <String, dynamic>{})['queuedAt'] ??
                c['updatedAt'] ??
                '')
            .toString();
    final queue =
        items
            .where(
              (c) =>
                  c['conflict'] == null &&
                  !session.openCaptures.contains(c['requestId']) &&
                  (force || !_resting(c)),
            )
            .toList()
          ..sort((a, b) => order(a).compareTo(order(b)));
    if (queue.isEmpty) return;
    sending = true;
    _notify();
    try {
      for (final snapshot in queue) {
        if (_held > 0) await _released?.future;
        if (_disposed ||
            session.stage != SessionStage.ready ||
            !session.online ||
            session.recoveryOwner != owner) {
          break;
        }
        final requestId = snapshot['requestId'] as String;
        if (session.openCaptures.contains(requestId)) continue;
        // Lo más reciente del disco: la pantalla pudo cambiarla.
        final fresh = (await session.recovery.list(
          owner,
        )).where((c) => c['requestId'] == requestId).firstOrNull;
        if (fresh == null) continue;
        _current = requestId;
        _itemDone = Completer<void>();
        try {
          await _upload(fresh);
        } finally {
          _current = null;
          _itemDone?.complete();
          _itemDone = null;
        }
      }
    } finally {
      sending = false;
      await load();
    }
  }

  bool isSending(String requestId) => _current == requestId;

  Future<void> _upload(Json snapshot) async {
    final capture = DraftController(
      session: session,
      bundle: object(snapshot['bundle']),
      recovered: snapshot,
      background: true,
    );
    try {
      final finishing =
          capture.finalizedResult != null ||
          capture.queuedFinalize != null ||
          capture.pendingFinalize != null;
      final done = finishing
          ? await capture.finalize() != null
          : await capture.sync();
      if (done) {
        if (finishing) sent++;
        if (capture.attention != null && !capture.removed) {
          capture.attention = null;
          await capture.persist();
        }
        return;
      }
      final failure = capture.lastFailure;
      // Sin señal, o nada que enviar todavía: se intenta en la próxima vuelta.
      if (failure == null || failure.offline) return;
      capture.attention = {
        'code': failure.code,
        'message': capture.error ?? failure.message,
        'at': DateTime.now().toUtc().toIso8601String(),
      };
      await capture.persist();
    } finally {
      capture.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _released?.complete();
    super.dispose();
  }
}

import 'dart:convert';

import '../../core/storage/draft_recovery_store.dart';
import 'mobile_api.dart';

/// Serializes read/modify/write operations, including writes from a route that
/// is closing. A failed write does not poison the queue or erase older drafts.
class DraftRecovery {
  DraftRecovery(this.store);
  final DraftRecoveryStore store;
  Future<void> _queue = Future.value();

  Future<T> _run<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Json> _read(String owner) async {
    final value = await store.read(owner);
    if (value == null) return {'format': 1, 'drafts': <Json>[]};
    final document = object(jsonDecode(value));
    if (document['format'] != 1 || document['drafts'] is! List) {
      throw const FormatException('Unsupported recovery document');
    }
    return document;
  }

  Future<List<Json>> list(String owner) =>
      _run(() async => objects((await _read(owner))['drafts']));

  /// Lo que hay en el disco ahora, sin esperar a las escrituras en curso:
  /// para mostrar y contar, nunca para modificar.
  Future<List<Json>> peek(String owner) async =>
      objects((await _read(owner))['drafts']);

  Future<Json?> active(String owner) => _run(() async {
    final document = await _read(owner);
    return objects(
      document['drafts'],
    ).where((d) => d['requestId'] == document['active']).firstOrNull;
  });

  /// Saves still waiting in the queue, by owner and draft.
  final Map<String, _QueuedSave> _queued = {};

  /// Every change starts a write, but a draft never has more than one write
  /// waiting: a newer snapshot replaces the queued one instead of queuing
  /// another full read/modify/write. Without this, a burst of keystrokes (or
  /// one write per scrolled pixel) left a backlog of disk syncs that kept the
  /// screen busy long after the operator stopped.
  ///
  /// The returned future completes when a write containing this snapshot, or
  /// a newer one of the same draft, is on disk.
  ///
  /// [active] marks the draft as the one to reopen on the next start; null
  /// keeps whatever was marked (the background upload does not change it).
  Future<void> save(String owner, Json snapshot, {required bool? active}) {
    // Detach now: later keystrokes must not mutate an enqueued snapshot.
    final encoded = jsonEncode(snapshot);
    final key = jsonEncode([owner, snapshot['requestId']]);
    final waiting = _queued[key];
    if (waiting != null) {
      waiting
        ..encoded = encoded
        ..active = active;
      return waiting.done;
    }
    final queued = _queued[key] = _QueuedSave(encoded, active);
    return queued.done = _run(() async {
      // From here on a newer snapshot needs a write of its own.
      _queued.remove(key);
      final copy = object(jsonDecode(queued.encoded));
      final document = await _read(owner);
      final drafts = objects(document['drafts']);
      drafts.removeWhere((d) => d['requestId'] == copy['requestId']);
      document['drafts'] = [copy, ...drafts];
      if (queued.active == true) {
        document['active'] = copy['requestId'];
      } else if (queued.active == false &&
          document['active'] == copy['requestId']) {
        document.remove('active');
      }
      await store.write(owner, jsonEncode(document));
    });
  }

  Future<void> remove(String owner, String requestId) => _run(() async {
    final document = await _read(owner);
    document['drafts'] = objects(
      document['drafts'],
    ).where((d) => d['requestId'] != requestId).toList();
    if (document['active'] == requestId) document.remove('active');
    await store.write(owner, jsonEncode(document));
  });
}

class _QueuedSave {
  _QueuedSave(this.encoded, this.active);
  String encoded;
  bool? active;
  late Future<void> done;
}

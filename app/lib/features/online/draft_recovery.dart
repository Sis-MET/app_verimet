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

  Future<Json?> active(String owner) => _run(() async {
    final document = await _read(owner);
    return objects(
      document['drafts'],
    ).where((d) => d['requestId'] == document['active']).firstOrNull;
  });

  Future<void> save(String owner, Json snapshot, {required bool active}) {
    // Detach now: later keystrokes must not mutate an enqueued snapshot.
    final copy = object(jsonDecode(jsonEncode(snapshot)));
    return _run(() async {
      final document = await _read(owner);
      final drafts = objects(document['drafts']);
      drafts.removeWhere((d) => d['requestId'] == copy['requestId']);
      document['drafts'] = [copy, ...drafts];
      if (active) {
        document['active'] = copy['requestId'];
      } else if (document['active'] == copy['requestId']) {
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

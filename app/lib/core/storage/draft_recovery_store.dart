import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'token_storage.dart';

/// Recovery documents are private to a server, tenant and authenticated user.
/// They contain unfinished capture only, never finalized evidence or tokens.
///
/// The same key/value store keeps the offline copy of what the server
/// returned (`offline_copy.dart`), under keys with their own prefix.
abstract interface class DraftRecoveryStore {
  Future<String?> read(String owner);
  Future<void> write(String owner, String document);

  /// Removes every key that starts with [prefix].
  Future<void> deletePrefix(String prefix);
  Future<void> close();
}

DraftRecoveryStore createDraftRecoveryStore() =>
    kIsWeb ? BrowserDraftRecoveryStore() : SqliteDraftRecoveryStore();

/// One atomic SQLite row contains both drafts and the active route pointer.
/// FULL acknowledges a write only after SQLite has synchronized its journal.
class SqliteDraftRecoveryStore extends GeneratedDatabase
    implements DraftRecoveryStore {
  SqliteDraftRecoveryStore([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'ivmet_draft_recovery',
              native: DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ),
      );

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => customStatement(
      'CREATE TABLE draft_recovery (owner TEXT PRIMARY KEY, document TEXT NOT NULL)',
    ),
    beforeOpen: (_) async {
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );

  @override
  Future<String?> read(String owner) async {
    final row = await customSelect(
      'SELECT document FROM draft_recovery WHERE owner = ?',
      variables: [Variable<String>(owner)],
    ).getSingleOrNull();
    return row?.read<String>('document');
  }

  @override
  Future<void> write(String owner, String document) => customStatement(
    'INSERT INTO draft_recovery (owner, document) VALUES (?, ?) '
    'ON CONFLICT(owner) DO UPDATE SET document = excluded.document',
    [owner, document],
  );

  @override
  Future<void> deletePrefix(String prefix) => customStatement(
    'DELETE FROM draft_recovery WHERE substr(owner, 1, ?) = ?',
    [prefix.length, prefix],
  );
}

/// Web persistence follows browser storage lifetime. The mobile application
/// uses SQLite; the browser adapter also permits local UI previews.
class BrowserDraftRecoveryStore implements DraftRecoveryStore {
  final _storage = const FlutterSecureStorage(
    aOptions: SecureTokenStorage.androidOptions,
    iOptions: SecureTokenStorage.iosOptions,
  );
  String _key(String owner) => 'ivmet.draft-recovery.v1.$owner';
  @override
  Future<String?> read(String owner) => _storage.read(key: _key(owner));
  @override
  Future<void> write(String owner, String document) =>
      _storage.write(key: _key(owner), value: document);
  @override
  Future<void> deletePrefix(String prefix) async {
    final keys = (await _storage.readAll()).keys.where(
      (key) => key.startsWith(_key(prefix)),
    );
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }

  @override
  Future<void> close() async {}
}

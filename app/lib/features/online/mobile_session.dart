import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/core_providers.dart';
import '../../core/storage/draft_recovery_store.dart';
import '../../core/utils/calendar_dates.dart';
import 'draft_recovery.dart';
import 'mobile_api.dart';

final draftRecoveryProvider = Provider<DraftRecovery>((ref) {
  final store = createDraftRecoveryStore();
  ref.onDispose(() => unawaited(store.close()));
  return DraftRecovery(store);
});

final mobileApiProvider = Provider<MobileApi>((ref) {
  final api = MobileApi(
    const MobileConfiguration.environment(),
    ref.watch(tokenStorageProvider),
  );
  ref.onDispose(api.dispose);
  return api;
});

final mobileSessionProvider = Provider<MobileSession>((ref) {
  final session = MobileSession(
    ref.watch(mobileApiProvider),
    recovery: ref.watch(draftRecoveryProvider),
  );
  ref.onDispose(session.dispose);
  return session;
});

enum SessionStage {
  starting,
  login,
  password,
  blocked,
  ready,
  offline,
  suspended,
}

class MobileSession extends ChangeNotifier {
  MobileSession(this.api, {DraftRecovery? recovery})
    : recovery = recovery ?? DraftRecovery(createDraftRecoveryStore()),
      _ownsRecovery = recovery == null {
    api.onFailure = observeFailure;
  }
  final MobileApi api;
  final DraftRecovery recovery;
  final bool _ownsRecovery;

  /// Dueno anotado en la ultima sesion validada de este dispositivo.
  ///
  /// Solo se usa cuando no hay usuario resuelto, que es lo que ocurre al abrir
  /// la app sin senal. Se llena en [_loadOfflineDrafts] y se vacia al cerrar
  /// sesion, a la vez que el dueno guardado en el almacen seguro.
  String? _offlineOwner;

  /// Clave de los borradores de este dispositivo.
  ///
  /// Se calcula con el usuario, que viene del servidor. Sin senal no hay
  /// usuario, y sin esta clave no se podria ni abrir ni seguir guardando lo que
  /// el operario ya escribio: por eso cae al dueno de la ultima sesion
  /// validada, que es el mismo valor.
  String get recoveryOwner {
    final current = user;
    if (current != null) {
      return jsonEncode([
        api.configuration.url,
        current['clientId'],
        current['id'],
      ]);
    }
    final stored = _offlineOwner;
    if (stored != null) return stored;
    throw StateError('Recovery requires an authenticated user');
  }

  /// Borradores de este dispositivo cuando no hay sesion validada.
  ///
  /// Se llena solo si el servidor no se pudo consultar. Nunca si denego el
  /// acceso: un 401 cierra la sesion y borra el dueno guardado, asi que quien
  /// perdio el acceso no llega aqui.
  List<Json> offlineDrafts = const [];

  SessionStage stage = SessionStage.starting;
  Json? user;
  Json access = {};
  Json bootstrap = {};
  String? error;
  int workspaceVersion = 0;
  int _check = 0;
  bool _checking = false;
  bool _disposed = false;
  bool _started = false;
  void observeFailure(MobileFailure failure) {
    if (_disposed || _checking) return;
    if (failure.offline) {
      suspend(disconnected: true);
    } else if (failure.unauthorized || failure.code == 'MOBILE_ACCESS_DENIED') {
      suspend();
      unawaited(refresh());
    }
  }

  bool get quality => user?['role'] == 'cliente_jefe_calidad';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (api.configuration.error != null) {
      stage = SessionStage.login;
      _notify();
      return;
    }
    try {
      await api.restore();
    } catch (_) {
      await api.clear();
    }
    await refresh();
  }

  Future<void> login(String username, String password) async {
    error = null;
    try {
      await api.login(username, password);
      workspaceVersion++;
      await refresh();
    } catch (failure) {
      error = failure is MobileFailure
          ? failure.message
          : 'No se pudo abrir la sesión de forma segura.';
      stage = SessionStage.login;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (_checking || _disposed) return;
    if (!api.hasSession) {
      user = null;
      bootstrap = {};
      stage = SessionStage.login;
      _notify();
      return;
    }
    final check = ++_check;
    _checking = true;
    try {
      final session = await api.read('session');
      if (check != _check || _disposed) return;
      final previousRole = user?['role'];
      user = session['user'] == null ? null : object(session['user']);
      if (previousRole != user?['role']) workspaceVersion++;
      access = object(session['access']);
      if (user == null) {
        await api.clear();
        stage = SessionStage.login;
        error = 'El usuario está deshabilitado. Consulta con Métrica.';
      } else if (![
        'cliente_operador',
        'cliente_jefe_calidad',
      ].contains(user!['role'])) {
        stage = SessionStage.blocked;
        error =
            'La administración de Métrica se realiza en RimMET, no en esta app.';
      } else if (user!['mustChangePassword'] == true) {
        stage = SessionStage.password;
      } else if (access['allowed'] != true) {
        stage = SessionStage.blocked;
        error =
            'Tu licencia no está activa. Solicita a Métrica revisar el contrato y los cupos de tu cuenta.';
      } else {
        final data = await api.read('bootstrap', clockFilters());
        if (check != _check || _disposed) return;
        if (jsonEncode(bootstrap['plants']) != jsonEncode(data['plants']) ||
            jsonEncode(bootstrap['areas']) != jsonEncode(data['areas'])) {
          workspaceVersion++;
        }
        bootstrap = data;
        error = null;
        stage = SessionStage.ready;
        offlineDrafts = const [];
        // Con el usuario ya resuelto se puede anotar quien es el dueno de los
        // borradores, para poder encontrarlos la proxima vez que no haya red.
        unawaited(api.storage.saveRecoveryOwner(recoveryOwner));
      }
      if (stage != SessionStage.ready) bootstrap = {};
    } catch (failure) {
      if (check != _check || _disposed) return;
      error = failure is MobileFailure
          ? failure.message
          : 'No se pudo validar el acceso con el servidor.';
      if (failure is MobileFailure && failure.unauthorized) {
        await api.clear();
        user = null;
        offlineDrafts = const [];
        _offlineOwner = null;
        stage = SessionStage.login;
      } else {
        stage = SessionStage.offline;
        await _loadOfflineDrafts();
      }
      if (stage == SessionStage.login) bootstrap = {};
    } finally {
      if (check == _check) {
        _checking = false;
        _notify();
      }
    }
  }

  /// Busca en el disco lo que el operario dejo a medias, con el dueno anotado
  /// en la ultima sesion validada.
  ///
  /// Es de solo lectura y no habilita la app: quien decide que se puede hacer
  /// con esto es la pantalla de recuperacion.
  Future<void> _loadOfflineDrafts() async {
    if (user != null || !api.hasSession) return;
    try {
      final owner = await api.storage.readRecoveryOwner();
      if (owner == null) return;
      offlineDrafts = await recovery.list(owner);
      _offlineOwner = owner;
    } catch (_) {
      offlineDrafts = const [];
      _offlineOwner = null;
    }
  }

  void suspend({bool disconnected = false}) {
    if (!api.hasSession || _disposed) return;
    _check++;
    _checking = false;
    stage = disconnected ? SessionStage.offline : SessionStage.suspended;
    error = disconnected
        ? 'Sin conexión. El contenido está protegido hasta validar el acceso. Las verificaciones conservan su borrador en este dispositivo.'
        : null;
    _notify();
  }

  Future<void> password(String value) async {
    await api.changePassword(value);
    await refresh();
  }

  Future<void> logout() async {
    _check++;
    _checking = false;
    user = null;
    bootstrap = {};
    offlineDrafts = const [];
    _offlineOwner = null;
    stage = SessionStage.login;
    error = null;
    workspaceVersion++;
    final completion = api.logout();
    _notify();
    final revoked = await completion;
    if (!revoked && !api.hasSession) {
      error =
          'Sesión eliminada de este equipo. No se pudo confirmar la revocación remota por falta de conexión.';
      _notify();
    }
  }

  @override
  void dispose() {
    api.onFailure = null;
    _disposed = true;
    _check++;
    if (_ownsRecovery) unawaited(recovery.store.close());
    super.dispose();
  }
}

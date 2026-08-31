import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/core_providers.dart';
import 'mobile_api.dart';

final mobileApiProvider = Provider<MobileApi>((ref) {
  final api = MobileApi(
    const MobileConfiguration.environment(),
    ref.watch(tokenStorageProvider),
  );
  ref.onDispose(api.dispose);
  return api;
});

final mobileSessionProvider = Provider<MobileSession>((ref) {
  final session = MobileSession(ref.watch(mobileApiProvider));
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
  MobileSession(this.api) {
    api.onFailure = observeFailure;
  }
  final MobileApi api;
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
        final data = await api.read('bootstrap');
        if (check != _check || _disposed) return;
        if (jsonEncode(bootstrap['plants']) != jsonEncode(data['plants']) ||
            jsonEncode(bootstrap['areas']) != jsonEncode(data['areas'])) {
          workspaceVersion++;
        }
        bootstrap = data;
        error = null;
        stage = SessionStage.ready;
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
        stage = SessionStage.login;
      } else {
        stage = SessionStage.offline;
      }
      if (stage == SessionStage.login) bootstrap = {};
    } finally {
      if (check == _check) {
        _checking = false;
        _notify();
      }
    }
  }

  void suspend({bool disconnected = false}) {
    if (!api.hasSession || _disposed) return;
    _check++;
    _checking = false;
    stage = disconnected ? SessionStage.offline : SessionStage.suspended;
    error = disconnected
        ? 'Sin conexión. El contenido está protegido hasta validar el acceso. Los cambios sin guardar solo permanecen en memoria.'
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
    super.dispose();
  }
}

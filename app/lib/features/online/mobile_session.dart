import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/core_providers.dart';
import '../../core/storage/draft_recovery_store.dart';
import '../../core/utils/calendar_dates.dart';
import 'capture_uploads.dart';
import 'commercial_plan.dart';
import 'draft_recovery.dart';
import 'mobile_api.dart';
import 'offline_copy.dart';
import 'setup_guide_memory.dart';

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

  /// Sin conexión y sin una copia vigente para trabajar: solo se recuperan
  /// las capturas de este teléfono.
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

  /// Lo que el teléfono guarda para trabajar sin señal.
  late final OfflineCopy copy = OfflineCopy(recovery.store);

  /// Lo que el teléfono recuerda de la guía de inicio de cada cuenta.
  late final GuideMemoryStore guideMemory = GuideMemoryStore(recovery.store);

  /// Lo capturado aquí que espera llegar al servidor.
  late final CaptureUploads uploads = CaptureUploads(this);

  /// Capturas abiertas en pantalla: el envío en segundo plano no las toca.
  final Set<String> openCaptures = {};

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

  /// En `ready`, si el servidor responde. Sin conexión la app trabaja con la
  /// copia del teléfono y las capturas esperan para enviarse.
  bool online = true;

  /// Permiso vigente de trabajar sin señal.
  OfflineGrant? grant;

  /// Cuándo se guardó lo que se ve, mientras se trabaja sin conexión.
  DateTime? copySavedAt;
  DateTime? _lastOnlineAt;
  DateTime? _prefetchedAt;
  bool _prefetching = false;

  int _check = 0;
  bool _checking = false;
  bool _disposed = false;
  bool _started = false;
  void observeFailure(MobileFailure failure) {
    if (_disposed || _checking) return;
    if (failure.offline) {
      connectionLost();
    } else if (failure.unauthorized || failure.code == 'MOBILE_ACCESS_DENIED') {
      suspend();
      unawaited(refresh());
    }
  }

  bool get quality => user?['role'] == 'cliente_jefe_calidad';

  /// Plan de la empresa con su uso, segun el ultimo `bootstrap`.
  CommercialPlan get plan =>
      CommercialPlan(object(bootstrap['plan'] ?? const <String, dynamic>{}));

  /// No queda lugar en el mes para otra captura, contando las que se
  /// empezaron en este teléfono y el servidor todavía no conoce.
  bool get monthlyCapturesFull {
    final limit = plan.limit(PlanResource.monthlyVerifications);
    if (limit == null) return false;
    return plan.used(PlanResource.monthlyVerifications) + uploads.notOnServer >=
        limit;
  }

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
          ? failure.offline
                ? 'Sin conexión. Para ingresar necesitas internet; después la app trabaja sin señal.'
                : failure.message
          : 'No se pudo abrir la sesión de forma segura.';
      stage = SessionStage.login;
      _notify();
    }
  }

  /// Crea la empresa con el codigo recibido y entra con su sesion. Los
  /// errores los muestra la pantalla de alta: no cambian la de acceso.
  Future<void> signup(Json data) async {
    error = null;
    await api.signupComplete(data);
    workspaceVersion++;
    await refresh();
  }

  /// Fija una contraseña nueva con el codigo recibido y entra.
  Future<void> resetPassword(String email, String code, String password) async {
    error = null;
    await api.passwordResetComplete(email, code, password);
    workspaceVersion++;
    await refresh();
  }

  /// La cuenta ya no existe: se cierra la sesión en este teléfono sin pedir
  /// nada al servidor y se descartan las capturas y la copia guardadas aquí.
  Future<void> accountDeleted(String message) async {
    try {
      final owner = recoveryOwner;
      for (final draft in await recovery.list(owner)) {
        await recovery.remove(owner, draft['requestId'].toString());
      }
      await copy.forget(owner);
      await guideMemory.forget(owner);
    } catch (_) {
      // Sin borradores ni copia que descartar.
    }
    _check++;
    _checking = false;
    _leaveWorkspace();
    workspaceVersion++;
    await api.clear();
    stage = SessionStage.login;
    error = message;
    _notify();
  }

  /// Lee una sección. En línea la guarda en la copia del teléfono; sin
  /// conexión responde con la copia, marcada con [OfflineCopy.savedAtKey].
  Future<Json> read(String section, [Json filters = const {}]) async {
    final copied = OfflineCopy.sections.contains(section);
    if (copied && !online) {
      final saved = await _fromCopy(section, filters);
      if (saved != null) return saved;
    }
    try {
      final data = await api.read(section, filters);
      if (copied) _remember(section, filters, data);
      return data;
    } on MobileFailure catch (failure) {
      if (!copied || !failure.offline || stage != SessionStage.ready) rethrow;
      final saved = await _fromCopy(section, filters);
      if (saved == null) throw const MobileFailure('OFFLINE_NOT_COPIED');
      return saved;
    }
  }

  String? get _ownerOrNull {
    try {
      return recoveryOwner;
    } catch (_) {
      return null;
    }
  }

  void _remember(String section, Json filters, Json data) {
    final owner = _ownerOrNull;
    if (owner == null) return;
    unawaited(
      copy
          .put(owner, OfflineCopy.key(section, filters), data)
          .catchError((Object _) {}),
    );
  }

  Future<Json?> _fromCopy(String section, Json filters) async {
    final owner = _ownerOrNull;
    if (owner == null) return null;
    try {
      final exact = await copy.get(owner, OfflineCopy.key(section, filters));
      if (exact != null) return exact.marked;
      // Sin señal se busca en todo el catálogo descargado.
      if (section == 'instruments') {
        final catalog = await copy.get(owner, OfflineCopy.catalogKey);
        if (catalog != null) {
          return OfflineEntry(
            searchCatalog(catalog.body, filters),
            catalog.savedAt,
          ).marked;
        }
      }
    } catch (_) {
      // Una copia ilegible es como no tenerla.
    }
    return null;
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
        await _forgetCopy();
        await api.clear();
        stage = SessionStage.login;
        error =
            'El usuario está deshabilitado. Consulta con el jefe de calidad de tu empresa.';
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
            'Tu acceso no está activo: tu cuenta no tiene cupo vigente en el plan de tu empresa. Pide al jefe de calidad que lo revise.';
      } else {
        final data = await api.read('bootstrap', clockFilters());
        if (check != _check || _disposed) return;
        _changedWorkspace(data);
        bootstrap = data;
        error = null;
        stage = SessionStage.ready;
        online = true;
        copySavedAt = null;
        offlineDrafts = const [];
        // Con el usuario ya resuelto se puede anotar quien es el dueno de los
        // borradores, para poder encontrarlos la proxima vez que no haya red.
        final owner = recoveryOwner;
        unawaited(api.storage.saveRecoveryOwner(owner));
        await _keepOffline(owner, data);
      }
      if (stage != SessionStage.ready) {
        bootstrap = {};
        if (stage != SessionStage.password) await _forgetCopy();
      }
    } catch (failure) {
      if (check != _check || _disposed) return;
      if (failure is MobileFailure && failure.unauthorized) {
        error = failure.message;
        await _forgetCopy();
        await api.clear();
        _leaveWorkspace();
        stage = SessionStage.login;
      } else if (failure is MobileFailure &&
          (failure.offline || (failure.status ?? 0) >= 500) &&
          await _openOffline(check)) {
        // Se sigue trabajando con la copia del teléfono.
      } else if (check == _check && !_disposed) {
        error =
            _expiredMessage ??
            (failure is MobileFailure
                ? failure.message
                : 'No se pudo validar el acceso con el servidor.');
        if (_expiredMessage != null) {
          // Venció el plazo sin señal: solo quedan las capturas del teléfono.
          user = null;
          bootstrap = {};
          copySavedAt = null;
        }
        _expiredMessage = null;
        stage = SessionStage.offline;
        online = true;
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

  void _changedWorkspace(Json data) {
    if (jsonEncode(bootstrap['plants']) != jsonEncode(data['plants']) ||
        jsonEncode(bootstrap['areas']) != jsonEncode(data['areas'])) {
      workspaceVersion++;
    }
  }

  /// Con la app abierta y en línea: envía lo pendiente y descarga lo
  /// necesario para trabajar sin conexión. Lo llama la pantalla principal
  /// cada vez que la sesión cambia; las dos tareas se limitan solas.
  void backgroundSync() {
    if (_disposed || stage != SessionStage.ready || !online) return;
    unawaited(uploads.run());
    unawaited(prefetch());
  }

  /// El servidor validó la cuenta: se renueva el permiso de trabajar sin
  /// señal y se guarda Inicio.
  Future<void> _keepOffline(String owner, Json home) async {
    final now = DateTime.now();
    _lastOnlineAt = now;
    grant = OfflineGrant(
      user: user!,
      access: access,
      validatedAt: now,
      lastSeen: now,
    );
    try {
      await copy.saveGrant(owner, grant!);
      await copy.put(
        owner,
        OfflineCopy.key('bootstrap', const {}),
        home,
        at: now,
      );
    } catch (_) {
      // Sin copia, la app se comporta como antes: pide señal.
    }
  }

  /// Abre la app con la copia del teléfono, si el permiso sigue vigente.
  Future<bool> _openOffline(int check) async {
    final now = DateTime.now();
    final current = grant;
    if (stage == SessionStage.ready && !online && current != null) {
      if (!current.usableAt(now)) return _expired();
      grant = current.seenAt(now);
      unawaited(
        copy.saveGrant(recoveryOwner, grant!).catchError((Object _) {}),
      );
      return true;
    }
    String? owner;
    try {
      owner = _ownerOrNull ?? await api.storage.readRecoveryOwner();
    } catch (_) {
      return false;
    }
    if (owner == null) return false;
    OfflineGrant? saved;
    OfflineEntry? home;
    try {
      saved = await copy.grant(owner);
      home = await copy.get(owner, OfflineCopy.key('bootstrap', const {}));
    } catch (_) {
      return false;
    }
    if (check != _check || _disposed || saved == null || home == null) {
      return false;
    }
    if (!saved.usableAt(now)) return _expired();
    grant = saved.seenAt(now);
    unawaited(copy.saveGrant(owner, grant!).catchError((Object _) {}));
    final previousRole = user?['role'];
    user = saved.user;
    access = saved.access;
    if (previousRole != user?['role']) workspaceVersion++;
    _changedWorkspace(home.body);
    bootstrap = home.body;
    copySavedAt = _lastOnlineAt ?? home.savedAt;
    _offlineOwner = owner;
    offlineDrafts = const [];
    online = false;
    error = null;
    stage = SessionStage.ready;
    unawaited(uploads.load());
    return true;
  }

  String? _expiredMessage;
  bool _expired() {
    _expiredMessage =
        'Pasaron más de ${OfflineCopy.validity.inDays} días sin validar tu cuenta. Conéctate a internet para seguir trabajando; tus capturas se conservan en este teléfono.';
    grant = null;
    return false;
  }

  /// Se cortó la conexión. Con una copia vigente se sigue trabajando; sin
  /// ella, el contenido queda protegido como antes.
  void connectionLost() {
    if (!api.hasSession || _disposed) return;
    final current = grant;
    if (stage == SessionStage.ready &&
        current != null &&
        current.usableAt(DateTime.now())) {
      if (online) {
        online = false;
        copySavedAt = _lastOnlineAt;
        _notify();
      }
      return;
    }
    suspend(disconnected: true);
  }

  /// Descarga lo necesario para trabajar sin señal: el catálogo completo, la
  /// ficha de cada balanza (con su configuración y sus pesas), la agenda de
  /// este mes y el siguiente, la primera página del historial y de los
  /// borradores y el plan. Como mucho cada 15 minutos; una ficha, cada 6
  /// horas.
  Future<void> prefetch({bool force = false}) async {
    final last = _prefetchedAt;
    if (_prefetching ||
        stage != SessionStage.ready ||
        !online ||
        (!force &&
            last != null &&
            DateTime.now().difference(last) < const Duration(minutes: 15))) {
      return;
    }
    _prefetching = true;
    final generation = api.epoch;
    bool current() =>
        !_disposed &&
        generation == api.epoch &&
        stage == SessionStage.ready &&
        online;
    try {
      final owner = recoveryOwner;
      final items = <Json>[];
      for (var page = 1; page <= 20; page++) {
        final data = await api.read('instruments', {
          'page': page,
          'pageSize': 100,
        });
        if (!current()) return;
        items.addAll(objects(data['items']));
        if (items.length >= (data['total'] as num).toInt()) break;
      }
      await copy.put(owner, OfflineCopy.catalogKey, {
        'total': items.length,
        'items': items,
      });
      for (final item in items.take(500)) {
        if (!current()) return;
        final filters = {'equipmentId': item['id']};
        final saved = await copy.get(
          owner,
          OfflineCopy.key('equipment', filters),
        );
        if (saved != null &&
            DateTime.now().difference(saved.savedAt) <
                const Duration(hours: 6)) {
          continue;
        }
        await read('equipment', {...clockFilters(), ...filters});
      }
      final now = today();
      for (final month in [
        DateTime.utc(now.year, now.month),
        DateTime.utc(now.year, now.month + 1),
      ]) {
        if (!current()) return;
        await read('agenda', {...clockFilters(), ...agendaMonth(month)});
      }
      // Una sección que el servidor rechaza no impide dar la descarga por
      // hecha; sin señal, se completa en la próxima vuelta.
      for (final (section, filters) in <(String, Json)>[
        ('history', const {'page': 1}),
        ('drafts', const {'page': 1}),
        ('plan', const {}),
      ]) {
        if (!current()) return;
        try {
          await read(section, filters);
        } on MobileFailure catch (failure) {
          if (failure.offline) return;
        }
      }
      _prefetchedAt = DateTime.now();
    } catch (_) {
      // Se completa en la próxima vuelta.
    } finally {
      _prefetching = false;
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
      unawaited(uploads.load());
    } catch (_) {
      offlineDrafts = const [];
      _offlineOwner = null;
    }
  }

  Future<void> _forgetCopy() async {
    final owner = _ownerOrNull ?? await api.storage.readRecoveryOwner();
    if (owner == null) return;
    try {
      await copy.forget(owner);
    } catch (_) {
      // Se intenta de nuevo al cerrar sesión.
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

  void _leaveWorkspace() {
    user = null;
    bootstrap = {};
    offlineDrafts = const [];
    _offlineOwner = null;
    online = true;
    grant = null;
    copySavedAt = null;
    _lastOnlineAt = null;
    _prefetchedAt = null;
    uploads.reset();
  }

  /// Cierra la sesión y borra la copia del teléfono. Las capturas se
  /// conservan bajo su cuenta; la pantalla no deja cerrar con verificaciones
  /// finalizadas sin enviar ([CaptureUploads.waiting]).
  Future<void> logout() async {
    final owner = _ownerOrNull;
    _check++;
    _checking = false;
    _leaveWorkspace();
    stage = SessionStage.login;
    error = null;
    workspaceVersion++;
    if (owner != null) {
      unawaited(copy.forget(owner).catchError((Object _) {}));
    }
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
    uploads.dispose();
    if (_ownsRecovery) unawaited(recovery.store.close());
    super.dispose();
  }
}

/// Filtros de la agenda de un mes; la pantalla y la descarga piden lo mismo
/// para que la copia sirva sin señal.
Json agendaMonth(DateTime month, {String? operator}) => {
  'from': dayKey(DateTime.utc(month.year, month.month)),
  'to': dayKey(DateTime.utc(month.year, month.month + 1, 0)),
  'operatorId': ?operator,
};

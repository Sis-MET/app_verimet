import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'mobile_api.dart';
import 'mobile_session.dart';
import 'trial_capture.dart';

String normalizedDecimal(String value) => value.trim().replaceAll(',', '.');
String? decimalError(
  String? value, {
  bool environment = false,
  bool humidity = false,
}) {
  final text = normalizedDecimal(value ?? '');
  if (text.isEmpty) return null;
  final pattern = environment
      ? RegExp(r'^-?[0-9]{1,6}(\.[0-9]{1,3})?$')
      : RegExp(r'^-?[0-9]{1,10}(\.[0-9]{1,9})?$');
  if (!pattern.hasMatch(text)) {
    return environment
        ? 'Usa hasta 3 decimales.'
        : 'Usa hasta 9 decimales, sin miles.';
  }
  if (humidity && (num.parse(text) < 0 || num.parse(text) > 100)) {
    return 'Debe estar entre 0 y 100.';
  }
  return null;
}

const draftStepTitles = [
  'Pesas patrón y ambiente',
  'Excentricidad',
  'Repetibilidad',
  'Linealidad',
  'Resumen',
];
const draftStepTypes = ['', 'eccentricity', 'repeatability', 'linearity', ''];

/// Captures raw strings locally before sending normalized, valid drafts.
/// Pending requests are journaled before the network call, so a lost response
/// is replayed with the exact body and UUID, even after restarting the process.
class DraftController extends ChangeNotifier {
  DraftController({
    required this.session,
    required this.bundle,
    Json? draft,
    Json? recovered,
  }) : owner = session.recoveryOwner {
    requestId =
        recovered?['requestId'] as String? ??
        draft?['request_uuid'] as String? ??
        const Uuid().v4();
    draftId = recovered?['draftId'] as String? ?? draft?['id'] as String?;
    version =
        recovered?['version']?.toString() ??
        draft?['version']?.toString() ??
        '0';
    step = ((recovered?['step'] as num?)?.toInt() ?? 0).clamp(0, 4);
    offsets = Map<String, dynamic>.from(recovered?['offsets'] as Map? ?? {});
    final previous = object(recovered?['raw'] ?? draft?['payload'] ?? {});
    flexible =
        previous['captureVersion'] == 2 ||
        (recovered == null && draft == null && plan['captureVersion'] == 2);
    raw = {
      if (flexible) 'captureVersion': 2,
      'temperature': previous['temperature'] ?? '',
      'humidity': previous['humidity'] ?? '',
      'observations': previous['observations'] ?? '',
      'certificates': List<String>.from(
        previous['certificates'] as List? ?? [],
      ),
      'tests': [
        for (final test in tests)
          flexible
              ? restoreFlexibleTrial(
                  test,
                  objects(
                    previous['tests'],
                  ).where((t) => t['id'] == test['id']).firstOrNull,
                )
              : _restoreTest(test, previous),
      ],
    };
    syncedHash =
        recovered?['syncedHash'] as String? ??
        (draft == null ? null : jsonEncode(payload));
    pendingSave = recovered?['pendingSave'] == null
        ? null
        : object(recovered!['pendingSave']);
    pendingFinalize = recovered?['pendingFinalize'] == null
        ? null
        : object(recovered!['pendingFinalize']);
    finalizedResult = recovered?['finalizedResult'] == null
        ? null
        : object(recovered!['finalizedResult']);
    if (pendingFinalize != null || finalizedResult != null) step = 4;
    error = recovered?['conflict'] as String?;
    conflict = error != null;
    session.addListener(_sessionChanged);
  }

  static Json _restoreTest(Json test, Json previous) {
    final saved = objects(
      previous['tests'],
    ).where((t) => t['id'] == test['id']).firstOrNull;
    final readings = objects(saved?['readings']);
    return {
      'id': test['id'],
      'omitted': saved?['omitted'] == true,
      'reason': saved?['reason'] ?? '',
      'readings': [
        for (final point in objects(test['points']))
          {
            'pointId': point['id'],
            'indication':
                readings
                    .where((r) => r['pointId'] == point['id'])
                    .firstOrNull?['indication'] ??
                '',
            'zero':
                readings
                    .where((r) => r['pointId'] == point['id'])
                    .firstOrNull?['zero'] ??
                '0',
          },
      ],
    };
  }

  final MobileSession session;
  final String owner;
  final Json bundle;
  Json get plan => object(bundle['plan']);
  Json get equipment => object(bundle['equipment']);
  List<Json> get tests => objects(plan['tests']);
  late final String requestId;
  String? draftId;
  late String version;
  late Json raw;
  late final bool flexible;
  late int step;
  late Json offsets;
  String? syncedHash;
  Json? pendingSave;
  Json? pendingFinalize;
  Json? finalizedResult;
  String? error;
  String? localError;
  bool conflict = false;
  bool syncing = false;
  bool finalizing = false;
  bool _disposed = false;
  bool _active = true;
  bool _removed = false;
  int _revision = 0;
  int _storedRevision = -1;
  Future<bool>? _syncing;
  Timer? _timer;

  bool get localSaved => _storedRevision == _revision && localError == null;
  bool get dirty => syncedHash != jsonEncode(payload);
  bool get locked =>
      finalizing || pendingFinalize != null || finalizedResult != null;
  double get offset => (offsets['$step'] as num?)?.toDouble() ?? 0;

  Json testInput(String id) =>
      (raw['tests'] as List).cast<Json>().firstWhere((t) => t['id'] == id);

  Json get payload => {
    if (flexible) 'captureVersion': 2,
    'tests': [
      for (final test in objects(raw['tests']))
        if (flexible)
          flexibleTrialPayload(test, normalizedDecimal)
        else
          {
            'id': test['id'],
            'omitted': test['omitted'],
            'reason': test['omitted'] == true
                ? (test['reason'] as String).trim()
                : '',
            'readings': test['omitted'] == true
                ? <Json>[]
                : [
                    for (final reading in objects(test['readings']))
                      {
                        'pointId': reading['pointId'],
                        'indication': normalizedDecimal(
                          reading['indication'] as String,
                        ),
                        'zero': normalizedDecimal(reading['zero'] as String),
                      },
                  ],
          },
    ],
    'certificates': List<String>.from(raw['certificates'] as List)..sort(),
    'temperature': normalizedDecimal(raw['temperature'] as String),
    'humidity': normalizedDecimal(raw['humidity'] as String),
    'observations': (raw['observations'] as String).trim(),
  };

  Json get snapshot => {
    'requestId': requestId,
    'draftId': draftId,
    'version': version,
    'bundle': bundle,
    'raw': raw,
    'step': step,
    'offsets': offsets,
    'syncedHash': syncedHash,
    'pendingSave': pendingSave,
    'pendingFinalize': pendingFinalize,
    'finalizedResult': finalizedResult,
    'conflict': conflict ? error : null,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> persist() async {
    if (_removed) return true;
    final revision = ++_revision;
    // save detaches the snapshot synchronously, before its first await.
    final write = session.recovery.save(owner, snapshot, active: _active);
    try {
      await write;
      _storedRevision = revision;
      localError = null;
      _notify();
      return true;
    } catch (_) {
      localError =
          'No se pudo guardar en este dispositivo. Mantén la app abierta y reintenta el guardado.';
      _notify();
      return false;
    }
  }

  void start() {
    unawaited(persist());
    _schedule();
  }

  void changed() {
    if (locked) return;
    unawaited(persist());
    _schedule();
    _notify();
  }

  void setOffset(double offset) {
    if (offset < 0 || offset == this.offset) return;
    offsets['$step'] = offset;
    unawaited(persist());
  }

  Future<bool> goTo(int target) async {
    final previous = step;
    step = target.clamp(0, 4);
    final saved = await persist();
    if (!saved) step = previous;
    _notify();
    if (saved) _schedule();
    return saved;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && _active && !locked && !conflict) {
      _timer = Timer(
        const Duration(milliseconds: 650),
        () => unawaited(sync()),
      );
    }
  }

  void _sessionChanged() {
    if (session.stage == SessionStage.ready) _schedule();
  }

  String? get draftIssue {
    if (decimalError(raw['temperature'] as String, environment: true) != null ||
        decimalError(
              raw['humidity'] as String,
              environment: true,
              humidity: true,
            ) !=
            null) {
      return 'Revisa la temperatura y la humedad para guardar en el servidor.';
    }
    for (final test in objects(raw['tests'])) {
      if (test['omitted'] == true) {
        if ((test['reason'] as String).trim().isEmpty) {
          return 'Indica el motivo de la prueba omitida.';
        }
      } else {
        for (final reading in objects(test['readings'])) {
          if (decimalError(reading['indication'] as String) != null ||
              (flexible && decimalError(reading['load'] as String) != null) ||
              decimalError(reading['zero'] as String) != null) {
            return 'Hay una lectura incompleta o con formato inválido. Se conserva en este dispositivo.';
          }
        }
      }
    }
    return null;
  }

  bool testComplete(Json test) => test['omitted'] == true
      ? (test['reason'] as String).trim().isNotEmpty
      : objects(test['readings']).isNotEmpty &&
            objects(test['readings']).every(
              (r) =>
                  (!flexible ||
                      ((r['load'] as String).trim().isNotEmpty &&
                          decimalError(r['load'] as String) == null)) &&
                  (r['indication'] as String).trim().isNotEmpty &&
                  decimalError(r['indication'] as String) == null &&
                  decimalError(r['zero'] as String) == null,
            );

  String? get completionIssue {
    if (draftIssue != null) return draftIssue;
    final inputs = objects(raw['tests']);
    if (inputs.isEmpty || !inputs.every(testComplete)) {
      return flexible
          ? 'Completa las cargas utilizadas y las indicaciones, o justifica la omisión de cada prueba.'
          : 'Completa las indicaciones o justifica la omisión de cada prueba.';
    }
    if (inputs.every((t) => t['omitted'] == true)) {
      return 'Debes ejecutar al menos una prueba.';
    }
    if (flexible) {
      for (final test in inputs.where((t) => t['omitted'] != true)) {
        final type = tests.firstWhere((t) => t['id'] == test['id'])['type'];
        final loads = objects(
          test['readings'],
        ).map((r) => canonicalTrialDecimal(r['load'] as String)!);
        if (loads.any(
          (v) => v.startsWith('-') || (type != 'linearity' && v == '0'),
        )) {
          return 'Las cargas de excentricidad y repetibilidad deben ser mayores que cero; las de linealidad pueden incluir cero.';
        }
        if (type == 'linearity' && loads.toSet().length < 2) {
          return 'Registra al menos dos cargas diferentes para evaluar la linealidad.';
        }
      }
    }
    return null;
  }

  Future<bool> sync() {
    _timer?.cancel();
    if (_syncing != null) return _syncing!;
    final future = _sync();
    _syncing = future;
    return future.whenComplete(() => _syncing = null);
  }

  Future<bool> _sync() async {
    if (_disposed ||
        !_active ||
        locked ||
        conflict ||
        session.stage != SessionStage.ready) {
      return false;
    }
    syncing = true;
    error = null;
    _notify();
    try {
      // Finish an ambiguous attempt before sending newer input. A successful
      // older response never marks newer keystrokes as synchronized.
      while (pendingSave != null || dirty) {
        if (_disposed || !_active) return false;
        if (pendingSave == null) {
          if (draftIssue != null) return false;
          pendingSave = {
            'request_id': requestId,
            'equipment_id': equipment['id'],
            'version_id': plan['id'],
            'expected_version': version,
            'content': payload,
            'save_id': const Uuid().v4(),
          };
        }
        if (!await persist()) return false;
        final request = object(pendingSave!);
        final result = await session.api.rpc(
          'ivmet_mobile_save_draft',
          request,
        );
        if (_disposed || !_active) return false;
        draftId = result['id'] as String;
        version = result['version'].toString();
        syncedHash = jsonEncode(request['content']);
        pendingSave = null;
        if (!await persist()) return false;
      }
      return true;
    } catch (failure) {
      error = failure is MobileFailure
          ? failure.message
          : 'No se pudo guardar en el servidor.';
      conflict =
          failure is MobileFailure &&
          [
            'ROW_VERSION_CONFLICT',
            'IDEMPOTENCY_CONFLICT',
            'DRAFT_EXPIRED',
            'DRAFT_NOT_ACCESSIBLE',
            'PLAN_NOT_ASSIGNED',
          ].contains(failure.code);
      // A definitive rejection did not commit. Keep uncertain attempts intact.
      if (failure is MobileFailure &&
          !failure.offline &&
          failure.status != null &&
          failure.status! < 500 &&
          !conflict) {
        pendingSave = null;
      }
      if (!_disposed && _active) await persist();
      return false;
    } finally {
      syncing = false;
      _notify();
    }
  }

  Future<bool> pause() async {
    _timer?.cancel();
    _active = false;
    final saved = await persist();
    if (!saved) _active = true;
    return saved;
  }

  Future<Json?> finalize() async {
    if (finalizing) return null;
    if (finalizedResult != null) return _finishRecovery();
    if (pendingFinalize == null) {
      if (completionIssue != null) {
        error = completionIssue;
        _notify();
        return null;
      }
      if (!await sync() || dirty || draftId == null) return null;
      pendingFinalize = {
        'draft_id': draftId,
        'expected_version': version,
        'finalize_id': const Uuid().v4(),
        'app_version_value': 'ivmet-flutter-v1',
        'device_id_value': '',
      };
    }
    finalizing = true;
    error = null;
    _notify();
    try {
      if (!await persist()) return null;
      finalizedResult = await session.api.rpc(
        'ivmet_mobile_finalize_draft',
        pendingFinalize!,
      );
      if (_disposed) return null;
      return await _finishRecovery();
    } catch (failure) {
      error = failure is MobileFailure
          ? failure.message
          : 'No se pudo confirmar la finalización. Puedes reintentar.';
      // Only a definite client rejection allows changing the finalized input.
      if (failure is MobileFailure &&
          failure.status != null &&
          failure.status! >= 400 &&
          failure.status! < 500 &&
          !failure.unauthorized) {
        pendingFinalize = null;
      }
      if (!_disposed) await persist();
      return null;
    } finally {
      finalizing = false;
      _notify();
    }
  }

  Future<Json?> _finishRecovery() async {
    if (!await persist()) return null;
    try {
      await session.recovery.remove(owner, requestId);
      _removed = true;
      return finalizedResult;
    } catch (_) {
      localError =
          'El resultado está guardado. Reintenta para cerrar el borrador de este dispositivo.';
      _notify();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

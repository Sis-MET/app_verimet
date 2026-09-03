import 'package:uuid/uuid.dart';

import 'mobile_api.dart';

const loadSources = {
  'standard': 'Pesas patrón',
  'process': 'Productos o cargas de trabajo',
  'mixed': 'Pesas patrón y cargas de trabajo',
};
const platformLabels = {
  'square': 'Cuadrada',
  'rectangular': 'Rectangular',
  'circular': 'Circular',
  'triangular': 'Triangular',
};
const loadingMethods = {
  'none': 'Sin método de carga',
  'return_zero': 'Ascenso con retorno a cero',
  'continuous': 'Ascenso continuo por pasos',
};
const substitutionMethods = {
  'none': 'Sin sustitución',
  'method_1': 'Método 1',
  'method_2': 'Método 2',
};

List<int> eccentricityCounts(String platform) => switch (platform) {
  'rectangular' => [3, 5],
  'circular' => [4, 5],
  'triangular' => [4],
  _ => [5],
};

/// A reading keeps its identity and raw text even when temporarily removed.
/// Suggestions never replace indications or become declared loads implicitly.
Json restoreFlexibleTrial(Json plan, Json? saved) {
  if (saved?['setup'] != null) {
    return {
      ...saved!,
      'setup': object(saved['setup']),
      'readings': objects(saved['readings']),
      'retainedReadings': objects(saved['retainedReadings']),
    };
  }
  final points = objects(plan['points']);
  final type = plan['type'];
  final count = points.length;
  final trial = <String, dynamic>{
    'id': plan['id'],
    'omitted': saved?['omitted'] ?? false,
    'reason': saved?['reason'] ?? '',
    'setup': {
      'source': 'process',
      'description': '',
      'notes': '',
      'platform': count == 3
          ? 'rectangular'
          : count == 4
          ? 'circular'
          : 'square',
      'indicatorPosition': 'front',
      'groupCount': 1,
      'measurementCount': [3, 5, 10].contains(count) ? count : 3,
      'pointCount': type == 'eccentricity'
          ? (count.clamp(3, 5))
          : count.clamp(2, 60),
      'loadingMethod': 'none',
      'substitutionMethod': 'none',
    },
    'readings': <Json>[],
    'retainedReadings': <Json>[],
  };
  resizeTrial(trial, plan);
  return trial;
}

List<Json> activeReadings(Json trial) =>
    (trial['readings'] as List).cast<Json>();
Json trialSetup(Json trial) => trial['setup'] as Json;

void resizeTrial(Json trial, Json plan) {
  final setup = trialSetup(trial);
  final repeat = plan['type'] == 'repeatability';
  final groups = repeat ? setup['groupCount'] as int : 1;
  final count =
      (repeat ? setup['measurementCount'] : setup['pointCount']) as int;
  final pool = [
    ...activeReadings(trial),
    ...objects(trial['retainedReadings']),
  ];
  final points = objects(plan['points']);
  final active = <Json>[];
  for (var group = 1; group <= groups; group++) {
    for (var slot = 1; slot <= count; slot++) {
      final old = pool
          .where((r) => r['group'] == group && r['slot'] == slot)
          .firstOrNull;
      if (old != null) {
        active.add(old);
        pool.remove(old);
      } else {
        final suggestion = points.where((p) => p['group'] == group).toList();
        final point = group == 1 && slot <= points.length
            ? points[slot - 1]
            : null;
        final groupLoad =
            active.where((r) => r['group'] == group).firstOrNull?['load'] ?? '';
        active.add({
          'pointId': point?['id'] ?? const Uuid().v4(),
          'group': group,
          'slot': slot,
          'suggestedLoad':
              point?['load'] ??
              suggestion.firstOrNull?['load'] ??
              points.firstOrNull?['load'] ??
              '',
          'load': repeat || plan['type'] == 'eccentricity' ? groupLoad : '',
          'indication': '',
          'zero': '',
        });
      }
    }
  }
  trial['readings'] = active;
  trial['retainedReadings'] = pool;
}

void setGroupLoad(Json trial, int group, String value) {
  for (final r in [
    ...activeReadings(trial),
    ...(trial['retainedReadings'] as List).cast<Json>(),
  ]) {
    if (r['group'] == group) r['load'] = value;
  }
}

BigInt? _decimal(String? text) {
  final value = (text ?? '').trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]{1,10}(\.[0-9]{1,9})?$').hasMatch(value)) return null;
  final parts = value.replaceFirst('-', '').split('.');
  final number = BigInt.parse(
    '${parts[0]}${(parts.length == 2 ? parts[1] : '').padRight(9, '0')}',
  );
  return value.startsWith('-') ? -number : number;
}

String _format(BigInt number) {
  final digits = number.abs().toString().padLeft(10, '0');
  final fraction = digits
      .substring(digits.length - 9)
      .replaceFirst(RegExp(r'0+$'), '');
  return '${number.isNegative ? '-' : ''}${digits.substring(0, digits.length - 9)}${fraction.isEmpty ? '' : '.$fraction'}';
}

String? indicationError(String indication, String load) {
  final i = _decimal(indication), l = _decimal(load);
  return i == null || l == null ? null : _format(i - l);
}

String? canonicalTrialDecimal(String value) {
  final number = _decimal(value);
  return number == null ? null : _format(number);
}

/// ServiceMET: accumulated load = base + substitution indication - reference error.
/// Exact fixed-point arithmetic; the server independently derives this again.
String? substitutionLoad(List<Json> readings, Json substitution) {
  final reference = readings
      .where((r) => r['pointId'] == substitution['referencePointId'])
      .firstOrNull;
  final base = readings
      .where((r) => r['pointId'] == substitution['basePointId'])
      .firstOrNull;
  final b = _decimal(base?['load'] as String?);
  final l = _decimal(reference?['load'] as String?);
  final i = _decimal(reference?['indication'] as String?);
  final s = _decimal(substitution['indication'] as String?);
  return b == null || l == null || i == null || s == null
      ? null
      : _format(b + s - (i - l));
}

void refreshSubstitutions(Json trial) {
  final preceding = <Json>[];
  for (final reading in activeReadings(trial)) {
    if (reading['substitution'] != null) {
      reading['load'] =
          substitutionLoad(preceding, object(reading['substitution'])) ?? '';
    }
    preceding.add(reading);
  }
}

Json flexibleTrialPayload(Json trial, String Function(String) normalize) {
  Json readingPayload(Json reading, {bool retained = false}) => {
    for (final key in ['pointId', 'group', 'slot']) key: reading[key],
    for (final key in ['load', 'indication', 'zero'])
      key: retained ? reading[key] : normalize(reading[key] as String),
    if (reading['substitution'] != null)
      'substitution': {
        ...object(reading['substitution']),
        'indication': normalize(
          object(reading['substitution'])['indication'] as String,
        ),
      },
  };
  return {
    'id': trial['id'],
    'omitted': trial['omitted'],
    'reason': trial['reason'],
    'setup': {...trialSetup(trial)},
    if (trial['substitutionDraft'] != null)
      'substitutionDraft': {...object(trial['substitutionDraft'])},
    'readings': [
      for (final r in activeReadings(trial))
        readingPayload(r, retained: trial['omitted'] == true),
    ],
    'retainedReadings': [
      for (final r in objects(trial['retainedReadings']))
        readingPayload(r, retained: true),
    ],
  };
}

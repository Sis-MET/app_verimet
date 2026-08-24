import 'dart:math' as math;

import '../../../../core/domain/reading_evaluation.dart';
import '../../../../core/domain/test_verdict.dart';
import '../../../../core/utils/measurement_format.dart';

/// Resultado de la prueba de repetibilidad.
///
/// Aqui no interesa cuanto se aleja la balanza del patron sino cuanto se
/// aleja de si misma: se repite la misma carga en el centro del receptor y se
/// mide la dispersion. Por eso el criterio es la desviacion estandar y no el
/// error maximo.
class RepeatabilityResult {
  const RepeatabilityResult({
    required this.readings,
    required this.mean,
    required this.standardDeviation,
    required this.range,
    required this.tolerance,
    required this.verdict,
  });

  final List<ReadingEvaluation> readings;
  final double mean;

  /// Desviacion estandar muestral (n − 1).
  final double standardDeviation;

  /// Diferencia entre la lectura mayor y la menor.
  final double range;

  final double tolerance;
  final TestVerdict verdict;

  String get formattedStandardDeviation => MeasurementFormat.format(standardDeviation, decimals: 3);
  String get formattedRange => MeasurementFormat.format(range);
  String get formattedTolerance => MeasurementFormat.format(tolerance);
}

/// Etiquetas de las lecturas repetidas.
List<String> repeatabilityLabels(int count) =>
    List<String>.generate(count, (index) => 'Lectura ${index + 1}');

/// Evalua la repetibilidad.
///
/// Con menos de dos lecturas no hay dispersion que calcular, asi que la
/// desviacion se reporta como cero y el veredicto queda pendiente.
RepeatabilityResult evaluateRepeatability(List<ReadingEvaluation> readings) {
  final tolerance = readings.isEmpty ? 0.0 : readings.first.tolerance;
  final values = <double>[
    for (final reading in readings)
      if (reading.value case final double value) value,
  ];

  final mean = values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

  var standardDeviation = 0.0;
  if (values.length > 1) {
    final sumOfSquares = values.fold<double>(
      0,
      (accumulated, value) => accumulated + math.pow(value - mean, 2),
    );
    standardDeviation = math.sqrt(sumOfSquares / (values.length - 1));
  }

  final range = values.isEmpty ? 0.0 : values.reduce(math.max) - values.reduce(math.min);

  final TestVerdict verdict;
  if (values.length != readings.length || values.length < 2) {
    verdict = TestVerdict.pending;
  } else if (standardDeviation > tolerance + 1e-9) {
    verdict = TestVerdict.fail;
  } else {
    verdict = TestVerdict.pass;
  }

  return RepeatabilityResult(
    readings: readings,
    mean: mean,
    standardDeviation: standardDeviation,
    range: range,
    tolerance: tolerance,
    verdict: verdict,
  );
}

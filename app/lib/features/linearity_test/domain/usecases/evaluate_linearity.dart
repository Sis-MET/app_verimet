import '../../../../core/domain/reading_evaluation.dart';
import '../../../../core/domain/test_verdict.dart';
import '../../../../core/utils/measurement_format.dart';

/// Resultado de la prueba de linealidad.
///
/// Recorre el alcance de la balanza en cinco puntos (cero, 25 %, 50 %, 75 % y
/// 100 %) y compara cada uno con su carga patron. Detecta la balanza que pesa
/// bien en el medio del rango y se desvia en los extremos, que es el caso que
/// mas se escapa cuando solo se verifica con una carga.
class LinearityResult {
  const LinearityResult({
    required this.readings,
    required this.maxError,
    required this.tolerance,
    required this.verdict,
  });

  final List<ReadingEvaluation> readings;
  final double maxError;
  final double tolerance;
  final TestVerdict verdict;

  String get formattedMaxError => MeasurementFormat.format(maxError);
  String get formattedTolerance => MeasurementFormat.format(tolerance);
}

/// Etiqueta de cada punto: la carga y que porcentaje del alcance representa.
List<String> linearityLabels(List<double> nominals, double fullScale) {
  return <String>[
    for (final nominal in nominals)
      if (nominal == 0)
        '0 kg — cero'
      else
        '${nominal.toStringAsFixed(0)} kg — '
            '${(nominal / fullScale * 100).round()} %',
  ];
}

/// Evalua la linealidad. Igual que en excentricidad, manda el punto peor.
LinearityResult evaluateLinearity(List<ReadingEvaluation> readings) {
  final tolerance = readings.isEmpty ? 0.0 : readings.first.tolerance;
  final maxError = maxAbsoluteError(readings);

  final TestVerdict verdict;
  if (readings.any((reading) => reading.isPending)) {
    verdict = TestVerdict.pending;
  } else if (readings.any((reading) => reading.isOutOfTolerance)) {
    verdict = TestVerdict.fail;
  } else {
    verdict = TestVerdict.pass;
  }

  return LinearityResult(
    readings: readings,
    maxError: maxError,
    tolerance: tolerance,
    verdict: verdict,
  );
}

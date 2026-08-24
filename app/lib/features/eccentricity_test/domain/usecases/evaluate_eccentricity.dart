import '../../../../core/domain/reading_evaluation.dart';
import '../../../../core/domain/test_verdict.dart';
import '../../../../core/utils/measurement_format.dart';

/// Resultado de la prueba de excentricidad.
///
/// La prueba pone la misma carga en cinco puntos del receptor y mira si el
/// indicador cambia segun donde se apoye. El criterio de aceptacion es el
/// error mas grande de los cinco, no su promedio: basta una esquina mala para
/// que la balanza pese distinto segun como se cargue.
class EccentricityResult {
  const EccentricityResult({
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

/// Las cinco posiciones del receptor de carga, en el orden en que se recorren.
const List<String> kEccentricityPositions = <String>[
  'Centro',
  'Anterior izquierda',
  'Anterior derecha',
  'Posterior izquierda',
  'Posterior derecha',
];

/// Evalua la excentricidad.
///
/// Mientras falte alguna lectura el veredicto es [TestVerdict.pending]: no se
/// declara conforme una prueba a medias, aunque lo capturado vaya bien.
EccentricityResult evaluateEccentricity(List<ReadingEvaluation> readings) {
  final tolerance = readings.isEmpty ? 0 : readings.first.tolerance;
  final maxError = maxAbsoluteError(readings);

  final TestVerdict verdict;
  if (readings.any((reading) => reading.isPending)) {
    verdict = TestVerdict.pending;
  } else if (readings.any((reading) => reading.isOutOfTolerance)) {
    verdict = TestVerdict.fail;
  } else {
    verdict = TestVerdict.pass;
  }

  return EccentricityResult(
    readings: readings,
    maxError: maxError,
    tolerance: tolerance.toDouble(),
    verdict: verdict,
  );
}

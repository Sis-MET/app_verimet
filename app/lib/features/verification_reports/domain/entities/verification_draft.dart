import '../../../../core/domain/reading_evaluation.dart';
import '../../../../core/domain/test_verdict.dart';
import '../../../eccentricity_test/domain/usecases/evaluate_eccentricity.dart';
import '../../../instruments/domain/entities/instrument.dart';
import '../../../linearity_test/domain/usecases/evaluate_linearity.dart';
import '../../../repeatability_test/domain/usecases/evaluate_repeatability.dart';

/// Los seis pasos de una verificacion intermedia, en orden.
///
/// Los dos primeros no miden nada: identifican el equipo y dejan registrado
/// con que patron y en que condiciones se midio. Sin eso la verificacion no es
/// trazable y no sirve como evidencia.
enum VerificationStep {
  equipo('Equipo'),
  patron('Patrón y condiciones'),
  excentricidad('Excentricidad'),
  repetibilidad('Repetibilidad'),
  linealidad('Linealidad'),
  resultado('Resultado');

  const VerificationStep(this.label);

  final String label;

  bool get isFirst => index == 0;
  bool get isLast => index == VerificationStep.values.length - 1;
}

/// Patron y condiciones ambientales con los que se hizo la verificacion.
class StandardConditions {
  const StandardConditions({
    required this.juegoPesas,
    required this.certificado,
    required this.venceCertificado,
    required this.temperatura,
    required this.humedad,
    required this.diasParaVencimiento,
  });

  /// Juego de pesas patron usado ("JP-07 · clase M1 · 20 kg ×3").
  final String juegoPesas;

  /// Certificado de calibracion del patron: es lo que da trazabilidad.
  final String certificado;

  final String venceCertificado;
  final String temperatura;
  final String humedad;

  /// Dias que le quedan al certificado del patron.
  final int diasParaVencimiento;

  StandardConditions copyWith({
    String? juegoPesas,
    String? certificado,
    String? venceCertificado,
    String? temperatura,
    String? humedad,
  }) {
    return StandardConditions(
      juegoPesas: juegoPesas ?? this.juegoPesas,
      certificado: certificado ?? this.certificado,
      venceCertificado: venceCertificado ?? this.venceCertificado,
      temperatura: temperatura ?? this.temperatura,
      humedad: humedad ?? this.humedad,
      diasParaVencimiento: diasParaVencimiento,
    );
  }
}

/// Verificacion en curso: todo lo capturado hasta ahora.
///
/// Es inmutable y vive en memoria hasta que se cierra. Al cerrarla pasa a la
/// cola de sincronizacion, no a la red: en planta lo normal es no tener VPN.
class VerificationDraft {
  const VerificationDraft({
    required this.step,
    required this.instrument,
    required this.conditions,
    required this.eccentricityReadings,
    required this.repeatabilityReadings,
    required this.linearityReadings,
  });

  final VerificationStep step;
  final Instrument instrument;
  final StandardConditions conditions;
  final List<ReadingEvaluation> eccentricityReadings;
  final List<ReadingEvaluation> repeatabilityReadings;
  final List<ReadingEvaluation> linearityReadings;

  EccentricityResult get eccentricity => evaluateEccentricity(eccentricityReadings);
  RepeatabilityResult get repeatability => evaluateRepeatability(repeatabilityReadings);
  LinearityResult get linearity => evaluateLinearity(linearityReadings);

  /// Veredicto de la verificacion completa.
  ///
  /// Una sola prueba fuera de tolerancia basta para no conforme: las tres
  /// miden defectos distintos y ninguna compensa a otra.
  TestVerdict get verdict {
    final verdicts = <TestVerdict>[eccentricity.verdict, repeatability.verdict, linearity.verdict];
    if (verdicts.contains(TestVerdict.fail)) return TestVerdict.fail;
    if (verdicts.contains(TestVerdict.pending)) return TestVerdict.pending;
    return TestVerdict.pass;
  }

  /// Que hacer con el equipo, en la voz de la app y no del manual.
  String get accionSugerida => switch (verdict) {
    TestVerdict.pass =>
      'Seguir con la frecuencia establecida. Próxima verificación intermedia en 30 días.',
    TestVerdict.fail =>
      'Retirar el equipo de uso para pesaje fiscal y solicitar ajuste a Métrica. '
          'La app deja el equipo marcado como no conforme hasta que se registre la corrección.',
    TestVerdict.pending =>
      'Faltan lecturas por capturar. Complete las tres pruebas para obtener el veredicto.',
  };

  double get progress => (step.index + 1) / VerificationStep.values.length;

  VerificationDraft copyWith({
    VerificationStep? step,
    Instrument? instrument,
    StandardConditions? conditions,
    List<ReadingEvaluation>? eccentricityReadings,
    List<ReadingEvaluation>? repeatabilityReadings,
    List<ReadingEvaluation>? linearityReadings,
  }) {
    return VerificationDraft(
      step: step ?? this.step,
      instrument: instrument ?? this.instrument,
      conditions: conditions ?? this.conditions,
      eccentricityReadings: eccentricityReadings ?? this.eccentricityReadings,
      repeatabilityReadings: repeatabilityReadings ?? this.repeatabilityReadings,
      linearityReadings: linearityReadings ?? this.linearityReadings,
    );
  }
}

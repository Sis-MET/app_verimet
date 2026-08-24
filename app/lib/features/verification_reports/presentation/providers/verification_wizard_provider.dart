import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/compliance_status.dart';
import '../../../../core/domain/reading_evaluation.dart';
import '../../../eccentricity_test/domain/usecases/evaluate_eccentricity.dart';
import '../../../instruments/domain/entities/instrument.dart';
import '../../../instruments/presentation/providers/instruments_providers.dart';
import '../../../linearity_test/domain/usecases/evaluate_linearity.dart';
import '../../../repeatability_test/domain/usecases/evaluate_repeatability.dart';
import '../../domain/entities/verification_draft.dart';

/// Cargas y tolerancias de la verificacion en curso.
///
/// DEMO: hoy son las del equipo de referencia del diseno (BAL-014, alcance
/// 60 kg). En cuanto exista el plan de verificacion por instrumento, estas
/// cifras salen de la API junto con el equipo: la tolerancia depende de la
/// division de escala y de la clase, no se decide en la app.
abstract final class _Plan {
  static const double eccentricityLoad = 20;
  static const double eccentricityTolerance = 0.02;

  static const double repeatabilityLoad = 30;
  static const double repeatabilityTolerance = 0.02;
  static const int repeatabilityCount = 6;

  static const double fullScale = 60;
  static const List<double> linearityPoints = <double>[0, 15, 30, 45, 60];
  static const double linearityTolerance = 0.03;

  /// Lecturas de arranque. Vienen del prototipo para poder recorrer el flujo
  /// completo sin una balanza delante; la linealidad trae un punto fuera de
  /// tolerancia a proposito, que es lo que ensena el camino de no conforme.
  static const List<String> seedEccentricity = <String>[
    '20,00',
    '19,99',
    '20,01',
    '19,98',
    '20,00',
  ];
  static const List<String> seedRepeatability = <String>[
    '30,00',
    '30,01',
    '29,99',
    '30,00',
    '30,01',
    '30,00',
  ];
  static const List<String> seedLinearity = <String>['0,00', '15,01', '30,00', '45,05', '60,02'];
}

/// Verificacion intermedia paso a paso.
///
/// El asistente es la unica pantalla de captura de la app: las tres pruebas
/// son pasos del mismo flujo y no pantallas sueltas, porque una verificacion
/// solo vale si se hicieron las tres sobre el mismo equipo y con el mismo
/// patron.
class VerificationWizardNotifier extends Notifier<VerificationDraft> {
  @override
  VerificationDraft build() {
    final instrument = ref.watch(instrumentByCodeProvider('BAL-014'));
    return _initial(instrument ?? _fallbackInstrument);
  }

  static const Instrument _fallbackInstrument = Instrument(
    codigo: 'BAL-014',
    tipo: 'Plataforma 60 kg',
    detalle: 'Mettler ICS449',
    area: 'Almacén',
    status: ComplianceStatus.noConforme,
    estadoLabel: 'Vencida',
  );

  VerificationDraft _initial(Instrument instrument) {
    return VerificationDraft(
      step: VerificationStep.equipo,
      instrument: instrument,
      conditions: const StandardConditions(
        juegoPesas: 'JP-07 · clase M1 · 20 kg ×3',
        certificado: 'CAL-2412-08',
        venceCertificado: '08 dic 2026',
        temperatura: '23,4 °C',
        humedad: '54 %',
        diasParaVencimiento: 110,
      ),
      eccentricityReadings: <ReadingEvaluation>[
        for (var i = 0; i < kEccentricityPositions.length; i++)
          ReadingEvaluation(
            label: kEccentricityPositions[i],
            rawValue: _Plan.seedEccentricity[i],
            nominal: _Plan.eccentricityLoad,
            tolerance: _Plan.eccentricityTolerance,
          ),
      ],
      repeatabilityReadings: <ReadingEvaluation>[
        for (var i = 0; i < _Plan.repeatabilityCount; i++)
          ReadingEvaluation(
            label: repeatabilityLabels(_Plan.repeatabilityCount)[i],
            rawValue: _Plan.seedRepeatability[i],
            nominal: _Plan.repeatabilityLoad,
            tolerance: _Plan.repeatabilityTolerance,
          ),
      ],
      linearityReadings: <ReadingEvaluation>[
        for (var i = 0; i < _Plan.linearityPoints.length; i++)
          ReadingEvaluation(
            label: linearityLabels(_Plan.linearityPoints, _Plan.fullScale)[i],
            rawValue: _Plan.seedLinearity[i],
            nominal: _Plan.linearityPoints[i],
            tolerance: _Plan.linearityTolerance,
          ),
      ],
    );
  }

  // — navegacion entre pasos —

  void next() {
    if (state.step.isLast) {
      reset();
      return;
    }
    state = state.copyWith(step: VerificationStep.values[state.step.index + 1]);
  }

  void previous() {
    if (state.step.isFirst) return;
    state = state.copyWith(step: VerificationStep.values[state.step.index - 1]);
  }

  void goTo(VerificationStep step) => state = state.copyWith(step: step);

  /// Empieza una verificacion nueva sobre el mismo equipo.
  void reset() => state = _initial(state.instrument);

  /// Cambia el equipo verificado y descarta lo capturado: las lecturas de un
  /// equipo no pueden arrastrarse a otro.
  void selectInstrument(Instrument instrument) => state = _initial(instrument);

  // — captura —

  void setEccentricityReading(int index, String value) {
    state = state.copyWith(
      eccentricityReadings: _replace(state.eccentricityReadings, index, value),
    );
  }

  void setRepeatabilityReading(int index, String value) {
    state = state.copyWith(
      repeatabilityReadings: _replace(state.repeatabilityReadings, index, value),
    );
  }

  void setLinearityReading(int index, String value) {
    state = state.copyWith(linearityReadings: _replace(state.linearityReadings, index, value));
  }

  void updateConditions(StandardConditions conditions) {
    state = state.copyWith(conditions: conditions);
  }

  List<ReadingEvaluation> _replace(List<ReadingEvaluation> readings, int index, String value) {
    final updated = List<ReadingEvaluation>.of(readings);
    updated[index] = updated[index].copyWith(rawValue: value);
    return updated;
  }
}

final verificationWizardProvider = NotifierProvider<VerificationWizardNotifier, VerificationDraft>(
  VerificationWizardNotifier.new,
);

/// Resultados derivados, para que las pantallas de cada prueba no tengan que
/// conocer el borrador entero.
final eccentricityResultProvider = Provider<EccentricityResult>(
  (ref) => ref.watch(verificationWizardProvider).eccentricity,
);

final repeatabilityResultProvider = Provider<RepeatabilityResult>(
  (ref) => ref.watch(verificationWizardProvider).repeatability,
);

final linearityResultProvider = Provider<LinearityResult>(
  (ref) => ref.watch(verificationWizardProvider).linearity,
);

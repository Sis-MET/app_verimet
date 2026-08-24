import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/domain/reading_evaluation.dart';
import 'package:ivmet/core/domain/test_verdict.dart';
import 'package:ivmet/features/eccentricity_test/domain/usecases/evaluate_eccentricity.dart';

List<ReadingEvaluation> _readings(List<String> values, {double tolerance = 0.02}) {
  return <ReadingEvaluation>[
    for (var i = 0; i < values.length; i++)
      ReadingEvaluation(
        label: kEccentricityPositions[i],
        rawValue: values[i],
        nominal: 20,
        tolerance: tolerance,
      ),
  ];
}

void main() {
  group('evaluateEccentricity', () {
    test('es conforme cuando las cinco posiciones caen dentro de la tolerancia', () {
      final result = _readings(<String>['20,00', '19,99', '20,01', '19,98', '20,00']);

      expect(evaluateEccentricity(result).verdict, TestVerdict.pass);
      expect(evaluateEccentricity(result).maxError, closeTo(0.02, 1e-9));
    });

    test('basta una esquina fuera para que la prueba sea no conforme', () {
      final result = evaluateEccentricity(
        _readings(<String>['20,00', '20,00', '20,00', '20,00', '20,04']),
      );

      expect(result.verdict, TestVerdict.fail);
      expect(result.maxError, closeTo(0.04, 1e-9));
    });

    test('el error justo en la tolerancia se acepta, pese a la coma flotante', () {
      final result = evaluateEccentricity(
        _readings(<String>['20,02', '20,00', '20,00', '20,00', '20,00']),
      );

      expect(result.verdict, TestVerdict.pass);
    });

    test('mientras falte una lectura el veredicto queda pendiente', () {
      final result = evaluateEccentricity(
        _readings(<String>['20,00', '19,99', '', '19,98', '20,00']),
      );

      expect(result.verdict, TestVerdict.pending);
    });

    test('acepta punto y coma decimal, porque el teclado ofrece el punto', () {
      final conComa = evaluateEccentricity(
        _readings(<String>['20,01', '20,00', '20,00', '20,00', '20,00']),
      );
      final conPunto = evaluateEccentricity(
        _readings(<String>['20.01', '20.00', '20.00', '20.00', '20.00']),
      );

      expect(conPunto.maxError, conComa.maxError);
      expect(conPunto.verdict, conComa.verdict);
    });
  });
}

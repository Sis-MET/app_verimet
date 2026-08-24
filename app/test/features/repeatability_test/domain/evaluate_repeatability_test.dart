import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/domain/reading_evaluation.dart';
import 'package:ivmet/core/domain/test_verdict.dart';
import 'package:ivmet/features/repeatability_test/domain/usecases/evaluate_repeatability.dart';

List<ReadingEvaluation> _readings(List<String> values, {double tolerance = 0.02}) {
  final labels = repeatabilityLabels(values.length);
  return <ReadingEvaluation>[
    for (var i = 0; i < values.length; i++)
      ReadingEvaluation(label: labels[i], rawValue: values[i], nominal: 30, tolerance: tolerance),
  ];
}

void main() {
  group('evaluateRepeatability', () {
    test('seis lecturas muy juntas dan conforme', () {
      final result = evaluateRepeatability(
        _readings(<String>['30,00', '30,01', '29,99', '30,00', '30,01', '30,00']),
      );

      expect(result.verdict, TestVerdict.pass);
      expect(result.standardDeviation, lessThan(0.02));
      expect(result.range, closeTo(0.02, 1e-9));
    });

    test('la dispersion alta es no conforme aunque la media de en el patron', () {
      final result = evaluateRepeatability(
        _readings(<String>['29,90', '30,10', '29,90', '30,10', '29,90', '30,10']),
      );

      expect(result.mean, closeTo(30, 1e-9));
      expect(result.verdict, TestVerdict.fail);
    });

    test('usa la desviacion muestral (n − 1), no la poblacional', () {
      // Con [1, 2, 3] la muestral es 1 y la poblacional 0,8165.
      final result = evaluateRepeatability(<ReadingEvaluation>[
        for (final value in <String>['1', '2', '3'])
          ReadingEvaluation(label: value, rawValue: value, nominal: 2, tolerance: 0.02),
      ]);

      expect(result.standardDeviation, closeTo(1, 1e-9));
    });

    test('con una sola lectura no hay dispersion que juzgar', () {
      final result = evaluateRepeatability(_readings(<String>['30,00']));

      expect(result.standardDeviation, 0);
      expect(result.verdict, TestVerdict.pending);
    });

    test('una lectura sin capturar deja la prueba pendiente', () {
      final result = evaluateRepeatability(
        _readings(<String>['30,00', '30,01', '', '30,00', '30,01', '30,00']),
      );

      expect(result.verdict, TestVerdict.pending);
    });
  });
}

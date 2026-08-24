import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/domain/reading_evaluation.dart';
import 'package:ivmet/core/domain/test_verdict.dart';
import 'package:ivmet/features/linearity_test/domain/usecases/evaluate_linearity.dart';

const List<double> _nominals = <double>[0, 15, 30, 45, 60];

List<ReadingEvaluation> _readings(List<String> values, {double tolerance = 0.03}) {
  final labels = linearityLabels(_nominals, 60);
  return <ReadingEvaluation>[
    for (var i = 0; i < values.length; i++)
      ReadingEvaluation(
        label: labels[i],
        rawValue: values[i],
        nominal: _nominals[i],
        tolerance: tolerance,
      ),
  ];
}

void main() {
  group('linearityLabels', () {
    test('nombra el cero y da el porcentaje del alcance de cada punto', () {
      expect(linearityLabels(_nominals, 60), <String>[
        '0 kg — cero',
        '15 kg — 25 %',
        '30 kg — 50 %',
        '45 kg — 75 %',
        '60 kg — 100 %',
      ]);
    });
  });

  group('evaluateLinearity', () {
    test('los cinco puntos dentro de tolerancia dan conforme', () {
      final result = evaluateLinearity(
        _readings(<String>['0,00', '15,01', '30,00', '45,02', '60,02']),
      );

      expect(result.verdict, TestVerdict.pass);
      expect(result.maxError, closeTo(0.02, 1e-9));
    });

    test('un solo punto desviado en el extremo hace no conforme la prueba', () {
      // Es el caso que una verificacion con una sola carga no veria.
      final result = evaluateLinearity(
        _readings(<String>['0,00', '15,01', '30,00', '45,05', '60,02']),
      );

      expect(result.verdict, TestVerdict.fail);
      expect(result.maxError, closeTo(0.05, 1e-9));
    });

    test('la desviacion negativa cuenta igual que la positiva', () {
      final result = evaluateLinearity(
        _readings(<String>['0,00', '15,00', '29,94', '45,00', '60,00']),
      );

      expect(result.verdict, TestVerdict.fail);
      expect(result.maxError, closeTo(0.06, 1e-9));
    });
  });
}

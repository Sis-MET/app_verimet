import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/verification_report.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera un PDF completo para la verificación de una balanza', () async {
    final bytes = await buildVerificationReport(
      fixtureVerificationData,
      generatedAt: DateTime.utc(2026, 9, 4, 16),
    );

    expect(bytes.length, greaterThan(15000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(
      verificationReportFilename(fixtureVerificationData),
      'verificacion_BAL-014_20260904.pdf',
    );
  });

  // El croquis de excentricidad se dibuja a mano sobre el lienzo del PDF: cada
  // forma toma una rama distinta, y una que reviente tumbaria la generacion
  // entera del informe. Se recorren todas.
  for (final (platform, points) in const [
    ('square', 5),
    ('rectangular', 3),
    ('circular', 4),
    ('triangular', 4),
  ]) {
    for (final indicator in const ['front', 'back', 'left', 'right']) {
      test(
        'dibuja la plataforma $platform con el indicador $indicator',
        () async {
          final data = _withEccentricitySetup(platform, points, indicator);
          final bytes = await buildVerificationReport(
            data,
            generatedAt: DateTime.utc(2026, 9, 4, 16),
            generatedBy: 'Operador de prueba (operador)',
          );
          expect(ascii.decode(bytes.take(4).toList()), '%PDF');
          expect(bytes.length, greaterThan(15000));
        },
      );
    }
  }

  test(
    'un expediente sin setup no dibuja croquis y sigue generandose',
    () async {
      final data = Map<String, dynamic>.from(fixtureVerificationData);
      data['tests'] = [
        for (final test in fixtureVerificationData['tests'] as List)
          {
            for (final entry in (test as Map).entries)
              if (entry.key != 'setup') entry.key: entry.value,
          },
      ];
      final bytes = await buildVerificationReport(data);
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    },
  );
}

/// Copia del expediente con otro montaje de excentricidad.
Map<String, dynamic> _withEccentricitySetup(
  String platform,
  int points,
  String indicator,
) {
  final data = Map<String, dynamic>.from(fixtureVerificationData);
  data['tests'] = [
    for (final test in fixtureVerificationData['tests'] as List)
      if ((test as Map)['tipo'] == 'eccentricity')
        {
          ...test,
          'setup': {
            'platform': platform,
            'pointCount': points,
            'indicatorPosition': indicator,
          },
        }
      else
        test,
  ];
  return data;
}

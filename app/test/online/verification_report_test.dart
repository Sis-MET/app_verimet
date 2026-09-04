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
}

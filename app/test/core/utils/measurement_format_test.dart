import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/utils/measurement_format.dart';

void main() {
  group('decimal exacto hacia la pantalla', () {
    test('quita los ceros de relleno del servidor y usa coma', () {
      expect(MeasurementFormat.display('20.000000000'), '20');
      expect(MeasurementFormat.display('0.010000000'), '0,01');
      expect(MeasurementFormat.display('10.500000000'), '10,5');
    });

    test('respeta lo que no tiene decimales y lo ya escrito con coma', () {
      expect(MeasurementFormat.display('12'), '12');
      expect(MeasurementFormat.display('100'), '100');
      expect(MeasurementFormat.display('10,50'), '10,5');
    });

    test('no convierte a double: nueve decimales llegan enteros', () {
      expect(
        MeasurementFormat.display('9999999999.123456789'),
        '9999999999,123456789',
      );
    });
  });
}

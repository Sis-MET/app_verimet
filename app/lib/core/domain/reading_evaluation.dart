import '../utils/measurement_format.dart';

/// Una lectura de balanza ya contrastada contra su valor nominal.
///
/// Las tres pruebas capturan lo mismo — una posicion o punto, lo que marco el
/// indicador y la carga que se puso encima — asi que comparten este tipo. Lo
/// que cambia entre pruebas es como se resume el conjunto, no la fila.
class ReadingEvaluation {
  const ReadingEvaluation({
    required this.label,
    required this.rawValue,
    required this.nominal,
    required this.tolerance,
  });

  /// Posicion o punto: "Centro", "Lectura 3", "15 kg — 25 %".
  final String label;

  /// Lo que hay en el campo, tal cual lo tecleo el operario.
  final String rawValue;

  /// Carga patron que se coloco.
  final double nominal;

  /// Tolerancia de la prueba, en unidades de la balanza.
  final double tolerance;

  /// Lectura interpretada, o `null` si el campo todavia no es un numero.
  double? get value => MeasurementFormat.parse(rawValue);

  /// Diferencia contra el nominal. `null` mientras no haya lectura.
  double? get error {
    final reading = value;
    return reading == null ? null : reading - nominal;
  }

  bool get isPending => value == null;

  /// Fuera de tolerancia. El epsilon evita que 0,02 contra tolerancia 0,02
  /// caiga en falso por el error de coma flotante.
  bool get isOutOfTolerance {
    final delta = error;
    return delta != null && delta.abs() > tolerance + 1e-9;
  }

  /// Error listo para pintar: "+0,01", "−0,02" o "—".
  String get formattedError => MeasurementFormat.signedError(error);

  ReadingEvaluation copyWith({String? rawValue}) => ReadingEvaluation(
    label: label,
    rawValue: rawValue ?? this.rawValue,
    nominal: nominal,
    tolerance: tolerance,
  );
}

/// Mayor desviacion absoluta del conjunto. Las lecturas pendientes no cuentan.
double maxAbsoluteError(Iterable<ReadingEvaluation> readings) {
  var maximum = 0.0;
  for (final reading in readings) {
    final delta = reading.error;
    if (delta != null && delta.abs() > maximum) maximum = delta.abs();
  }
  return maximum;
}

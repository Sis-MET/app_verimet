import 'mobile_api.dart';

final _scale = BigInt.from(10).pow(9);
const _massFactors = <String, int>{
  't': 1000000000,
  'kg': 1000000,
  'g': 1000,
  'mg': 1,
};

class IndicationPrecision {
  const IndicationPrecision._({
    required this.decimals,
    required this.scaledDivision,
  });

  final int decimals;
  final BigInt scaledDivision;

  String get divisionLabel => _formatScaled(scaledDivision, decimals);
}

BigInt? _scaledNumber(Object? value) {
  final text = value?.toString().trim().replaceAll(',', '.') ?? '';
  final match = RegExp(
    r'^(-?)([0-9]{1,19})(?:\.([0-9]{0,9}))?$',
  ).firstMatch(text);
  if (match == null) return null;
  final fraction = (match.group(3) ?? '').padRight(9, '0');
  final scaled =
      BigInt.parse(match.group(2)!) * _scale +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
  return match.group(1) == '-' ? -scaled : scaled;
}

int _decimalPlaces(Object? value) {
  final normalized = value?.toString().trim().replaceAll(',', '.') ?? '';
  if (!normalized.contains('.')) return 0;
  final fraction = normalized.split('.').last.replaceFirst(RegExp(r'0+$'), '');
  return fraction.length.clamp(0, 9);
}

BigInt? _unitFactor(String unit) {
  final factor = _massFactors[unit.trim().toLowerCase()];
  return factor == null ? null : BigInt.from(factor);
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator).abs();
  return remainder * BigInt.two >= denominator.abs()
      ? quotient + (numerator.isNegative ? -BigInt.one : BigInt.one)
      : quotient;
}

String _formatScaled(BigInt scaled, int decimals) {
  final divisor = BigInt.from(10).pow(9 - decimals);
  final rounded = _divideRounded(scaled, divisor);
  final digits = rounded.abs().toString().padLeft(decimals + 1, '0');
  final sign = rounded.isNegative ? '-' : '';
  if (decimals == 0) return '$sign$digits';
  final split = digits.length - decimals;
  return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
}

/// Decimales con los que se lee un rango del catalogo.
///
/// Manda `cantidad_decimales`, que es lo que declara la ficha del instrumento.
/// Si no viene, se deduce de la division de escala: una balanza con d = 0,1 no
/// resuelve mas de un decimal, por mucho que el catalogo entregue el numero con
/// nueve.
int rangeDecimals(Json range) {
  final configured = int.tryParse(
    range['cantidad_decimales']?.toString() ?? '',
  );
  if (configured != null && configured >= 0 && configured <= 9) {
    return configured;
  }
  return _decimalPlaces(range['division_escala']);
}

/// Capacidad maxima del rango, con los decimales que el instrumento resuelve.
///
/// Postgres entrega `numeric` con toda su escala —"6100.000000000"— y pintarlo
/// tal cual atribuye a la balanza una resolucion que no tiene.
String rangeCapacityLabel(Json range) =>
    _rangeLabel(range['capacidad_max'], rangeDecimals(range));

/// Division de escala del rango.
///
/// Usa sus propios decimales y no los del rango: si el catalogo declarase menos
/// de los que la division necesita, redondearla la haria desaparecer.
String rangeDivisionLabel(Json range) => _rangeLabel(
  range['division_escala'],
  _decimalPlaces(range['division_escala']),
);

/// Nunca inventa: si el valor no es un numero reconocible se devuelve tal cual
/// llego, que es lo unico honesto con un dato de catalogo incompleto.
String _rangeLabel(Object? value, int decimals) {
  final scaled = _scaledNumber(value);
  if (scaled == null) return value?.toString().trim() ?? '';
  return _formatScaled(scaled, decimals);
}

/// Selects the first weighing range whose capacity contains [load].
/// This mirrors ServiceMET's range selection and falls back to the last range
/// when the entered load exceeds all configured capacities.
IndicationPrecision? indicationPrecisionForLoad(
  List<Json> ranges,
  String load,
  String unit,
) {
  final value = _scaledNumber(load);
  final targetFactor = _unitFactor(unit);
  if (value == null || targetFactor == null) return null;
  final loadMass = value * targetFactor;
  final candidates = <({Json range, BigInt capacityMass})>[];
  for (final range in ranges) {
    final capacity = _scaledNumber(range['capacidad_max']);
    final division = _scaledNumber(range['division_escala']);
    final factor = _unitFactor(range['unidad']?.toString() ?? unit);
    if (capacity != null &&
        capacity > BigInt.zero &&
        division != null &&
        division > BigInt.zero &&
        factor != null) {
      candidates.add((range: range, capacityMass: capacity * factor));
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.capacityMass.compareTo(b.capacityMass));
  final selected = candidates.firstWhere(
    (candidate) => loadMass <= candidate.capacityMass,
    orElse: () => candidates.last,
  );
  final rangeUnit = selected.range['unidad']?.toString() ?? unit;
  final sourceFactor = _unitFactor(rangeUnit)!;
  final sourceDivision = _scaledNumber(selected.range['division_escala'])!;
  final division = _divideRounded(sourceDivision * sourceFactor, targetFactor);
  if (division <= BigInt.zero) return null;
  final sameUnit = rangeUnit.trim().toLowerCase() == unit.trim().toLowerCase();
  final configuredDecimals = int.tryParse(
    selected.range['cantidad_decimales']?.toString() ?? '',
  );
  final decimals =
      sameUnit &&
          configuredDecimals != null &&
          configuredDecimals >= 0 &&
          configuredDecimals <= 9
      ? configuredDecimals
      : sameUnit
      ? _decimalPlaces(selected.range['division_escala'])
      : _decimalPlaces(_formatScaled(division, 9));
  return IndicationPrecision._(decimals: decimals, scaledDivision: division);
}

/// Formats the entered load as the initial indication for its weighing range.
/// If range data is unavailable, the exact entered text is retained.
String indicationFromLoad(List<Json> ranges, String load, String unit) {
  final value = _scaledNumber(load);
  if (value == null) return load.trim();
  final precision = indicationPrecisionForLoad(ranges, load, unit);
  return precision == null
      ? load.trim()
      : _formatScaled(value, precision.decimals);
}

/// Returns ServiceMET-style indication choices around the load in steps of d.
List<String> indicationSuggestions(
  List<Json> ranges,
  String load,
  String unit, {
  int steps = 5,
}) {
  final base = _scaledNumber(load);
  final precision = indicationPrecisionForLoad(ranges, load, unit);
  if (base == null || precision == null) return const [];
  return [
    for (var offset = steps; offset >= -steps; offset--)
      if (base + precision.scaledDivision * BigInt.from(offset) >= BigInt.zero)
        _formatScaled(
          base + precision.scaledDivision * BigInt.from(offset),
          precision.decimals,
        ),
  ];
}

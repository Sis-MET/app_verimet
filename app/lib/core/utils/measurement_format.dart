/// Lectura y escritura de valores de balanza.
///
/// En planta se escribe con coma decimal, pero el teclado del telefono ofrece
/// el punto: aceptar los dos evita que el operario tenga que pelear con el
/// teclado con guantes puestos. Hacia la pantalla siempre sale coma.
abstract final class MeasurementFormat {
  /// Signo menos tipografico (U+2212). Se distingue del guion a un brazo de
  /// distancia, que es como se lee esta app.
  static const String minus = '−';

  /// Marcador de lectura sin capturar.
  static const String empty = '—';

  /// Convierte lo tecleado a numero. Devuelve `null` si aun no es un numero
  /// valido, para poder pintar la fila como pendiente en vez de como error.
  static double? parse(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  /// Formatea con coma decimal ("20,01").
  static String format(double value, {int decimals = 2}) {
    return value.toStringAsFixed(decimals).replaceAll('.', ',');
  }

  /// Error con signo explicito ("+0,01", "−0,02"). Siempre lleva signo: en una
  /// columna de errores, el que no lo lleva se confunde con un cero.
  static String signedError(double? value, {int decimals = 2}) {
    if (value == null) return empty;
    final sign = value >= 0 ? '+' : minus;
    return '$sign${format(value.abs(), decimals: decimals)}';
  }
}

/// Fechas de calendario sin hora, con nombres en espanol.
///
/// La app no carga la localizacion de Material: estos rotulos son los de la
/// agenda, el editor de periodicidad y el selector de dia.
library;

const weekdayInitials = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

const weekdayNames = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Fecha sin hora, en UTC para que sumar dias no cruce cambios de horario.
DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime addDays(DateTime value, int days) =>
    DateTime.utc(value.year, value.month, value.day + days);

/// Hoy en el telefono, sin hora.
DateTime today() => dateOnly(DateTime.now());

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "2026-10-07", la forma en que viajan las fechas con la API.
String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// "7 oct".
String shortDayLabel(DateTime value) =>
    '${value.day} ${monthNames[value.month - 1].substring(0, 3)}';

/// "miércoles 7 de octubre".
String longDayLabel(DateTime value) =>
    '${weekdayNames[value.weekday - 1]} ${value.day} de '
    '${monthNames[value.month - 1]}';

/// "07/10/2026".
String numericDayLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

/// "Octubre 2026".
String monthTitle(DateTime value) {
  final name = monthNames[value.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${value.year}';
}

/// Desfase horario del telefono. El servidor lo usa para decidir que dia es
/// "hoy" en planta y en que dia cayo cada verificacion.
Map<String, int> clockFilters() => {
  'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
};

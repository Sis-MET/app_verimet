import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/utils/calendar_dates.dart';
import 'mobile_api.dart';

export '../../core/utils/calendar_dates.dart';

/// Como se cuentan las fechas de una prueba.
enum ScheduleMode {
  /// Fechas fijas de calendario: se mantienen aunque una verificacion se
  /// atrase.
  fixed,

  /// Un intervalo despues de la ultima verificacion realizada.
  rolling,
}

enum ScheduleUnit {
  day('Días', 'día', 'días'),
  week('Semanas', 'semana', 'semanas'),
  month('Meses', 'mes', 'meses'),
  year('Años', 'año', 'años');

  const ScheduleUnit(this.label, this.singular, this.plural);
  final String label;
  final String singular;
  final String plural;

  /// Mismos topes que `private.schedule_normalize`.
  int get maximum => switch (this) {
    day => 365,
    week => 52,
    month => 24,
    year => 5,
  };
}

/// Dentro del mes: un dia fijo (el 15) o un dia de la semana (el primer lunes).
enum MonthMode { day, weekday }

/// Accesos rapidos del editor. Cubren lo habitual en planta; lo demas se
/// arma en "Personalizada".
enum SchedulePreset {
  daily('Diaria'),
  workdays('Días hábiles'),
  weekly('Semanal'),
  biweekly('Quincenal'),
  monthly('Mensual'),
  bimonthly('Bimestral'),
  quarterly('Trimestral'),
  semiannual('Semestral'),
  annual('Anual'),
  custom('Personalizada');

  const SchedulePreset(this.label);
  final String label;
}

const ordinalNames = ['primer', 'segundo', 'tercer', 'cuarto', 'último'];

/// Periodicidad de una prueba de verificacion intermedia.
///
/// Es la regla que guarda Supabase (`private.schedule_normalize`) y la misma
/// aritmetica de fechas (`private.schedule_next` y `schedule_previous`). Aqui
/// solo alimenta la vista previa del editor: el calendario, la vigencia y lo
/// que cuenta como realizado se calculan en el servidor.
@immutable
class CheckSchedule {
  const CheckSchedule({
    required this.mode,
    required this.unit,
    required this.every,
    required this.warningDays,
    this.startsOn,
    this.weekdays = const [],
    this.monthMode = MonthMode.day,
    this.monthDay = 1,
    this.weekOfMonth = 1,
    this.weekday = 1,
  });

  /// Las configuraciones anteriores solo tenian dias entre pruebas, contados
  /// desde la ultima verificacion; el aviso era la cuarta parte, hasta 30.
  factory CheckSchedule.legacyDays(int days) => CheckSchedule(
    mode: ScheduleMode.rolling,
    unit: ScheduleUnit.day,
    every: days.clamp(1, 365),
    warningDays: math.min(30, days ~/ 4),
  );

  factory CheckSchedule.fromJson(Json json) {
    final unit = ScheduleUnit.values.byName(json['unit'] as String);
    return CheckSchedule(
      mode: ScheduleMode.values.byName(json['mode'] as String),
      unit: unit,
      every: (json['every'] as num).toInt(),
      warningDays: (json['warningDays'] as num).toInt(),
      startsOn: json['startsOn'] == null
          ? null
          : parseDayKey(json['startsOn'] as String),
      weekdays: [
        for (final day in json['weekdays'] as List? ?? const [])
          (day as num).toInt(),
      ],
      monthMode: json['monthMode'] == 'weekday'
          ? MonthMode.weekday
          : MonthMode.day,
      monthDay: (json['monthDay'] as num?)?.toInt() ?? 1,
      weekOfMonth: (json['weekOfMonth'] as num?)?.toInt() ?? 1,
      weekday: (json['weekday'] as num?)?.toInt() ?? 1,
    );
  }

  /// Regla de un acceso rapido, anclada en [today].
  factory CheckSchedule.preset(SchedulePreset preset, DateTime today) {
    final day = dateOnly(today);
    CheckSchedule fixed(
      ScheduleUnit unit,
      int every,
      int warning, {
      List<int> weekdays = const [],
    }) => CheckSchedule(
      mode: ScheduleMode.fixed,
      unit: unit,
      every: every,
      warningDays: warning,
      startsOn: day,
      weekdays: weekdays,
      monthDay: day.day,
      weekOfMonth: _weekOfMonth(day),
      weekday: day.weekday,
    );
    return switch (preset) {
      SchedulePreset.daily => fixed(ScheduleUnit.day, 1, 0),
      SchedulePreset.workdays => fixed(
        ScheduleUnit.week,
        1,
        0,
        weekdays: const [1, 2, 3, 4, 5],
      ),
      SchedulePreset.weekly => fixed(
        ScheduleUnit.week,
        1,
        1,
        weekdays: [day.weekday],
      ),
      SchedulePreset.biweekly => fixed(
        ScheduleUnit.week,
        2,
        2,
        weekdays: [day.weekday],
      ),
      // "Personalizada" parte de la mensual; el editor la ajusta desde ahi.
      SchedulePreset.monthly ||
      SchedulePreset.custom => fixed(ScheduleUnit.month, 1, 5),
      SchedulePreset.bimonthly => fixed(ScheduleUnit.month, 2, 7),
      SchedulePreset.quarterly => fixed(ScheduleUnit.month, 3, 10),
      SchedulePreset.semiannual => fixed(ScheduleUnit.month, 6, 15),
      SchedulePreset.annual => fixed(ScheduleUnit.year, 1, 30),
    };
  }

  final ScheduleMode mode;
  final ScheduleUnit unit;
  final int every;
  final int warningDays;
  final DateTime? startsOn;
  final List<int> weekdays;
  final MonthMode monthMode;
  final int monthDay;
  final int weekOfMonth;
  final int weekday;

  bool get fixed => mode == ScheduleMode.fixed;
  bool get monthly => unit == ScheduleUnit.month || unit == ScheduleUnit.year;

  /// La forma canonica que guarda el servidor: solo las claves que aplican.
  Json toJson() => {
    'mode': mode.name,
    'unit': unit.name,
    'every': every,
    'warningDays': warningDays,
    if (fixed) 'startsOn': dayKey(startsOn!),
    if (fixed && unit == ScheduleUnit.week) 'weekdays': ([...weekdays]..sort()),
    if (fixed && monthly) ...{
      'monthMode': monthMode.name,
      if (monthMode == MonthMode.day) 'monthDay': monthDay,
      if (monthMode == MonthMode.weekday) ...{
        'weekOfMonth': weekOfMonth,
        'weekday': weekday,
      },
    },
  };

  CheckSchedule copyWith({
    ScheduleMode? mode,
    ScheduleUnit? unit,
    int? every,
    int? warningDays,
    DateTime? startsOn,
    List<int>? weekdays,
    MonthMode? monthMode,
    int? monthDay,
    int? weekOfMonth,
    int? weekday,
  }) {
    final nextUnit = unit ?? this.unit;
    return CheckSchedule(
      mode: mode ?? this.mode,
      unit: nextUnit,
      every: (every ?? this.every).clamp(1, nextUnit.maximum),
      warningDays: (warningDays ?? this.warningDays).clamp(0, 90),
      startsOn: startsOn ?? this.startsOn,
      weekdays: weekdays ?? this.weekdays,
      monthMode: monthMode ?? this.monthMode,
      monthDay: monthDay ?? this.monthDay,
      weekOfMonth: weekOfMonth ?? this.weekOfMonth,
      weekday: weekday ?? this.weekday,
    );
  }

  /// Completa lo que una regla necesita para guardarse: fecha de inicio y,
  /// segun la unidad, dias de la semana o el dia del mes.
  CheckSchedule completed(DateTime today) {
    final start = startsOn ?? dateOnly(today);
    return copyWith(
      startsOn: start,
      weekdays: weekdays.isEmpty ? [start.weekday] : weekdays,
    );
  }

  /// El acceso rapido que describe esta regla, o [SchedulePreset.custom].
  SchedulePreset get preset {
    if (!fixed) return SchedulePreset.custom;
    final days = [...weekdays]..sort();
    return switch ((unit, every)) {
      (ScheduleUnit.day, 1) => SchedulePreset.daily,
      (ScheduleUnit.week, 1) when listEquals(days, const [1, 2, 3, 4, 5]) =>
        SchedulePreset.workdays,
      // Sumar un dia a la semanal no la vuelve "personalizada".
      (ScheduleUnit.week, 1) => SchedulePreset.weekly,
      (ScheduleUnit.week, 2) => SchedulePreset.biweekly,
      (ScheduleUnit.month, 1) => SchedulePreset.monthly,
      (ScheduleUnit.month, 2) => SchedulePreset.bimonthly,
      (ScheduleUnit.month, 3) => SchedulePreset.quarterly,
      (ScheduleUnit.month, 6) => SchedulePreset.semiannual,
      (ScheduleUnit.year, 1) => SchedulePreset.annual,
      _ => SchedulePreset.custom,
    };
  }

  /// "Cada mes, el día 15", "De lunes a viernes", "30 días después de la
  /// última verificación".
  String get summary {
    if (!fixed) {
      return '$every ${every == 1 ? unit.singular : unit.plural} '
          'después de la última verificación';
    }
    final cadence = every == 1
        ? switch (unit) {
            ScheduleUnit.day => 'Todos los días',
            ScheduleUnit.week => 'Cada semana',
            ScheduleUnit.month => 'Cada mes',
            ScheduleUnit.year => 'Cada año',
          }
        : 'Cada $every ${unit.plural}';
    switch (unit) {
      case ScheduleUnit.day:
        return cadence;
      case ScheduleUnit.week:
        final days = [...weekdays]..sort();
        if (every == 1 && listEquals(days, const [1, 2, 3, 4, 5])) {
          return 'De lunes a viernes';
        }
        if (days.length == 7) return '$cadence, todos los días';
        return '$cadence: ${_joined([for (final d in days) weekdayNames[d - 1]])}';
      case ScheduleUnit.month:
        return '$cadence, $_dayInMonth';
      case ScheduleUnit.year:
        final month = monthNames[(startsOn ?? DateTime.now()).month - 1];
        return monthMode == MonthMode.day
            ? '$cadence, el ${_monthDayLabel(monthDay)} de $month'
            : '$cadence, $_dayInMonth de $month';
    }
  }

  String get _dayInMonth => monthMode == MonthMode.day
      ? 'el día ${_monthDayLabel(monthDay)}'
      : 'el ${ordinalNames[weekOfMonth - 1]} ${weekdayNames[weekday - 1]}';

  static String _monthDayLabel(int day) =>
      day >= 29 ? '$day (o el último del mes)' : '$day';

  String get warningLabel => warningDays == 0
      ? 'Sin aviso previo'
      : 'Aviso $warningDays ${warningDays == 1 ? 'día' : 'días'} antes';

  /// Primera fecha fija igual o posterior a [onOrAfter].
  DateTime? next(DateTime onOrAfter) {
    final start = startsOn;
    if (!fixed || start == null) return null;
    var lower = _later(dateOnly(onOrAfter), start);
    switch (unit) {
      case ScheduleUnit.day:
        final steps = (_daysBetween(start, lower) / every).ceil();
        return addDays(start, steps * every);
      case ScheduleUnit.week:
        if (weekdays.isEmpty) return null;
        final weekStart = addDays(start, 1 - start.weekday);
        var index = _daysBetween(weekStart, lower) ~/ 7;
        if (index % every != 0) {
          index = (index ~/ every + 1) * every;
          lower = addDays(weekStart, 7 * index);
        }
        for (var attempt = 0; attempt < 2; attempt++) {
          final candidates = [
            for (final day in weekdays) addDays(weekStart, 7 * index + day - 1),
          ].where((date) => !date.isBefore(lower)).toList()..sort();
          if (candidates.isNotEmpty) return candidates.first;
          index += every;
          lower = addDays(weekStart, 7 * index);
        }
        return null;
      case ScheduleUnit.month:
      case ScheduleUnit.year:
        final step = unit == ScheduleUnit.year ? every * 12 : every;
        final zero = _monthIndex(start);
        final offset = ((_monthIndex(lower) - zero) / step).ceil() * step;
        var candidate = _monthDate(zero + offset);
        if (candidate.isBefore(lower)) {
          candidate = _monthDate(zero + offset + step);
        }
        return candidate;
    }
  }

  /// Las proximas [count] fechas desde [from]. En "desde la ultima", se
  /// cuentan a partir de [lastRun] o, sin verificaciones, desde [from].
  List<DateTime> upcoming(DateTime from, {int count = 4, DateTime? lastRun}) {
    final day = dateOnly(from);
    if (!fixed) {
      final base = dateOnly(lastRun ?? day);
      return [for (var k = 1; k <= count; k++) addInterval(base, k * every)];
    }
    final dates = <DateTime>[];
    var cursor = next(day);
    while (cursor != null && dates.length < count) {
      dates.add(cursor);
      cursor = next(addDays(cursor, 1));
    }
    return dates;
  }

  /// Suma [amount] unidades a [base]. Los meses se recortan al ultimo dia,
  /// como PostgreSQL: 31/01 + 1 mes = 28/02.
  DateTime addInterval(DateTime base, int amount) => switch (unit) {
    ScheduleUnit.day => addDays(base, amount),
    ScheduleUnit.week => addDays(base, 7 * amount),
    ScheduleUnit.month => _addMonths(base, amount),
    ScheduleUnit.year => _addMonths(base, 12 * amount),
  };

  DateTime _monthDate(int index) {
    final year = index ~/ 12, month = index % 12 + 1;
    final last = _daysInMonth(year, month);
    if (monthMode == MonthMode.day) {
      return DateTime.utc(year, month, math.min(monthDay, last));
    }
    if (weekOfMonth == 5) {
      final end = DateTime.utc(year, month, last);
      return addDays(end, -((end.weekday - weekday + 7) % 7));
    }
    final first = DateTime.utc(year, month);
    return addDays(
      first,
      (weekday - first.weekday + 7) % 7 + 7 * (weekOfMonth - 1),
    );
  }

  /// Dos reglas son la misma si el servidor guardaria lo mismo.
  @override
  bool operator ==(Object other) =>
      other is CheckSchedule &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

int _weekOfMonth(DateTime day) => math.min(4, (day.day - 1) ~/ 7 + 1);

DateTime _later(DateTime a, DateTime b) => a.isBefore(b) ? b : a;

int _daysBetween(DateTime from, DateTime to) => to.difference(from).inDays;

int _monthIndex(DateTime value) => value.year * 12 + value.month - 1;

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

DateTime _addMonths(DateTime value, int months) {
  final index = _monthIndex(value) + months;
  final year = index ~/ 12, month = index % 12 + 1;
  return DateTime.utc(
    year,
    month,
    math.min(value.day, _daysInMonth(year, month)),
  );
}

String _joined(List<String> words) => words.length < 2
    ? words.join()
    : '${words.sublist(0, words.length - 1).join(', ')} y ${words.last}';

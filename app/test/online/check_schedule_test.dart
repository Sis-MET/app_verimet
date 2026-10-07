import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/check_schedule.dart';

/// Los mismos casos que `scripts/test-operator-agenda-db.mjs` comprueba en
/// PostgreSQL: la vista previa del editor no puede prometer otras fechas que
/// las que despues muestra la agenda.
void main() {
  DateTime day(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return DateTime.utc(parts[0], parts[1], parts[2]);
  }

  String? next(Map<String, dynamic> rule, String date) {
    final result = CheckSchedule.fromJson(rule).next(day(date));
    return result == null ? null : dayKey(result);
  }

  test('días, semanas, meses, último día del mes y años bisiestos', () {
    final days = {
      'mode': 'fixed',
      'unit': 'day',
      'every': 3,
      'warningDays': 0,
      'startsOn': '2026-01-01',
    };
    expect(next(days, '2025-06-01'), '2026-01-01');
    expect(next(days, '2026-01-02'), '2026-01-04');

    final weeks = {
      'mode': 'fixed',
      'unit': 'week',
      'every': 2,
      'warningDays': 0,
      'startsOn': '2026-10-07',
      'weekdays': [1, 4],
    };
    expect(next(weeks, '2026-10-01'), '2026-10-08');
    expect(next(weeks, '2026-10-09'), '2026-10-19');
    expect(next(weeks, '2026-10-20'), '2026-10-22');

    final monthEnd = {
      'mode': 'fixed',
      'unit': 'month',
      'every': 1,
      'warningDays': 0,
      'startsOn': '2026-01-15',
      'monthMode': 'day',
      'monthDay': 31,
    };
    expect(next(monthEnd, '2026-02-01'), '2026-02-28');

    final lastFriday = {
      'mode': 'fixed',
      'unit': 'month',
      'every': 1,
      'warningDays': 0,
      'startsOn': '2026-10-01',
      'monthMode': 'weekday',
      'weekOfMonth': 5,
      'weekday': 5,
    };
    expect(next(lastFriday, '2026-10-01'), '2026-10-30');

    final firstMonday = {
      'mode': 'fixed',
      'unit': 'month',
      'every': 3,
      'warningDays': 0,
      'startsOn': '2026-10-01',
      'monthMode': 'weekday',
      'weekOfMonth': 1,
      'weekday': 1,
    };
    expect(next(firstMonday, '2026-10-01'), '2026-10-05');
    expect(next(firstMonday, '2026-10-06'), '2027-01-04');

    final leap = {
      'mode': 'fixed',
      'unit': 'year',
      'every': 1,
      'warningDays': 0,
      'startsOn': '2028-02-29',
      'monthMode': 'day',
      'monthDay': 29,
    };
    expect(next(leap, '2029-01-01'), '2029-02-28');
  });

  test('desde la última verificación suma meses como PostgreSQL', () {
    const rolling = CheckSchedule(
      mode: ScheduleMode.rolling,
      unit: ScheduleUnit.month,
      every: 1,
      warningDays: 5,
    );
    expect(
      rolling
          .upcoming(day('2026-01-10'), count: 3, lastRun: day('2026-01-31'))
          .map(dayKey),
      ['2026-02-28', '2026-03-31', '2026-04-30'],
    );
  });

  test('cada acceso rápido se reconoce y se describe en palabras', () {
    final wednesday = day('2026-10-07');
    final expected = {
      SchedulePreset.daily: 'Todos los días',
      SchedulePreset.workdays: 'De lunes a viernes',
      SchedulePreset.weekly: 'Cada semana: miércoles',
      SchedulePreset.biweekly: 'Cada 2 semanas: miércoles',
      SchedulePreset.monthly: 'Cada mes, el día 7',
      SchedulePreset.quarterly: 'Cada 3 meses, el día 7',
      SchedulePreset.annual: 'Cada año, el 7 de octubre',
    };
    for (final MapEntry(key: preset, value: summary) in expected.entries) {
      final schedule = CheckSchedule.preset(preset, wednesday);
      expect(schedule.preset, preset);
      expect(schedule.summary, summary);
    }
    final lastFriday = CheckSchedule.preset(
      SchedulePreset.monthly,
      wednesday,
    ).copyWith(monthMode: MonthMode.weekday, weekOfMonth: 5, weekday: 5);
    expect(lastFriday.summary, 'Cada mes, el último viernes');
    expect(
      CheckSchedule.legacyDays(30).summary,
      '30 días después de la última verificación',
    );
    expect(CheckSchedule.legacyDays(30).warningLabel, 'Aviso 7 días antes');
  });

  test('la regla viaja en la forma canónica que guarda el servidor', () {
    final schedule = CheckSchedule.preset(
      SchedulePreset.weekly,
      day('2026-10-07'),
    ).copyWith(weekdays: [5, 1]);
    expect(schedule.toJson(), {
      'mode': 'fixed',
      'unit': 'week',
      'every': 1,
      'warningDays': 1,
      'startsOn': '2026-10-07',
      'weekdays': [1, 5],
    });
    expect(CheckSchedule.fromJson(schedule.toJson()), schedule);
    expect(CheckSchedule.legacyDays(30).toJson(), {
      'mode': 'rolling',
      'unit': 'day',
      'every': 30,
      'warningDays': 7,
    });
  });
}

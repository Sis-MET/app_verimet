import 'package:flutter/material.dart';

import '../../core/utils/calendar_dates.dart';
import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';
import 'surface_card.dart';

/// Urgencia de lo que hay un dia. El dia toma la mas alta de sus balanzas.
enum DayTone { overdue, due, scheduled, done }

/// Lo que se marca bajo el numero de un dia: cuantas balanzas y con que tono.
@immutable
class DayMarker {
  const DayMarker({required this.count, required this.tone});
  final int count;
  final DayTone tone;
}

/// Mes en rejilla de lunes a domingo.
///
/// Es la pieza de la agenda y del selector de dia. Solo dibuja los dias del
/// mes —los huecos de los meses vecinos quedan vacios— para que la rejilla
/// se lea sin ruido; debajo de cada numero, una pastilla con el numero de
/// balanzas y el color de la mas urgente.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    required this.month,
    required this.today,
    required this.onSelect,
    this.selected,
    this.markers = const {},
    this.onMonth,
    super.key,
  });

  /// Cualquier dia del mes que se muestra.
  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Marcas por [dayKey].
  final Map<String, DayMarker> markers;

  /// Cambiar de mes; sin el, el encabezado no tiene flechas.
  final ValueChanged<DateTime>? onMonth;

  static const double _cellHeight = 52;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final first = DateTime.utc(month.year, month.month);
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final rows = ((leading + days) / 7).ceil();

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (onMonth != null)
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: () =>
                      onMonth!(DateTime.utc(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
              Expanded(
                child: Text(
                  monthTitle(first),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.figure(context, size: 20),
                ),
              ),
              if (onMonth != null)
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: () =>
                      onMonth!(DateTime.utc(month.year, month.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final initial in weekdayInitials)
                Expanded(
                  child: Text(
                    initial,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(context, size: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: SizedBox(
                      height: _cellHeight,
                      child: () {
                        final number = row * 7 + column - leading + 1;
                        if (number < 1 || number > days) {
                          return const SizedBox.shrink();
                        }
                        final day = DateTime.utc(
                          month.year,
                          month.month,
                          number,
                        );
                        return _DayCell(
                          day: day,
                          isToday: sameDay(day, today),
                          isSelected:
                              selected != null && sameDay(day, selected!),
                          marker: markers[dayKey(day)],
                          palette: palette,
                          onTap: () => onSelect(day),
                        );
                      }(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.marker,
    required this.palette,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final DayMarker? marker;
  final IndustryPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = marker?.count ?? 0;
    final (Color fill, Color ink) = switch (marker?.tone) {
      DayTone.overdue => (palette.failSurface, palette.failInk),
      DayTone.due => (palette.accent, palette.card),
      DayTone.scheduled => (palette.accentSoft, palette.accentDeep),
      DayTone.done => (palette.successSurface, palette.successInk),
      null => (Colors.transparent, palette.muted),
    };

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${longDayLabel(day)}${count == 0 ? '' : ', $count ${count == 1 ? 'balanza' : 'balanzas'}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? palette.accentInk : Colors.transparent,
                border: isToday && !isSelected
                    ? Border.all(color: palette.accentInk, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  fontFamilyFallback: AppFonts.fallback,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  height: 1,
                  color: isSelected
                      ? palette.card
                      : isToday
                      ? palette.accentInk
                      : palette.text,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 13,
              child: count == 0
                  ? null
                  : Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elige un dia en una hoja inferior con el mismo calendario de la agenda.
Future<DateTime?> showDayPicker(
  BuildContext context, {
  required DateTime initial,
  required String title,
}) => showModalBottomSheet<DateTime>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _DayPickerSheet(initial: dateOnly(initial), title: title),
);

class _DayPickerSheet extends StatefulWidget {
  const _DayPickerSheet({required this.initial, required this.title});
  final DateTime initial;
  final String title;

  @override
  State<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends State<_DayPickerSheet> {
  late DateTime selected = widget.initial;
  late DateTime month = widget.initial;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: AppTextStyles.figure(context, size: 22)),
          const SizedBox(height: 2),
          Text(
            longDayLabel(selected),
            style: AppTextStyles.caption(context, size: 12),
          ),
          const SizedBox(height: 12),
          MonthCalendar(
            month: month,
            today: today(),
            selected: selected,
            onSelect: (day) => setState(() => selected = day),
            onMonth: (value) => setState(() => month = value),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Usar esta fecha'),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/choice_pill.dart';
import '../../shared/widgets/month_calendar.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/segmented_pills.dart';
import '../../shared/widgets/surface_card.dart';
import 'check_schedule.dart';

/// Lo que devuelve el editor: la regla y si vale para todas las pruebas.
class ScheduleChoice {
  const ScheduleChoice(this.schedule, {this.applyToAll = false});
  final CheckSchedule schedule;
  final bool applyToAll;
}

/// Abre el editor de periodicidad de una prueba.
Future<ScheduleChoice?> showScheduleEditor(
  BuildContext context, {
  required CheckSchedule initial,
  required String testLabel,
  bool offerApplyToAll = false,
  bool customAllowed = true,
}) => showModalBottomSheet<ScheduleChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.92,
    child: ScheduleEditor(
      initial: initial,
      testLabel: testLabel,
      offerApplyToAll: offerApplyToAll,
      customAllowed: customAllowed,
    ),
  ),
);

/// Editor de periodicidad.
///
/// Arriba, en una frase, lo que se va a guardar y las proximas fechas: el jefe
/// de calidad no tiene que traducir "cada 2 semanas, lunes y jueves" a un
/// calendario. Debajo, de lo general a lo fino: como se cuenta (fechas fijas o
/// desde la ultima), los accesos rapidos y, solo cuando aplican, los dias de
/// la semana o del mes. "Personalizada" abre el intervalo libre.
///
/// Sin [customAllowed] (el plan gratuito) solo quedan los accesos rapidos con
/// fechas fijas, que es lo que Supabase acepta para ese plan: "Personalizada"
/// y "Desde la ultima" muestran el candado y dicen donde estan.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({
    required this.initial,
    required this.testLabel,
    this.offerApplyToAll = false,
    this.customAllowed = true,
    super.key,
  });

  final CheckSchedule initial;
  final String testLabel;
  final bool offerApplyToAll;
  final bool customAllowed;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late CheckSchedule schedule = _allowed(
    widget.initial.completed(DateTime.now()),
  );
  late bool custom = schedule.preset == SchedulePreset.custom;
  bool applyToAll = false;

  /// Se toco algo que el plan no incluye: lo dice el aviso del editor.
  bool locked = false;

  /// Una regla a medida que el plan ya no admite arranca como mensual.
  CheckSchedule _allowed(CheckSchedule value) =>
      widget.customAllowed || value.preset != SchedulePreset.custom
      ? value
      : CheckSchedule.preset(SchedulePreset.monthly, value.startsOn!);

  void _lock() => setState(() => locked = true);

  DateTime get start => schedule.startsOn!;

  void _update(CheckSchedule next) => setState(() => schedule = next);

  void _choosePreset(SchedulePreset preset) {
    if (preset == SchedulePreset.custom && !widget.customAllowed) {
      _lock();
      return;
    }
    if (preset == SchedulePreset.custom) {
      setState(() => custom = true);
      return;
    }
    setState(() {
      custom = false;
      schedule = CheckSchedule.preset(preset, start);
    });
  }

  /// Desde la ultima solo hay intervalo: los dias de la semana o del mes se
  /// conservan por si se vuelve a fechas fijas, pero no se guardan.
  void _chooseMode(ScheduleMode mode) =>
      mode == ScheduleMode.rolling && !widget.customAllowed
      ? _lock()
      : _update(schedule.copyWith(mode: mode));

  /// Semana del mes en que cae la primera fecha: el 7 es el primer miercoles.
  int get _startWeekOfMonth => ((start.day - 1) ~/ 7 + 1).clamp(1, 4);

  void _chooseUnit(ScheduleUnit unit) => _update(
    schedule.copyWith(
      unit: unit,
      weekdays: schedule.weekdays.isEmpty ? [start.weekday] : null,
    ),
  );

  Future<void> _pickStart() async {
    final picked = await showDayPicker(
      context,
      initial: start,
      title: 'Primera fecha',
    );
    if (picked == null || !mounted) return;
    // La primera fecha arrastra el dia del mes y el de la semana, salvo que el
    // jefe haya marcado varios dias a mano.
    _update(
      schedule.copyWith(
        startsOn: picked,
        monthDay: picked.day,
        weekday: picked.weekday,
        weekOfMonth: schedule.weekOfMonth == 5
            ? 5
            : ((picked.day - 1) ~/ 7 + 1).clamp(1, 4),
        weekdays: schedule.weekdays.length == 1 ? [picked.weekday] : null,
      ),
    );
  }

  void _toggleWeekday(int day) {
    final days = {...schedule.weekdays};
    if (days.contains(day)) {
      if (days.length == 1) return;
      days.remove(day);
    } else {
      days.add(day);
    }
    _update(schedule.copyWith(weekdays: days.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final preset = custom ? SchedulePreset.custom : schedule.preset;
    final showWeekdays =
        schedule.fixed &&
        schedule.unit == ScheduleUnit.week &&
        (custom || preset != SchedulePreset.workdays);
    final showMonthMode = schedule.fixed && schedule.monthly;
    final upcoming = schedule.upcoming(today());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            children: [
              Kicker(widget.testLabel),
              const SizedBox(height: 2),
              Text(
                'Periodicidad',
                style: AppTextStyles.figure(context, size: 26),
              ),
              const SizedBox(height: 12),
              SurfaceCard(
                key: const ValueKey('schedule-summary'),
                background: palette.accentSoft,
                borderColor: palette.accentSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.summary,
                      style: AppTextStyles.figure(
                        context,
                        size: 19,
                        color: palette.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      schedule.warningLabel,
                      style: TextStyle(fontSize: 12, color: palette.accentDeep),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      schedule.fixed
                          ? 'PRÓXIMAS FECHAS'
                          : 'SI SE VERIFICA HOY, LAS SIGUIENTES',
                      style: AppTextStyles.caption(context, size: 10.5),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final date in upcoming)
                          _DateChip(shortDayLabel(date)),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionLabel('Cómo se cuenta'),
              SegmentedPills<ScheduleMode>(
                selected: schedule.mode,
                onSelect: _chooseMode,
                segments: const [
                  PillSegment(ScheduleMode.fixed, 'Fechas fijas'),
                  PillSegment(ScheduleMode.rolling, 'Desde la última'),
                ],
              ),
              _Hint(
                schedule.fixed
                    ? 'Las fechas quedan en la agenda aunque una verificación se atrase.'
                    : 'Cada verificación realizada fija la siguiente fecha.',
              ),
              if (schedule.fixed) ...[
                const SectionLabel('Frecuencia'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in SchedulePreset.values)
                      ChoicePill(
                        key: ValueKey('preset-${option.name}'),
                        label: option.label,
                        icon:
                            option == SchedulePreset.custom &&
                                !widget.customAllowed
                            ? Icons.lock_outline
                            : null,
                        selected: option == preset,
                        onTap: () => _choosePreset(option),
                      ),
                  ],
                ),
              ],
              if (locked)
                Padding(
                  key: const ValueKey('schedule-locked'),
                  padding: const EdgeInsets.only(top: 12),
                  child: _Hint(
                    'Tu plan usa las periodicidades predefinidas con fechas fijas. '
                    'La periodicidad a medida y contar desde la última están en planes superiores: pídelo en Ajustes › Mi plan.',
                  ),
                ),
              if (custom || !schedule.fixed) ...[
                const SectionLabel('Repetir cada'),
                _Stepper(
                  key: const ValueKey('schedule-every'),
                  value: schedule.every,
                  minimum: 1,
                  maximum: schedule.unit.maximum,
                  label: schedule.every == 1
                      ? schedule.unit.singular
                      : schedule.unit.plural,
                  onChanged: (value) =>
                      _update(schedule.copyWith(every: value)),
                ),
                const SizedBox(height: 10),
                SegmentedPills<ScheduleUnit>(
                  selected: schedule.unit,
                  onSelect: _chooseUnit,
                  segments: [
                    for (final unit in ScheduleUnit.values)
                      PillSegment(unit, unit.label),
                  ],
                ),
              ],
              if (showWeekdays) ...[
                const SectionLabel('Qué días'),
                _WeekdayPicker(
                  selected: schedule.weekdays,
                  onToggle: _toggleWeekday,
                ),
              ],
              if (showMonthMode) ...[
                const SectionLabel('Qué día del mes'),
                SegmentedPills<MonthMode>(
                  selected: schedule.monthMode,
                  onSelect: (mode) => _update(
                    schedule.copyWith(
                      monthMode: mode,
                      monthDay: start.day,
                      weekOfMonth: _startWeekOfMonth,
                      weekday: start.weekday,
                    ),
                  ),
                  segments: [
                    PillSegment(MonthMode.day, 'El día ${start.day}'),
                    PillSegment(
                      MonthMode.weekday,
                      'El ${ordinalNames[_startWeekOfMonth - 1]} '
                      '${weekdayNames[start.weekday - 1]}',
                    ),
                  ],
                ),
                if (schedule.monthMode == MonthMode.weekday) ...[
                  const SizedBox(height: 8),
                  ChoicePill(
                    key: const ValueKey('month-last-weekday'),
                    label: 'Usar el último ${weekdayNames[start.weekday - 1]}',
                    selected: schedule.weekOfMonth == 5,
                    onTap: () => _update(
                      schedule.copyWith(
                        weekOfMonth: schedule.weekOfMonth == 5
                            ? _startWeekOfMonth
                            : 5,
                        weekday: start.weekday,
                      ),
                    ),
                  ),
                ],
              ],
              if (schedule.fixed) ...[
                const SectionLabel('Primera fecha'),
                SurfaceList(
                  children: [
                    _ActionRow(
                      key: const ValueKey('schedule-start'),
                      icon: Icons.event_outlined,
                      label: longDayLabel(start),
                      caption: 'Desde aquí se cuentan las fechas fijas',
                      onTap: _pickStart,
                    ),
                  ],
                ),
              ],
              const SectionLabel('Aviso previo'),
              _Stepper(
                key: const ValueKey('schedule-warning'),
                value: schedule.warningDays,
                minimum: 0,
                maximum: 90,
                label: schedule.warningDays == 1 ? 'día antes' : 'días antes',
                onChanged: (value) =>
                    _update(schedule.copyWith(warningDays: value)),
              ),
              const _Hint(
                'Desde ese día la balanza aparece como próxima en la agenda, y una verificación hecha entonces cuenta para esa fecha.',
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.divider)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.offerApplyToAll)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: applyToAll,
                    onChanged: (value) =>
                        setState(() => applyToAll = value ?? false),
                    title: const Text('Usar en todas las pruebas elegidas'),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ScheduleChoice(schedule, applyToAll: applyToAll),
                  ),
                  child: const Text('Aplicar periodicidad'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: IndustryPalette.of(context).muted,
      ),
    ),
  );
}

class _DateChip extends StatelessWidget {
  const _DateChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.reading(context, size: 12.5, color: palette.text),
      ),
    );
  }
}

/// Lunes a domingo como siete botones redondos.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});
  final List<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var day = 1; day <= 7; day++)
          Semantics(
            button: true,
            selected: selected.contains(day),
            label: weekdayNames[day - 1],
            excludeSemantics: true,
            child: Material(
              key: ValueKey('weekday-$day'),
              color: selected.contains(day) ? palette.accent : palette.card,
              shape: CircleBorder(
                side: BorderSide(
                  color: selected.contains(day)
                      ? palette.accent
                      : palette.divider,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onToggle(day),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: Text(
                      weekdayInitials[day - 1],
                      style: TextStyle(
                        fontFamily: AppFonts.heading,
                        fontFamilyFallback: AppFonts.fallback,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: selected.contains(day)
                            ? palette.card
                            : palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Numero con menos y mas, para valores cortos que se ajustan de a uno.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final int value;
  final int minimum;
  final int maximum;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Menos',
          onPressed: value > minimum ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$value',
                  style: AppTextStyles.figure(context, size: 24),
                ),
                TextSpan(
                  text: '  $label',
                  style: TextStyle(
                    fontSize: 13,
                    color: IndustryPalette.of(context).muted,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          tooltip: 'Más',
          onPressed: value < maximum ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );
}

/// Fila con icono, texto y chevron dentro de una lista agrupada.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: palette.accentInk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.figure(context, size: 17)),
                  Text(
                    caption,
                    style: TextStyle(fontSize: 11.5, color: palette.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

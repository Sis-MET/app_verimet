import 'package:flutter/material.dart';

import '../../core/utils/calendar_dates.dart';
import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/choice_pill.dart';
import '../../shared/widgets/month_calendar.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/surface_card.dart';
import 'equipment_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Estado de una fecha de verificacion, como lo devuelve la agenda.
enum AgendaState {
  overdue('OVERDUE', 'Atrasada', DayTone.overdue),
  missed('MISSED', 'No realizada', DayTone.overdue),
  dueToday('DUE_TODAY', 'Hoy', DayTone.due),
  dueSoon('DUE_SOON', 'Próxima', DayTone.due),
  scheduled('SCHEDULED', 'Programada', DayTone.scheduled),
  done('DONE', 'Hecha', DayTone.done);

  const AgendaState(this.code, this.label, this.tone);
  final String code;
  final String label;
  final DayTone tone;

  static AgendaState of(Object? code) => values.firstWhere(
    (state) => state.code == code,
    orElse: () => AgendaState.scheduled,
  );
}

/// La mas urgente de una lista: el orden del enum es el de urgencia.
AgendaState worstState(Iterable<AgendaState> states) =>
    states.reduce((a, b) => a.index <= b.index ? a : b);

/// Agenda: que balanza toca verificar cada dia.
///
/// El operador ve sus balanzas asignadas; el jefe de calidad, las de sus
/// plantas, con quien tiene cada una y un filtro por operador. Arriba, lo
/// atrasado, que es lo primero que hay que resolver; en el centro el mes, con
/// cuantas balanzas hay cada dia y el color de la mas urgente; debajo, el
/// detalle del dia elegido.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({required this.session, super.key});
  final MobileSession session;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late DateTime month = today();
  late DateTime selected = today();

  /// `null` todas; `unassigned` sin operador; si no, el id del operador.
  String? operator;
  final Map<String, String> operators = {};
  bool showAllOverdue = false;

  Json? data;
  bool loading = false;
  String? error;
  int _request = 0;

  bool get quality => widget.session.quality;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final first = DateTime.utc(month.year, month.month);
    final last = DateTime.utc(month.year, month.month + 1, 0);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.session.api.read('agenda', {
        ...clockFilters(),
        'from': dayKey(first),
        'to': dayKey(last),
        'operatorId': ?operator,
      });
      if (!mounted || request != _request) return;
      // Los operadores del filtro salen de lo que ya se vio: un operador sin
      // balanzas en el mes no tiene nada que mostrar.
      for (final item in [
        ...objects(result['items']),
        ...objects(result['overdue']),
      ]) {
        for (final person in objects(object(item['equipment'])['assignees'])) {
          operators[person['id'] as String] = valueLabel(person['name']);
        }
      }
      setState(() {
        data = result;
        loading = false;
      });
    } catch (failure) {
      if (!mounted || request != _request) return;
      setState(() {
        loading = false;
        error = failure is MobileFailure
            ? failure.message
            : 'No se pudo cargar la agenda.';
      });
    }
  }

  void _changeMonth(DateTime value) {
    final now = today();
    setState(() {
      month = value;
      selected = value.year == now.year && value.month == now.month
          ? now
          : DateTime.utc(value.year, value.month);
    });
    _load();
  }

  void _filter(String? value) {
    if (value == operator) return;
    setState(() => operator = value);
    _load();
  }

  Future<void> _open(Json equipment) async {
    await openPage(
      context,
      EquipmentScreen(
        session: widget.session,
        equipmentId: equipment['id'] as String,
      ),
    );
    if (mounted) _load();
  }

  /// Una fila por balanza y dia, con sus pruebas.
  Map<String, List<Json>> get _byDay {
    final days = <String, List<Json>>{};
    for (final item in objects(data?['items'])) {
      days.putIfAbsent(item['date'] as String, () => []).add(item);
    }
    return days;
  }

  Map<String, DayMarker> _markers(Map<String, List<Json>> days) => {
    for (final MapEntry(key: day, value: items) in days.entries)
      day: DayMarker(
        count: items.length,
        tone: worstState([
          for (final item in items)
            for (final test in objects(item['tests']))
              AgendaState.of(test['state']),
        ]).tone,
      ),
  };

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final days = _byDay;
    final dayItems = days[dayKey(selected)] ?? const <Json>[];
    final overdue = objects(data?['overdue']);
    final bootstrap = session.bootstrap;
    final unassignedOperator =
        bootstrap['equipmentScope'] == 'ASSIGNED' &&
        (bootstrap['equipmentCount'] as num? ?? 0) == 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kicker(valueLabel(object(bootstrap['client'])['name'])),
                    const SizedBox(height: 2),
                    Text(
                      'Agenda',
                      style: AppTextStyles.figure(context, size: 29),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        quality
                            ? 'Verificaciones programadas en tus plantas'
                            : 'Tus balanzas asignadas',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: IndustryPalette.of(context).muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Volver a hoy',
                onPressed: () => _changeMonth(today()),
                icon: const Icon(Icons.today_outlined),
              ),
            ],
          ),
          if (quality) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (value, label) in [
                    (null, 'Todas'),
                    ('unassigned', 'Sin operador'),
                    for (final entry in operators.entries)
                      (entry.key, entry.value),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoicePill(
                        key: ValueKey('agenda-filter-${value ?? 'all'}'),
                        label: label,
                        icon: value == null || value == 'unassigned'
                            ? null
                            : Icons.person_outline,
                        selected: operator == value,
                        onTap: () => _filter(value),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SizedBox(
            height: 3,
            child: loading ? const LinearProgressIndicator() : null,
          ),
          if (unassignedOperator)
            const Notice(
              'Aún no tienes balanzas asignadas. El jefe de calidad te las asigna desde Plantas › Operadores.',
              icon: Icons.person_search_outlined,
            ),
          if (error != null) ...[
            Notice(error!, alert: true),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _load,
                child: const Text('Reintentar'),
              ),
            ),
          ],
          if (overdue.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OverdueCard(
              items: overdue,
              showAll: showAllOverdue,
              showAssignees: quality,
              onToggle: () => setState(() => showAllOverdue = !showAllOverdue),
              onOpen: _open,
            ),
          ],
          const SizedBox(height: 12),
          MonthCalendar(
            key: const ValueKey('agenda-calendar'),
            month: month,
            today: today(),
            selected: selected,
            markers: _markers(days),
            onSelect: (day) => setState(() => selected = day),
            onMonth: _changeMonth,
          ),
          SectionLabel(
            '${longDayLabel(selected)} · ${dayItems.length} '
            '${dayItems.length == 1 ? 'balanza' : 'balanzas'}',
          ),
          if (dayItems.isEmpty)
            Text(
              data == null ? '' : 'Nada programado para este día.',
              style: TextStyle(
                fontSize: 13,
                color: IndustryPalette.of(context).muted,
              ),
            )
          else
            SurfaceList(
              children: [
                for (final item in dayItems)
                  _AgendaRow(
                    equipment: object(item['equipment']),
                    tests: objects(item['tests']),
                    showAssignees: quality,
                    onTap: () => _open(object(item['equipment'])),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const Notice(
            'Cuenta como hecha cualquier verificación finalizada en la ventana de cada fecha, con o sin pesas patrón. La trazabilidad se indica en su resultado.',
          ),
        ],
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  const _OverdueCard({
    required this.items,
    required this.showAll,
    required this.showAssignees,
    required this.onToggle,
    required this.onOpen,
  });
  final List<Json> items;
  final bool showAll;
  final bool showAssignees;
  final VoidCallback onToggle;
  final ValueChanged<Json> onOpen;

  static const _preview = 3;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final visible = showAll ? items : items.take(_preview).toList();
    return SurfaceCard(
      key: const ValueKey('agenda-overdue'),
      padding: EdgeInsets.zero,
      borderColor: palette.failSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: palette.failSurface,
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: palette.failInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'balanza atrasada' : 'balanzas atrasadas'}',
                    style: AppTextStyles.figure(
                      context,
                      size: 17,
                      color: palette.failInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: palette.hairline,
              ),
            _AgendaRow(
              equipment: object(visible[i]['equipment']),
              tests: [
                for (final test in objects(visible[i]['tests']))
                  {...test, 'state': 'OVERDUE'},
              ],
              caption:
                  'Tocaba el ${numericDayLabel(parseDayKey(visible[i]['dueOn'] as String))}',
              showAssignees: showAssignees,
              onTap: () => onOpen(object(visible[i]['equipment'])),
            ),
          ],
          if (items.length > _preview)
            TextButton(
              onPressed: onToggle,
              child: Text(
                showAll ? 'Ver menos' : 'Ver las ${items.length} atrasadas',
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila de balanza en la agenda: codigo, donde esta, que pruebas tocan y su
/// estado; para el jefe, quien la tiene asignada.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.equipment,
    required this.tests,
    required this.showAssignees,
    required this.onTap,
    this.caption,
  });
  final Json equipment;
  final List<Json> tests;
  final bool showAssignees;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final state = worstState([
      for (final test in tests) AgendaState.of(test['state']),
    ]);
    final assignees = objects(equipment['assignees']);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customerEquipmentCode(equipment),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.reading(
                            context,
                            size: 16,
                            color: palette.accentInk,
                          ),
                        ),
                      ),
                      _StatePill(state),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${valueLabel(equipment['departamento'])} · ${valueLabel(equipment['planta'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.figure(context, size: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      for (final test in tests)
                        tests.length > 1 &&
                                AgendaState.of(test['state']) ==
                                    AgendaState.done
                            ? '${testLabel(test['type'])} ✓'
                            : testLabel(test['type']),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: TextStyle(fontSize: 11.5, color: palette.failInk),
                    ),
                  if (showAssignees) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: assignees.isEmpty
                              ? palette.fail
                              : palette.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            assignees.isEmpty
                                ? 'Sin operador asignado'
                                : assignees
                                      .map((a) => valueLabel(a['name']))
                                      .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: assignees.isEmpty
                                  ? palette.fail
                                  : palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill(this.state);
  final AgendaState state;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final (Color fill, Color ink) = switch (state.tone) {
      DayTone.overdue => (palette.failSurface, palette.failInk),
      DayTone.due => (palette.accent, palette.card),
      DayTone.scheduled => (palette.accentSoft, palette.accentDeep),
      DayTone.done => (palette.successSurface, palette.successInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.4,
          height: 1.3,
          color: ink,
        ),
      ),
    );
  }
}

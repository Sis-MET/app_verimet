import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/choice_pill.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/segmented_pills.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Operadores de una planta y cuantas balanzas tiene cada uno.
///
/// Es la tercera pastilla de Plantas, solo para el jefe de calidad. Los
/// usuarios y sus plantas los habilita Metrica en RimMET con los cupos del
/// contrato; aqui se decide que balanzas verifica cada operador. Un operador
/// sin balanzas no ve ninguna.
class OperatorsPanel extends StatefulWidget {
  const OperatorsPanel({required this.session, super.key});
  final MobileSession session;

  @override
  State<OperatorsPanel> createState() => _OperatorsPanelState();
}

class _OperatorsPanelState extends State<OperatorsPanel> {
  late String? plantId = _plants.firstOrNull?['id'] as String?;
  int revision = 0;

  List<Json> get _plants => objects(widget.session.bootstrap['plants']);

  Future<void> _openMember(Json member) async {
    final saved = await openPage<bool>(
      context,
      OperatorAssignmentScreen(
        session: widget.session,
        plantId: plantId!,
        member: member,
      ),
    );
    if (saved == true && mounted) {
      setState(() => revision++);
      unawaited(widget.session.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final plants = _plants;
    if (plantId == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 140),
        children: const [
          Notice(
            'No tienes plantas asignadas. Solicita su habilitación en RimMET.',
          ),
        ],
      );
    }
    return RemotePanel(
      dataKey: '$plantId|$revision',
      load: () => widget.session.api.read('team', {'plantId': plantId}),
      builder: (data) {
        final palette = IndustryPalette.of(context);
        final members = objects(data['members']);
        final total = (data['equipmentCount'] as num? ?? 0).toInt();
        final unassigned = (data['unassignedCount'] as num? ?? 0).toInt();

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 140),
          children: [
            if (plants.length > 1) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final plant in plants)
                    ChoicePill(
                      key: ValueKey('team-plant-${plant['id']}'),
                      icon: Icons.factory_outlined,
                      label: valueLabel(plant['name']),
                      selected: plant['id'] == plantId,
                      onTap: () =>
                          setState(() => plantId = plant['id'] as String),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            StatStrip(
              cells: [
                StatCell(value: '$total', label: 'Balanzas'),
                StatCell(value: '${members.length}', label: 'Operadores'),
                StatCell(
                  value: '$unassigned',
                  label: 'Sin operador',
                  valueColor: unassigned > 0 ? palette.fail : null,
                ),
              ],
            ),
            if (unassigned > 0)
              Notice(
                '$unassigned ${unassigned == 1 ? 'balanza no tiene' : 'balanzas no tienen'} operador: no aparecen en la agenda de nadie. Asígnalas desde cada operador.',
                icon: Icons.warning_amber_outlined,
              ),
            const SectionLabel('Operadores'),
            if (members.isEmpty)
              const Notice(
                'Esta planta no tiene operadores. Métrica crea los usuarios y les habilita plantas en RimMET, dentro de los cupos del plan.',
              )
            else
              SurfaceList(
                children: [
                  for (final member in members)
                    _MemberRow(
                      member: member,
                      total: total,
                      onTap: () => _openMember(member),
                    ),
                ],
              ),
            const Notice(
              'Cada operador ve, verifica y recibe en su agenda solo las balanzas que le asignes. Una balanza puede tener varios operadores.',
              icon: Icons.groups_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.total,
    required this.onTap,
  });
  final Json member;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final assigned = (member['assignedCount'] as num? ?? 0).toInt();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            _Initials(valueLabel(member['name'])),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valueLabel(member['name']),
                    style: AppTextStyles.figure(context, size: 17),
                  ),
                  Text(
                    assigned == 0
                        ? 'Sin balanzas asignadas · no verá ninguna'
                        : '$assigned de $total ${total == 1 ? 'balanza' : 'balanzas'} · ${valueLabel(member['username'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: assigned == 0 ? palette.fail : palette.muted,
                    ),
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

class _Initials extends StatelessWidget {
  const _Initials(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final letters = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        letters,
        style: AppTextStyles.figure(
          context,
          size: 16,
          color: palette.accentInk,
        ),
      ),
    );
  }
}

enum _AssignmentView { all, chosen }

/// Balanzas de un operador en una planta: lista para marcar, agrupada por
/// departamento, con busqueda y "marcar todas".
class OperatorAssignmentScreen extends StatefulWidget {
  const OperatorAssignmentScreen({
    required this.session,
    required this.plantId,
    required this.member,
    super.key,
  });
  final MobileSession session;
  final String plantId;
  final Json member;

  @override
  State<OperatorAssignmentScreen> createState() =>
      _OperatorAssignmentScreenState();
}

class _OperatorAssignmentScreenState extends State<OperatorAssignmentScreen> {
  late final Future<Json> future = widget.session.api.read('team-member', {
    'plantId': widget.plantId,
    'userId': widget.member['id'],
  });
  Set<String>? original;
  final chosen = <String>{};
  _AssignmentView view = _AssignmentView.all;
  String search = '';
  bool busy = false;
  bool leaving = false;
  String? error;
  String requestId = const Uuid().v4();
  Set<String>? pending;

  bool get dirty =>
      original != null &&
      (original!.length != chosen.length || !original!.containsAll(chosen));

  void _toggle(String id) {
    setState(() {
      chosen.contains(id) ? chosen.remove(id) : chosen.add(id);
      _invalidatePending();
    });
  }

  void _setMany(Iterable<String> ids, bool value) {
    setState(() {
      value ? chosen.addAll(ids) : chosen.removeAll(ids);
      _invalidatePending();
    });
  }

  /// Un reintento con el mismo request_id debe llevar exactamente lo mismo.
  void _invalidatePending() {
    if (pending != null &&
        (pending!.length != chosen.length || !pending!.containsAll(chosen))) {
      pending = null;
      requestId = const Uuid().v4();
    }
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      pending ??= {...chosen};
    });
    try {
      await widget.session.api.rpc('ivmet_customer_assign_equipment', {
        'assignment': {
          'userId': widget.member['id'],
          'plantId': widget.plantId,
          'equipmentIds': pending!.toList()..sort(),
        },
        'request_id': requestId,
      });
      if (!mounted) return;
      setState(() => leaving = true);
      Navigator.of(context).pop(true);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = failure is MobileFailure
            ? failure.message
            : 'No pudimos confirmar el guardado. Reintenta sin cambiar la selección.';
        if (failure is MobileFailure &&
            !failure.offline &&
            (failure.status ?? 500) < 500) {
          pending = null;
          requestId = const Uuid().v4();
        }
      });
    }
  }

  Future<void> _askLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text(
          'Los cambios de balanzas de este operador no se guardarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  bool _matches(Json item) {
    if (view == _AssignmentView.chosen && !chosen.contains(item['id'])) {
      return false;
    }
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      item['cod_interno'],
      item['cod_metrica'],
      item['departamento'],
      item['marca'],
      item['modelo'],
    ].any((value) => '${value ?? ''}'.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!busy && !dirty),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) _askLeave();
    },
    child: OnlinePage(
      title: valueLabel(widget.member['name']),
      child: FutureBuilder<Json>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Notice(
                snapshot.error is MobileFailure
                    ? (snapshot.error as MobileFailure).message
                    : 'No se pudo cargar las balanzas.',
                alert: true,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = objects(snapshot.data!['items']);
          if (original == null) {
            original = {
              for (final item in items)
                if (item['assigned'] == true) item['id'] as String,
            };
            chosen.addAll(original!);
          }
          return _body(context, items);
        },
      ),
    ),
  );

  Widget _body(BuildContext context, List<Json> items) {
    final palette = IndustryPalette.of(context);
    final visible = items.where(_matches).toList();
    final departments = <String, List<Json>>{};
    for (final item in visible) {
      departments
          .putIfAbsent(valueLabel(item['departamento']), () => [])
          .add(item);
    }
    final allVisibleChosen =
        visible.isNotEmpty && visible.every((i) => chosen.contains(i['id']));

    return FloatingActionLayout(
      action: WizardNavPill.action(
        label: busy
            ? 'Guardando…'
            : pending != null
            ? 'Reintentar guardado'
            : 'Guardar · ${chosen.length} ${chosen.length == 1 ? 'balanza' : 'balanzas'}',
        icon: Icons.check_rounded,
        onNext: busy || !(dirty || pending != null) ? null : _save,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          18,
          8,
          18,
          WizardNavPill.contentPadding,
        ),
        children: [
          if (error != null) Notice(error!, alert: true),
          Kicker('Balanzas asignadas'),
          const SizedBox(height: 2),
          Text(
            '${chosen.length} de ${items.length}',
            style: AppTextStyles.figure(context, size: 29),
          ),
          Text(
            'Marca las balanzas que ${valueLabel(widget.member['name'])} verificará en esta planta.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedPills<_AssignmentView>(
            selected: view,
            onSelect: (value) => setState(() => view = value),
            segments: const [
              PillSegment(_AssignmentView.all, 'Todas'),
              PillSegment(_AssignmentView.chosen, 'Marcadas'),
            ],
          ),
          const SizedBox(height: 12),
          LabeledInput(
            label: 'Buscar',
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Código, departamento o marca',
              ),
              onChanged: (value) => setState(() => search = value),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: visible.isEmpty
                  ? null
                  : () => _setMany(
                      visible.map((i) => i['id'] as String),
                      !allVisibleChosen,
                    ),
              child: Text(
                allVisibleChosen
                    ? 'Desmarcar las ${visible.length}'
                    : 'Marcar las ${visible.length}',
              ),
            ),
          ),
          if (visible.isEmpty)
            Text(
              'Ninguna balanza coincide.',
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
          for (final MapEntry(key: department, value: group)
              in departments.entries) ...[
            SectionLabel(
              department,
              padding: const EdgeInsets.only(top: 14, bottom: 8),
            ),
            SurfaceList(
              children: [
                for (final item in group)
                  _EquipmentCheckRow(
                    item: item,
                    checked: chosen.contains(item['id']),
                    onTap: () => _toggle(item['id'] as String),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EquipmentCheckRow extends StatelessWidget {
  const _EquipmentCheckRow({
    required this.item,
    required this.checked,
    required this.onTap,
  });
  final Json item;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final others =
        (item['assigneeCount'] as num? ?? 0).toInt() -
        (item['assigned'] == true ? 1 : 0);
    final brand = valueLabel(item['marca']);
    final model = valueLabel(item['modelo']);
    return Semantics(
      checked: checked,
      child: InkWell(
        key: ValueKey('assign-${item['id']}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerEquipmentCode(item),
                      style: AppTextStyles.reading(
                        context,
                        size: 15,
                        color: palette.accentInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      brand == model ? brand : '$brand $model',
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    Text(
                      others > 0
                          ? 'También la tiene${others == 1 ? '' : 'n'} $others ${others == 1 ? 'operador' : 'operadores'} más'
                          : checked
                          ? 'Solo este operador'
                          : 'Sin operador',
                      style: TextStyle(
                        fontSize: 11,
                        color: others == 0 && !checked
                            ? palette.fail
                            : palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(value: checked, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Operadores de una balanza, desde su ficha.
class EquipmentOperatorsScreen extends StatefulWidget {
  const EquipmentOperatorsScreen({
    required this.session,
    required this.equipmentId,
    required this.equipmentCode,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  final String equipmentCode;

  @override
  State<EquipmentOperatorsScreen> createState() =>
      _EquipmentOperatorsScreenState();
}

class _EquipmentOperatorsScreenState extends State<EquipmentOperatorsScreen> {
  late final Future<Json> future = widget.session.api.read('equipment-team', {
    'equipmentId': widget.equipmentId,
  });
  Set<String>? original;
  final chosen = <String>{};
  bool busy = false;
  String? error;
  String requestId = const Uuid().v4();

  bool get dirty =>
      original != null &&
      (original!.length != chosen.length || !original!.containsAll(chosen));

  Future<void> _save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.api.rpc('ivmet_customer_assign_equipment', {
        'assignment': {
          'equipmentId': widget.equipmentId,
          'userIds': chosen.toList()..sort(),
        },
        'request_id': requestId,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = failure is MobileFailure
            ? failure.message
            : 'No pudimos confirmar el guardado. Reintenta.';
        if (failure is MobileFailure &&
            !failure.offline &&
            (failure.status ?? 500) < 500) {
          requestId = const Uuid().v4();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Operadores',
    child: FutureBuilder<Json>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Notice(
              snapshot.error is MobileFailure
                  ? (snapshot.error as MobileFailure).message
                  : 'No se pudo cargar los operadores.',
              alert: true,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = objects(snapshot.data!['members']);
        if (original == null) {
          original = {
            for (final member in members)
              if (member['assigned'] == true) member['id'] as String,
          };
          chosen.addAll(original!);
        }
        final palette = IndustryPalette.of(context);
        return FloatingActionLayout(
          action: WizardNavPill.action(
            label: busy ? 'Guardando…' : 'Guardar operadores',
            icon: Icons.check_rounded,
            onNext: busy || !dirty ? null : _save,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              18,
              8,
              18,
              WizardNavPill.contentPadding,
            ),
            children: [
              if (error != null) Notice(error!, alert: true),
              Kicker('Balanza'),
              const SizedBox(height: 2),
              Text(
                widget.equipmentCode,
                style: AppTextStyles.figure(context, size: 29),
              ),
              Text(
                'Quién la verifica y la ve en su agenda.',
                style: TextStyle(fontSize: 12.5, color: palette.muted),
              ),
              const SizedBox(height: 14),
              if (members.isEmpty)
                const Notice(
                  'La planta de esta balanza no tiene operadores. Métrica los habilita en RimMET.',
                )
              else
                SurfaceList(
                  children: [
                    for (final member in members)
                      CheckboxListTile(
                        key: ValueKey('operator-${member['id']}'),
                        value: chosen.contains(member['id']),
                        onChanged: (value) => setState(
                          () => value == true
                              ? chosen.add(member['id'] as String)
                              : chosen.remove(member['id']),
                        ),
                        title: Text(valueLabel(member['name'])),
                        subtitle: Text(valueLabel(member['username'])),
                      ),
                  ],
                ),
              if (chosen.isEmpty && members.isNotEmpty)
                const Notice(
                  'Sin operador, nadie la verá en su agenda ni podrá verificarla, salvo el jefe de calidad.',
                  icon: Icons.warning_amber_outlined,
                ),
            ],
          ),
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tile_grid.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'check_schedule.dart';
import 'commercial_plan.dart';
import 'customer_configuration.dart';
import 'draft_screen.dart';
import 'equipment_check_configuration.dart';
import 'equipment_registration.dart';
import 'equipment_validation.dart';
import 'history_screen.dart';
import 'measurement_suggestions.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'plan_screen.dart';
import 'team_screen.dart';

/// Ficha de una balanza: sus datos, su plan de verificacion y la vigencia de
/// cada prueba.
///
/// Es el segundo nivel del catalogo y desde aqui arrancan la captura, el
/// historial y la configuracion del equipo. Vivia dentro de
/// `catalog_screen.dart`, que asi juntaba dos pantallas distintas en el mismo
/// archivo.

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  int revision = 0;
  MobileSession get session => widget.session;
  String get equipmentId => widget.equipmentId;
  Future<void> configure(Widget page) async {
    await openPage(context, page);
    if (mounted) setState(() => revision++);
  }

  /// Tras la baja la balanza ya no es accesible: la ficha se cierra.
  Future<void> retire(Json equipment) async {
    final retired = await openPage<bool>(
      context,
      RetireRegisteredEquipment(session: session, equipment: equipment),
    );
    if (!mounted) return;
    if (retired == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => revision++);
    }
  }

  /// Cada captura nueva ocupa un lugar del mes del plan; Supabase lo vuelve
  /// a comprobar al guardar el primer borrador.
  Future<void> _start(Json data) async {
    if (session.plan.full(PlanResource.monthlyVerifications)) {
      await showPlanLimit(
        context,
        session,
        const PlanLimit(resource: PlanResource.monthlyVerifications),
      );
      return;
    }
    await configure(DraftScreen(session: session, bundle: data));
  }

  static bool _canStart(Json data) =>
      data['customerValidated'] == true &&
      data['plan'] != null &&
      object(data['plan'])['finalizationEnabled'] == true;

  /// Acciones raras de la ficha: en ⋮ y no al pie de la pagina.
  List<Widget> _menu(Json data) {
    final registered = data['registeredByCustomer'] == true;
    final menu = pageMenu([
      if (session.quality && registered && data['registrationShared'] == true)
        wizardMenuItem<VoidCallback>(
          () => configure(
            CustomerSetupScreen(
              session: session,
              initialSection: 'updates',
              equipmentId: equipmentId,
            ),
          ),
          Icons.outbox_outlined,
          'Ver envíos a Métrica',
        ),
      if (session.quality && registered)
        wizardMenuItem<VoidCallback>(
          () => retire(object(data['equipment'])),
          Icons.remove_circle_outline,
          'Dar de baja esta balanza',
        ),
    ]);
    return [?menu];
  }

  @override
  Widget build(BuildContext context) => RemotePage(
    title: 'Ficha de la balanza',
    dataKey: '$revision',
    load: () => session.api.read('equipment', {
      ...clockFilters(),
      'equipmentId': equipmentId,
    }),
    actions: _menu,
    // Lo que se viene a hacer a la ficha: fijo a la vista.
    floating: (data) => WizardNavPill.action(
      key: const ValueKey('start-verification'),
      label: 'Iniciar verificación',
      icon: Icons.play_arrow_rounded,
      onNext: _canStart(data) ? () => _start(data) : null,
    ),
    builder: (data) {
      final palette = IndustryPalette.of(context);
      final equipment = object(data['equipment']);
      final plan = data['plan'] == null ? null : object(data['plan']);
      final ranges = objects(data['ranges']);
      final validated = data['customerValidated'] == true;
      final sharePending = data['customerUpdatePending'] == true;
      final canStart = _canStart(data);
      final registered = data['registeredByCustomer'] == true;
      final registrationShared = data['registrationShared'] == true;
      final schedules = <String, CheckSchedule>{
        for (final due in objects(data['schedule']))
          if (due['rule'] is Map)
            due['type'] as String: CheckSchedule.fromJson(object(due['rule'])),
      };
      final assignees = objects(data['assignees']);

      return ListView(
        padding: const EdgeInsets.fromLTRB(
          18,
          8,
          18,
          WizardNavPill.contentPadding,
        ),
        children: [
          Kicker('Código interno de la empresa'),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  customerEquipmentCode(equipment),
                  style: AppTextStyles.figure(context, size: 32),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: StatusTag(
                  registered
                      ? registeredEquipmentLabel
                      : validated
                      ? 'Ficha validada'
                      : 'Sin validar',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!registered)
                  DetailField('Código Métrica', equipment['cod_metrica']),
                DetailField(
                  'Marca y modelo',
                  '${valueLabel(equipment['marca'])} · ${valueLabel(equipment['modelo'])}',
                ),
                DetailField('Serie', equipment['serie']),
                DetailField('Ubicación', equipment['ubicacion']),
                if (registered) ...[
                  DetailField('Tipo', equipment['tipo_balanza']),
                  DetailField('Clase', equipment['clase']),
                ],
                for (final range in ranges)
                  DetailField(
                    'Rango ${range['numero_rango']}',
                    registered
                        ? registeredRangeLabel({
                            'capacity': range['capacidad_max'],
                            'division': range['division_escala'],
                            'interval': range['intervalo_verificacion'],
                          }, valueLabel(range['unidad']))
                        : '${rangeCapacityLabel(range)} ${range['unidad']}'
                              ' · división ${rangeDivisionLabel(range)} ${range['unidad']}',
                  ),
              ],
            ),
          ),
          const SectionLabel('Verificación'),
          // "Iniciar verificación" es la pildora fija; si no se puede, aqui
          // se dice por que.
          if (!canStart)
            Notice(
              !validated
                  ? 'Para iniciar una verificación, valida antes la ficha de la balanza.'
                  : plan == null
                  ? 'Para iniciar una verificación, la balanza necesita sus pruebas configuradas.'
                  : 'La configuración todavía no habilita el cálculo de resultados.',
              icon: Icons.info_outline,
            ),
          TileGrid(
            cells: [
              // La ficha de una balanza registrada nace validada: no hay
              // catálogo contra el que revisarla, se corrige al editarla.
              if (!registered)
                TileCell(
                  ActionTile(
                    icon: Icons.fact_check_outlined,
                    label: validated ? 'Revisar ficha' : 'Validar ficha',
                    caption: validated
                        ? 'Corrige datos privados del equipo'
                        : 'Confirma los datos antes de capturar',
                    onTap: () => configure(
                      EquipmentValidation(
                        session: session,
                        equipmentId: equipmentId,
                      ),
                    ),
                  ),
                ),
              if (registered && session.quality)
                TileCell(
                  ActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Editar balanza',
                    caption: data['registrationInUse'] == true
                        ? 'Identificación y área'
                        : 'Datos, área y rangos',
                    onTap: () => configure(
                      EquipmentRegistrationScreen.edit(
                        session: session,
                        equipmentId: equipmentId,
                      ),
                    ),
                  ),
                ),
              if (session.quality)
                TileCell(
                  ActionTile(
                    icon: Icons.tune_outlined,
                    label: plan == null
                        ? 'Configurar pruebas'
                        : 'Actualizar pruebas',
                    caption: ranges.isEmpty
                        ? 'Falta capacidad y división'
                        : validated
                        ? 'Puntos, tolerancias y frecuencia'
                        : 'Valida la ficha primero',
                    onTap: validated && ranges.isNotEmpty
                        ? () => configure(
                            EquipmentCheckConfigurationScreen(
                              session: session,
                              bundle: data,
                            ),
                          )
                        : null,
                  ),
                ),
              TileCell(
                ActionTile(
                  icon: Icons.history,
                  label: 'Historial',
                  caption: 'Resultados privados del equipo',
                  onTap: () => openPage(
                    context,
                    HistoryScreen(session: session, equipmentId: equipmentId),
                  ),
                ),
              ),
              TileCell(
                ActionTile(
                  icon: Icons.edit_note,
                  label: 'Borradores',
                  caption: 'Capturas sin finalizar',
                  onTap: () => openPage(
                    context,
                    HistoryScreen(
                      session: session,
                      equipmentId: equipmentId,
                      drafts: true,
                    ),
                  ),
                ),
              ),
              if (session.quality && sharePending && !registered)
                TileCell(
                  ActionTile(
                    icon: Icons.share_outlined,
                    label: 'Compartir con Métrica',
                    caption: 'Enviar la corrección de la ficha',
                    onTap: () => configure(
                      ShareEquipmentUpdate(
                        session: session,
                        equipmentId: equipmentId,
                      ),
                    ),
                  ),
                ),
              if (session.quality &&
                  registered &&
                  data['registrationSharePending'] == true)
                TileCell(
                  ActionTile(
                    icon: Icons.send_outlined,
                    label: 'Enviar a Métrica',
                    caption: registrationShared
                        ? 'Autoriza enviar los datos actualizados'
                        : 'Autoriza compartir los datos de esta balanza',
                    onTap: () => configure(
                      ShareEquipmentRegistration(
                        session: session,
                        equipmentId: equipmentId,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (session.quality) ...[
            const SectionLabel('Operadores'),
            SurfaceList(
              children: [
                InkWell(
                  key: const ValueKey('equipment-operators'),
                  onTap: () => configure(
                    EquipmentOperatorsScreen(
                      session: session,
                      equipmentId: equipmentId,
                      equipmentCode: customerEquipmentCode(equipment),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 20,
                          color: assignees.isEmpty
                              ? palette.fail
                              : palette.accentInk,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            assignees.isEmpty
                                ? 'Sin operador: nadie la ve en su agenda'
                                : assignees
                                      .map((a) => valueLabel(a['name']))
                                      .join(', '),
                            style: TextStyle(
                              fontSize: 13.5,
                              color: assignees.isEmpty
                                  ? palette.fail
                                  : palette.text,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: palette.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (registered) ...[
            Notice(
              registrationShared
                  ? 'Balanza registrada por tu empresa. Métrica recibió sus datos con tu autorización.'
                  : 'Balanza registrada por tu empresa. Es privada: Métrica no la ve salvo que el jefe de calidad autorice enviarla.',
              icon: Icons.shield_outlined,
            ),
          ],
          if (session.quality && ranges.isEmpty)
            const Notice(
              'Faltan la capacidad y la división de escala. Solicita a Métrica revisar el catálogo antes de configurar las verificaciones.',
              icon: Icons.warning_amber_outlined,
              alert: true,
            ),
          if (plan == null)
            Notice(
              !session.quality
                  ? 'El jefe de calidad todavía no configuró las verificaciones de esta balanza.'
                  : registered
                  ? 'Configura las verificaciones de esta balanza.'
                  : 'Valida primero la ficha y configura las verificaciones de esta balanza.',
            )
          else ...[
            const SectionLabel('Verificaciones activas'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final test in objects(plan['tests']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            testLabel(test['type']),
                            style: AppTextStyles.figure(context, size: 17),
                          ),
                          Text(
                            () {
                              final schedule =
                                  schedules[test['type']] ??
                                  CheckSchedule.legacyDays(
                                    (test['frequencyDays'] as num?)?.toInt() ??
                                        30,
                                  );
                              return '${schedule.summary} · '
                                  '${schedule.warningLabel.toLowerCase()}';
                            }(),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (objects(data['schedule']).isNotEmpty) ...[
              const SectionLabel('Vigencia por prueba'),
              SurfaceList(
                children: [
                  for (final due in objects(data['schedule']))
                    _ScheduleRow(due: due),
                ],
              ),
            ],
            const Notice(
              'Control interno privado. IvMET recalcula el resultado en Supabase al finalizar. Cualquier verificación finalizada cumple la fecha de cada prueba; la trazabilidad se indica en el resultado.',
            ),
          ],
        ],
      );
    },
  );
}

/// "07/10/2026" de una fecha de la API: dia de calendario, sin zona horaria.
String _dueLabel(Object? value) {
  final text = value?.toString() ?? '';
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
      ? numericDayLabel(parseDayKey(text))
      : dateLabel(value);
}

/// Fila de vigencia: la prueba, cuando vence y con que urgencia.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.due});
  final Json due;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final overdue = due['state'] == 'OVERDUE';
    final soon = due['state'] == 'DUE_SOON';
    final color = overdue
        ? palette.fail
        : soon
        ? palette.accentInk
        : palette.muted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Icon(
            overdue
                ? Icons.error_outline
                : soon
                ? Icons.schedule
                : Icons.check_circle_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  testLabel(due['type']),
                  style: AppTextStyles.figure(context, size: 16),
                ),
                Text(
                  '${due['state'] == 'OVERDUE' ? 'Tocaba' : 'Próxima'}: ${_dueLabel(due['dueAt'])}'
                  '${(due['lastRunAt'] ?? due['lastTraceableAt']) == null ? ' · sin verificación previa' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

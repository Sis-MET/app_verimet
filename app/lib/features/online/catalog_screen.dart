import 'package:flutter/material.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/blueprint_card.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/tile_grid.dart';
import 'draft_screen.dart';
import 'history_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'customer_configuration.dart';
import 'equipment_check_configuration.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    required this.session,
    this.plantId,
    this.areaId,
    super.key,
  });
  final MobileSession session;
  final String? plantId;
  final String? areaId;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  _CatalogView view = _CatalogView.byPlant;
  String search = '';
  int page = 1;
  int revision = 0;

  Json? get plant => objects(
    widget.session.bootstrap['plants'],
  ).where((item) => item['id'] == widget.plantId).firstOrNull;

  void _selectView(_CatalogView next) {
    if (view == next) return;
    setState(() {
      view = next;
      search = '';
      page = 1;
    });
  }

  void _openEquipment(BuildContext context, Json equipment) => openPage(
    context,
    EquipmentScreen(
      session: widget.session,
      equipmentId: equipment['id'] as String,
    ),
  );

  Widget _equipmentResults({required bool completeList}) => RemotePanel(
    dataKey: '${widget.plantId}|${widget.areaId}|$search|$page|$revision',
    load: () => widget.session.api.read('instruments', {
      'plantId': widget.plantId,
      'areaId': widget.areaId,
      'search': search,
      'page': page,
    }),
    builder: (data) {
      final items = objects(data['items']);
      final total = (data['total'] as num).toInt();

      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 140),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$total ${total == 1 ? 'balanza autorizada' : 'balanzas autorizadas'}',
                  style: AppTextStyles.caption(context, size: 12),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => setState(() => revision++),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (items.isEmpty)
            const Notice('No hay balanzas habilitadas para este filtro.')
          else if (completeList)
            for (final equipment in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EquipmentListRow(
                  equipment: equipment,
                  onTap: () => _openEquipment(context, equipment),
                ),
              )
          else
            TileGrid(
              minTileHeight: 148,
              cells: [
                for (final equipment in items)
                  TileCell(
                    _EquipmentTile(
                      equipment: equipment,
                      onTap: () => _openEquipment(context, equipment),
                    ),
                  ),
              ],
            ),
          if (total > 25)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                    child: const Text('Anterior'),
                  ),
                  Text(
                    'Página $page',
                    style: AppTextStyles.caption(context, size: 12),
                  ),
                  TextButton(
                    onPressed: page * 25 < total
                        ? () => setState(() => page++)
                        : null,
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _searchField({required String label}) => TextField(
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.search),
      helperText: 'Pulsa buscar en el teclado para consultar.',
    ),
    textInputAction: TextInputAction.search,
    onSubmitted: (value) => setState(() {
      search = value.trim();
      page = 1;
    }),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.plantId != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Kicker(valueLabel(plant?['name'])),
                const SizedBox(height: 2),
                Text(
                  'Balanzas',
                  style: AppTextStyles.figure(context, size: 29),
                ),
                const SizedBox(height: 12),
                _searchField(label: 'Código interno o marca'),
              ],
            ),
          ),
          Expanded(child: _equipmentResults(completeList: false)),
        ],
      );
    }

    final client = object(widget.session.bootstrap['client']);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(valueLabel(client['name'])),
              const SizedBox(height: 2),
              Text('Verificar', style: AppTextStyles.figure(context, size: 29)),
              const SizedBox(height: 12),
              TileGrid(
                minTileHeight: 112,
                cells: [
                  TileCell(
                    ActionTile(
                      icon: Icons.factory_outlined,
                      label: 'Por planta',
                      caption: 'Explorar las balanzas de cada planta',
                      primary: view == _CatalogView.byPlant,
                      onTap: () => _selectView(_CatalogView.byPlant),
                    ),
                  ),
                  TileCell(
                    ActionTile(
                      icon: Icons.format_list_numbered,
                      label: 'Lista completa',
                      caption: 'Buscar por código o departamento',
                      primary: view == _CatalogView.completeList,
                      onTap: () => _selectView(_CatalogView.completeList),
                    ),
                  ),
                ],
              ),
              if (view == _CatalogView.completeList) ...[
                const SizedBox(height: 14),
                _searchField(label: 'Código interno, departamento o marca'),
              ],
            ],
          ),
        ),
        Expanded(
          child: view == _CatalogView.byPlant
              ? _PlantPicker(session: widget.session)
              : _equipmentResults(completeList: true),
        ),
      ],
    );
  }
}

enum _CatalogView { byPlant, completeList }

/// Primer nivel de Verificar: las plantas se leen como los módulos de Inicio.
class _PlantPicker extends StatelessWidget {
  const _PlantPicker({required this.session});
  final MobileSession session;

  @override
  Widget build(BuildContext context) {
    final plants = objects(session.bootstrap['plants']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 140),
      children: [
        Text(
          'Selecciona una planta',
          style: AppTextStyles.figure(context, size: 23),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 18),
          child: Text(
            'Después verás únicamente las balanzas disponibles en esa planta.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: IndustryPalette.of(context).muted,
            ),
          ),
        ),
        if (plants.isEmpty)
          const Notice(
            'No tienes plantas asignadas. Solicita su habilitación en RimMET.',
          )
        else
          TileGrid(
            minTileHeight: 132,
            cells: [
              for (final plant in plants)
                TileCell(
                  ActionTile(
                    icon: Icons.factory_outlined,
                    label: valueLabel(plant['name']),
                    caption:
                        '${plant['equipmentCount'] ?? '—'} balanzas · ${valueLabel(plant['code'])}',
                    onTap: () => openPage(
                      context,
                      OnlinePage(
                        title: valueLabel(plant['name']),
                        child: CatalogScreen(
                          session: session,
                          plantId: plant['id'] as String,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Módulo de balanza: manda el código del cliente; el de Métrica es trazabilidad.
class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({required this.equipment, required this.onTap});
  final Json equipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final marca = valueLabel(equipment['marca']);
    final modelo = valueLabel(equipment['modelo']);

    return BlueprintCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            customerEquipmentCode(equipment),
            style: AppTextStyles.reading(
              context,
              size: 16,
              color: palette.accentInk,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                marca == modelo ? marca : '$marca $modelo',
                style: AppTextStyles.figure(context, size: 18),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                '${equipment['planta']} · ${equipment['area']}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: palette.muted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Métrica · ${valueLabel(equipment['cod_metrica'])}',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  color: palette.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila compacta de la vista general: código del cliente y departamento mandan.
class _EquipmentListRow extends StatelessWidget {
  const _EquipmentListRow({required this.equipment, required this.onTap});
  final Json equipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final department = valueLabel(
      equipment['departamento'] ?? equipment['area'],
    );
    final brand = valueLabel(equipment['marca']);
    final model = valueLabel(equipment['modelo']);

    return BlueprintCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerEquipmentCode(equipment),
                  style: AppTextStyles.reading(
                    context,
                    size: 16,
                    color: palette.accentInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  'Departamento · $department',
                  style: AppTextStyles.figure(context, size: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${valueLabel(equipment['planta'])} · ${brand == model ? brand : '$brand $model'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: palette.muted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Métrica · ${valueLabel(equipment['cod_metrica'])}',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: palette.muted),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Ficha de la balanza',
    child: RemotePanel(
      dataKey: '$revision',
      load: () => session.api.read('equipment', {'equipmentId': equipmentId}),
      builder: (data) {
        final palette = IndustryPalette.of(context);
        final equipment = object(data['equipment']);
        final plan = data['plan'] == null ? null : object(data['plan']);
        final ranges = objects(data['ranges']);
        final validated = data['customerValidated'] == true;
        final sharePending = data['customerUpdatePending'] == true;
        final canStart = validated && plan?['finalizationEnabled'] == true;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
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
                    validated ? 'Ficha validada' : 'Sin validar',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            BlueprintCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DetailField('Código Métrica', equipment['cod_metrica']),
                  DetailField(
                    'Marca y modelo',
                    '${valueLabel(equipment['marca'])} · ${valueLabel(equipment['modelo'])}',
                  ),
                  DetailField('Serie', equipment['serie']),
                  DetailField('Ubicación', equipment['ubicacion']),
                  for (final range in ranges)
                    DetailField(
                      'Rango ${range['numero_rango']}',
                      '${range['capacidad_max']} ${range['unidad']} · división ${range['division_escala']}',
                    ),
                ],
              ),
            ),
            const SectionLabel('Comprobación'),
            TileGrid(
              cells: [
                TileCell.wide(
                  ActionTile(
                    icon: Icons.play_arrow,
                    label: 'Iniciar comprobación',
                    caption: canStart
                        ? 'Capturar lecturas con la configuración activa'
                        : validated
                        ? 'La configuración todavía no habilita el cálculo'
                        : 'Valida antes la ficha de la balanza',
                    primary: canStart,
                    onTap: canStart
                        ? () => openPage(
                            context,
                            DraftScreen(session: session, bundle: data),
                          )
                        : null,
                  ),
                ),
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
                if (session.quality && sharePending)
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
              ],
            ),
            if (session.quality && ranges.isEmpty)
              const Notice(
                'Faltan la capacidad y la división de escala. Solicita a Métrica revisar el catálogo antes de configurar las comprobaciones.',
                icon: Icons.warning_amber_outlined,
                alert: true,
              ),
            if (plan == null)
              Notice(
                session.quality
                    ? 'Valida primero la ficha y configura las comprobaciones de esta balanza.'
                    : 'El jefe de calidad todavía no configuró las comprobaciones de esta balanza.',
              )
            else ...[
              const SectionLabel('Comprobaciones activas'),
              BlueprintCard(
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
                              'Cada ${test['frequencyDays']} días · ${objects(test['points']).length} puntos · ${test['unit']}',
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
                for (final due in objects(data['schedule']))
                  _ScheduleRow(due: due),
              ],
              const Notice(
                'Control interno privado. IvMET recalcula el resultado en Supabase al finalizar y deriva el próximo vencimiento de cada prueba trazable.',
              ),
            ],
          ],
        );
      },
    ),
  );
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
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
                  'Próxima: ${dateLabel(due['dueAt'])}'
                  '${due['lastTraceableAt'] == null ? ' · sin ejecución trazable previa' : ''}',
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

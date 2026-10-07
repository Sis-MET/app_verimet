import 'package:flutter/material.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/segmented_pills.dart';
import '../../shared/widgets/tile_grid.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'equipment_registration.dart';
import 'equipment_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({required this.session, this.plantId, super.key});
  final MobileSession session;
  final String? plantId;
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

  /// Alta de una balanza de esta planta; al terminar se abre su ficha para
  /// configurar las verificaciones.
  Future<void> _register(BuildContext context) async {
    final receipt = await openPage<Json>(
      context,
      EquipmentRegistrationScreen.create(
        session: widget.session,
        plantId: widget.plantId!,
      ),
    );
    if (!mounted) return;
    setState(() => revision++);
    final id = receipt?['id'];
    if (id is! String || !context.mounted) return;
    await openPage(
      context,
      EquipmentScreen(session: widget.session, equipmentId: id),
    );
    if (mounted) setState(() => revision++);
  }

  Widget _equipmentResults({required bool completeList}) => RemotePanel(
    dataKey: '${widget.plantId}|$search|$page|$revision',
    load: () => widget.session.api.read('instruments', {
      'plantId': widget.plantId,
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
            Notice(
              widget.session.quality && widget.plantId != null
                  ? 'No hay balanzas habilitadas para este filtro. Si tu empresa incorporó una balanza nueva, regístrala.'
                  : 'No hay balanzas habilitadas para este filtro.',
            )
          else
            SurfaceList(
              children: [
                for (final equipment in items)
                  _EquipmentRow(
                    equipment: equipment,
                    showPlant: completeList,
                    onTap: () => _openEquipment(context, equipment),
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

  Widget _searchField({required String label}) => LabeledInput(
    label: label,
    child: TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        helperText: 'Pulsa buscar en el teclado para consultar.',
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (value) => setState(() {
        search = value.trim();
        page = 1;
      }),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.plantId != null) {
      final page = Column(
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
      // Registrar es la accion de la planta: fija a la vista, no en la
      // cabecera.
      return widget.session.quality
          ? FloatingActionLayout(
              action: WizardNavPill.action(
                label: 'Registrar balanza',
                icon: Icons.add,
                onNext: () => _register(context),
              ),
              child: page,
            )
          : page;
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
              SegmentedPills<_CatalogView>(
                selected: view,
                onSelect: _selectView,
                segments: const [
                  PillSegment(_CatalogView.byPlant, 'Por planta'),
                  PillSegment(_CatalogView.completeList, 'Lista completa'),
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

/// Fila de balanza dentro de la lista agrupada: mandan el código del cliente y
/// el departamento; el código de Métrica es trazabilidad.
///
/// Es la misma fila en la lista completa y dentro de una planta. Antes, dentro
/// de la planta, cada balanza era un módulo del mosaico y la pantalla se leía
/// como una rejilla de cajas. Ahí la planta ya está en la cabecera, así que la
/// fila no la repite ([showPlant]).
class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({
    required this.equipment,
    required this.showPlant,
    required this.onTap,
  });
  final Json equipment;
  final bool showPlant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final department = valueLabel(
      equipment['departamento'] ?? equipment['area'],
    );
    final brand = valueLabel(equipment['marca']);
    final model = valueLabel(equipment['modelo']);
    final instrument = brand == model ? brand : '$brand $model';

    return InkWell(
      onTap: onTap,
      splashColor: palette.accent.withValues(alpha: 0.10),
      highlightColor: palette.accent.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
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
                    showPlant
                        ? '${valueLabel(equipment['planta'])} · $instrument'
                        : instrument,
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
                    registeredByCustomer(equipment)
                        ? registeredEquipmentLabel
                        : 'Métrica · ${valueLabel(equipment['cod_metrica'])}',
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/tile_grid.dart';
import 'customer_form.dart';
import 'equipment_validation.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

class CustomerSetupScreen extends StatefulWidget {
  const CustomerSetupScreen({
    required this.session,
    this.initialSection = 'plants',
    this.plantId,
    this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String initialSection;
  final String? plantId;
  final String? equipmentId;
  @override
  State<CustomerSetupScreen> createState() => _CustomerSetupScreenState();
}

class _CustomerSetupScreenState extends State<CustomerSetupScreen> {
  late String section =
      const {
        'plants',
        'areas',
        'patterns',
        'updates',
      }.contains(widget.initialSection)
      ? widget.initialSection
      : 'plants';
  late String? plantId =
      widget.plantId ??
      objects(widget.session.bootstrap['plants']).firstOrNull?['id'] as String?;
  int page = 1, revision = 0;
  Map<String, String> get plants => {
    for (final p in objects(widget.session.bootstrap['plants']))
      p['id'] as String: valueLabel(p['name']),
  };
  Future<void> edit(Widget form) async {
    await openPage<bool>(context, form);
    if (mounted) setState(() => revision++);
  }

  void areaForm([Json? area]) => edit(
    CustomerForm(
      session: widget.session,
      title: area == null ? 'Nueva área' : 'Editar área',
      action: 'area.save',
      notice:
          'Esta área pertenece solo a la planta seleccionada. Guardarla no la envía a Métrica.',
      initial: {
        'plantId': plantId,
        'name': area?['name'] ?? '',
        'active': area?['active'] ?? true,
        if (area?['id'] != null) 'id': area!['id'],
        if (area?['version'] != null) 'version': area!['version'],
      },
      fields: const [
        CustomerField('name', 'Nombre del área'),
        CustomerField('active', 'Área activa', kind: 'bool', required: false),
      ],
    ),
  );
  void patternForm([Json? p]) => edit(
    CustomerForm(
      session: widget.session,
      title: p == null ? 'Nuevo patrón' : 'Editar patrón',
      action: 'pattern.save',
      notice:
          'Registra tus patrones y sus plantas autorizadas. Los certificados se agregan después y conservan su historial.',
      initial: {
        'code': p?['codigo'] ?? '',
        'description': p?['descripcion'] ?? '',
        'type': p?['tipo'] ?? 'pesas',
        'class': p?['clase'] ?? '',
        'unit': p?['unidad'] ?? '',
        'capacity': p?['capacidad'] ?? '',
        'active': p?['activo'] ?? true,
        'plantIds': p?['plantIds'] ?? [if (plantId != null) plantId],
        if (p != null) 'id': p['id'],
        if (p != null) 'version': p['row_version'],
      },
      fields: [
        const CustomerField('code', 'Código del patrón', max: 100),
        const CustomerField('description', 'Descripción', max: 300),
        const CustomerField('type', 'Tipo', max: 50),
        const CustomerField('class', 'Clase', required: false, max: 50),
        const CustomerField('unit', 'Unidad', required: false, max: 20),
        const CustomerField(
          'capacity',
          'Capacidad',
          kind: 'decimal',
          required: false,
        ),
        CustomerField(
          'plantIds',
          'Plantas donde se utilizará',
          kind: 'multi',
          options: plants,
        ),
        const CustomerField(
          'active',
          'Patrón activo',
          kind: 'bool',
          required: false,
        ),
      ],
    ),
  );
  void certificateForm(Json pattern) => edit(
    CustomerForm(
      session: widget.session,
      title: 'Nuevo certificado',
      action: 'certificate.create',
      initial: {'patternId': pattern['id']},
      notice:
          'Cada certificado es un registro histórico. Para corregir uno, anúlalo con motivo y registra el correcto.',
      fields: const [
        CustomerField('number', 'Número de certificado'),
        CustomerField('lab', 'Laboratorio', max: 250),
        CustomerField('calibratedOn', 'Fecha de calibración', kind: 'date'),
        CustomerField('expiresOn', 'Fecha de vencimiento', kind: 'date'),
      ],
    ),
  );

  Widget _plantManagement(BuildContext context) {
    final bootstrap = widget.session.bootstrap;
    final availablePlants = objects(bootstrap['plants']);
    final availableAreas = objects(bootstrap['areas']);
    final client = object(bootstrap['client']);

    return OnlinePage(
      title: 'Gestionar plantas',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          Kicker(valueLabel(client['name'])),
          const SizedBox(height: 2),
          Text(
            'Plantas y sus áreas',
            style: AppTextStyles.figure(context, size: 29),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 18),
            child: Text(
              'Selecciona una planta para crear, revisar o editar únicamente sus áreas.',
              style: AppTextStyles.caption(context, size: 12.5),
            ),
          ),
          if (availablePlants.isEmpty)
            const Notice(
              'No tienes plantas asignadas. Solicita su habilitación en RimMET.',
            )
          else
            TileGrid(
              minTileHeight: 132,
              cells: [
                for (final plant in availablePlants)
                  TileCell(
                    ActionTile(
                      icon: Icons.factory_outlined,
                      label: valueLabel(plant['name']),
                      caption:
                          '${availableAreas.where((area) => area['plantId'] == plant['id']).length} áreas · Gestionar áreas',
                      onTap: () => edit(
                        CustomerSetupScreen(
                          session: widget.session,
                          initialSection: 'areas',
                          plantId: plant['id'] as String,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (section == 'plants') return _plantManagement(context);

    final title = section == 'areas'
        ? 'Áreas · ${plants[plantId] ?? 'Planta'}'
        : section == 'patterns'
        ? 'Gestionar patrones'
        : 'Actualizaciones compartidas';

    return OnlinePage(
      title: title,
      child: Column(
        children: [
          if (section == 'patterns')
            Padding(
              padding: const EdgeInsets.all(16),
              child: LabeledInput(
                label: 'Filtrar patrones por planta',
                child: DropdownButtonFormField<String>(
                  initialValue: plantId,
                  isExpanded: true,
                  items: plants.entries
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.key,
                          child: Text(p.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    plantId = v;
                    page = 1;
                  }),
                ),
              ),
            ),
          if (plantId == null && (section == 'areas' || section == 'patterns'))
            const Notice('No tienes plantas autorizadas.')
          else
            Expanded(
              child: RemotePanel(
                dataKey: '$section|$plantId|$page|$revision',
                load: () => customerRead(widget.session, section, {
                  'plantId': plantId,
                  'page': page,
                  if (section == 'updates') 'id': widget.equipmentId,
                }),
                builder: (data) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    if (section == 'areas') ...[
                      FilledButton.icon(
                        onPressed: areaForm,
                        icon: const Icon(Icons.add),
                        label: const Text('Nueva área'),
                      ),
                      OutlinedButton(
                        onPressed: () => edit(
                          AreaSuggestions(
                            session: widget.session,
                            plantId: plantId!,
                          ),
                        ),
                        child: const Text('Sugerir áreas desde Ubicación'),
                      ),
                      const Notice(
                        'Las coincidencias ignoran mayúsculas, acentos y espacios repetidos. Cada planta mantiene sus propias áreas.',
                      ),
                    ],
                    if (section == 'patterns')
                      FilledButton.icon(
                        onPressed: patternForm,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo patrón'),
                      ),
                    if (section == 'updates')
                      const Notice(
                        'Solo se comparte lo que autorizaste explícitamente. Los cambios posteriores requieren una autorización nueva.',
                      ),
                    if (objects(data['items']).isEmpty)
                      const Notice('Todavía no hay registros en esta sección.'),
                    for (final item in objects(data['items']))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: section == 'areas'
                              ? ListTile(
                                  title: Text(valueLabel(item['name'])),
                                  subtitle: Text(
                                    item['active'] == true
                                        ? 'Activa'
                                        : 'Inactiva',
                                  ),
                                  trailing: const Icon(Icons.edit_outlined),
                                  onTap: () => areaForm(item),
                                )
                              : section == 'patterns'
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['codigo']} · ${item['descripcion']}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      '${valueLabel(item['tipo'])} · ${valueLabel(item['capacidad'])} ${item['unidad'] ?? ''}',
                                    ),
                                    if (item['canEdit'] == true)
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: () => patternForm(item),
                                            child: const Text('Editar patrón'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                certificateForm(item),
                                            child: const Text(
                                              'Agregar certificado',
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      const Notice(
                                        'Para editar este patrón necesitas acceso a todas sus plantas.',
                                      ),
                                    for (final cert in objects(
                                      item['certificates'],
                                    ))
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '${cert['numero']} · ${cert['laboratorio']}',
                                        ),
                                        subtitle: Text(
                                          'Calibrado: ${dateLabel(cert['calibrado_el'])}\nVence: ${dateLabel(cert['vence_el'])} · ${cert['estado'] == 'ANNULLED' ? 'Anulado' : 'Registrado'}',
                                        ),
                                        trailing:
                                            cert['estado'] == 'ACTIVE' &&
                                                item['canEdit'] == true
                                            ? IconButton(
                                                tooltip: 'Anular certificado',
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                ),
                                                onPressed: () => edit(
                                                  CustomerForm(
                                                    session: widget.session,
                                                    title: 'Anular certificado',
                                                    action: 'certificate.annul',
                                                    initial: {
                                                      'id': cert['id'],
                                                      'version':
                                                          cert['row_version'],
                                                    },
                                                    fields: const [
                                                      CustomerField(
                                                        'reason',
                                                        'Motivo',
                                                        max: 2000,
                                                      ),
                                                    ],
                                                    submitLabel:
                                                        'Anular conservando historial',
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      valueLabel(
                                        object(item['snapshot'])['code'],
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    DetailField(
                                      'Enviado',
                                      dateLabel(item['autorizado_at']),
                                    ),
                                    DetailField(
                                      'Estado',
                                      item['visibilidad'] == 'WITHDRAWN'
                                          ? 'Acceso retirado'
                                          : item['estado'] == 'REVIEWED'
                                          ? 'Revisado por Métrica'
                                          : 'Pendiente de revisión',
                                    ),
                                    DetailField(
                                      'Comentario de Métrica',
                                      item['comentario'],
                                    ),
                                    EvidenceSection(
                                      title: 'Información autorizada',
                                      children: [
                                        EquipmentUpdatePreview(
                                          snapshot: object(item['snapshot']),
                                        ),
                                      ],
                                    ),
                                    if (widget.session.quality &&
                                        item['visibilidad'] == 'SHARED')
                                      TextButton(
                                        onPressed: () => edit(
                                          CustomerForm(
                                            session: widget.session,
                                            title: 'Retirar acceso a Métrica',
                                            action: 'update.withdraw',
                                            initial: {
                                              'id': item['id'],
                                              'version': item['row_version'],
                                            },
                                            notice:
                                                'No elimina las copias que Métrica ya haya recibido.',
                                            fields: const [
                                              CustomerField(
                                                'reason',
                                                'Motivo',
                                                max: 2000,
                                              ),
                                            ],
                                            submitLabel: 'Retirar acceso',
                                          ),
                                        ),
                                        child: const Text('Retirar acceso'),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: page > 1
                              ? () => setState(() => page--)
                              : null,
                          child: const Text('Anterior'),
                        ),
                        Text('Página $page'),
                        TextButton(
                          onPressed: page * 25 < (data['total'] as num)
                              ? () => setState(() => page++)
                              : null,
                          child: const Text('Siguiente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AreaSuggestions extends StatefulWidget {
  const AreaSuggestions({
    required this.session,
    required this.plantId,
    super.key,
  });
  final MobileSession session;
  final String plantId;
  @override
  State<AreaSuggestions> createState() => _AreaSuggestionsState();
}

class _AreaSuggestionsState extends State<AreaSuggestions> {
  int page = 1, revision = 0;
  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Áreas sugeridas',
    child: RemotePanel(
      dataKey: '$page|$revision',
      load: () => customerRead(widget.session, 'area-suggestions', {
        'plantId': widget.plantId,
        'page': page,
      }),
      builder: (data) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Notice(
            'Revisa los nombres encontrados en Ubicación. Crear un área no reasigna balanzas: el área se confirma al validar cada ficha.',
          ),
          if (objects(data['items']).isEmpty)
            const Notice('No quedan ubicaciones nuevas para sugerir.'),
          for (final item in objects(data['items']))
            Card(
              child: ListTile(
                title: Text(item['name'] as String),
                subtitle: Text(
                  '${item['equipment_count']} balanzas con esta ubicación',
                ),
                trailing: const Icon(Icons.add),
                onTap: () async {
                  final changed = await openPage<bool>(
                    context,
                    CustomerForm(
                      session: widget.session,
                      title: 'Confirmar área',
                      action: 'area.save',
                      initial: {
                        'plantId': widget.plantId,
                        'name': item['name'],
                        'active': true,
                      },
                      fields: const [CustomerField('name', 'Nombre del área')],
                    ),
                  );
                  if (mounted && changed == true) {
                    setState(() {
                      page = 1;
                      revision++;
                    });
                  }
                },
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: page > 1 ? () => setState(() => page--) : null,
                child: const Text('Anterior'),
              ),
              TextButton(
                onPressed: page * 25 < (data['total'] as num)
                    ? () => setState(() => page++)
                    : null,
                child: const Text('Siguiente'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../../core/domain/compliance_status.dart';
import '../../core/utils/calendar_dates.dart';
import '../../core/utils/measurement_format.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'company_plants.dart';
import 'customer_form.dart';
import 'equipment_validation.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

Map<String, String> _plantNames(MobileSession session) => {
  for (final p in objects(session.bootstrap['plants']))
    p['id'] as String: valueLabel(p['name']),
};

/// Áreas de una planta y actualizaciones de ficha compartidas con Métrica.
///
/// Antes también listaba las plantas y los patrones. Las plantas ya estaban en
/// la pestaña Plantas, así que "Gestionar plantas" repetía la misma lista:
/// ahora la pestaña entra directo a las áreas de cada planta y los patrones
/// tienen su propia pastilla ([PatternsPanel]).
class CustomerSetupScreen extends StatefulWidget {
  const CustomerSetupScreen({
    required this.session,
    this.initialSection = 'areas',
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
  late final String section = widget.initialSection == 'updates'
      ? 'updates'
      : 'areas';
  late final String? plantId =
      widget.plantId ??
      objects(widget.session.bootstrap['plants']).firstOrNull?['id'] as String?;
  int page = 1, revision = 0;
  Future<void> edit(Widget form) async {
    await openPage<bool>(context, form);
    if (mounted) setState(() => revision++);
  }

  /// Si se desactivó, la planta ya no está en la lista: se vuelve atrás.
  Future<void> _editPlant() async {
    final saved = await editPlant(context, widget.session, plantId!);
    if (!saved || !mounted) return;
    await widget.session.refresh();
    if (!mounted) return;
    final stillActive = objects(
      widget.session.bootstrap['plants'],
    ).any((plant) => plant['id'] == plantId);
    stillActive ? setState(() => revision++) : Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final title = section == 'areas'
        ? 'Áreas · ${_plantNames(widget.session)[plantId] ?? 'Planta'}'
        : 'Actualizaciones compartidas';

    final areas = section == 'areas' && plantId != null;
    return OnlinePage(
      title: title,
      // Crear es la accion de la pagina; sugerir desde Ubicacion, una extra.
      floating: areas
          ? WizardNavPill.action(
              label: 'Nueva área',
              icon: Icons.add,
              onNext: areaForm,
            )
          : null,
      actions: [
        if (areas)
          ?pageMenu([
            wizardMenuItem<VoidCallback>(
              () => edit(
                AreaSuggestions(session: widget.session, plantId: plantId!),
              ),
              Icons.auto_fix_high_outlined,
              'Sugerir áreas desde Ubicación',
            ),
            if (managesPlants(widget.session))
              wizardMenuItem<VoidCallback>(
                _editPlant,
                Icons.edit_outlined,
                'Editar planta',
              ),
          ]),
      ],
      child: section == 'areas' && plantId == null
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Notice('No tienes plantas autorizadas.'),
            )
          : RemotePanel(
              dataKey: '$section|$plantId|$page|$revision',
              load: () => customerRead(widget.session, section, {
                'plantId': plantId,
                'page': page,
                if (section == 'updates') 'id': widget.equipmentId,
              }),
              builder: (data) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  WizardNavPill.contentPadding,
                ),
                children: [
                  if (section == 'areas') ...[
                    const Notice(
                      'Las coincidencias ignoran mayúsculas, acentos y espacios repetidos. Cada planta mantiene sus propias áreas.',
                    ),
                  ],
                  if (section == 'updates')
                    const Notice(
                      'Solo se comparte lo que autorizaste explícitamente. Los cambios posteriores requieren una autorización nueva.',
                    ),
                  if (objects(data['items']).isEmpty)
                    const Notice('Todavía no hay registros en esta sección.'),
                  for (final item in objects(data['items']))
                    Card(
                      // El tema deja las tarjetas sin margen: seguidas, se
                      // pegaban unas a otras.
                      margin: const EdgeInsets.only(bottom: 12),
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
                  _PageControls(
                    page: page,
                    total: (data['total'] as num).toInt(),
                    onChanged: (value) => setState(() => page = value),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Pesas patrón del cliente: filtro por planta, alta y edición.
///
/// Va dentro de la pestaña Plantas, en su propia pastilla. Era una pantalla
/// aparte a la que se entraba desde un módulo de esa misma pestaña, que además
/// enseñaba plantas y áreas: todo quedaba mezclado.
///
/// Cada patrón lleva sus certificados de calibración: se agregan, se ven con
/// su estado (vigente, vencido o anulado) y se anulan conservando historial.
/// Es el único camino para que una verificación sea trazable: RimMET no crea
/// certificados, porque los patrones los administra la empresa.
class PatternsPanel extends StatefulWidget {
  const PatternsPanel({required this.session, super.key});
  final MobileSession session;
  @override
  State<PatternsPanel> createState() => _PatternsPanelState();
}

class _PatternsPanelState extends State<PatternsPanel> {
  late String? plantId =
      objects(widget.session.bootstrap['plants']).firstOrNull?['id'] as String?;
  int page = 1, revision = 0;
  late final Map<String, String> plants = _plantNames(widget.session);

  Future<void> edit(Widget form) async {
    await openPage<bool>(context, form);
    if (mounted) setState(() => revision++);
  }

  void patternForm([Json? p]) => edit(
    CustomerForm(
      session: widget.session,
      title: p == null ? 'Nuevo patrón' : 'Editar patrón',
      action: 'pattern.save',
      notice: 'Registra tus patrones y las plantas donde se utilizan.',
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

  /// Un certificado nuevo para [pattern]. Las fechas se eligen en el
  /// calendario; el número no puede repetir otro del patrón, ni anulado.
  void certificateForm(Json pattern) {
    final taken = {
      for (final cert in objects(pattern['certificates']))
        _certificateKey(cert['numero']),
    };
    edit(
      CustomerForm(
        session: widget.session,
        title: 'Nuevo certificado',
        action: 'certificate.create',
        submitLabel: 'Guardar certificado',
        notice:
            'Certificado de calibración de ${valueLabel(pattern['codigo'])}. Mientras esté vigente, las verificaciones que usan esta pesa son trazables.',
        initial: {
          'patternId': pattern['id'],
          'number': '',
          'lab': '',
          'calibratedOn': '',
          'expiresOn': '',
        },
        fields: [
          CustomerField(
            'number',
            'Número de certificado',
            check: (value, _) => taken.contains(_certificateKey(value))
                ? 'Este patrón ya tiene un certificado con ese número.'
                : null,
          ),
          const CustomerField('lab', 'Laboratorio', max: 250),
          CustomerField(
            'calibratedOn',
            'Fecha de calibración',
            kind: 'date',
            // Solo la fecha: «hoy» es UTC sin hora y la fecha tecleada,
            // medianoche local; comparadas tal cual, hoy salía futuro.
            check: (value, _) =>
                dateOnly(DateTime.parse(value)).isAfter(today())
                ? 'La calibración no puede ser una fecha futura.'
                : null,
          ),
          CustomerField(
            'expiresOn',
            'Vence el',
            kind: 'date',
            check: (value, values) {
              final calibrated = DateTime.tryParse(
                values['calibratedOn']?.toString() ?? '',
              );
              return calibrated != null &&
                      dateOnly(
                        DateTime.parse(value),
                      ).isBefore(dateOnly(calibrated))
                  ? 'El vencimiento no puede ser anterior a la calibración.'
                  : null;
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (plantId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Notice('No tienes plantas autorizadas.'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
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
        Expanded(
          child: RemotePanel(
            dataKey: 'patterns|$plantId|$page|$revision',
            load: () => customerRead(widget.session, 'patterns', {
              'plantId': plantId,
              'page': page,
            }),
            builder: (data) => ListView(
              // Los 140 de abajo son el hueco de la barra de navegación.
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 140),
              children: [
                FilledButton.icon(
                  onPressed: patternForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo patrón'),
                ),
                // Sin este aire el botón quedaba apoyado en la primera tarjeta.
                const SizedBox(height: 16),
                if (objects(data['items']).isEmpty)
                  const Notice('Todavía no hay patrones en esta planta.'),
                for (final item in objects(data['items']))
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['codigo']} · ${item['descripcion']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(_patternSummary(item)),
                          if (!objects(item['certificates']).any(
                            (cert) =>
                                _CertificateState.of(cert) ==
                                _CertificateState.valid,
                          ))
                            const Notice(
                              'Sin certificado vigente: las verificaciones con esta pesa salen «No trazable».',
                              icon: Icons.warning_amber_outlined,
                            ),
                          if (item['canEdit'] == true)
                            Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () => patternForm(item),
                                  child: const Text('Editar patrón'),
                                ),
                                TextButton.icon(
                                  key: ValueKey(
                                    'pattern-add-certificate-${item['id']}',
                                  ),
                                  onPressed: () => certificateForm(item),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Agregar certificado'),
                                ),
                              ],
                            )
                          else
                            const Notice(
                              'Para editar este patrón o agregarle certificados necesitas acceso a todas sus plantas.',
                            ),
                          for (final cert in objects(item['certificates']))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${cert['numero']} · ${cert['laboratorio']}',
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Calibrado: ${dateLabel(cert['calibrado_el'])}\nVence: ${dateLabel(cert['vence_el'])}',
                                    ),
                                    const SizedBox(height: 4),
                                    _CertificateState.of(cert).tag,
                                  ],
                                ),
                              ),
                              trailing:
                                  cert['estado'] == 'ACTIVE' &&
                                      item['canEdit'] == true
                                  ? IconButton(
                                      tooltip: 'Anular certificado',
                                      icon: const Icon(Icons.cancel_outlined),
                                      onPressed: () => edit(
                                        CustomerForm(
                                          session: widget.session,
                                          title: 'Anular certificado',
                                          action: 'certificate.annul',
                                          initial: {
                                            'id': cert['id'],
                                            'version': cert['row_version'],
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
                      ),
                    ),
                  ),
                _PageControls(
                  page: page,
                  total: (data['total'] as num).toInt(),
                  onChanged: (value) => setState(() => page = value),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Clave para comparar números de certificado como el servidor: sin
/// mayúsculas ni espacios sobrantes.
String _certificateKey(Object? number) =>
    (number?.toString() ?? '').trim().toLowerCase();

/// Cómo está un certificado hoy, en el teléfono. El servidor decide la
/// trazabilidad al finalizar; esto solo orienta a quien mira la lista.
enum _CertificateState {
  valid('Vigente', ComplianceStatus.conforme),
  expired('Vencido', ComplianceStatus.noConforme),
  annulled('Anulado', null);

  const _CertificateState(this.label, this.status);
  final String label;
  final ComplianceStatus? status;

  static _CertificateState of(Json cert) {
    if (cert['estado'] == 'ANNULLED') return _CertificateState.annulled;
    final expires = DateTime.tryParse(cert['vence_el']?.toString() ?? '');
    return expires != null && !dateOnly(expires).isBefore(today())
        ? _CertificateState.valid
        : _CertificateState.expired;
  }

  Widget get tag => StatusTag(label, status: status);
}

/// "Pesas · 20 kg". La capacidad llega del servidor con nueve decimales y
/// punto ("20.000000000"); en pantalla va con coma y sin ceros de relleno.
String _patternSummary(Json pattern) {
  final capacity = pattern['capacidad']?.toString() ?? '';
  final unit = pattern['unidad']?.toString() ?? '';
  return [
    valueLabel(pattern['tipo']),
    if (capacity.isEmpty)
      valueLabel(null)
    else
      '${MeasurementFormat.display(capacity)} $unit'.trim(),
  ].join(' · ');
}

/// Anterior, página actual y siguiente, con páginas de 25 registros.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.page,
    required this.total,
    required this.onChanged,
  });

  final int page;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton(
        onPressed: page > 1 ? () => onChanged(page - 1) : null,
        child: const Text('Anterior'),
      ),
      Text('Página $page'),
      TextButton(
        onPressed: page * 25 < total ? () => onChanged(page + 1) : null,
        child: const Text('Siguiente'),
      ),
    ],
  );
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
              margin: const EdgeInsets.only(bottom: 12),
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

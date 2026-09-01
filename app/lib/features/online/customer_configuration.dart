import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/tile_grid.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

Future<Json> customerRead(
  MobileSession session,
  String section, [
  Json filters = const {},
]) => session.api.rpc('ivmet_customer_read', {
  'section': section,
  'filters': filters,
});

class CustomerField {
  const CustomerField(
    this.keyName,
    this.label, {
    this.required = true,
    this.kind = 'text',
    this.options = const {},
    this.max = 150,
    this.readOnly = false,
  });
  final String keyName, label, kind;
  final bool required, readOnly;
  final int max;
  final Map<String, String> options;
}

/// UUID y payload congelados al perder una respuesta: reintentar no duplica.
class CustomerForm extends StatefulWidget {
  const CustomerForm({
    required this.session,
    required this.title,
    required this.action,
    required this.fields,
    required this.initial,
    this.payload,
    this.notice,
    this.preview,
    this.afterFields,
    this.submitLabel = 'Guardar',
    this.externalDirty = false,
    super.key,
  });
  final MobileSession session;
  final String title, action, submitLabel;
  final List<CustomerField> fields;
  final Json initial;
  final Json Function(Json)? payload;
  final String? notice;
  final Widget? preview;
  final Widget? afterFields;
  final bool externalDirty;
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final form = GlobalKey<FormState>();
  late Json values = Map.of(widget.initial);
  String requestId = const Uuid().v4();
  Json? pending;
  bool busy = false, dirty = false, leaving = false;
  String? error;
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= object(
        jsonDecode(jsonEncode(widget.payload?.call(values) ?? Map.of(values))),
      );
      await widget.session.api.rpc('ivmet_customer_mutate', {
        'action': widget.action,
        'payload': pending,
        'request_id': requestId,
      });
      if (!mounted) return;
      setState(() {
        leaving = true;
        dirty = false;
        busy = false;
      });
      Navigator.of(context).pop(true);
    } on MobileFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message;
        if (!failure.offline && (failure.status ?? 0) < 500) {
          pending = null;
          requestId = const Uuid().v4();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No pudimos confirmar el guardado. Reintenta sin cambiar los datos.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> askLeave() async {
    if (busy) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir del formulario?'),
        content: Text(
          pending != null
              ? 'El guardado no está confirmado. Puedes reintentar aquí o revisar el registro al volver.'
              : 'Se perderán los cambios que no hayas guardado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar editando'),
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        leaving ||
        (!busy && !dirty && !widget.externalDirty && pending == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) askLeave();
    },
    child: OnlinePage(
      title: widget.title,
      child: Form(
        key: form,
        onChanged: () {
          if (!dirty) setState(() => dirty = true);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.notice != null) Notice(widget.notice!),
            if (widget.preview != null) widget.preview!,
            if (error != null) Notice(error!, icon: Icons.error_outline),
            if (pending != null && !busy)
              const Notice(
                'Respuesta pendiente. Reintenta con los mismos datos para evitar duplicados.',
              ),
            for (final field in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: field.kind == 'bool'
                    ? FormField<bool>(
                        initialValue: values[field.keyName] == true,
                        validator: (_) =>
                            field.required && values[field.keyName] != true
                            ? 'Debes confirmar para continuar.'
                            : null,
                        builder: (state) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(field.label),
                              value: values[field.keyName] == true,
                              onChanged: busy || pending != null
                                  ? null
                                  : (v) => setState(() {
                                      values[field.keyName] = v;
                                      dirty = true;
                                      state.didChange(v);
                                    }),
                            ),
                            if (state.hasError)
                              Text(
                                state.errorText!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      )
                    : field.kind == 'multi'
                    ? FormField<List<String>>(
                        validator: (_) =>
                            field.required &&
                                (values[field.keyName] as List? ?? []).isEmpty
                            ? 'Selecciona al menos una planta.'
                            : null,
                        builder: (state) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(field.label),
                            for (final option in field.options.entries)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(option.value),
                                value: (values[field.keyName] as List? ?? [])
                                    .contains(option.key),
                                onChanged: busy || pending != null
                                    ? null
                                    : (v) => setState(() {
                                        final selected = List<String>.from(
                                          values[field.keyName] as List? ?? [],
                                        );
                                        v == true
                                            ? selected.add(option.key)
                                            : selected.remove(option.key);
                                        values[field.keyName] = selected;
                                        dirty = true;
                                        state.didChange(selected);
                                      }),
                              ),
                            if (state.hasError)
                              Text(
                                state.errorText!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      )
                    : field.kind == 'select'
                    ? DropdownButtonFormField<String>(
                        initialValue: values[field.keyName]?.toString() ?? '',
                        isExpanded: true,
                        decoration: InputDecoration(labelText: field.label),
                        items: field.options.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: busy || pending != null
                            ? null
                            : (v) => setState(() {
                                values[field.keyName] = v;
                                dirty = true;
                              }),
                        validator: (v) =>
                            field.required && (v == null || v.isEmpty)
                            ? 'Selecciona una opción.'
                            : null,
                      )
                    : TextFormField(
                        initialValue: values[field.keyName]?.toString() ?? '',
                        readOnly: field.readOnly || busy || pending != null,
                        maxLength: field.max,
                        keyboardType: field.kind == 'decimal'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: field.label,
                          hintText: field.kind == 'date' ? 'AAAA-MM-DD' : null,
                        ),
                        onChanged: (v) {
                          values[field.keyName] = v;
                          if (!dirty) setState(() => dirty = true);
                        },
                        validator: (v) {
                          if (field.required && (v ?? '').trim().isEmpty) {
                            return 'Completa este campo.';
                          }
                          if (field.kind == 'decimal' &&
                              (v ?? '').isNotEmpty &&
                              !RegExp(
                                r'^(0|[1-9]\d{0,9})(\.\d{1,9})?$',
                              ).hasMatch(v!)) {
                            return 'Usa punto decimal y hasta 9 decimales.';
                          }
                          if (field.kind == 'date' &&
                              !RegExp(
                                r'^\d{4}-\d{2}-\d{2}$',
                              ).hasMatch(v ?? '')) {
                            return 'Usa AAAA-MM-DD.';
                          }
                          return null;
                        },
                      ),
              ),
            if (widget.afterFields != null)
              AbsorbPointer(
                absorbing: busy || pending != null,
                child: widget.afterFields!,
              ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(
                busy
                    ? 'Guardando…'
                    : pending != null
                    ? 'Reintentar guardado'
                    : widget.submitLabel,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

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
              child: DropdownButtonFormField<String>(
                initialValue: plantId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filtrar patrones por planta',
                ),
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
                                    ExpansionTile(
                                      title: const Text(
                                        'Información autorizada',
                                      ),
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

class EquipmentValidation extends StatelessWidget {
  const EquipmentValidation({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Validar ficha de la balanza',
    load: () => customerRead(session, 'equipment', {'id': equipmentId}),
    builder: (bundle) {
      final master = object(bundle['master']),
          existing = bundle['customer'] == null
              ? <String, dynamic>{}
              : object(bundle['customer']);
      final effective = {...master, ...object(existing['datos'] ?? {})};
      return CustomerForm(
        session: session,
        title: 'Validar ficha de la balanza',
        action: 'equipment.validate',
        notice:
            'Comprueba los datos del catálogo. Las capacidades y divisiones se conservan como datos técnicos de DataMET. Tus correcciones quedan privadas hasta que el jefe de calidad autorice compartirlas.',
        preview: Notice(
          'Ubicación del catálogo: ${valueLabel(master['ubicacion'])}. Si hay una coincidencia, sugerimos el área existente. También puedes confirmar un nombre nuevo.',
        ),
        initial: {
          'id': equipmentId,
          'catalogHash': master['source_hash'],
          'version': existing['row_version'] ?? '0',
          for (final key in [
            'ubicacion',
            'cod_interno',
            'marca',
            'modelo',
            'serie',
          ])
            key: effective[key] ?? '',
          'areaId': bundle['areaId'] ?? bundle['suggestedAreaId'] ?? '',
          'areaName':
              bundle['areaId'] == null && bundle['suggestedAreaId'] == null
              ? bundle['suggestedArea'] ?? ''
              : '',
          'confirmed': false,
        },
        fields: [
          const CustomerField('ubicacion', 'Ubicación actual', required: false),
          const CustomerField('cod_interno', 'Código interno', required: false),
          const CustomerField('marca', 'Marca', required: false),
          const CustomerField('modelo', 'Modelo', required: false),
          const CustomerField('serie', 'Serie', required: false),
          CustomerField(
            'areaId',
            'Área de esta planta',
            kind: 'select',
            required: false,
            options: {
              '': 'Sin área',
              for (final a in objects(bundle['areas']))
                a['id'] as String: a['name'] as String,
            },
          ),
          const CustomerField(
            'areaName',
            'Nombre de área nueva (reemplaza la selección)',
            required: false,
          ),
          const CustomerField(
            'confirmed',
            'He revisado la información de esta balanza',
            kind: 'bool',
          ),
        ],
        payload: (v) => {
          'id': equipmentId,
          'catalogHash': master['source_hash'],
          'version': existing['row_version'] ?? '0',
          'areaId': (v['areaName'] as String? ?? '').trim().isEmpty
              ? v['areaId']
              : '',
          'areaName': v['areaName'] ?? '',
          'data': {
            for (final key in [
              'ubicacion',
              'cod_interno',
              'marca',
              'modelo',
              'serie',
            ])
              key: v[key],
          },
        },
        submitLabel: 'Guardar validación privada',
      );
    },
  );
}

class EquipmentUpdatePreview extends StatelessWidget {
  const EquipmentUpdatePreview({required this.snapshot, super.key});
  final Json snapshot;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DetailField(
        'Balanza / planta',
        '${snapshot['code']} · ${snapshot['plantCode']}',
      ),
      for (final field in const {
        'ubicacion': 'Ubicación',
        'cod_interno': 'Código interno',
        'marca': 'Marca',
        'modelo': 'Modelo',
        'serie': 'Serie',
      }.entries)
        DetailField(
          field.value,
          '${valueLabel(object(snapshot['catalog'])[field.key])} → ${valueLabel(object(snapshot['customer'])[field.key])}',
        ),
      DetailField('Área confirmada', snapshot['area']),
    ],
  );
}

class ShareEquipmentUpdate extends StatelessWidget {
  const ShareEquipmentUpdate({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Compartir actualización con Métrica',
    load: () => customerRead(session, 'share-preview', {'id': equipmentId}),
    builder: (preview) => CustomerForm(
      session: session,
      title: 'Compartir actualización con Métrica',
      action: 'update.share',
      notice: preview['notice'] as String,
      preview: EquipmentUpdatePreview(snapshot: object(preview['snapshot'])),
      initial: {
        'id': equipmentId,
        'hash': preview['hash'],
        'consentVersion': preview['consentVersion'],
        'consent': false,
      },
      fields: const [
        CustomerField('message', 'Mensaje para Métrica', max: 2000),
        CustomerField(
          'consent',
          'Autorizo enviar únicamente la información mostrada para preparar próximas calibraciones.',
          kind: 'bool',
        ),
      ],
      submitLabel: 'Autorizar y enviar actualización',
    ),
  );
}

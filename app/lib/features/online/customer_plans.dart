import 'package:flutter/material.dart';
import 'customer_configuration.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

String planState(Object? state) => switch (state) {
  'DRAFT' => 'Borrador',
  'PUBLISHED' => 'Publicado',
  'RETIRED' => 'Retirado',
  _ => valueLabel(state),
};
const planMethods = {
  'absolute_error': 'Error de indicación',
  'range': 'Diferencia máxima entre posiciones',
  'sample_standard_deviation': 'Desviación estándar muestral',
};
const planTypes = ['linearity', 'repeatability', 'eccentricity'];
Json newPlanPoint(int order) => {
  'code': 'P$order',
  'label': '',
  'load': '',
  'tolerance': '',
  'group': '1',
  'position': '',
  'direction': '',
  'metadata': <String, dynamic>{},
};
List<Json> newPlanPoints(String type) => [
  for (var index = 1; index <= 5; index++)
    {
      ...newPlanPoint(index),
      'label': type == 'linearity'
          ? 'Carga $index'
          : type == 'repeatability'
          ? 'Repetición $index'
          : index == 1
          ? 'Referencia central'
          : 'Posición $index',
      'position': type == 'eccentricity'
          ? index == 1
                ? 'centro'
                : 'posición $index'
          : '',
    },
];

Json planTestPayload(Json trial) => {
  'type': trial['type'],
  'unit': trial['unit'],
  'frequencyDays': trial['frequencyDays'],
  'warningDays': trial['warningDays'],
  'decisionRule': trial['decisionRule'] ?? 'direct',
  'toleranceSource': trial['toleranceSource'] ?? 'CLIENT_PROCESS',
  'uncertainty': trial['uncertainty'] ?? '',
  'points': [
    for (final point in trial['points'] as List<Json>)
      {
        'code': point['code'],
        'label': point['label'],
        'load': point['load'],
        'tolerance': point['tolerance'],
        'group': point['group'],
        'position': point['position'],
        'direction': point['direction'],
        'metadata': point['metadata'],
      },
  ],
};

class CustomerPlanEditor extends StatefulWidget {
  const CustomerPlanEditor({
    required this.session,
    this.record,
    this.clone = false,
    super.key,
  });
  final MobileSession session;
  final Json? record;
  final bool clone;
  @override
  State<CustomerPlanEditor> createState() => _CustomerPlanEditorState();
}

class _CustomerPlanEditorState extends State<CustomerPlanEditor> {
  late List<Json> tests = [
    for (final t in objects(widget.record?['tests']))
      {
        'type': t['tipo'],
        'method': t['metodo_evaluacion'],
        'methodCode': t['metodo_codigo'],
        'unit': t['unidad'],
        'frequencyDays': t['frecuencia_dias'].toString(),
        'warningDays': t['aviso_dias'].toString(),
        'decisionRule': t['regla_decision'] ?? 'direct',
        'toleranceSource': t['fuente_tolerancia'] ?? 'CLIENT_PROCESS',
        'uncertainty': t['incertidumbre_expandida']?.toString() ?? '',
        'points': [
          for (final p in objects(t['points']))
            {
              'code': p['codigo'],
              'label': p['etiqueta'],
              'load': p['carga_nominal'],
              'tolerance': p['tolerancia'],
              'group': p['grupo'].toString(),
              'position': p['posicion'] ?? '',
              'direction': p['direccion'] ?? '',
              'metadata': p['metadata'] ?? <String, dynamic>{},
            },
        ],
      },
  ];
  bool changed = false;
  Widget input(
    Json target,
    String keyName,
    String label, {
    bool required = true,
    String kind = 'text',
    int max = 200,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: target[keyName]?.toString() ?? '',
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      keyboardType: kind == 'decimal'
          ? const TextInputType.numberWithOptions(decimal: true)
          : kind == 'int'
          ? TextInputType.number
          : TextInputType.text,
      onChanged: (value) {
        target[keyName] = value;
        changed = true;
      },
      validator: (value) {
        if (required && (value ?? '').trim().isEmpty) {
          return 'Completa este campo.';
        }
        if (kind == 'decimal' &&
            (value ?? '').isNotEmpty &&
            !RegExp(r'^(0|[1-9]\d{0,9})(\.\d{1,9})?$').hasMatch(value ?? '')) {
          return 'Usa punto y hasta 9 decimales.';
        }
        if (kind == 'int' && !RegExp(r'^\d{1,4}$').hasMatch(value ?? '')) {
          return 'Escribe un número entero.';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: widget.clone
        ? 'Nueva versión del plan'
        : widget.record == null
        ? 'Nuevo plan metrológico'
        : 'Editar borrador de plan',
    load: () => customerRead(widget.session, 'method-catalog'),
    builder: (catalog) => _editor(context, catalog),
  );

  Widget _editor(BuildContext context, Json catalog) {
    final profiles = objects(catalog['profiles']);
    final profileOptions = {
      for (final profile in profiles)
        profile['code'] as String: profile['name'] as String,
    };
    final currentProfile = widget.record?['procedimiento_referencia']
        ?.toString();
    final initialProfile = profileOptions.containsKey(currentProfile)
        ? currentProfile!
        : profileOptions.keys.firstOrNull ?? '';
    return CustomerForm(
      session: widget.session,
      title: widget.clone
          ? 'Nueva versión del plan'
          : widget.record == null
          ? 'Nuevo plan metrológico'
          : 'Editar borrador de plan',
      action: 'plan.save',
      externalDirty: changed,
      notice:
          'Selecciona un perfil de control interno. IvMET fija el método y la fórmula; tu empresa define frecuencias, cargas, límites y regla de decisión. No constituye calibración acreditada ni verificación legal.',
      initial: {
        'name': widget.record?['name'] ?? '',
        'procedureReference': initialProfile,
        'notes': widget.record?['notas'] ?? '',
      },
      fields: [
        CustomerField(
          'name',
          'Nombre del plan',
          max: 200,
          readOnly: widget.record != null,
        ),
        CustomerField(
          'procedureReference',
          'Perfil de comprobación interna',
          kind: 'select',
          options: profileOptions,
        ),
        CustomerField(
          'notes',
          'Notas de la versión',
          required: false,
          max: 3000,
        ),
      ],
      payload: (values) => {
        ...values,
        if (widget.record != null && !widget.clone) 'id': widget.record!['id'],
        if (widget.record != null && !widget.clone)
          'version': widget.record!['draft_revision'],
        if (widget.clone) 'planId': widget.record!['plan_id'],
        'tests': tests.map(planTestPayload).toList(),
      },
      afterFields: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pruebas del plan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          FormField<bool>(
            validator: (_) =>
                tests.isEmpty ? 'Incluye al menos una prueba.' : null,
            builder: (state) => Column(
              children: [
                for (final type in planTypes)
                  CheckboxListTile(
                    title: Text(testLabel(type)),
                    contentPadding: EdgeInsets.zero,
                    value: tests.any((t) => t['type'] == type),
                    onChanged: (value) => setState(() {
                      changed = true;
                      if (value == true) {
                        tests.add({
                          'type': type,
                          'unit': '',
                          'frequencyDays': '',
                          'warningDays': '',
                          'decisionRule': 'direct',
                          'toleranceSource': 'CLIENT_PROCESS',
                          'uncertainty': '',
                          'points': newPlanPoints(type),
                        });
                      } else {
                        tests.removeWhere((t) => t['type'] == type);
                      }
                      state.didChange(tests.isNotEmpty);
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
          ),
          for (final trial in tests)
            Card(
              key: ValueKey(trial['type']),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testLabel(trial['type']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Notice(
                      'Método controlado por IvMET: ${planMethods[trial['method']] ?? switch (trial['type']) {
                            'linearity' => 'Error de indicación',
                            'repeatability' => 'Desviación estándar muestral',
                            _ => 'Diferencia máxima entre posiciones',
                          }}. El móvil no puede sustituir esta fórmula.',
                    ),
                    const SizedBox(height: 12),
                    input(trial, 'unit', 'Unidad', max: 20),
                    input(
                      trial,
                      'frequencyDays',
                      'Frecuencia en días',
                      kind: 'int',
                      max: 4,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue:
                          trial['decisionRule'] as String? ?? 'direct',
                      decoration: const InputDecoration(
                        labelText: 'Regla de decisión',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'direct',
                          child: Text('Comparación directa'),
                        ),
                        DropdownMenuItem(
                          value: 'guard_band',
                          child: Text('Banda de guarda con incertidumbre'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        trial['decisionRule'] = v;
                        changed = true;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          trial['toleranceSource'] as String? ??
                          'CLIENT_PROCESS',
                      decoration: const InputDecoration(
                        labelText: 'Origen del límite de aceptación',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'CLIENT_PROCESS',
                          child: Text('Proceso interno del cliente'),
                        ),
                        const DropdownMenuItem(
                          value: 'MANUFACTURER',
                          child: Text('Especificación del fabricante'),
                        ),
                        const DropdownMenuItem(
                          value: 'CALIBRATION_REPORT',
                          child: Text('Informe de calibración'),
                        ),
                        if (trial['type'] == 'linearity')
                          const DropdownMenuItem(
                            value: 'OIML_IN_SERVICE_REFERENCE',
                            child: Text('Referencia OIML R 76 en servicio'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        trial['toleranceSource'] = v;
                        changed = true;
                      }),
                    ),
                    const SizedBox(height: 12),
                    input(
                      trial,
                      'uncertainty',
                      'Incertidumbre expandida (solo banda de guarda)',
                      required: false,
                      kind: 'decimal',
                      max: 20,
                    ),
                    input(
                      trial,
                      'warningDays',
                      'Avisar antes, en días',
                      kind: 'int',
                      max: 4,
                    ),
                    for (final (index, point)
                        in (trial['points'] as List<Json>).indexed)
                      Card(
                        key: ObjectKey(point),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text('Punto ${index + 1}')),
                                  IconButton(
                                    tooltip: 'Quitar punto',
                                    onPressed:
                                        (trial['points'] as List).length <= 5
                                        ? null
                                        : () => setState(() {
                                            (trial['points'] as List).removeAt(
                                              index,
                                            );
                                            changed = true;
                                          }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              input(point, 'code', 'Código de punto', max: 100),
                              input(point, 'label', 'Descripción del punto'),
                              input(
                                point,
                                'load',
                                'Carga nominal',
                                kind: 'decimal',
                                max: 20,
                              ),
                              input(
                                point,
                                'tolerance',
                                'Tolerancia',
                                kind: 'decimal',
                                max: 20,
                              ),
                              input(
                                point,
                                'group',
                                'Grupo / repetición',
                                kind: 'int',
                                max: 4,
                              ),
                              input(
                                point,
                                'position',
                                'Posición',
                                required: false,
                                max: 100,
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: point['direction'] as String,
                                decoration: const InputDecoration(
                                  labelText: 'Dirección',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text('No aplica'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ascending',
                                    child: Text('Ascendente'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'descending',
                                    child: Text('Descendente'),
                                  ),
                                ],
                                onChanged: (v) {
                                  point['direction'] = v;
                                  changed = true;
                                },
                              ),
                              const SizedBox(height: 12),
                              input(
                                point['metadata'] as Json,
                                'platform',
                                'Plataforma / etapa sustitutiva',
                                required: false,
                                max: 100,
                              ),
                            ],
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: (trial['points'] as List).length >= 200
                          ? null
                          : () => setState(() {
                              (trial['points'] as List).add(
                                newPlanPoint(
                                  (trial['points'] as List).length + 1,
                                ),
                              );
                              changed = true;
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar punto'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      submitLabel: 'Guardar borrador del plan',
    );
  }
}

class CustomerPlanDetail extends StatefulWidget {
  const CustomerPlanDetail({
    required this.session,
    required this.plan,
    this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final Json plan;
  final String? equipmentId;
  @override
  State<CustomerPlanDetail> createState() => _CustomerPlanDetailState();
}

class _CustomerPlanDetailState extends State<CustomerPlanDetail> {
  int revision = 0;
  Future<void> edit(Widget page) async {
    final changed = await openPage<bool>(context, page);
    if (mounted && changed == true) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Plan metrológico',
    child: RemotePanel(
      dataKey: '$revision',
      load: () =>
          customerRead(widget.session, 'plan', {'id': widget.plan['id']}),
      builder: (p) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            p['name'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          DetailField('Estado', '${planState(p['estado'])} · v${p['version']}'),
          DetailField('Procedimiento', p['procedimiento_referencia']),
          const Notice(
            'Plan de comprobación interna. El método lo controla IvMET; las cargas, límites y frecuencias pertenecen al cliente.',
            icon: Icons.rule_outlined,
          ),
          for (final t in objects(p['tests']))
            ExpansionTile(
              title: Text(testLabel(t['tipo'])),
              subtitle: Text(
                'Cada ${t['frecuencia_dias']} días · ${t['unidad']} · ${planMethods[t['metodo_evaluacion']] ?? valueLabel(t['metodo_evaluacion'])}',
              ),
              children: [
                for (final point in objects(t['points']))
                  ListTile(
                    title: Text('${point['codigo']} · ${point['etiqueta']}'),
                    subtitle: Text(
                      'Carga ${point['carga_nominal']} · tolerancia ${point['tolerancia']}\nGrupo ${point['grupo']} · ${point['posicion'] ?? ''}',
                    ),
                  ),
              ],
            ),
          if (widget.session.quality) ...[
            FilledButton(
              onPressed: () => edit(
                CustomerPlanEditor(
                  session: widget.session,
                  record: p,
                  clone: p['estado'] != 'DRAFT',
                ),
              ),
              child: Text(
                p['estado'] == 'DRAFT'
                    ? 'Editar borrador'
                    : 'Crear nueva versión',
              ),
            ),
            if (p['estado'] != 'RETIRED')
              OutlinedButton(
                onPressed: () => edit(
                  CustomerForm(
                    session: widget.session,
                    title: p['estado'] == 'DRAFT'
                        ? 'Publicar versión'
                        : 'Retirar versión',
                    action: p['estado'] == 'DRAFT'
                        ? 'plan.publish'
                        : 'plan.retire',
                    initial: {
                      'id': p['id'],
                      'version': p['draft_revision'],
                      'confirmed': false,
                    },
                    payload: (v) => {
                      'id': p['id'],
                      'version': p['draft_revision'],
                    },
                    notice: p['estado'] == 'DRAFT'
                        ? 'Al publicar, el perfil, los puntos, límites y frecuencias quedan inmutables. Las comprobaciones asignadas usarán esta versión exacta.'
                        : 'Se conserva el historial. Los borradores existentes mantienen la versión que utilizaron.',
                    fields: const [
                      CustomerField(
                        'confirmed',
                        'Confirmo esta operación sobre el plan',
                        kind: 'bool',
                      ),
                    ],
                    submitLabel: p['estado'] == 'DRAFT'
                        ? 'Publicar'
                        : 'Retirar',
                  ),
                ),
                child: Text(
                  p['estado'] == 'DRAFT'
                      ? 'Publicar versión'
                      : 'Retirar versión',
                ),
              ),
            if (p['estado'] == 'PUBLISHED' && widget.equipmentId != null)
              FilledButton(
                onPressed: () => edit(
                  CustomerForm(
                    session: widget.session,
                    title: 'Asignar plan a la balanza',
                    action: 'plan.assign',
                    initial: {'confirmed': false},
                    payload: (_) => {
                      'equipmentId': widget.equipmentId,
                      'planVersionId': p['id'],
                    },
                    notice:
                        'La asignación empieza al guardar y conserva el historial anterior. La ficha de la balanza debe estar validada.',
                    fields: const [
                      CustomerField(
                        'confirmed',
                        'Confirmo usar este plan en esta balanza',
                        kind: 'bool',
                      ),
                    ],
                    submitLabel: 'Asignar plan',
                  ),
                ),
                child: const Text('Asignar a esta balanza'),
              ),
          ],
        ],
      ),
    ),
  );
}

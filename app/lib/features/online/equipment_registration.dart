import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/measurement_format.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/segmented_pills.dart';
import 'customer_form.dart';
import 'draft_controller.dart' show normalizedDecimal;
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Balanzas que la empresa incorpora sin que Métrica tenga acceso a ellas.
///
/// El jefe de calidad las registra con su área, su identificación y hasta tres
/// rangos. Quedan privadas y listas para configurar sus verificaciones; solo
/// llegan a Métrica si él autoriza enviarlas ([ShareEquipmentRegistration]).
///
/// Supabase repite todas las reglas de este formulario. Aquí se validan antes
/// para señalar el campo exacto, no para decidir.

const _units = ['kg', 'g', 't', 'mg'];
const _classes = ['I', 'II', 'III', 'IIII'];
const _maxRanges = 3;

class _RangeInput {
  _RangeInput({
    String capacity = '',
    String division = '',
    String interval = '',
  }) : capacity = TextEditingController(
         text: MeasurementFormat.display(capacity),
       ),
       division = TextEditingController(
         text: MeasurementFormat.display(division),
       ),
       interval = TextEditingController(
         text: MeasurementFormat.display(interval),
       );

  final TextEditingController capacity;
  final TextEditingController division;
  final TextEditingController interval;

  Json payload() => {
    'capacity': normalizedDecimal(capacity.text),
    'division': normalizedDecimal(division.text),
    'interval': normalizedDecimal(interval.text),
  };

  void dispose() {
    capacity.dispose();
    division.dispose();
    interval.dispose();
  }
}

/// Alta ([EquipmentRegistrationScreen.create]) o corrección
/// ([EquipmentRegistrationScreen.edit]) de una balanza registrada.
///
/// Al guardar devuelve el recibo del servidor, con el `id` de la balanza.
class EquipmentRegistrationScreen extends StatelessWidget {
  const EquipmentRegistrationScreen.create({
    required this.session,
    required String this.plantId,
    super.key,
  }) : equipmentId = null;

  const EquipmentRegistrationScreen.edit({
    required this.session,
    required String this.equipmentId,
    super.key,
  }) : plantId = null;

  final MobileSession session;
  final String? plantId;
  final String? equipmentId;

  @override
  Widget build(BuildContext context) {
    final id = equipmentId;
    if (id == null) {
      return _RegistrationForm(
        session: session,
        plantId: plantId!,
        areas: [
          for (final area in objects(session.bootstrap['areas']))
            if (area['plantId'] == plantId) area,
        ],
      );
    }
    return RemotePanel(
      frameTitle: 'Editar balanza',
      load: () => customerRead(session, 'registration', {'id': id}),
      builder: (data) => _RegistrationForm(
        session: session,
        plantId: data['plantId'] as String,
        areas: objects(data['areas']),
        current: data,
      ),
    );
  }
}

class _RegistrationForm extends StatefulWidget {
  const _RegistrationForm({
    required this.session,
    required this.plantId,
    required this.areas,
    this.current,
  });

  final MobileSession session;
  final String plantId;
  final List<Json> areas;

  /// Lo que devuelve `ivmet_customer_read('registration')` al corregir.
  final Json? current;

  @override
  State<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<_RegistrationForm> {
  static final _exact = RegExp(r'^(0|[1-9]\d{0,9})(\.\d{1,9})?$');

  final form = GlobalKey<FormState>();
  late final Json data = object(widget.current?['data'] ?? {});
  late final bool editing = widget.current != null;

  /// Con capturas o verificaciones, los datos técnicos sostienen evidencia.
  late final bool technicalLocked = widget.current?['inUse'] == true;

  late bool newArea = widget.areas.isEmpty;
  late String? areaId = widget.current?['areaId'] as String?;
  late final areaName = TextEditingController();
  late final code = TextEditingController(text: data['cod_interno'] ?? '');
  late final brand = TextEditingController(text: data['marca'] ?? '');
  late final model = TextEditingController(text: data['modelo'] ?? '');
  late final serial = TextEditingController(text: data['serie'] ?? '');
  late final location = TextEditingController(text: data['ubicacion'] ?? '');
  late String type = data['tipo'] as String? ?? 'PLATFORM';
  late String unit = data['unidad'] as String? ?? 'kg';
  late String accuracyClass = data['clase'] as String? ?? '';
  late final List<_RangeInput> ranges = [
    for (final range in objects(widget.current?['ranges']))
      _RangeInput(
        capacity: range['capacity']?.toString() ?? '',
        division: range['division']?.toString() ?? '',
        interval: range['interval']?.toString() ?? '',
      ),
    if (widget.current == null) _RangeInput(),
  ];

  bool confirmed = false;
  bool busy = false;
  bool dirty = false;
  bool leaving = false;
  String? error;
  String requestId = const Uuid().v4();
  Json? pending;

  bool get frozen => busy || pending != null;

  @override
  void dispose() {
    for (final controller in [areaName, code, brand, model, serial, location]) {
      controller.dispose();
    }
    for (final range in ranges) {
      range.dispose();
    }
    super.dispose();
  }

  void changed(VoidCallback update) {
    setState(() {
      update();
      dirty = true;
    });
  }

  double? _number(TextEditingController controller) =>
      double.tryParse(normalizedDecimal(controller.text));

  String? _decimalError(String text, {required bool required}) {
    final value = normalizedDecimal(text);
    if (value.isEmpty) return required ? 'Completa este campo.' : null;
    if (!_exact.hasMatch(value)) return 'Usa hasta 9 decimales, sin miles.';
    return null;
  }

  String? _capacityError(int index) {
    final base = _decimalError(ranges[index].capacity.text, required: true);
    if (base != null) return base;
    final value = _number(ranges[index].capacity)!;
    if (value <= 0) return 'Debe ser mayor que cero.';
    final previous = index == 0 ? null : _number(ranges[index - 1].capacity);
    if (previous != null && value <= previous) {
      return 'Debe superar la capacidad del rango $index.';
    }
    return null;
  }

  String? _divisionError(int index) {
    final base = _decimalError(ranges[index].division.text, required: true);
    if (base != null) return base;
    final value = _number(ranges[index].division)!;
    if (value <= 0) return 'Debe ser mayor que cero.';
    final capacity = _number(ranges[index].capacity);
    if (capacity != null && value >= capacity) {
      return 'Debe ser menor que la capacidad máxima.';
    }
    return null;
  }

  String? _intervalError(int index) {
    final base = _decimalError(ranges[index].interval.text, required: false);
    if (base != null || ranges[index].interval.text.trim().isEmpty) return base;
    final value = _number(ranges[index].interval)!;
    final division = _number(ranges[index].division);
    if (division != null && value < division) {
      return 'No puede ser menor que la división d.';
    }
    final capacity = _number(ranges[index].capacity);
    if (capacity != null && value >= capacity) {
      return 'Debe ser menor que la capacidad máxima.';
    }
    return null;
  }

  Json _payload() => {
    if (editing) 'id': widget.current!['id'],
    if (editing) 'version': widget.current!['version'],
    if (!editing) 'plantId': widget.plantId,
    'areaId': newArea ? '' : areaId ?? '',
    'areaName': newArea ? areaName.text.trim() : '',
    'data': {
      'cod_interno': code.text.trim(),
      'marca': brand.text.trim(),
      'modelo': model.text.trim(),
      'serie': serial.text.trim(),
      'ubicacion': location.text.trim(),
      'tipo': type,
      'clase': accuracyClass,
      'unidad': unit,
    },
    'ranges': [for (final range in ranges) range.payload()],
  };

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (busy) return;
    if (!form.currentState!.validate()) {
      setState(() => error = 'Revisa los campos marcados antes de guardar.');
      return;
    }
    if (!confirmed) {
      setState(() => error = 'Confirma que revisaste los datos de la balanza.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= object(jsonDecode(jsonEncode(_payload())));
      final result = await widget.session.api.rpc('ivmet_customer_mutate', {
        'action': editing ? 'equipment.edit' : 'equipment.register',
        'payload': pending,
        'request_id': requestId,
      });
      // Un área nueva y el conteo de balanzas viven en el bootstrap.
      unawaited(widget.session.refresh());
      if (!mounted) return;
      setState(() {
        leaving = true;
        dirty = false;
        busy = false;
      });
      Navigator.of(context).pop(result);
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
        title: const Text('¿Salir sin guardar?'),
        content: Text(
          pending != null
              ? 'El guardado no está confirmado. Puedes reintentarlo sin duplicar la balanza.'
              : 'Se perderán los datos que no hayas guardado.',
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
    canPop: leaving || (!busy && !dirty && pending == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) askLeave();
    },
    child: OnlinePage(
      title: editing ? 'Editar balanza' : 'Registrar balanza',
      child: Form(
        key: form,
        onChanged: () {
          if (!dirty) setState(() => dirty = true);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Notice(
              editing
                  ? 'Corrige los datos de la balanza que registró tu empresa. El área y la identificación se pueden cambiar siempre.'
                  : 'Registra una balanza que Métrica todavía no tiene en su catálogo. Queda privada de tu empresa y lista para configurar sus verificaciones.',
            ),
            if (error != null) Notice(error!, icon: Icons.error_outline),
            if (pending != null && !busy)
              const Notice(
                'Respuesta pendiente. Reintenta con los mismos datos para evitar duplicados.',
              ),
            ..._areaSection(),
            ..._identificationSection(),
            ..._technicalSection(),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Confirmo que estos datos corresponden a la balanza',
              ),
              value: confirmed,
              onChanged: frozen
                  ? null
                  : (value) => changed(() => confirmed = value == true),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(
                busy
                    ? 'Guardando…'
                    : pending != null
                    ? 'Reintentar guardado'
                    : editing
                    ? 'Guardar cambios'
                    : 'Registrar balanza',
              ),
            ),
            if (!editing)
              const Notice(
                'Métrica no recibe esta balanza. Si más adelante quieres que la conozca, autoriza el envío desde su ficha.',
                icon: Icons.shield_outlined,
              ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _areaSection() => [
    const SectionLabel('Área'),
    if (widget.areas.isEmpty)
      const Notice(
        'Esta planta todavía no tiene áreas: escribe el nombre de la primera.',
      )
    else
      AbsorbPointer(
        absorbing: frozen,
        child: SegmentedPills<bool>(
          selected: newArea,
          onSelect: (value) => changed(() => newArea = value),
          segments: const [
            PillSegment(false, 'Área existente'),
            PillSegment(true, 'Área nueva'),
          ],
        ),
      ),
    const SizedBox(height: 14),
    if (newArea)
      _text(areaName, 'Nombre del área nueva', max: 150, required: true)
    else
      LabeledInput(
        label: 'Área de la planta',
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          initialValue: widget.areas.any((area) => area['id'] == areaId)
              ? areaId
              : null,
          isExpanded: true,
          items: [
            for (final area in widget.areas)
              DropdownMenuItem(
                value: area['id'] as String,
                child: Text(
                  valueLabel(area['name']),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: frozen ? null : (value) => changed(() => areaId = value),
          validator: (value) =>
              value == null || value.isEmpty ? 'Elige un área.' : null,
        ),
      ),
  ];

  List<Widget> _identificationSection() => [
    const SectionLabel('Identificación'),
    _text(code, 'Código interno', max: 50, required: true),
    _text(brand, 'Marca', max: 50),
    _text(model, 'Modelo', max: 50),
    _text(serial, 'Serie', max: 70),
    _text(location, 'Ubicación', max: 150),
  ];

  List<Widget> _technicalSection() {
    final locked = frozen || technicalLocked;
    final palette = IndustryPalette.of(context);
    return [
      const SectionLabel('Datos técnicos'),
      if (technicalLocked)
        const Notice(
          'Esta balanza ya tiene capturas o verificaciones: sus datos técnicos no se pueden cambiar. Si son incorrectos, dala de baja y regístrala de nuevo.',
          icon: Icons.lock_outline,
        ),
      Opacity(
        opacity: technicalLocked ? 0.55 : 1,
        child: AbsorbPointer(
          absorbing: locked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledInput(
                label: 'Tipo de balanza',
                padding: const EdgeInsets.only(bottom: 16),
                child: SegmentedPills<String>(
                  selected: type,
                  onSelect: (value) => changed(() => type = value),
                  segments: const [
                    PillSegment('PLATFORM', 'Balanza o plataforma'),
                    PillSegment('TRUCK', 'Báscula camionera'),
                  ],
                ),
              ),
              LabeledInput(
                label: 'Unidad',
                padding: const EdgeInsets.only(bottom: 16),
                child: SegmentedPills<String>(
                  selected: unit,
                  onSelect: (value) => changed(() => unit = value),
                  segments: [for (final u in _units) PillSegment(u, u)],
                ),
              ),
              LabeledInput(
                label:
                    'Clase de exactitud (opcional; tócala de nuevo para quitarla)',
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedPills<String>(
                  selected: accuracyClass,
                  onSelect: (value) => changed(
                    () => accuracyClass = accuracyClass == value ? '' : value,
                  ),
                  segments: [for (final c in _classes) PillSegment(c, c)],
                ),
              ),
            ],
          ),
        ),
      ),
      for (var index = 0; index < ranges.length; index++)
        Padding(
          key: ObjectKey(ranges[index]),
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rango ${index + 1}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (index > 0 && !locked)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.fail,
                      ),
                      onPressed: () {
                        final removed = ranges[index];
                        changed(() => ranges.removeAt(index));
                        // Sus campos siguen montados hasta el próximo frame.
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => removed.dispose(),
                        );
                      },
                      child: const Text('Quitar rango'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _decimal(
                ranges[index].capacity,
                'Capacidad máxima ($unit)',
                readOnly: locked,
                validator: () => _capacityError(index),
              ),
              _decimal(
                ranges[index].division,
                'División de escala d ($unit)',
                readOnly: locked,
                validator: () => _divisionError(index),
              ),
              _decimal(
                ranges[index].interval,
                'Intervalo de verificación e ($unit, opcional)',
                readOnly: locked,
                validator: () => _intervalError(index),
              ),
            ],
          ),
        ),
      if (!locked && ranges.length < _maxRanges)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => changed(() => ranges.add(_RangeInput())),
            icon: const Icon(Icons.add),
            label: const Text('Agregar rango'),
          ),
        ),
    ];
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    required int max,
    bool required = false,
  }) => LabeledInput(
    label: label,
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      readOnly: frozen,
      maxLength: max,
      validator: (value) => required && (value ?? '').trim().isEmpty
          ? 'Completa este campo.'
          : null,
    ),
  );

  Widget _decimal(
    TextEditingController controller,
    String label, {
    required bool readOnly,
    required String? Function() validator,
  }) => LabeledInput(
    label: label,
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (_) => validator(),
    ),
  );
}

/// Lo que se autoriza a entregar a Métrica: identificación, área y rangos.
class EquipmentRegistrationPreview extends StatelessWidget {
  const EquipmentRegistrationPreview({required this.snapshot, super.key});
  final Json snapshot;

  @override
  Widget build(BuildContext context) {
    final customer = object(snapshot['customer']);
    final technical = object(snapshot['technical']);
    final unit = valueLabel(technical['unit']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailField(
          'Balanza / planta',
          '${valueLabel(snapshot['code'])} · ${valueLabel(snapshot['plantName'] ?? snapshot['plantCode'])}',
        ),
        DetailField(
          'Marca y modelo',
          '${valueLabel(customer['marca'])} · ${valueLabel(customer['modelo'])}',
        ),
        DetailField('Serie', customer['serie']),
        DetailField('Ubicación', customer['ubicacion']),
        DetailField('Área', snapshot['area']),
        DetailField('Tipo', technical['type']),
        DetailField('Clase', technical['class']),
        for (final range in objects(technical['ranges']))
          DetailField(
            'Rango ${range['number']}',
            registeredRangeLabel(range, unit),
          ),
      ],
    );
  }
}

/// "150 kg · d 0,02 kg · e 0,02 kg", con decimales exactos y coma.
String registeredRangeLabel(Json range, String unit) {
  String value(Object? raw) => MeasurementFormat.display(raw?.toString() ?? '');
  final interval = value(range['interval']);
  return '${value(range['capacity'])} $unit · d ${value(range['division'])} $unit'
      '${interval.isEmpty ? '' : ' · e $interval $unit'}';
}

class ShareEquipmentRegistration extends StatelessWidget {
  const ShareEquipmentRegistration({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;

  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Enviar balanza a Métrica',
    load: () =>
        customerRead(session, 'registration-preview', {'id': equipmentId}),
    builder: (preview) => CustomerForm(
      session: session,
      title: 'Enviar balanza a Métrica',
      action: 'registration.share',
      notice: preview['notice'] as String,
      preview: EquipmentRegistrationPreview(
        snapshot: object(preview['snapshot']),
      ),
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
          'Autorizo enviar únicamente los datos mostrados de esta balanza.',
          kind: 'bool',
        ),
      ],
      submitLabel: 'Autorizar y enviar',
    ),
  );
}

/// Baja de una balanza registrada. Devuelve `true` si se confirmó.
class RetireRegisteredEquipment extends StatelessWidget {
  const RetireRegisteredEquipment({
    required this.session,
    required this.equipment,
    super.key,
  });
  final MobileSession session;
  final Json equipment;

  @override
  Widget build(BuildContext context) => CustomerForm(
    session: session,
    title: 'Dar de baja la balanza',
    action: 'equipment.retire',
    notice:
        'La balanza deja de estar disponible para capturar y verificar. Su historial se conserva. Para volver a usarla habrá que registrarla de nuevo.',
    preview: DetailField('Balanza', customerEquipmentCode(equipment)),
    initial: {
      'id': equipment['id'],
      'version': '${equipment['source_version']}',
      'confirmed': false,
    },
    fields: const [
      CustomerField('reason', 'Motivo de la baja', max: 2000),
      CustomerField(
        'confirmed',
        'Entiendo que la balanza dejará de estar disponible',
        kind: 'bool',
      ),
    ],
    payload: (values) => {
      'id': values['id'],
      'version': values['version'],
      'reason': values['reason'],
    },
    submitLabel: 'Dar de baja',
  );
}

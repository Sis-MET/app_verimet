import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

const _frequencyOptions = <String, String>{
  '7': 'Semanal',
  '30': 'Mensual',
  '90': 'Trimestral',
  '180': 'Semestral',
  '365': 'Anual',
};

class _CheckConfiguration {
  _CheckConfiguration({
    required this.type,
    required this.enabled,
    required this.frequencyDays,
    required this.tolerance,
  });

  final String type;
  bool enabled;
  String frequencyDays;
  final TextEditingController tolerance;

  void dispose() {
    tolerance.dispose();
  }
}

/// Configura una sola rutina por balanza. El versionado, la publicación y la
/// asignación continúan existiendo en Supabase, pero son una operación atómica
/// y no forman parte del trabajo del cliente.
class EquipmentCheckConfigurationScreen extends StatefulWidget {
  const EquipmentCheckConfigurationScreen({
    required this.session,
    required this.bundle,
    super.key,
  });

  final MobileSession session;
  final Json bundle;

  @override
  State<EquipmentCheckConfigurationScreen> createState() =>
      _EquipmentCheckConfigurationScreenState();
}

class _EquipmentCheckConfigurationScreenState
    extends State<EquipmentCheckConfigurationScreen> {
  static final _decimal = RegExp(r'^(0|[1-9]\d{0,9})(\.\d{1,9})?$');
  final form = GlobalKey<FormState>();
  final pages = PageController();
  late final Json equipment = object(widget.bundle['equipment']);
  late final List<Json> ranges = objects(widget.bundle['ranges']);
  late final Json? current = widget.bundle['plan'] == null
      ? null
      : object(widget.bundle['plan']);
  late final bool truck = _isTruck(equipment);
  late final Json largestRange = _largestRange(ranges);
  late final String unit = valueLabel(largestRange['unidad']);
  late final double maximum =
      double.tryParse(largestRange['capacidad_max']?.toString() ?? '') ?? 0;
  late final Map<String, _CheckConfiguration> checks = _initialChecks();

  int step = 0;
  bool busy = false;
  bool dirty = false;
  bool leaving = false;
  String? error;
  String requestId = const Uuid().v4();
  Json? pending;

  static bool _isTruck(Json equipment) {
    final description = [
      equipment['instrumento'],
      equipment['tipo_instrumento'],
      equipment['tipo_balanza'],
      equipment['plataforma'],
    ].join(' ').toLowerCase();
    return description.contains('camion') ||
        description.contains('camión') ||
        description.contains('vehicular') ||
        description.contains('truck');
  }

  static Json _largestRange(List<Json> ranges) {
    if (ranges.isEmpty) return <String, dynamic>{};
    return ranges.reduce((left, right) {
      final a = double.tryParse(left['capacidad_max']?.toString() ?? '') ?? 0;
      final b = double.tryParse(right['capacidad_max']?.toString() ?? '') ?? 0;
      return b > a ? right : left;
    });
  }

  Map<String, _CheckConfiguration> _initialChecks() {
    final existing = <String, Json>{
      for (final test in objects(current?['tests']))
        test['type'] as String: test,
    };
    _CheckConfiguration make(String type) {
      final test = existing[type];
      final points = objects(test?['points']);
      final tolerances = points
          .map((point) => point['tolerance']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
      return _CheckConfiguration(
        type: type,
        enabled: test != null || current == null,
        frequencyDays: test?['frequencyDays']?.toString() ?? '30',
        tolerance: TextEditingController(
          text: tolerances.length == 1 ? tolerances.single : '',
        ),
      );
    }

    return {
      for (final type in const ['linearity', 'repeatability', 'eccentricity'])
        type: make(type),
    };
  }

  @override
  void dispose() {
    pages.dispose();
    for (final check in checks.values) {
      check.dispose();
    }
    super.dispose();
  }

  void changed() {
    if (!dirty || pending != null) {
      setState(() {
        dirty = true;
        pending = null;
        requestId = const Uuid().v4();
      });
    }
  }

  String label(String type) => switch (type) {
    'linearity' => 'Linealidad',
    'repeatability' => 'Repetibilidad',
    'eccentricity' => truck ? 'Desplazamiento de carga' : 'Excentricidad',
    _ => testLabel(type),
  };

  String description(String type) => switch (type) {
    'linearity' => 'Compara la indicación en diferentes cargas.',
    'repeatability' => 'Repite una misma carga y evalúa su dispersión.',
    'eccentricity' =>
      truck
          ? 'Compara inicio, centro y final de la plataforma.'
          : 'Compara el centro y las posiciones de la plataforma.',
    _ => '',
  };

  String? decimalValidator(String? value, {bool zeroAllowed = false}) {
    final text = value?.trim() ?? '';
    if (!_decimal.hasMatch(text)) return 'Usa punto y hasta 9 decimales.';
    final number = double.tryParse(text);
    if (number == null || (!zeroAllowed && number <= 0)) {
      return 'Debe ser mayor que cero.';
    }
    if (number > maximum) return 'No puede superar $maximum $unit.';
    return null;
  }

  bool _selectedChecksAreValid() {
    if (checks.values.any((check) => check.enabled)) return true;
    setState(() => error = 'Selecciona al menos una comprobación.');
    return false;
  }

  Future<void> next() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (step == 0 && !_selectedChecksAreValid()) return;
    setState(() {
      error = null;
      step++;
    });
    await pages.animateToPage(
      step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> previous() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (step == 0) return;
    setState(() {
      error = null;
      step--;
    });
    await pages.animateToPage(
      step,
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
    );
  }

  Json _payload() => {
    'tests': [
      for (final check in checks.values.where((value) => value.enabled))
        {
          'type': check.type,
          'frequencyDays': check.frequencyDays,
          'tolerance': check.tolerance.text.trim(),
        },
    ],
  };

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (busy || !_selectedChecksAreValid()) return;
    if (!form.currentState!.validate()) {
      setState(() => error = 'Revisa los límites antes de guardar.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= object(jsonDecode(jsonEncode(_payload())));
      await widget.session.api.rpc('ivmet_customer_configure_checks', {
        'equipment_id': equipment['id'],
        'configuration': pending,
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
        title: const Text('¿Salir de la configuración?'),
        content: Text(
          pending != null
              ? 'El guardado todavía no está confirmado. Puedes reintentarlo sin duplicar la configuración.'
              : 'Se perderán los cambios que no hayas guardado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar configurando'),
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
    canPop: leaving || (!busy && !dirty && pending == null && step == 0),
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (step > 0) {
        previous();
      } else {
        askLeave();
      }
    },
    child: OnlinePage(
      title: 'Configurar comprobaciones',
      child: Form(
        key: form,
        child: Column(
          children: [
            LinearProgressIndicator(value: (step + 1) / 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(switch (step) {
                      0 => '1. Pruebas y periodicidad',
                      _ => '2. Errores permisibles y confirmación',
                    }, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('${step + 1} de 2'),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: error == null
                  ? const SizedBox.shrink(key: ValueKey('no-error'))
                  : Padding(
                      key: ValueKey(error),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Notice(error!, icon: Icons.error_outline),
                    ),
            ),
            Expanded(
              child: PageView(
                controller: pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [_testsStep(), _limitsStep()],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : previous,
                        child: const Text('Atrás'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : step < 1
                          ? next
                          : save,
                      child: Text(
                        busy
                            ? 'Guardando…'
                            : step < 1
                            ? 'Continuar'
                            : pending != null
                            ? 'Reintentar guardado'
                            : current == null
                            ? 'Activar configuración'
                            : 'Guardar nueva versión',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _testsStep() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      Text(
        valueLabel(equipment['cod_metrica']),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text('Capacidad de referencia: ${largestRange['capacidad_max']} $unit'),
      const Notice(
        'Selecciona las comprobaciones que necesita tu proceso. Puedes utilizar una periodicidad diferente para cada una.',
      ),
      for (final check in checks.values) _checkSelector(check),
    ],
  );

  Widget _checkSelector(_CheckConfiguration check) {
    final options = Map<String, String>.of(_frequencyOptions);
    options.putIfAbsent(
      check.frequencyDays,
      () => 'Cada ${check.frequencyDays} días',
    );
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: check.enabled,
            title: Text(label(check.type)),
            subtitle: Text(description(check.type)),
            onChanged: (value) {
              setState(() => check.enabled = value ?? false);
              changed();
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: !check.enabled
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('${check.type}-${check.frequencyDays}'),
                      initialValue: check.frequencyDays,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Periodicidad',
                      ),
                      items: [
                        for (final option in options.entries)
                          DropdownMenuItem(
                            value: option.key,
                            child: Text(option.value),
                          ),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('Personalizada…'),
                        ),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        final selected = value == 'custom'
                            ? await _customFrequency(check.frequencyDays)
                            : value;
                        if (selected == null || !mounted) return;
                        setState(() => check.frequencyDays = selected);
                        changed();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<String?> _customFrequency(String current) async {
    final controller = TextEditingController(text: current);
    final dialogForm = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Periodicidad personalizada'),
        content: Form(
          key: dialogForm,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Días entre pruebas'),
            validator: (value) {
              final days = int.tryParse(value ?? '');
              return days == null || days < 1 || days > 3650
                  ? 'Ingresa entre 1 y 3650 días.'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogForm.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Widget _limitsStep() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      const Notice(
        'El límite pertenece al proceso interno de tu empresa. IvMET aplicará comparación directa y calculará el resultado en Supabase.',
        icon: Icons.rule_outlined,
      ),
      for (final check in checks.values.where((value) => value.enabled))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label(check.type),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Periodicidad: ${_frequencyOptions[check.frequencyDays] ?? 'cada ${check.frequencyDays} días'}',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: check.tolerance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: check.type == 'linearity'
                        ? 'Error permisible de las indicaciones ($unit)'
                        : 'Error permisible ($unit)',
                    helperText:
                        'Se aplicará a todos los puntos de esta prueba.',
                  ),
                  validator: (value) => check.enabled
                      ? decimalValidator(value, zeroAllowed: false)
                      : null,
                  onChanged: (_) => changed(),
                ),
              ],
            ),
          ),
        ),
      Notice(
        current == null
            ? 'Al activar, la configuración quedará disponible inmediatamente para esta balanza.'
            : 'Al guardar, IvMET activará una nueva versión sin modificar las comprobaciones anteriores.',
        icon: Icons.verified_outlined,
      ),
    ],
  );
}

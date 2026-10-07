import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/wizard_chrome.dart';

import 'check_schedule.dart';
import 'measurement_suggestions.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'schedule_editor.dart';

class _CheckConfiguration {
  _CheckConfiguration({
    required this.type,
    required this.enabled,
    required this.schedule,
    required this.tolerance,
  });

  final String type;
  bool enabled;
  CheckSchedule schedule;
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
  final scaffold = GlobalKey<ScaffoldState>();
  static const _stepTitles = ['Pruebas y periodicidad', 'Errores permisibles'];
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
    // La vigencia trae la regla guardada; las configuraciones anteriores solo
    // tienen dias entre pruebas.
    final rules = <String, Json>{
      for (final due in objects(widget.bundle['schedule']))
        if (due['rule'] is Map) due['type'] as String: object(due['rule']),
    };
    CheckSchedule scheduleOf(String type, Json? test) {
      final rule = rules[type];
      if (rule != null) return CheckSchedule.fromJson(rule);
      final days = int.tryParse('${test?['frequencyDays'] ?? ''}');
      if (days != null) return CheckSchedule.legacyDays(days);
      return CheckSchedule.preset(SchedulePreset.monthly, DateTime.now());
    }

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
        schedule: scheduleOf(type, test),
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
    setState(() => error = 'Selecciona al menos una verificación.');
    return false;
  }

  void _goTo(int target) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      error = null;
      step = target.clamp(0, _stepTitles.length - 1);
    });
  }

  void next() {
    if (step == 0 && !_selectedChecksAreValid()) {
      showWizardMessage(context, 'Selecciona al menos una verificación.');
      return;
    }
    _goTo(step + 1);
  }

  void previous() {
    if (step > 0) _goTo(step - 1);
  }

  /// Atras del sistema: cierra el panel, retrocede un paso y en el primero
  /// pregunta antes de perder lo que no se guardo.
  void _onSystemBack() {
    if (closeWizardDrawer(scaffold)) return;
    if (step > 0) {
      previous();
    } else {
      unawaited(askLeave());
    }
  }

  List<WizardStep> _wizardSteps() {
    final enabled = checks.values.where((check) => check.enabled).toList();
    final limits = enabled
        .where((check) => decimalValidator(check.tolerance.text) == null)
        .length;
    return [
      WizardStep(
        title: _stepTitles[0],
        detail: enabled.isEmpty
            ? 'Ninguna prueba elegida'
            : enabled.map((check) => label(check.type)).join(' · '),
        progress: enabled.isNotEmpty
            ? WizardProgress.complete
            : step > 0
            ? WizardProgress.review
            : WizardProgress.pending,
      ),
      WizardStep(
        title: _stepTitles[1],
        detail: enabled.isEmpty
            ? 'Elige antes las pruebas'
            : '$limits de ${enabled.length} '
                  '${enabled.length == 1 ? 'límite' : 'límites'}',
        progress: enabled.isNotEmpty && limits == enabled.length
            ? WizardProgress.complete
            : WizardProgress.pending,
      ),
    ];
  }

  Json _payload() => {
    'tests': [
      for (final check in checks.values.where((value) => value.enabled))
        {
          'type': check.type,
          'schedule': check.schedule.toJson(),
          'tolerance': check.tolerance.text.trim(),
        },
    ],
  };

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (busy || !_selectedChecksAreValid()) return;
    if (!form.currentState!.validate()) {
      revealFirstFormError(
        context,
        form,
        message: 'Revisa los límites antes de guardar.',
      );
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
      if (!didPop) _onSystemBack();
    },
    child: WizardScaffold(
      scaffoldKey: scaffold,
      kicker: 'Configurar verificaciones',
      title: current == null
          ? 'Configurar verificaciones'
          : 'Actualizar verificaciones',
      drawerTitle: valueLabel(
        equipment['cod_interno'] ?? equipment['cod_metrica'],
      ),
      steps: _wizardSteps(),
      current: step,
      onSelectStep: _goTo,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          icon: const Icon(Icons.more_vert),
          onSelected: (_) {
            if (dirty || pending != null) {
              unawaited(askLeave());
            } else {
              Navigator.of(context).pop();
            }
          },
          itemBuilder: (context) => [
            wizardMenuItem(
              'leave',
              Icons.logout,
              dirty || pending != null ? 'Salir sin guardar' : 'Salir',
              enabled: !busy,
            ),
          ],
        ),
      ],
      body: Form(
        key: form,
        child: KeyedSubtree(
          key: ValueKey(step),
          child: step == 0 ? _testsStep() : _limitsStep(),
        ),
      ),
      pill: WizardNavPill(
        label: busy
            ? 'Guardando…'
            : step == 0
            ? 'Continuar'
            : pending != null
            ? 'Reintentar guardado'
            : current == null
            ? 'Activar configuración'
            : 'Guardar nueva versión',
        icon: step == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded,
        onBack: step > 0 && !busy ? previous : null,
        onNext: busy
            ? null
            : step == 0
            ? next
            : save,
      ),
    ),
  );

  Widget _testsStep() => ListView(
    padding: const EdgeInsets.fromLTRB(
      20,
      18,
      20,
      WizardNavPill.contentPadding,
    ),
    children: [
      if (error != null) Notice(error!, icon: Icons.error_outline),
      WizardStepHeading(
        title: _stepTitles[0],
        caption:
            '${valueLabel(equipment['cod_interno'] ?? equipment['cod_metrica'])} · '
            'capacidad de referencia ${rangeCapacityLabel(largestRange)} $unit. '
            'Elige las pruebas que necesita tu proceso y cuándo tocan.',
      ),
      const SizedBox(height: 6),
      for (final check in checks.values) _checkSelector(check),
    ],
  );

  Future<void> _editSchedule(_CheckConfiguration check) async {
    final enabled = checks.values.where((value) => value.enabled).toList();
    final choice = await showScheduleEditor(
      context,
      initial: check.schedule,
      testLabel: label(check.type),
      offerApplyToAll: enabled.length > 1,
    );
    if (choice == null || !mounted) return;
    setState(() {
      for (final target in choice.applyToAll ? enabled : [check]) {
        target.schedule = choice.schedule;
      }
    });
    changed();
  }

  Widget _checkSelector(_CheckConfiguration check) {
    final palette = IndustryPalette.of(context);
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
                : InkWell(
                    key: ValueKey('schedule-${check.type}'),
                    onTap: () => _editSchedule(check),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 10, 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_repeat_outlined,
                            size: 20,
                            color: palette.accentInk,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PERIODICIDAD',
                                  style: AppTextStyles.caption(
                                    context,
                                    size: 10.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  check.schedule.summary,
                                  style: AppTextStyles.figure(
                                    context,
                                    size: 17,
                                  ),
                                ),
                                Text(
                                  check.schedule.warningLabel,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: palette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Cambiar',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.accentInk,
                            ),
                          ),
                          Icon(Icons.chevron_right, color: palette.accentInk),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _limitsStep() => ListView(
    padding: const EdgeInsets.fromLTRB(
      20,
      18,
      20,
      WizardNavPill.contentPadding,
    ),
    children: [
      if (error != null) Notice(error!, icon: Icons.error_outline),
      WizardStepHeading(
        title: _stepTitles[1],
        caption:
            'El límite pertenece al proceso interno de tu empresa. IvMET compara directamente y calcula el resultado en Supabase.',
      ),
      if (checks.values.every((check) => !check.enabled))
        const Notice('Elige antes al menos una prueba en el paso 1.'),
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
                Text('Periodicidad: ${check.schedule.summary.toLowerCase()}'),
                const SizedBox(height: 12),
                LabeledInput(
                  label: check.type == 'linearity'
                      ? 'Error permisible de las indicaciones ($unit)'
                      : 'Error permisible ($unit)',
                  child: TextFormField(
                    controller: check.tolerance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      helperText:
                          'Se aplicará a todos los puntos de esta prueba.',
                    ),
                    validator: (value) => check.enabled
                        ? decimalValidator(value, zeroAllowed: false)
                        : null,
                    // Tambien redibuja la linea de progreso.
                    onChanged: (_) {
                      changed();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      Notice(
        current == null
            ? 'Al activar, la configuración quedará disponible inmediatamente para esta balanza.'
            : 'Al guardar, IvMET activará una nueva versión sin modificar las verificaciones anteriores.',
        icon: Icons.verified_outlined,
      ),
    ],
  );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/blueprint_card.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/tile_grid.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

String normalizedDecimal(String value) => value.trim().replaceAll(',', '.');
String? decimalError(
  String? value, {
  bool environment = false,
  bool humidity = false,
}) {
  final text = normalizedDecimal(value ?? '');
  if (text.isEmpty) return null; // Un borrador puede estar incompleto.
  final pattern = environment
      ? RegExp(r'^-?[0-9]{1,6}(\.[0-9]{1,3})?$')
      : RegExp(r'^-?[0-9]{1,10}(\.[0-9]{1,9})?$');
  if (!pattern.hasMatch(text)) {
    return environment
        ? 'Usa hasta 3 decimales.'
        : 'Usa hasta 9 decimales, sin miles.';
  }
  // Solo condiciones ambientales, nunca cargas o indicaciones metrológicas.
  if (humidity && (num.parse(text) < 0 || num.parse(text) > 100)) {
    return 'Debe estar entre 0 y 100.';
  }
  return null;
}

class DraftScreen extends StatefulWidget {
  const DraftScreen({
    required this.session,
    required this.bundle,
    this.draft,
    super.key,
  });
  final MobileSession session;
  final Json bundle;
  final Json? draft;
  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _TrialInput {
  _TrialInput(this.plan, Json? saved)
    : omitted = saved?['omitted'] == true,
      reason = TextEditingController(text: saved?['reason'] as String? ?? '') {
    final previous = {
      for (final r in objects(saved?['readings'])) r['pointId']: r,
    };
    for (final point in objects(plan['points'])) {
      final id = point['id'] as String;
      readings[id] = (
        TextEditingController(
          text: previous[id]?['indication'] as String? ?? '',
        ),
        TextEditingController(text: previous[id]?['zero'] as String? ?? ''),
      );
    }
    completed =
        saved != null &&
        (omitted
            ? reason.text.trim().isNotEmpty
            : readings.values.every(
                (reading) => reading.$1.text.trim().isNotEmpty,
              ));
  }
  final Json plan;
  bool omitted;
  late bool completed;
  final TextEditingController reason;
  final Map<String, (TextEditingController, TextEditingController)> readings =
      {};
  Json get payload => {
    'id': plan['id'],
    'omitted': omitted,
    'reason': omitted ? reason.text.trim() : '',
    'readings': omitted
        ? <Json>[]
        : [
            for (final entry in readings.entries)
              {
                'pointId': entry.key,
                'indication': normalizedDecimal(entry.value.$1.text),
                'zero': normalizedDecimal(entry.value.$2.text),
              },
          ],
  };
  void dispose() {
    reason.dispose();
    for (final pair in readings.values) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
  }
}

class _DraftScreenState extends State<DraftScreen> {
  final form = GlobalKey<FormState>();
  final uuid = const Uuid();
  late final Json plan = object(widget.bundle['plan']);
  late final Json equipment = object(widget.bundle['equipment']);
  late final Json previous = widget.draft == null
      ? {}
      : object(widget.draft!['payload']);
  late final String requestId =
      widget.draft?['request_uuid'] as String? ?? uuid.v4();
  late String? draftId = widget.draft?['id'] as String?;
  late String version = widget.draft?['version']?.toString() ?? '0';
  late final List<_TrialInput> trials = objects(plan['tests'])
      .map(
        (p) => _TrialInput(
          p,
          objects(
            previous['tests'],
          ).where((t) => t['id'] == p['id']).firstOrNull,
        ),
      )
      .toList();
  late final temperature = TextEditingController(
    text: previous['temperature'] as String? ?? '',
  );
  late final humidity = TextEditingController(
    text: previous['humidity'] as String? ?? '',
  );
  late final observations = TextEditingController(
    text: previous['observations'] as String? ?? '',
  );
  late final Set<String> certificates = Set<String>.from(
    previous['certificates'] as List? ?? [],
  );
  String? attemptHash;
  String? saveId;
  String? finalizationId;
  String? error;
  String? savedAt;
  bool busy = false;
  bool dirty = false;
  @override
  void dispose() {
    for (final trial in trials) {
      trial.dispose();
    }
    temperature.dispose();
    humidity.dispose();
    observations.dispose();
    super.dispose();
  }

  void changed() {
    if (!dirty) setState(() => dirty = true);
  }

  bool get allTrialsComplete =>
      trials.isNotEmpty && trials.every((trial) => trial.completed);

  Future<void> openTrial(_TrialInput trial) async {
    await openPage<bool>(
      context,
      _TrialCaptureScreen(trial: trial, onChanged: changed),
    );
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final payload = {
      'tests': trials.map((t) => t.payload).toList(),
      'certificates': certificates.toList()..sort(),
      'temperature': normalizedDecimal(temperature.text),
      'humidity': normalizedDecimal(humidity.text),
      'observations': observations.text.trim(),
    };
    final hash = jsonEncode(payload);
    // Si se perdió la respuesta, reintentar exactamente lo mismo reutiliza UUID.
    if (attemptHash != hash) {
      saveId = uuid.v4();
      attemptHash = hash;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.api.rpc('ivmet_mobile_save_draft', {
        'request_id': requestId,
        'equipment_id': equipment['id'],
        'version_id': plan['id'],
        'expected_version': version,
        'content': payload,
        'save_id': saveId,
      });
      if (!mounted) return;
      setState(() {
        draftId = result['id'] as String;
        version = result['version'].toString();
        savedAt = result['savedAt'].toString();
        dirty = false;
        finalizationId = null;
      });
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure
              ? failure.message
              : 'No se pudo guardar el borrador.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? get completionIssue {
    if (!allTrialsComplete) {
      return 'Finaliza cada ficha de prueba antes de continuar.';
    }
    var executed = 0;
    for (final trial in trials) {
      if (trial.omitted) {
        if (trial.reason.text.trim().isEmpty) {
          return 'Justifica todas las pruebas omitidas.';
        }
        continue;
      }
      executed++;
      if (trial.readings.values.any(
        (reading) => reading.$1.text.trim().isEmpty,
      )) {
        return 'Completa todas las indicaciones de las pruebas ejecutadas.';
      }
    }
    if (executed == 0) return 'Debes ejecutar al menos una prueba.';
    return null;
  }

  Future<void> finalize() async {
    if (busy || dirty || draftId == null || !form.currentState!.validate()) {
      return;
    }
    final issue = completionIssue;
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar comprobación interna'),
        content: const Text(
          'Supabase calculará nuevamente errores, métricas y regla de decisión. El resultado será privado e inmutable. No equivale a una calibración acreditada ni a una verificación legal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    finalizationId ??= uuid.v4();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.api
          .rpc('ivmet_mobile_finalize_draft', {
            'draft_id': draftId,
            'expected_version': version,
            'finalize_id': finalizationId,
            'app_version_value': 'ivmet-flutter-v1',
            'device_id_value': '',
          });
      if (!mounted) return;
      final verdict = verdictLabel(result['verdict']);
      final traceability = result['traceability'] == 'traceable'
          ? 'trazable'
          : 'sin trazabilidad vigente';
      setState(() => busy = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Resultado guardado'),
          content: Text(
            '$verdict · $traceability. La comprobación permanece privada; una alerta solo se compartirá si el jefe de calidad lo autoriza.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ver historial'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.maybePop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure
              ? failure.message
              : 'No se pudo finalizar la comprobación.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || busy) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambios sin guardar'),
          content: const Text(
            'Los cambios de esta pantalla aún no están en Supabase. ¿Quieres salir sin guardarlos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir capturando'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir sin guardar'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: OnlinePage(
      title: 'Comprobación · ${customerEquipmentCode(equipment)}',
      child: Form(
        key: form,
        onChanged: changed,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Notice(
              plan['notice']?.toString() ??
                  'Comprobación metrológica interna y privada. No se enviará a Métrica ni cambiará el estado de la balanza.',
              icon: Icons.shield_outlined,
            ),
            Text(
              'Configuración activa · versión interna ${plan['version']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: temperature,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Temperatura (°C)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (v) => decimalError(v, environment: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: humidity,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Humedad relativa (%)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  decimalError(v, environment: true, humidity: true),
            ),
            const SizedBox(height: 20),
            Text(
              'Patrones y certificados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (objects(widget.bundle['patterns']).isEmpty)
              const Notice(
                'No hay patrones disponibles para esta planta. El borrador puede quedar incompleto.',
              ),
            for (final pattern in objects(widget.bundle['patterns']))
              ExpansionTile(
                title: Text('${pattern['code']} · ${pattern['description']}'),
                children: [
                  for (final cert in objects(pattern['certificates']))
                    CheckboxListTile(
                      title: Text(valueLabel(cert['number'])),
                      subtitle: Text(
                        '${cert['laboratory']} · vence ${dateLabel(cert['expiresOn'])}${cert['expired'] == true ? ' · VENCIDO' : ''}',
                      ),
                      value: certificates.contains(cert['id']),
                      onChanged: busy
                          ? null
                          : (checked) => setState(() {
                              for (final c in objects(
                                pattern['certificates'],
                              )) {
                                certificates.remove(c['id']);
                              }
                              if (checked == true) {
                                certificates.add(cert['id'] as String);
                              }
                              dirty = true;
                            }),
                    ),
                ],
              ),
            const Notice(
              'Un certificado vencido no aporta trazabilidad. Su selección se conserva en el borrador; no se emitirá un resultado válido por ello.',
            ),
            const SectionLabel('Pruebas de comprobación'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${trials.where((trial) => trial.completed).length} de ${trials.length} completadas',
                style: AppTextStyles.caption(context, size: 12),
              ),
            ),
            TileGrid(
              minTileHeight: 128,
              cells: [
                for (final trial in trials)
                  TileCell(
                    _TrialTile(
                      trial: trial,
                      onTap: busy ? null : () => openTrial(trial),
                    ),
                  ),
              ],
            ),
            if (!allTrialsComplete)
              const Notice(
                'Abre cada ficha, registra sus datos y pulsa Finalizar prueba. Podrás volver a entrar para revisarla.',
                icon: Icons.touch_app_outlined,
              ),
            TextFormField(
              controller: observations,
              enabled: !busy,
              maxLength: 4000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observaciones'),
            ),
            if (error != null) Notice(error!, icon: Icons.error_outline),
            if (savedAt != null)
              Notice(
                'Guardado en Supabase · versión $version${dirty ? ' · hay cambios pendientes' : ''}',
                icon: Icons.cloud_done_outlined,
              ),
            if (allTrialsComplete) ...[
              FilledButton.icon(
                onPressed: busy ? null : save,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(busy ? 'Guardando…' : 'Guardar borrador privado'),
              ),
              const SizedBox(height: 8),
              if (plan['finalizationEnabled'] == true)
                FilledButton.icon(
                  onPressed: busy || dirty || draftId == null ? null : finalize,
                  icon: const Icon(Icons.task_alt),
                  label: Text(
                    dirty || draftId == null
                        ? 'Guarda antes de finalizar'
                        : 'Finalizar comprobación interna',
                  ),
                )
              else
                const OutlinedButton(
                  onPressed: null,
                  child: Text('Este plan aún no admite finalización'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Ficha resumida de una prueba. Conserva el lenguaje de módulos del Inicio.
class _TrialTile extends StatelessWidget {
  const _TrialTile({required this.trial, required this.onTap});
  final _TrialInput trial;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final completed = trial.completed;
    final ink = completed ? palette.successInk : palette.text;
    final points = objects(trial.plan['points']).length;

    return BlueprintCard(
      onTap: onTap,
      background: completed ? palette.successSurface : null,
      markColor: completed ? palette.success : null,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                completed ? Icons.check_circle : Icons.science_outlined,
                size: 25,
                color: completed ? palette.success : palette.accentInk,
              ),
              if (completed) ...[
                const Spacer(),
                Text(
                  'COMPLETADA',
                  style: AppTextStyles.caption(
                    context,
                    size: 10,
                  ).copyWith(color: palette.successInk),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                testLabel(trial.plan['type']),
                style: AppTextStyles.figure(context, size: 18, color: ink),
              ),
              const SizedBox(height: 3),
              Text(
                completed
                    ? 'Pulsa para revisar los datos'
                    : '$points ${points == 1 ? 'punto' : 'puntos'} · ${trial.plan['unit']}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: completed ? palette.successInk : palette.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Captura enfocada: al entrar solo se ve una prueba y sus puntos.
class _TrialCaptureScreen extends StatefulWidget {
  const _TrialCaptureScreen({required this.trial, required this.onChanged});
  final _TrialInput trial;
  final VoidCallback onChanged;

  @override
  State<_TrialCaptureScreen> createState() => _TrialCaptureScreenState();
}

class _TrialCaptureScreenState extends State<_TrialCaptureScreen> {
  final form = GlobalKey<FormState>();

  void changed() {
    widget.trial.completed = false;
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void finish() {
    if (!form.currentState!.validate()) return;
    widget.trial.completed = true;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final trial = widget.trial;
    final unit = valueLabel(trial.plan['unit']);

    return OnlinePage(
      title: testLabel(trial.plan['type']),
      child: Form(
        key: form,
        onChanged: changed,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (trial.completed)
              const Notice(
                'Esta prueba está completada. Puedes revisar los valores y finalizarla nuevamente si haces cambios.',
                icon: Icons.check_circle_outline,
              )
            else
              Notice(
                '${objects(trial.plan['points']).length} puntos · $unit · frecuencia ${trial.plan['frequencyDays']} días',
                icon: Icons.science_outlined,
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Omitir esta prueba'),
              subtitle: const Text('Requiere indicar el motivo.'),
              value: trial.omitted,
              onChanged: (value) {
                trial.omitted = value;
                changed();
              },
            ),
            if (trial.omitted)
              TextFormField(
                controller: trial.reason,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo de omisión',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Debes justificar la omisión.'
                    : null,
              )
            else
              for (final point in objects(trial.plan['points'])) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: BlueprintCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${point['order']}. ${point['label']}',
                          style: AppTextStyles.figure(context, size: 17),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Carga ${point['load']} $unit · tolerancia ${point['tolerance']}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: IndustryPalette.of(context).muted,
                          ),
                        ),
                        if (point['position'] != null ||
                            point['direction'] != null)
                          Text(
                            '${point['position'] ?? ''} ${point['direction'] ?? ''} · grupo ${point['group']}',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: IndustryPalette.of(context).muted,
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: trial.readings[point['id']]!.$1,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Indicación',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Ingresa la indicación.';
                            }
                            return decimalError(value);
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: trial.readings[point['id']]!.$2,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Retorno a cero (opcional)',
                          ),
                          validator: decimalError,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: finish,
              icon: const Icon(Icons.check),
              label: const Text('Finalizar prueba'),
            ),
          ],
        ),
      ),
    );
  }
}

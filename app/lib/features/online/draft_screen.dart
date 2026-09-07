import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import 'draft_controller.dart';
import 'draft_steps.dart';
import 'history_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

export 'draft_controller.dart' show decimalError, normalizedDecimal;

/// Revalidate access before exposing a locally recovered equipment snapshot.
class RecoveredDraftScreen extends StatelessWidget {
  const RecoveredDraftScreen({
    required this.session,
    required this.snapshot,
    super.key,
  });
  final MobileSession session;
  final Json snapshot;
  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Recuperar comprobación',
    load: () => session.api.read('equipment', {
      'equipmentId': object(object(snapshot['bundle'])['equipment'])['id'],
    }),
    builder: (_) => DraftScreen(
      session: session,
      bundle: object(snapshot['bundle']),
      recovered: snapshot,
    ),
  );
}

class DraftScreen extends StatefulWidget {
  const DraftScreen({
    required this.session,
    required this.bundle,
    this.draft,
    this.recovered,
    super.key,
  });
  final MobileSession session;
  final Json bundle;
  final Json? draft;
  final Json? recovered;
  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> {
  late final Future<DraftController> future = _load();
  Future<DraftController> _load() async {
    final local = await widget.session.recovery.list(
      widget.session.recoveryOwner,
    );
    final recovered =
        widget.recovered ??
        local.where((d) {
          if (widget.draft != null) {
            return d['requestId'] == widget.draft!['request_uuid'];
          }
          final bundle = object(d['bundle']);
          return object(bundle['equipment'])['id'] ==
                  object(widget.bundle['equipment'])['id'] &&
              object(bundle['plan'])['id'] ==
                  object(widget.bundle['plan'])['id'];
        }).firstOrNull;
    final controller = DraftController(
      session: widget.session,
      bundle: recovered == null ? widget.bundle : object(recovered['bundle']),
      draft: widget.draft,
      recovered: recovered,
    );
    if (!mounted) controller.dispose();
    return controller;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DraftController>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) return _DraftWizard(controller: snapshot.data!);
      return OnlinePage(
        title: 'Recuperar comprobación',
        child: Center(
          child: snapshot.hasError
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Notice(
                    'No se pudo abrir la recuperación local. Vuelve a abrir la comprobación; tus borradores se conservan.',
                    alert: true,
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class _DraftWizard extends StatefulWidget {
  const _DraftWizard({required this.controller});
  final DraftController controller;
  @override
  State<_DraftWizard> createState() => _DraftWizardState();
}

class _DraftWizardState extends State<_DraftWizard>
    with WidgetsBindingObserver {
  DraftController get capture => widget.controller;
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> fields = {};

  /// Lo que se ve en cada paso. Se rehace en cada `build` porque no guarda
  /// estado: lo unico vivo son `capture` y `fields`, que son de aqui.
  DraftSteps get steps => DraftSteps(
    capture: capture,
    fields: fields,
    onGoToStep: _go,
    onSaveDraft: _save,
  );
  late ScrollController scroll;
  bool navigating = false;
  bool allowPop = false;
  bool restoringScroll = false;
  bool confirming = false;
  late bool headerHidden;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final name in ['temperature', 'humidity', 'observations']) {
      _register(
        name,
        capture.raw[name] as String,
        (text) => capture.raw[name] = text,
      );
    }
    for (final plan in capture.tests) {
      final input = capture.testInput(plan['id'] as String);
      _register(
        '${plan['id']}:reason',
        input['reason'] as String,
        (text) => input['reason'] = text,
      );
      if (capture.flexible) continue;
      for (final reading in (input['readings'] as List).cast<Json>()) {
        for (final name in ['indication', 'zero']) {
          _register(
            '${plan['id']}:${reading['pointId']}:$name',
            reading[name] as String,
            (text) => reading[name] = text,
          );
        }
      }
    }
    scroll = ScrollController(initialScrollOffset: capture.offset)
      ..addListener(_scrolled);
    headerHidden = capture.offset > 12;
    capture.addListener(_updated);
    capture.start();
  }

  void _register(String id, String initial, ValueChanged<String> update) {
    final controller = TextEditingController(text: initial);
    var previous = initial;
    controller.addListener(() {
      if (previous == controller.text) return;
      previous = controller.text;
      update(previous);
      capture.changed();
    });
    fields[id] = controller;
  }

  void _updated() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    if (restoringScroll || !scroll.hasClients) return;
    capture.setOffset(scroll.offset);
    final hidden = scroll.offset > 12;
    if (hidden != headerHidden && mounted) {
      setState(() => headerHidden = hidden);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(capture.persist());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    capture.removeListener(_updated);
    capture.dispose();
    scroll.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _go(int target) async {
    if (navigating || capture.locked) return;
    if (target > capture.step && !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => navigating = true);
    restoringScroll = true;
    await capture.goTo(target);
    if (!mounted) return;
    setState(() {
      navigating = false;
      headerHidden = capture.offset > 12;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(capture.offset.clamp(0, scroll.position.maxScrollExtent));
      }
      restoringScroll = false;
    });
  }

  Future<void> _leave() async {
    if (navigating || capture.finalizing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => navigating = true);
    final saved = await capture.pause();
    if (!mounted) return;
    setState(() {
      navigating = false;
      allowPop = saved;
    });
    if (saved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _save() async {
    if (await capture.persist()) await capture.sync();
  }

  Future<void> _compareServer() async {
    try {
      final remote = await capture.session.api.read('draft', {
        'id': capture.draftId,
      });
      if (!mounted) return;
      final payload = object(remote['payload']);
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Datos guardados en el servidor'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tu captura local se conserva. Revisa las diferencias antes de continuar.',
                  ),
                  DetailField('Temperatura (°C)', payload['temperature']),
                  DetailField('Humedad relativa (%)', payload['humidity']),
                  for (final input in objects(payload['tests'])) ...[
                    SectionLabel(
                      testLabel(
                        capture.tests
                            .where((t) => t['id'] == input['id'])
                            .firstOrNull?['type'],
                      ),
                    ),
                    if (input['omitted'] == true)
                      DetailField('Omitida', input['reason']),
                    for (final reading in objects(input['readings'])) ...[
                      DetailField('Indicación', reading['indication']),
                      DetailField('Retorno a cero', reading['zero']),
                    ],
                  ],
                  DetailField('Observaciones', payload['observations']),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver a mi captura'),
            ),
          ],
        ),
      );
    } catch (failure) {
      if (mounted) {
        setState(
          () => capture.error = failure is MobileFailure
              ? failure.message
              : 'No se pudo consultar la versión del servidor.',
        );
      }
    }
  }

  Future<void> _finalize() async {
    if (confirming || capture.finalizing) return;
    if (!capture.locked && capture.completionIssue != null) {
      setState(() => capture.error = capture.completionIssue);
      return;
    }
    confirming = true;
    if (!capture.locked) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Finalizar comprobación interna'),
          content: const Text(
            'Se guardarán los datos y se calculará el resultado. La comprobación quedará privada y no se podrá editar. No equivale a una calibración acreditada ni a una verificación legal.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finalizar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        confirming = false;
        return;
      }
    }
    final result = await capture.finalize();
    confirming = false;
    if (result == null || !mounted) return;
    final traceability = result['traceability'] == 'traceable'
        ? 'trazable'
        : 'sin trazabilidad vigente';
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resultado guardado'),
        content: Text(
          '${verdictLabel(result['verdict'])} · $traceability. La comprobación permanece privada.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ver historial'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => HistoryScreen(
              session: capture.session,
              equipmentId: capture.equipment['id'] as String,
            ),
          ),
          result: true,
        );
      }
    });
  }

  String get _saveStatus {
    if (capture.localError != null) return capture.localError!;
    if (!capture.localSaved) return 'Guardando en este dispositivo…';
    if (capture.pendingFinalize != null) {
      return 'Finalización pendiente de confirmar. Tus datos están conservados.';
    }
    if (capture.syncing) {
      return 'Guardado en este dispositivo · enviando al servidor…';
    }
    if (capture.dirty) {
      return 'Guardado en este dispositivo · pendiente de enviar';
    }
    return 'Guardado en este dispositivo y en el servidor';
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final step = capture.step;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || navigating) return;
        if (step > 0 && !capture.locked) {
          unawaited(_go(step - 1));
        } else {
          unawaited(_leave());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Comprobación · ${customerEquipmentCode(capture.equipment)}',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: headerHidden
                      ? const SizedBox.shrink()
                      : Padding(
                          key: const ValueKey('draft-step-header'),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  for (var index = 0; index < 5; index++) ...[
                                    if (index > 0)
                                      Expanded(
                                        child: Divider(
                                          color: index <= step
                                              ? palette.accentInk
                                              : palette.track,
                                        ),
                                      ),
                                    Semantics(
                                      selected: index == step,
                                      label:
                                          'Paso ${index + 1}: ${draftStepTitles[index]}',
                                      child: IconButton.filledTonal(
                                        tooltip: draftStepTitles[index],
                                        onPressed:
                                            index < step &&
                                                !capture.locked &&
                                                !navigating
                                            ? () => _go(index)
                                            : null,
                                        style: IconButton.styleFrom(
                                          backgroundColor: index == step
                                              ? palette.accentInk
                                              : palette.surface,
                                          disabledBackgroundColor: index == step
                                              ? palette.accentInk
                                              : palette.surface,
                                          foregroundColor: index == step
                                              ? palette.card
                                              : palette.text,
                                          disabledForegroundColor: index == step
                                              ? palette.card
                                              : palette.muted,
                                        ),
                                        icon: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Paso ${step + 1} de 5',
                                style: AppTextStyles.caption(context, size: 12),
                              ),
                              Text(
                                draftStepTitles[step],
                                style: AppTextStyles.figure(context, size: 25),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    capture.localError != null
                                        ? Icons.error_outline
                                        : capture.dirty
                                        ? Icons.save_outlined
                                        : Icons.cloud_done_outlined,
                                    size: 16,
                                    color: capture.localError != null
                                        ? palette.fail
                                        : palette.muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _saveStatus,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: palette.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: form,
                  child: ListView(
                    key: const ValueKey('draft-content'),
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      if (capture.localError != null)
                        OutlinedButton(
                          onPressed: _save,
                          child: const Text('Reintentar guardado'),
                        ),
                      if (capture.error != null)
                        Notice(capture.error!, alert: true),
                      if (capture.conflict) ...[
                        const Notice(
                          'Se conserva tu captura local. El servidor tiene otra versión; no se sobrescribirá automáticamente.',
                        ),
                        if (capture.draftId != null)
                          OutlinedButton(
                            onPressed: _compareServer,
                            child: const Text('Ver datos del servidor'),
                          ),
                      ],
                      if (capture.draftIssue != null && capture.dirty)
                        Notice(capture.draftIssue!),
                      KeyedSubtree(
                        key: ValueKey(step),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: step == 0
                              ? steps.preparation(context)
                              : step == 4
                              ? steps.summary(context)
                              : steps.testStep(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (step > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: navigating || capture.locked
                                  ? null
                                  : () => _go(step - 1),
                              child: const Text('Anterior'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: 2,
                          child: step < 4
                              ? FilledButton.icon(
                                  onPressed: navigating || capture.locked
                                      ? null
                                      : () => _go(step + 1),
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                  ),
                                  label: const Text('Siguiente'),
                                )
                              : FilledButton(
                                  onPressed:
                                      navigating ||
                                          capture.finalizing ||
                                          capture.plan['finalizationEnabled'] !=
                                              true
                                      ? null
                                      : _finalize,
                                  child: Text(
                                    capture.finalizing
                                        ? 'Finalizando…'
                                        : capture.locked
                                        ? 'Confirmar resultado'
                                        : 'Guardar y finalizar',
                                  ),
                                ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: navigating || capture.finalizing
                          ? null
                          : _leave,
                      icon: const Icon(Icons.save_outlined, size: 17),
                      label: const Text('Guardar y salir'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/numeric_keypad.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'draft_controller.dart';
import 'draft_steps.dart';
import 'history_screen.dart';
import 'measurement_suggestions.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

export 'draft_controller.dart' show decimalError, normalizedDecimal;

/// Revalidate access before exposing a locally recovered equipment snapshot.
/// Sin señal no hay con qué revalidar: el permiso de trabajar sin conexión
/// ya es esa validación, y la captura trae su propia copia de la balanza.
class RecoveredDraftScreen extends StatelessWidget {
  const RecoveredDraftScreen({
    required this.session,
    required this.snapshot,
    super.key,
  });
  final MobileSession session;
  final Json snapshot;
  @override
  Widget build(BuildContext context) => !session.online
      ? DraftScreen(
          session: session,
          bundle: object(snapshot['bundle']),
          recovered: snapshot,
        )
      : RemotePanel(
          frameTitle: 'Recuperar verificación',
          load: () => session.api.read('equipment', {
            'equipmentId': object(
              object(snapshot['bundle'])['equipment'],
            )['id'],
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
    final uploads = widget.session.uploads;
    // Si justo se está enviando, se espera: la pantalla abre lo que quedó.
    await uploads.hold();
    try {
      final local = await widget.session.recovery.list(
        widget.session.recoveryOwner,
      );
      final requested = widget.recovered?['requestId'];
      final recovered = requested != null
          // Lo más reciente del disco, no la copia con la que se llegó aquí.
          // Si ya no está, se envió mientras tanto.
          ? local.where((d) => d['requestId'] == requested).firstOrNull ??
                (throw const _AlreadySent())
          : local.where((d) {
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
    } finally {
      uploads.release();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DraftController>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) return _DraftWizard(controller: snapshot.data!);
      return OnlinePage(
        title: 'Recuperar verificación',
        child: Center(
          child: snapshot.error is _AlreadySent
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Notice(
                    'Esta verificación ya llegó al servidor. Búscala en el historial.',
                    icon: Icons.cloud_done_outlined,
                  ),
                )
              : snapshot.hasError
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Notice(
                    'No se pudo abrir la recuperación local. Vuelve a abrir la verificación; tus borradores se conservan.',
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
  final scaffold = GlobalKey<ScaffoldState>();
  final Map<String, TextEditingController> fields = {};

  /// Lo que se ve en cada paso. Se rehace en cada `build` porque no guarda
  /// estado: lo unico vivo son `capture` y `fields`, que son de aqui.
  DraftSteps get steps => DraftSteps(
    capture: capture,
    fields: fields,
    onGoToStep: _go,
    onSaveDraft: _save,
    onToggleOmission: _toggleOmission,
  );
  late ScrollController scroll;

  /// Teclado numerico propio de las lecturas. Mientras escribe ocupa el sitio
  /// de la pildora de navegacion.
  final keypad = NumericKeypadController();
  bool navigating = false;
  bool allowPop = false;
  bool restoringScroll = false;
  bool confirming = false;

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
    capture.setOffset(scroll.position.pixels);
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
    keypad.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// Ir a un paso. "Siguiente" valida el paso actual; el panel de pasos lleva
  /// a cualquiera sin validar ([validate] en false), y lo que quede incompleto
  /// se marca en el panel y lo frena la finalizacion.
  Future<void> _go(int target, {bool validate = true}) async {
    if (navigating || capture.locked) return;
    if (validate && target > capture.step && !form.currentState!.validate()) {
      revealFirstFormError(context, form);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => navigating = true);
    restoringScroll = true;
    await capture.goTo(target);
    if (!mounted) return;
    setState(() => navigating = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(capture.offset.clamp(0, scroll.position.maxScrollExtent));
      }
      restoringScroll = false;
    });
  }

  void _tell(String message, {SnackBarAction? action}) =>
      showWizardMessage(context, message, action: action);

  /// Omitir o volver a incluir la prueba del paso. Las lecturas se conservan:
  /// al incluirla de nuevo vuelven tal cual.
  void _toggleOmission(Json input) {
    if (capture.locked) return;
    keypad.close();
    input['omitted'] = input['omitted'] != true;
    capture.changed();
  }

  Future<void> _leave() async {
    if (navigating || capture.finalizing) return;
    keypad.close();
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

  /// Atras del sistema: primero cierra el panel de pasos o el teclado, despues
  /// retrocede un paso. Nunca sale de la captura: un gesto accidental en el
  /// borde no deja al operario fuera; se sale con ⋮ › Guardar y salir.
  void _onSystemBack() {
    if (closeWizardDrawer(scaffold)) return;
    if (keypad.visible) {
      keypad.close();
      return;
    }
    if (capture.step > 0 && !capture.locked) {
      unawaited(_go(capture.step - 1));
      return;
    }
    _tell('Es el primer paso. Para salir usa ⋮ › Guardar y salir.');
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
      if (scroll.hasClients) {
        unawaited(
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    confirming = true;
    if (!capture.locked) {
      final online = capture.session.online;
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Finalizar verificación intermedia'),
          content: Text(
            online
                ? 'Se guardarán los datos y se calculará el resultado. La verificación intermedia quedará privada y no se podrá editar. No equivale a una calibración acreditada ni a una verificación legal.'
                : 'No hay señal: la verificación queda finalizada en este teléfono, con la hora de ahora, y se envía sola cuando vuelva la conexión. El servidor calcula el resultado al recibirla. Ya no se podrá editar. No equivale a una calibración acreditada ni a una verificación legal.',
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
    if (result['queued'] == true) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Finalizada en el teléfono'),
          content: const Text(
            'Se enviará sola cuando vuelva la señal, aunque estés en otra pantalla. El resultado lo calcula el servidor al recibirla. Mientras tanto la ves en Por enviar.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return;
    }
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
          '${verdictLabel(result['verdict'])} · $traceability. La verificación permanece privada.',
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

  _SaveState get _saveState {
    if (capture.localError != null || capture.attention != null) {
      return _SaveState.error;
    }
    if (capture.pendingFinalize != null || capture.queuedFinalize != null) {
      return _SaveState.waiting;
    }
    if (capture.syncing) return _SaveState.syncing;
    if (capture.dirty) return _SaveState.local;
    return _SaveState.synced;
  }

  String get _saveStatus {
    if (capture.localError != null) return capture.localError!;
    if (!capture.localSaved) return 'Guardando en este dispositivo…';
    if (capture.attention != null) {
      return 'El servidor no aceptó el envío: ${capture.attention!['message']}';
    }
    if (capture.pendingFinalize != null) {
      return 'Finalización pendiente de confirmar. Tus datos están conservados.';
    }
    if (capture.queuedFinalize != null) {
      return 'Finalizada en este dispositivo · se enviará al recuperar la señal';
    }
    if (!capture.session.online && capture.dirty) {
      return 'Sin señal · guardado en este dispositivo; se enviará al recuperar la conexión';
    }
    if (capture.syncing) {
      return 'Guardado en este dispositivo · enviando al servidor…';
    }
    if (capture.dirty && capture.draftIssue != null) {
      return 'Guardado en este dispositivo · se enviará al servidor cuando los datos estén completos';
    }
    if (capture.dirty) {
      return 'Guardado en este dispositivo · pendiente de enviar';
    }
    return 'Guardado en este dispositivo y en el servidor';
  }

  void _explainSave() {
    final canSend =
        capture.localError == null &&
        capture.dirty &&
        capture.draftIssue == null &&
        !capture.syncing &&
        !capture.locked;
    _tell(
      _saveStatus,
      action: capture.localError != null
          ? SnackBarAction(label: 'Reintentar', onPressed: _save)
          : canSend
          ? SnackBarAction(label: 'Enviar ahora', onPressed: _save)
          : null,
    );
  }

  /// Un paso por prueba y dos de marco. "Completo" no es "visitado": una
  /// prueba lo esta cuando tiene todas sus lecturas o un motivo de omision.
  List<WizardStep> _wizardSteps() {
    final step = capture.step;
    final certificates = (capture.raw['certificates'] as List).length;
    final environmentIssue =
        decimalError(capture.raw['temperature'] as String, environment: true) !=
            null ||
        decimalError(
              capture.raw['humidity'] as String,
              environment: true,
              humidity: true,
            ) !=
            null;
    WizardStep test(int index) {
      final plan = capture.tests
          .where((t) => t['type'] == draftStepTypes[index])
          .firstOrNull;
      if (plan == null) {
        return WizardStep(
          title: draftStepTitles[index],
          detail: 'No incluida en la configuración',
          progress: WizardProgress.complete,
          enabled: !capture.locked,
        );
      }
      final input = capture.testInput(plan['id'] as String);
      final readings = objects(input['readings']);
      final filled = readings
          .where((r) => (r['indication'] as String).trim().isNotEmpty)
          .length;
      final complete = capture.testComplete(input);
      return WizardStep(
        title: draftStepTitles[index],
        detail: input['omitted'] == true
            ? complete
                  ? 'Omitida'
                  : 'Omitida · falta el motivo'
            : complete
            ? 'Lecturas completas'
            : '$filled de ${readings.length} lecturas',
        progress: complete
            ? WizardProgress.complete
            : index < step
            ? WizardProgress.review
            : WizardProgress.pending,
        enabled: !capture.locked,
      );
    }

    return [
      WizardStep(
        title: draftStepTitles[0],
        detail: [
          certificates == 0
              ? 'Sin pesas patrón'
              : '$certificates ${certificates == 1 ? 'certificado' : 'certificados'}',
          if ((capture.raw['temperature'] as String).isNotEmpty)
            '${capture.raw['temperature']} °C',
          if ((capture.raw['humidity'] as String).isNotEmpty)
            '${capture.raw['humidity']} %',
        ].join(' · '),
        progress: environmentIssue
            ? WizardProgress.review
            : step > 0
            ? WizardProgress.complete
            : WizardProgress.pending,
        enabled: !capture.locked,
      ),
      for (var index = 1; index <= 3; index++) test(index),
      WizardStep(
        title: draftStepTitles[4],
        detail: capture.locked
            ? 'Finalización en curso'
            : 'Observaciones y finalizar',
        progress: capture.finalizedResult != null
            ? WizardProgress.complete
            : WizardProgress.pending,
      ),
    ];
  }

  /// La prueba del paso actual, si el paso es de una prueba configurada.
  Json? get _currentTest {
    if (capture.step < 1 || capture.step > 3) return null;
    final plan = capture.tests
        .where((t) => t['type'] == draftStepTypes[capture.step])
        .firstOrNull;
    return plan == null ? null : capture.testInput(plan['id'] as String);
  }

  Future<void> _showEquipment() async {
    keypad.close();
    final equipment = capture.equipment;
    final ranges = objects(capture.bundle['ranges']);
    final selected = (capture.raw['certificates'] as List).toSet();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Kicker('Balanza'),
              const SizedBox(height: 2),
              Text(
                customerEquipmentCode(equipment),
                style: AppTextStyles.figure(context, size: 26),
              ),
              if (!registeredByCustomer(equipment))
                DetailField('Código Métrica', equipment['cod_metrica']),
              DetailField(
                'Marca y modelo',
                '${valueLabel(equipment['marca'])} · ${valueLabel(equipment['modelo'])}',
              ),
              DetailField('Serie', equipment['serie']),
              DetailField('Ubicación', equipment['ubicacion']),
              for (final range in ranges)
                DetailField(
                  'Rango ${range['numero_rango']}',
                  '${rangeCapacityLabel(range)} ${range['unidad']}'
                      ' · d = ${rangeDivisionLabel(range)} ${range['unidad']}',
                ),
              const SectionLabel('Pesas patrón elegidas'),
              if (selected.isEmpty)
                const Text('Ninguna: se usan productos o cargas de trabajo.')
              else
                for (final pattern in objects(capture.bundle['patterns']))
                  for (final cert in objects(pattern['certificates']))
                    if (selected.contains(cert['id']))
                      DetailField(
                        '${pattern['code']} · ${pattern['description']}',
                        '${cert['number']}${cert['expired'] == true ? ' · VENCIDO' : ''}',
                      ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionsMenu() {
    final test = _currentTest;
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Más opciones',
      icon: const Icon(Icons.more_vert),
      onOpened: keypad.close,
      onSelected: (action) => switch (action) {
        _MenuAction.omission => _toggleOmission(test!),
        _MenuAction.equipment => unawaited(_showEquipment()),
        _MenuAction.server => unawaited(_compareServer()),
        _MenuAction.leave => unawaited(_leave()),
      },
      itemBuilder: (context) => [
        if (test != null && !capture.locked)
          wizardMenuItem(
            _MenuAction.omission,
            test['omitted'] == true
                ? Icons.playlist_add_check
                : Icons.do_not_disturb_on_outlined,
            test['omitted'] == true
                ? 'Incluir esta prueba'
                : 'Omitir esta prueba',
          ),
        wizardMenuItem(
          _MenuAction.equipment,
          Icons.info_outline,
          'Datos de la balanza',
        ),
        if (capture.conflict && capture.draftId != null)
          wizardMenuItem(
            _MenuAction.server,
            Icons.cloud_sync_outlined,
            'Ver datos del servidor',
          ),
        wizardMenuItem(
          _MenuAction.leave,
          Icons.logout,
          'Guardar y salir',
          enabled: !navigating && !capture.finalizing,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = capture.step;
    final wizard = _wizardSteps();
    final last = step == draftStepTitles.length - 1;

    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !navigating) _onSystemBack();
      },
      child: NumericKeypadScope(
        controller: keypad,
        child: WizardScaffold(
          scaffoldKey: scaffold,
          kicker: 'Verificación intermedia',
          title: customerEquipmentCode(capture.equipment),
          steps: wizard,
          current: step,
          onSelectStep: (index) => unawaited(_go(index, validate: false)),
          // Al abrir el panel se cierra el teclado propio.
          onDrawerOpened: keypad.close,
          actions: [
            // Cambia con cada escritura: escucha su propia senal y no la de
            // toda la captura.
            ListenableBuilder(
              listenable: capture.status,
              builder: (context, _) => _SaveStatusButton(
                state: _saveState,
                text: _saveStatus,
                onPressed: _explainSave,
              ),
            ),
            _optionsMenu(),
          ],
          banner: capture.localError == null
              ? null
              : _SaveErrorBanner(message: capture.localError!, onRetry: _save),
          body: Form(
            key: form,
            child: ListView(
              key: const ValueKey('draft-content'),
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(
                20,
                18,
                20,
                WizardNavPill.contentPadding,
              ),
              children: [
                if (capture.error != null) Notice(capture.error!, alert: true),
                if (capture.queuedFinalize != null) ...[
                  if (capture.attention case final attention?) ...[
                    Notice(
                      'El servidor no aceptó esta verificación: ${attention['message']}',
                      icon: Icons.error_outline,
                      alert: true,
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('reopen-capture'),
                      onPressed: () => unawaited(capture.reopen()),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Corregir la captura'),
                    ),
                  ] else
                    Notice(
                      'Finalizada en este teléfono el ${dateTimeLabel(capture.measuredAt)}. '
                      '${capture.session.online ? 'Se está enviando al servidor.' : 'Se enviará sola cuando vuelva la señal; el servidor calcula el resultado.'}',
                      icon: Icons.schedule_send_outlined,
                    ),
                ],
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
                KeyedSubtree(
                  key: ValueKey(step),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: step == 0
                        ? steps.preparation(context)
                        : last
                        ? steps.summary(context)
                        : steps.testStep(context),
                  ),
                ),
              ],
            ),
          ),
          // El teclado numerico ocupa el lugar de la pildora.
          pill: ListenableBuilder(
            listenable: keypad,
            builder: (context, _) => keypad.visible
                ? const SizedBox.shrink()
                : WizardNavPill(
                    label: !last
                        ? 'Siguiente'
                        : capture.finalizing
                        ? capture.queuedFinalize != null
                              ? 'Enviando…'
                              : 'Finalizando…'
                        : capture.queuedFinalize != null &&
                              capture.pendingFinalize == null
                        ? capture.session.online
                              ? 'Enviar ahora'
                              : 'Esperando señal'
                        : capture.locked
                        ? 'Confirmar resultado'
                        : 'Finalizar',
                    icon: last
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    onBack: step > 0 && !capture.locked && !navigating
                        ? () => _go(step - 1)
                        : null,
                    onNext: !last
                        ? navigating || capture.locked
                              ? null
                              : () => _go(step + 1)
                        : navigating ||
                              capture.finalizing ||
                              capture.plan['finalizationEnabled'] != true ||
                              (capture.queuedFinalize != null &&
                                  !capture.session.online)
                        ? null
                        : _finalize,
                  ),
          ),
          footer: ListenableBuilder(
            listenable: keypad,
            builder: (context, _) => keypad.visible
                ? NumericKeypad(controller: keypad)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

enum _MenuAction { omission, equipment, server, leave }

/// La captura que se quería abrir ya no está en el teléfono: se envió.
class _AlreadySent implements Exception {
  const _AlreadySent();
}

enum _SaveState { error, waiting, syncing, local, synced }

/// Estado del guardado como un icono del AppBar: antes era una linea de texto
/// fija bajo los pasos. El texto completo va en el tooltip y al tocarlo.
class _SaveStatusButton extends StatelessWidget {
  const _SaveStatusButton({
    required this.state,
    required this.text,
    required this.onPressed,
  });
  final _SaveState state;
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final Widget glyph = switch (state) {
      _SaveState.error => Icon(
        Icons.error_outline,
        key: const ValueKey('error'),
        color: palette.fail,
      ),
      _SaveState.waiting => Icon(
        Icons.hourglass_top_rounded,
        key: const ValueKey('waiting'),
        color: palette.accentInk,
      ),
      _SaveState.syncing => SizedBox.square(
        key: const ValueKey('syncing'),
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: palette.accentInk,
        ),
      ),
      _SaveState.local => Icon(
        Icons.cloud_upload_outlined,
        key: const ValueKey('local'),
        color: palette.muted,
      ),
      _SaveState.synced => Icon(
        Icons.cloud_done_outlined,
        key: const ValueKey('synced'),
        color: palette.muted,
      ),
    };
    return IconButton(
      tooltip: text,
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: glyph,
      ),
    );
  }
}

/// Aviso fijo bajo el AppBar mientras el telefono no puede guardar: lo escrito
/// sigue en pantalla pero no esta en el disco.
class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: palette.failSurface,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: palette.failInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 12.5, color: palette.failInk),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Reintentar guardado'),
            ),
          ],
        ),
      ),
    );
  }
}

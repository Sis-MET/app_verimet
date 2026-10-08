import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/labeled_field.dart';
import 'mobile_api.dart';
import 'offline_recovery.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'self_service_access.dart';
import 'workspace_screen.dart';

class OnlineEntry extends ConsumerStatefulWidget {
  const OnlineEntry({super.key});
  @override
  ConsumerState<OnlineEntry> createState() => _OnlineEntryState();
}

class _OnlineEntryState extends ConsumerState<OnlineEntry>
    with WidgetsBindingObserver {
  late final MobileSession session;
  Timer? timer;
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  bool foreground = true;
  bool handlingBack = false;
  String? navigatorUserId;
  GlobalKey<NavigatorState> workspaceNavigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    session = ref.read(mobileSessionProvider);
    WidgetsBinding.instance.addObserver(this);
    unawaited(session.start());
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (foreground) unawaited(session.refresh());
    });
    connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        session.suspend(disconnected: true);
      } else if (foreground && session.stage == SessionStage.offline) {
        unawaited(session.refresh());
      }
    }, onError: (Object _) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      unawaited(session.refresh());
    } else {
      session.suspend();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(connectivity?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> handleBack() async {
    if (handlingBack) return;
    handlingBack = true;
    try {
      if (await (workspaceNavigator.currentState?.maybePop() ??
          Future.value(false))) {
        return;
      }
      if (!mounted) return;
      final exit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Salir de IvMET?'),
          content: const Text(
            'Estás en la pantalla principal. Puedes cancelar para continuar trabajando.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir'),
            ),
          ],
        ),
      );
      if (exit == true) await SystemNavigator.pop();
    } finally {
      handlingBack = false;
    }
  }

  Widget workspace(bool ready) {
    final userId = session.user!['id'].toString();
    if (navigatorUserId != userId) {
      navigatorUserId = userId;
      workspaceNavigator = GlobalKey<NavigatorState>();
    }
    return PopScope(
      key: ValueKey('workspace-$userId'),
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(handleBack());
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !ready,
              child: ExcludeSemantics(
                excluding: !ready,
                child: AnimatedOpacity(
                  opacity: ready ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Navigator(
                    key: workspaceNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => WorkspaceScreen(session: session),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: ready
                  ? const SizedBox.shrink(key: ValueKey('workspace-ready'))
                  : KeyedSubtree(
                      key: const ValueKey('workspace-locked'),
                      child: _locked(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      late Widget content;
      if (session.user != null &&
          session.bootstrap.isNotEmpty &&
          [
            SessionStage.ready,
            SessionStage.offline,
            SessionStage.suspended,
          ].contains(session.stage)) {
        // Conservar campos en memoria al cambiar de app no habilita uso offline:
        // todo el navegador queda oculto, sin semántica ni interacción.
        final ready = session.stage == SessionStage.ready;
        content = workspace(ready);
      } else if (session.stage == SessionStage.login ||
          session.stage == SessionStage.password) {
        content = AccessForm(
          key: ValueKey(session.stage),
          session: session,
          changingPassword: session.stage == SessionStage.password,
        );
      } else if (session.stage == SessionStage.starting) {
        content = const Scaffold(
          key: ValueKey('starting'),
          body: Center(child: CircularProgressIndicator()),
        );
      } else if (session.stage == SessionStage.offline &&
          session.offlineDrafts.isNotEmpty) {
        // Sin poder validar la sesion no se entra a la app, pero tampoco se
        // deja al operario mirando un muro con su captura dentro del telefono.
        content = KeyedSubtree(
          key: const ValueKey('offline-recovery'),
          child: OfflineRecoveryScreen(session: session),
        );
      } else {
        content = KeyedSubtree(
          key: const ValueKey('access-locked'),
          child: _locked(),
        );
      }
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 170),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: content,
      );
    },
  );

  Widget _locked() => OnlinePage(
    title: 'Acceso a IvMET',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.lock_outline, size: 48),
        Notice(session.error ?? 'Conecta con el servidor para continuar.'),
        FilledButton(
          onPressed: session.refresh,
          child: const Text('Comprobar acceso'),
        ),
        TextButton(
          onPressed: session.logout,
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );
}

class AccessForm extends StatefulWidget {
  const AccessForm({
    required this.session,
    required this.changingPassword,
    super.key,
  });
  final MobileSession session;
  final bool changingPassword;
  @override
  State<AccessForm> createState() => _AccessFormState();
}

class _AccessFormState extends State<AccessForm> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  bool hidden = true;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.changingPassword) {
        await widget.session.password(password.text);
      } else {
        await widget.session.login(username.text, password.text);
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure
              ? failure.message
              : 'No se pudo completar el acceso.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configError = widget.session.api.configuration.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'IvMET',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.changingPassword
                            ? 'Define tu contraseña personal'
                            : 'Verificaciones metrológicas',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      if (configError != null) Notice(configError),
                      if (widget.changingPassword)
                        const Notice(
                          'Tu contraseña temporal debe cambiarse antes de acceder. Usa al menos 12 caracteres.',
                        )
                      else
                        LabeledInput(
                          label: 'Usuario o correo',
                          child: TextFormField(
                            controller: username,
                            enabled: !busy,
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Ingresa tu usuario o tu correo.'
                                : null,
                          ),
                        ),
                      const SizedBox(height: 16),
                      LabeledInput(
                        label: widget.changingPassword
                            ? 'Nueva contraseña'
                            : 'Contraseña',
                        child: TextFormField(
                          controller: password,
                          enabled: !busy,
                          obscureText: hidden,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [
                            widget.changingPassword
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              tooltip: hidden
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () => setState(() => hidden = !hidden),
                              icon: Icon(
                                hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              (v?.length ?? 0) <
                                      (widget.changingPassword ? 12 : 1) ||
                                  (v?.length ?? 0) > 200
                              ? 'Revisa la longitud de la contraseña.'
                              : null,
                          onFieldSubmitted: (_) {
                            if (!widget.changingPassword) unawaited(submit());
                          },
                        ),
                      ),
                      if (widget.changingPassword) ...[
                        const SizedBox(height: 16),
                        LabeledInput(
                          label: 'Confirmar contraseña',
                          child: TextFormField(
                            controller: confirmation,
                            enabled: !busy,
                            obscureText: true,
                            validator: (v) => v != password.text
                                ? 'Las contraseñas no coinciden.'
                                : null,
                          ),
                        ),
                      ],
                      if (error ?? widget.session.error
                          case final String message)
                        Notice(message, icon: Icons.error_outline),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy || configError != null ? null : submit,
                        child: Text(
                          busy
                              ? 'Comprobando…'
                              : widget.changingPassword
                              ? 'Guardar contraseña'
                              : 'Ingresar',
                        ),
                      ),
                      if (widget.changingPassword)
                        TextButton(
                          onPressed: busy ? null : widget.session.logout,
                          child: const Text('Cerrar sesión'),
                        )
                      else ...[
                        TextButton(
                          key: const ValueKey('access-forgot'),
                          onPressed: busy || configError != null
                              ? null
                              : () => openPage<void>(
                                  context,
                                  PasswordResetScreen(
                                    session: widget.session,
                                    email: username.text,
                                  ),
                                ),
                          child: const Text('¿Olvidaste tu contraseña?'),
                        ),
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 14),
                        Text(
                          '¿Tu empresa aún no usa IvMET?',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('access-signup'),
                          onPressed: busy || configError != null
                              ? null
                              : () => openPage<void>(
                                  context,
                                  SignupScreen(session: widget.session),
                                ),
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Crear cuenta de empresa'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Si tu empresa ya usa IvMET, pide tu usuario al jefe de calidad. Se requiere conexión a internet.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

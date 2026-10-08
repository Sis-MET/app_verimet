import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Versión de las condiciones que acepta quien registra una empresa. Supabase
/// y `ivmet-signup` exigen la misma.
const termsVersion = 'ivmet-terms-v1';

/// Condiciones de uso que se muestran al registrarse.
const termsOfUse = '''
IvMET registra verificaciones intermedias: controles internos que tu empresa hace entre calibraciones formales, con la configuración que ella misma define. No es un certificado de calibración ni una verificación legal, y no sirve para demostrar conformidad ante IBMETRO ni ante otra autoridad.

Las balanzas, verificaciones y lecturas que registres pertenecen a tu empresa. Métrica Ltda. solo recibe lo que el jefe de calidad comparte expresamente, y los datos de contacto que dejas al registrarte, para atender tu cuenta y tus solicitudes de plan.

La cuenta empieza en el plan gratuito, con límites de plantas, balanzas, usuarios y verificaciones al mes. Métrica puede ajustar los planes; lo que ya registraste se conserva.

Quien crea la cuenta es el jefe de calidad de la empresa y responde por los usuarios que crea y por las contraseñas que entrega.''';

/// Patrón de correo que acepta el servidor (`private.valid_email`).
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _emailError(String? value) {
  final email = (value ?? '').trim();
  if (email.length < 6 || email.length > 100 || !_email.hasMatch(email)) {
    return 'Escribe un correo válido.';
  }
  return null;
}

String? _passwordError(String? value) =>
    (value?.length ?? 0) < 12 || (value?.length ?? 0) > 200
    ? 'Usa al menos 12 caracteres.'
    : null;

/// Código de 6 dígitos (Supabase admite hasta 10).
String? _codeError(String? value) =>
    RegExp(r'^\d{6,10}$').hasMatch((value ?? '').trim())
    ? null
    : 'Escribe el código de 6 dígitos.';

/// Sale a la app ya con sesión. Un aviso que siga a la vista cruzaría la
/// transición en dos pantallas a la vez.
void _leave(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)
    ?..removeCurrentSnackBar()
    ..clearSnackBars();
  Navigator.of(context).pop();
}

Future<void> showTermsOfUse(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Condiciones de uso'),
    content: const SingleChildScrollView(child: Text(termsOfUse)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);

/// Pide otro código: Auth limita a uno por minuto.
class _ResendCode extends StatefulWidget {
  const _ResendCode({required this.sentAt, required this.onResend});
  final DateTime sentAt;
  final Future<void> Function() onResend;
  @override
  State<_ResendCode> createState() => _ResendCodeState();
}

class _ResendCodeState extends State<_ResendCode> {
  Timer? timer;
  bool busy = false;

  int get _wait =>
      60 - DateTime.now().difference(widget.sentAt).inSeconds.clamp(0, 60);

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (_wait <= 0) timer?.cancel();
    });
  }

  @override
  void didUpdateWidget(_ResendCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentAt != widget.sentAt && (timer?.isActive != true)) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        if (_wait <= 0) timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: busy || _wait > 0
          ? null
          : () async {
              setState(() => busy = true);
              try {
                await widget.onResend();
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(
        _wait > 0 ? 'Reenviar código en $_wait s' : 'Reenviar código',
      ),
    ),
  );
}

/// Alta de una empresa desde la app, en tres pasos: la empresa, la cuenta del
/// jefe de calidad y el código que llega al correo. Al confirmarlo la empresa
/// queda en el plan gratuito y se entra directamente.
class SignupScreen extends StatefulWidget {
  const SignupScreen({required this.session, super.key});
  final MobileSession session;
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final scaffold = GlobalKey<ScaffoldState>();
  final forms = List.generate(3, (_) => GlobalKey<FormState>());
  final company = TextEditingController();
  final plant = TextEditingController();
  final city = TextEditingController();
  final country = TextEditingController(text: 'Bolivia');
  final phone = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final code = TextEditingController();
  int step = 0;
  bool accepted = false;
  bool hidden = true;
  bool busy = false;
  String? error;

  /// Cuándo se envió el código y a qué correo: cambiar el correo exige otro.
  DateTime? sentAt;
  String? sentTo;

  static const _titles = ['Tu empresa', 'Tu cuenta', 'Código'];

  @override
  void dispose() {
    for (final controller in [
      company,
      plant,
      city,
      country,
      phone,
      name,
      email,
      password,
      confirmation,
      code,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Json get _data => {
    'email': email.text.trim(),
    'company': company.text.trim(),
    'plantName': plant.text.trim(),
    'city': city.text.trim(),
    'country': country.text.trim(),
    'phone': phone.text.trim(),
    'name': name.text.trim(),
    'acceptTerms': accepted,
    'termsVersion': termsVersion,
  };

  List<WizardStep> get _steps => [
    for (var i = 0; i < 3; i++)
      WizardStep(
        title: _titles[i],
        detail: switch (i) {
          0 =>
            company.text.trim().isEmpty
                ? 'Nombre y planta'
                : company.text.trim(),
          1 =>
            email.text.trim().isEmpty
                ? 'Nombre, correo y contraseña'
                : email.text.trim(),
          _ => sentAt == null ? 'Llega a tu correo' : 'Enviado',
        },
        progress: i < step ? WizardProgress.complete : WizardProgress.pending,
        enabled: i <= step,
      ),
  ];

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on MobileFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo completar el registro. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    await widget.session.api.signupStart(_data);
    if (!mounted) return;
    setState(() {
      sentAt = DateTime.now();
      sentTo = email.text.trim().toLowerCase();
      step = 2;
    });
  });

  Future<void> _complete() => _run(() async {
    await widget.session.signup({
      ..._data,
      'code': code.text.trim(),
      'password': password.text,
    });
    if (mounted) _leave(context);
  });

  Future<void> _next() async {
    if (busy || !forms[step].currentState!.validate()) {
      if (!busy) revealFirstFormError(context, forms[step]);
      return;
    }
    if (step == 0) {
      setState(() => step = 1);
    } else if (step == 1) {
      if (!accepted) {
        setState(() => error = 'Acepta las condiciones de uso para continuar.');
        return;
      }
      // El mismo correo con un código vigente no pide otro.
      if (sentTo == email.text.trim().toLowerCase() && sentAt != null) {
        setState(() {
          error = null;
          step = 2;
        });
      } else {
        await _sendCode();
      }
    } else {
      await _complete();
    }
  }

  void _back() {
    if (busy) return;
    if (step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        error = null;
        step--;
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    List<String> hints = const [],
    String? hint,
    bool obscure = false,
    Widget? suffix,
    int max = 100,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: LabeledInput(
      label: label,
      child: TextFormField(
        controller: controller,
        enabled: !busy,
        keyboardType: keyboard,
        autofillHints: hints,
        obscureText: obscure,
        autocorrect: !obscure && keyboard != TextInputType.emailAddress,
        enableSuggestions: !obscure,
        maxLength: max,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          suffixIcon: suffix,
        ),
        validator: validator,
        onChanged: (_) => setState(() {}),
      ),
    ),
  );

  Widget _body() {
    final palette = IndustryPalette.of(context);
    return Form(
      key: forms[step],
      child: AutofillGroup(
        child: ListView(
          key: ValueKey('signup-step-$step'),
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            WizardNavPill.contentPadding,
          ),
          children: [
            ...switch (step) {
              0 => [
                const WizardStepHeading(
                  title: 'Tu empresa',
                  caption:
                      'Así la verás en IvMET. Luego podrás crear sus áreas y registrar sus balanzas.',
                ),
                const Notice(
                  'Empiezas en el plan gratuito, con límites de plantas, balanzas, usuarios y verificaciones al mes. Cuando necesites más, pide un plan superior desde la app.',
                  icon: Icons.workspace_premium_outlined,
                ),
                _field(
                  'Nombre de la empresa',
                  company,
                  hints: const [AutofillHints.organizationName],
                  validator: (v) => (v ?? '').trim().length < 2
                      ? 'Escribe el nombre de la empresa.'
                      : null,
                ),
                _field('Nombre de la primera planta (opcional)', plant),
                _field(
                  'Ciudad (opcional)',
                  city,
                  hints: const [AutofillHints.addressCity],
                ),
                _field(
                  'País',
                  country,
                  hints: const [AutofillHints.countryName],
                ),
                _field(
                  'Teléfono (opcional)',
                  phone,
                  keyboard: TextInputType.phone,
                  hints: const [AutofillHints.telephoneNumber],
                  max: 40,
                ),
              ],
              1 => [
                const WizardStepHeading(
                  title: 'Tu cuenta',
                  caption:
                      'Serás el jefe de calidad: configuras las verificaciones y creas los usuarios de tu equipo.',
                ),
                _field(
                  'Nombre y apellido',
                  name,
                  hints: const [AutofillHints.name],
                  max: 200,
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Escribe tu nombre.' : null,
                ),
                _field(
                  'Correo electrónico',
                  email,
                  keyboard: TextInputType.emailAddress,
                  hints: const [AutofillHints.email],
                  validator: _emailError,
                ),
                _field(
                  'Contraseña',
                  password,
                  obscure: hidden,
                  hints: const [AutofillHints.newPassword],
                  max: 200,
                  validator: _passwordError,
                  suffix: IconButton(
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
                _field(
                  'Confirmar contraseña',
                  confirmation,
                  obscure: true,
                  max: 200,
                  validator: (v) => v != password.text
                      ? 'Las contraseñas no coinciden.'
                      : null,
                ),
                CheckboxListTile(
                  key: const ValueKey('signup-terms'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: accepted,
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          accepted = value == true;
                          if (accepted) error = null;
                        }),
                  title: const Text('Acepto las condiciones de uso de IvMET'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => showTermsOfUse(context),
                    child: const Text('Leer condiciones de uso'),
                  ),
                ),
              ],
              _ => [
                const WizardStepHeading(
                  title: 'Revisa tu correo',
                  caption: 'El código confirma que el correo es tuyo.',
                ),
                Notice(
                  'Enviamos un código de 6 dígitos a $sentTo. Si no lo ves, revisa el correo no deseado.',
                  icon: Icons.mark_email_unread_outlined,
                ),
                _field(
                  'Código',
                  code,
                  keyboard: TextInputType.number,
                  hints: const [AutofillHints.oneTimeCode],
                  max: 10,
                  validator: _codeError,
                ),
                if (sentAt != null)
                  _ResendCode(sentAt: sentAt!, onResend: _sendCode),
              ],
            },
            if (error case final message?)
              Notice(message, icon: Icons.error_outline, alert: true),
            if (step == 0)
              Text(
                'Si tu empresa ya usa IvMET, pide tu usuario al jefe de calidad en lugar de crear otra cuenta.',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: step == 0 && !busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !closeWizardDrawer(scaffold)) _back();
    },
    child: WizardScaffold(
      scaffoldKey: scaffold,
      kicker: 'Nueva cuenta',
      title: 'Crear cuenta de empresa',
      steps: _steps,
      current: step,
      // El panel se cierra solo; solo se vuelve a pasos ya hechos.
      onSelectStep: (target) {
        if (target < step && !busy) setState(() => step = target);
      },
      body: _body(),
      pill: WizardNavPill(
        key: const ValueKey('signup-pill'),
        label: busy
            ? 'Un momento…'
            : switch (step) {
                0 => 'Siguiente',
                1 => 'Enviar código',
                _ => 'Crear empresa',
              },
        icon: step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded,
        onBack: busy ? null : _back,
        onNext: busy ? null : _next,
      ),
    ),
  );
}

/// Recuperar la contraseña con un código al correo. Sirve para las cuentas
/// cuyo usuario es su correo; las demás las restablece el jefe de calidad.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({required this.session, this.email, super.key});
  final MobileSession session;
  final String? email;
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final form = GlobalKey<FormState>();
  late final email = TextEditingController(
    text: (widget.email ?? '').contains('@') ? widget.email!.trim() : '',
  );
  final code = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  DateTime? sentAt;
  bool busy = false;
  bool hidden = true;
  String? error;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on MobileFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo completar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    await widget.session.api.passwordResetStart(email.text);
    if (mounted) setState(() => sentAt = DateTime.now());
  });

  Future<void> _submit() async {
    if (busy) return;
    if (!form.currentState!.validate()) {
      revealFirstFormError(context, form);
      return;
    }
    if (sentAt == null) return _send();
    await _run(() async {
      await widget.session.resetPassword(email.text, code.text, password.text);
      if (mounted) _leave(context);
    });
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Recuperar contraseña',
    floating: WizardNavPill.action(
      key: const ValueKey('reset-pill'),
      label: busy
          ? 'Un momento…'
          : sentAt == null
          ? 'Enviar código'
          : 'Guardar contraseña',
      icon: sentAt == null ? Icons.send_rounded : Icons.check_rounded,
      onNext: busy ? null : _submit,
    ),
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          18,
          20,
          WizardNavPill.contentPadding,
        ),
        children: [
          const WizardStepHeading(
            title: 'Tu correo',
            caption:
                'Si te registraste con tu correo, te enviamos un código para elegir una contraseña nueva.',
          ),
          LabeledInput(
            label: 'Correo electrónico',
            child: TextFormField(
              controller: email,
              enabled: !busy && sentAt == null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              validator: _emailError,
            ),
          ),
          if (sentAt != null) ...[
            const SizedBox(height: 10),
            Notice(
              'Si ${email.text.trim()} tiene una cuenta, le llegó un código de 6 dígitos.',
              icon: Icons.mark_email_unread_outlined,
            ),
            LabeledInput(
              label: 'Código',
              child: TextFormField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _codeError,
              ),
            ),
            const SizedBox(height: 14),
            LabeledInput(
              label: 'Contraseña nueva',
              child: TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: hidden,
                autofillHints: const [AutofillHints.newPassword],
                validator: _passwordError,
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
              ),
            ),
            const SizedBox(height: 14),
            LabeledInput(
              label: 'Confirmar contraseña',
              child: TextFormField(
                controller: confirmation,
                enabled: !busy,
                obscureText: true,
                validator: (v) =>
                    v != password.text ? 'Las contraseñas no coinciden.' : null,
              ),
            ),
            _ResendCode(sentAt: sentAt!, onResend: _send),
          ],
          if (error case final message?)
            Notice(message, icon: Icons.error_outline, alert: true),
          const Notice(
            'Si tu usuario no es un correo, pide al jefe de calidad de tu empresa una contraseña temporal.',
          ),
        ],
      ),
    ),
  );
}

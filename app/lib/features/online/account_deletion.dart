import 'package:flutter/material.dart';

import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'commercial_plan.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Página web para eliminar una cuenta sin la app. Es la que se registra en
/// Play Console; su fuente está en `web/eliminar-cuenta/`.
const accountDeletionUrl = 'https://metrica.com.bo/ivmet/eliminar-cuenta';

/// Eliminar la propia cuenta o, el jefe de calidad de una empresa
/// autoregistrada, la empresa completa. Se confirma con la contraseña.
///
/// Las verificaciones no se borran: la evidencia de IvMET es inmutable y queda
/// sin datos personales. Eso se dice antes de confirmar, no después.
class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    required this.session,
    this.company = false,
    super.key,
  });
  final MobileSession session;

  /// Toda la empresa, en vez de solo la cuenta propia.
  final bool company;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final password = TextEditingController();
  bool understood = false;
  bool hidden = true;
  bool busy = false;
  String? error;

  bool get company => widget.company;

  // Se toman al abrir: tras eliminar, la sesión se vacía mientras esta
  // pantalla todavía se ve.
  late final String companyName;
  late final String username;
  late final int users;
  late final bool soleManagerWarning;
  bool deleted = false;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    companyName = valueLabel(
      object(session.bootstrap['client'] ?? const <String, dynamic>{})['name'],
    );
    username = session.user!['username'].toString();
    users = session.plan.used(PlanResource.users);
    soleManagerWarning =
        !widget.company && session.quality && session.plan.selfService;
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (busy || !understood || password.text.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.api.deleteAccount(
        scope: company ? 'company' : 'account',
        username: username,
        password: password.text,
      );
      deleted = true;
      // La sesión se cierra y la app vuelve al acceso con el aviso.
      await widget.session.accountDeleted(
        company
            ? 'Se eliminó la empresa y todas sus cuentas.'
            : 'Se eliminó tu cuenta.',
      );
    } on MobileFailure catch (failure) {
      if (mounted) {
        setState(
          () => error = failure.code == 'INVALID_CREDENTIALS'
              ? 'La contraseña no es correcta.'
              : failure.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo eliminar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted && !deleted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return OnlinePage(
      title: company ? 'Eliminar la empresa' : 'Eliminar mi cuenta',
      floating: WizardNavPill.action(
        key: const ValueKey('delete-account-confirm'),
        label: busy ? 'Eliminando…' : 'Eliminar definitivamente',
        icon: Icons.delete_forever_outlined,
        onNext: busy || !understood || password.text.isEmpty ? null : _delete,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          18,
          20,
          WizardNavPill.contentPadding,
        ),
        children: [
          WizardStepHeading(
            title: company ? companyName : 'Tu cuenta',
            caption: company
                ? 'Se elimina la empresa con todas sus cuentas. No se puede deshacer.'
                : 'Se elimina tu acceso a IvMET. No se puede deshacer.',
          ),
          const SectionLabel('Se elimina'),
          for (final item in [
            if (company) ...[
              users == 1
                  ? 'La cuenta de su único usuario y su acceso.'
                  : 'Las cuentas de sus $users usuarios y su acceso.',
              'El nombre de la empresa, sus plantas y los datos de contacto que dejaste al registrarla.',
              'El plan y las solicitudes de plan superior.',
            ] else ...[
              'Tu usuario, tu contraseña y tu acceso a la app.',
              'Tu nombre y tu correo: donde aparecían, queda «Usuario eliminado».',
              'Las capturas que dejaste sin finalizar, aquí y en el servidor.',
            ],
          ])
            _Line(item, icon: Icons.remove_circle_outline, color: palette.fail),
          const SectionLabel('Se conserva, sin datos personales'),
          _Line(
            company
                ? 'Las verificaciones finalizadas y sus lecturas, sin el nombre de la empresa ni de las personas.'
                : 'Las verificaciones que finalizaste: siguen siendo de la empresa, firmadas como «Usuario eliminado».',
            icon: Icons.lock_outline,
            color: palette.muted,
          ),
          _Line(
            'El registro de auditoría de lo que se hizo y cuándo.',
            icon: Icons.lock_outline,
            color: palette.muted,
          ),
          const Notice(
            'La evidencia de una verificación no se modifica ni se borra: así se puede demostrar lo que se midió. Por eso se conserva, desvinculada de quien la hizo.',
            icon: Icons.verified_outlined,
          ),
          if (soleManagerWarning)
            const Notice(
              'Si eres el único jefe de calidad, primero nombra a otro en Ajustes › Usuarios o elimina la empresa completa.',
              icon: Icons.info_outline,
            ),
          const SizedBox(height: 6),
          LabeledInput(
            label: 'Tu contraseña',
            child: TextFormField(
              key: const ValueKey('delete-account-password'),
              controller: password,
              enabled: !busy,
              obscureText: hidden,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
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
          CheckboxListTile(
            key: const ValueKey('delete-account-understood'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: understood,
            onChanged: busy
                ? null
                : (value) => setState(() => understood = value == true),
            title: Text(
              company
                  ? 'Entiendo que la empresa y todas sus cuentas se eliminan definitivamente.'
                  : 'Entiendo que mi cuenta se elimina definitivamente.',
            ),
          ),
          if (error case final message?)
            Notice(message, icon: Icons.error_outline, alert: true),
          const Notice(
            'También puedes pedir la eliminación sin la app, desde $accountDeletionUrl.',
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.icon, required this.color});
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: IndustryPalette.of(context).text,
            ),
          ),
        ),
      ],
    ),
  );
}

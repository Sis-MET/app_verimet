import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/labeled_field.dart';
import '../providers/auth_providers.dart';

/// Ingreso a la app.
///
/// No hay registro ni "olvide mi contrasena" a proposito: los accesos los
/// asigna Metrica por contrato con cada empresa, y un operario que no puede
/// entrar tiene que hablar con su responsable de calidad, no con un
/// formulario.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController(text: 'j.morales@embol.bo');
  final _passwordController = TextEditingController(text: '············');
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await ref
        .read(authProvider.notifier)
        .signIn(email: _emailController.text, password: _passwordController.text);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // El formulario se centra cuando cabe y se desplaza cuando el
            // teclado se come la pantalla; el estado de la VPN se queda
            // anclado abajo en los dos casos.
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(30, 40, 30, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'IvMET',
                        style: AppTextStyles.figure(
                          context,
                          size: 52,
                        ).copyWith(letterSpacing: 52 * -0.02, height: 1),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'MÉTRICA LTDA · VERIFICACIONES INTERMEDIAS',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          letterSpacing: 11 * 0.22,
                          color: palette.accentInk,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 26, bottom: 24),
                        child: Container(height: 1, color: palette.divider),
                      ),
                      LabeledField(
                        label: 'Usuario',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Contraseña',
                        controller: _passwordController,
                        obscureText: true,
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        child: Text(_submitting ? 'Ingresando…' : 'Ingresar'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Los accesos los asigna Métrica. Esta app no tiene registro: '
                        'si no puede ingresar, contacte a su responsable de calidad.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(30, 0, 30, 34), child: _VpnHint()),
          ],
        ),
      ),
    );
  }
}

/// Estado de la VPN antes de intentar entrar.
///
/// Se muestra en el login porque el fallo mas comun no es la contrasena sino
/// el tunel caido: verlo antes de pulsar Ingresar ahorra el error generico.
class _VpnHint extends StatelessWidget {
  const _VpnHint();

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Row(
      children: [
        Container(width: 7, height: 7, color: palette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'VPN corporativa detectada · api.metrica.local',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
          ),
        ),
      ],
    );
  }
}

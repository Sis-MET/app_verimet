import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/proportion_bar.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../eccentricity_test/presentation/widgets/eccentricity_step.dart';
import '../../../linearity_test/presentation/widgets/linearity_step.dart';
import '../../../repeatability_test/presentation/widgets/repeatability_step.dart';
import '../../domain/entities/verification_draft.dart';
import '../providers/verification_wizard_provider.dart';
import '../widgets/instrument_step.dart';
import '../widgets/result_step.dart';
import '../widgets/standards_step.dart';

/// Verificacion intermedia paso a paso.
///
/// Las tres pruebas van dentro del mismo asistente y no en pantallas sueltas:
/// una verificacion solo es valida si las tres se hicieron sobre el mismo
/// equipo, con el mismo patron y en la misma sesion. Separarlas invitaria a
/// dejar una a medias.
class VerificationWizardScreen extends ConsumerWidget {
  const VerificationWizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final draft = ref.watch(verificationWizardProvider);
    final notifier = ref.read(verificationWizardProvider.notifier);
    final step = draft.step;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Kicker('Verificación intermedia'),
                    const SizedBox(height: 2),
                    Text(step.label, style: AppTextStyles.figure(context, size: 26)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Paso ${step.index + 1} de ${VerificationStep.values.length}',
                  style: AppTextStyles.reading(context, size: 12, color: palette.muted),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
            child: ProportionBar(
              height: 3,
              segments: <(int, Color)>[
                (step.index + 1, palette.accent),
                (VerificationStep.values.length - step.index - 1, palette.track),
              ],
            ),
          ),
          switch (step) {
            VerificationStep.equipo => const InstrumentStep(),
            VerificationStep.patron => const StandardsStep(),
            VerificationStep.excentricidad => const EccentricityStep(),
            VerificationStep.repetibilidad => const RepeatabilityStep(),
            VerificationStep.linealidad => const LinearityStep(),
            VerificationStep.resultado => const ResultStep(),
          },
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: step.isFirst ? null : notifier.previous,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: notifier.next, child: Text(_nextLabel(step))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// El boton nombra lo que va a pasar, no "Siguiente": antes de linealidad
  /// avisa de que el paso siguiente ya calcula, y en el resultado ofrece
  /// empezar otra.
  String _nextLabel(VerificationStep step) => switch (step) {
    VerificationStep.linealidad => 'Calcular resultado',
    VerificationStep.resultado => 'Nueva verificación',
    _ => 'Continuar',
  };
}

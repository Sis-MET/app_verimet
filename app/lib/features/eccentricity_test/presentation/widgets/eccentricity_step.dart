import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/readings_capture.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../../verification_reports/presentation/providers/verification_wizard_provider.dart';

/// Paso de excentricidad del asistente.
///
/// La misma carga en los cinco puntos del receptor. Manda el error mas grande:
/// si una esquina se desvia, la balanza pesa distinto segun donde se apoye el
/// producto, aunque el centro salga perfecto.
class EccentricityStep extends ConsumerWidget {
  const EccentricityStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final result = ref.watch(eccentricityResultProvider);
    final notifier = ref.read(verificationWizardProvider.notifier);
    final carga = result.readings.isEmpty ? 0.0 : result.readings.first.nominal;

    return ReadingsCapture(
      readings: result.readings,
      onChanged: notifier.setEccentricityReading,
      loadDescription: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            const TextSpan(text: 'Carga de prueba '),
            TextSpan(
              text: '${carga.toStringAsFixed(2).replaceAll('.', ',')} kg',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' (1/3 del alcance)'),
          ],
        ),
        style: TextStyle(fontSize: 12.5, color: palette.mutedStrong),
      ),
      toleranceLabel: 'Tol. ±${result.formattedTolerance}',
      footer: ReadingsFooter(
        summary: 'Error máximo ${result.formattedMaxError} kg',
        badge: VerdictBadge(verdict: result.verdict),
      ),
    );
  }
}

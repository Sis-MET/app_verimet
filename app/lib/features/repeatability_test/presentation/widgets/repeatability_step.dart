import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/readings_capture.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../../verification_reports/presentation/providers/verification_wizard_provider.dart';

/// Paso de repetibilidad del asistente.
///
/// Se repite la misma carga en el centro del receptor. Lo que se juzga es la
/// dispersion entre lecturas — la desviacion estandar — y no la distancia al
/// patron: una balanza puede estar descentrada y seguir siendo repetible.
class RepeatabilityStep extends ConsumerWidget {
  const RepeatabilityStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final result = ref.watch(repeatabilityResultProvider);
    final notifier = ref.read(verificationWizardProvider.notifier);
    final carga = result.readings.isEmpty ? 0.0 : result.readings.first.nominal;

    return ReadingsCapture(
      readings: result.readings,
      onChanged: notifier.setRepeatabilityReading,
      loadDescription: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            const TextSpan(text: 'Carga repetida '),
            TextSpan(
              text: '${carga.toStringAsFixed(2).replaceAll('.', ',')} kg',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' · centro del receptor'),
          ],
        ),
        style: TextStyle(fontSize: 12.5, color: palette.mutedStrong),
      ),
      toleranceLabel: 'Tol. s ≤ ${result.formattedTolerance}',
      footer: ReadingsFooter(
        summary:
            'Desv. estándar ${result.formattedStandardDeviation} · '
            'rango ${result.formattedRange}',
        badge: VerdictBadge(verdict: result.verdict),
      ),
    );
  }
}

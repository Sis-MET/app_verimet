import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/readings_capture.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../../verification_reports/presentation/providers/verification_wizard_provider.dart';

/// Paso de linealidad del asistente.
///
/// Cinco puntos repartidos por el alcance. Es la prueba que descubre la
/// balanza que pesa bien en el medio del rango y se desvia en los extremos,
/// que es justo lo que no se ve verificando con una sola carga.
class LinearityStep extends ConsumerWidget {
  const LinearityStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final result = ref.watch(linearityResultProvider);
    final notifier = ref.read(verificationWizardProvider.notifier);

    return ReadingsCapture(
      readings: result.readings,
      onChanged: notifier.setLinearityReading,
      loadDescription: Text(
        '${result.readings.length} puntos sobre el rango',
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

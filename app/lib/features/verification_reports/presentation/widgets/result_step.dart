import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/test_verdict.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/blueprint_card.dart';
import '../../../sync/domain/entities/pending_verification.dart';
import '../../../sync/presentation/providers/sync_providers.dart';
import '../providers/verification_wizard_provider.dart';

/// Ultimo paso: veredicto, accion sugerida y cierre.
///
/// La app no se limita a decir conforme o no conforme: dice que hacer con el
/// equipo. Ese texto es la diferencia entre un registro y una decision, y es
/// lo que el operario necesita antes de volver a poner la balanza en linea.
class ResultStep extends ConsumerWidget {
  const ResultStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final draft = ref.watch(verificationWizardProvider);
    final verdict = draft.verdict;
    final isFail = verdict.isFail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlueprintCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'VEREDICTO DE LA VERIFICACIÓN',
                style: AppTextStyles.caption(context, size: 10.5),
              ),
              const SizedBox(height: 2),
              Text(
                verdict.label,
                style: AppTextStyles.figure(
                  context,
                  size: 34,
                  color: isFail ? palette.fail : palette.accentInk,
                ).copyWith(height: 1.1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(height: 1, color: palette.divider),
              ),
              _TestRow(
                label: 'Excentricidad',
                verdict: draft.eccentricity.verdict,
                detail: draft.eccentricity.formattedMaxError,
              ),
              _TestRow(
                label: 'Repetibilidad',
                verdict: draft.repeatability.verdict,
                detail: 's ${draft.repeatability.formattedStandardDeviation}',
              ),
              _TestRow(
                label: 'Linealidad',
                verdict: draft.linearity.verdict,
                detail: draft.linearity.formattedMaxError,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BlueprintCard(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ACCIÓN SUGERIDA',
                style: AppTextStyles.caption(
                  context,
                  size: 10.5,
                ).copyWith(color: palette.accentInk, letterSpacing: 10.5 * 0.12),
              ),
              const SizedBox(height: 4),
              Text(draft.accionSugerida, style: const TextStyle(fontSize: 13.5, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(width: 7, height: 7, color: palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Se guardará en el equipo y se enviará cuando haya VPN.',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: verdict == TestVerdict.pending
              ? null
              : () => _close(context, ref, draft.instrument.codigo),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: const Text('Cerrar y guardar verificación'),
        ),
        TextButton(
          // TODO(IvMET-reports): generar el PDF del informe con los datos del
          // borrador y abrirlo desde `verification_reports`.
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El informe PDF llega con la feature reports.')),
          ),
          child: const Text('Ver informe PDF'),
        ),
      ],
    );
  }

  /// Cierra la verificacion: a la cola local, nunca directo a la red.
  void _close(BuildContext context, WidgetRef ref, String instrumentCode) {
    ref
        .read(syncQueueProvider.notifier)
        .enqueue(
          PendingVerification(
            // TODO(IvMET-sync): usar `UuidGenerator` y la fecha real de cierre
            // cuando la verificacion se persista en Drift.
            clientUuid: 'local-${DateTime.now().millisecondsSinceEpoch}',
            instrumentCode: instrumentCode,
            capturadaEl: 'ahora',
            status: SyncStatus.pending,
          ),
        );
    ref.read(verificationWizardProvider.notifier).reset();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Verificación de $instrumentCode guardada y puesta en cola.')),
    );
  }
}

/// Una prueba en el resumen: su veredicto y la cifra que lo justifica.
class _TestRow extends StatelessWidget {
  const _TestRow({required this.label, required this.verdict, required this.detail});

  final String label;
  final TestVerdict verdict;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(
            '${verdict.label} · $detail',
            style: TextStyle(
              fontSize: 13.5,
              color: verdict.isFail ? palette.fail : palette.mutedStrong,
            ),
          ),
        ],
      ),
    );
  }
}

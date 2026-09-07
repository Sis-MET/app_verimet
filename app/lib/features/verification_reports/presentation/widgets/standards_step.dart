import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../../shared/widgets/industry_icons.dart';
import '../../../../shared/widgets/labeled_field.dart';
import '../providers/verification_wizard_provider.dart';

/// Segundo paso: con que patron y en que condiciones se mide.
///
/// Sin certificado vigente del juego de pesas la verificacion no es trazable,
/// asi que la app avisa aqui — antes de capturar nada — y no al cerrar, cuando
/// el operario ya bajo las pesas del estante.
class StandardsStep extends ConsumerStatefulWidget {
  const StandardsStep({super.key});

  @override
  ConsumerState<StandardsStep> createState() => _StandardsStepState();
}

class _StandardsStepState extends ConsumerState<StandardsStep> {
  late final TextEditingController _juegoPesas;
  late final TextEditingController _certificado;
  late final TextEditingController _vence;
  late final TextEditingController _temperatura;
  late final TextEditingController _humedad;

  @override
  void initState() {
    super.initState();
    final conditions = ref.read(verificationWizardProvider).conditions;
    _juegoPesas = TextEditingController(text: conditions.juegoPesas);
    _certificado = TextEditingController(text: conditions.certificado);
    _vence = TextEditingController(text: conditions.venceCertificado);
    _temperatura = TextEditingController(text: conditions.temperatura);
    _humedad = TextEditingController(text: conditions.humedad);
  }

  @override
  void dispose() {
    _juegoPesas.dispose();
    _certificado.dispose();
    _vence.dispose();
    _temperatura.dispose();
    _humedad.dispose();
    super.dispose();
  }

  void _push() {
    final notifier = ref.read(verificationWizardProvider.notifier);
    notifier.updateConditions(
      ref
          .read(verificationWizardProvider)
          .conditions
          .copyWith(
            juegoPesas: _juegoPesas.text,
            certificado: _certificado.text,
            venceCertificado: _vence.text,
            temperatura: _temperatura.text,
            humedad: _humedad.text,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final conditions = ref.watch(verificationWizardProvider).conditions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Juego de pesas patrón',
          controller: _juegoPesas,
          minHeight: 44,
          fontSize: 15,
          onChanged: (_) => _push(),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Certificado',
                controller: _certificado,
                minHeight: 44,
                fontSize: 15,
                onChanged: (_) => _push(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: 'Vence',
                controller: _vence,
                minHeight: 44,
                fontSize: 15,
                onChanged: (_) => _push(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Temperatura',
                controller: _temperatura,
                minHeight: 44,
                fontSize: 15,
                onChanged: (_) => _push(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: 'Humedad',
                controller: _humedad,
                minHeight: 44,
                fontSize: 15,
                onChanged: (_) => _push(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: IndustryIconView(
                  IndustryIcon.info,
                  size: 19,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El certificado del patrón vence en ${conditions.diasParaVencimiento} días. '
                  'Si venciera antes de la próxima verificación, la app la marcará como no '
                  'trazable.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: palette.mutedStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

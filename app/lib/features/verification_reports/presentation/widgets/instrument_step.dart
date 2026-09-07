import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../../instruments/domain/entities/instrument.dart';
import '../providers/verification_wizard_provider.dart';

/// Primer paso: confirmar que equipo se tiene delante.
///
/// Es el paso que evita el error mas caro de todos — capturar una verificacion
/// buena en la ficha del equipo equivocado — y por eso muestra la placa
/// completa y no solo el codigo.
class InstrumentStep extends ConsumerWidget {
  const InstrumentStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final instrument = ref.watch(verificationWizardProvider).instrument;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      instrument.codigo,
                      style: AppTextStyles.figure(context, size: 22),
                    ),
                  ),
                  StatusTag(instrument.area),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                instrument.marcaModelo ?? instrument.tipo,
                style: TextStyle(fontSize: 13, color: palette.mutedStrong),
              ),
              const SizedBox(height: 14),
              _PlateGrid(instrument: instrument),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Confirme que es el equipo que tiene enfrente. El código también puede '
          'leerse del QR pegado en la placa.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.muted),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          // TODO(IvMET-instruments): abrir el lector de QR y cargar el equipo
          // por codigo de placa.
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El lector de QR llega con la feature instruments.',
              ),
            ),
          ),
          child: const Text('Escanear otro equipo'),
        ),
      ],
    );
  }
}

/// Datos de placa que definen las tolerancias de la verificacion.
class _PlateGrid extends StatelessWidget {
  const _PlateGrid({required this.instrument});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('Alcance máx.', instrument.alcanceMaximo ?? '—'),
      ('División (d)', instrument.division ?? '—'),
      ('Clase', instrument.clase ?? '—'),
      ('Últ. verificación', instrument.ultimaVerificacion ?? 'Sin registro'),
    ];

    return Column(
      children: [
        for (var row = 0; row < entries.length; row += 2)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PlateEntry(entry: entries[row])),
                const SizedBox(width: 14),
                Expanded(
                  child: row + 1 < entries.length
                      ? _PlateEntry(entry: entries[row + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlateEntry extends StatelessWidget {
  const _PlateEntry({required this.entry});

  final (String, String) entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.$1.toUpperCase(),
          style: AppTextStyles.caption(context, size: 10.5),
        ),
        Text(entry.$2, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

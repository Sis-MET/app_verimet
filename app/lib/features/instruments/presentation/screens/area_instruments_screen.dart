import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/compliance_status.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../domain/entities/instrument.dart';
import '../providers/instruments_providers.dart';

/// Segundo nivel: los equipos de un area.
///
/// La lista se lee por la barra de color de la izquierda antes que por el
/// texto: de pie en planta, lo primero que hace falta saber es cuales estan
/// mal, no como se llaman.
class AreaInstrumentsScreen extends ConsumerWidget {
  const AreaInstrumentsScreen({required this.area, super.key});

  final String area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final instruments = ref.watch(areaInstrumentsProvider(area));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.areas),
              style: TextButton.styleFrom(padding: const EdgeInsets.only(right: 8)),
              child: const Text('← Áreas'),
            ),
          ),
          const SizedBox(height: 6),
          Text(area, style: AppTextStyles.figure(context, size: 29)),
          const SizedBox(height: 4),
          Text(
            '${instruments.length} equipos registrados',
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
          const SizedBox(height: 16),
          for (final instrument in instruments)
            _InstrumentRow(
              instrument: instrument,
              onTap: () => context.go(AppRoutes.instrumentHistory(area, instrument.codigo)),
            ),
        ],
      ),
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  const _InstrumentRow({required this.instrument, required this.onTap});

  final Instrument instrument;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    final barColor = switch (instrument.status) {
      ComplianceStatus.conforme => palette.accentMid,
      ComplianceStatus.observado => palette.accentStrong,
      ComplianceStatus.noConforme => palette.failBar,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.divider)),
        ),
        child: Row(
          children: [
            Container(width: 4, height: 34, color: barColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${instrument.codigo} · ${instrument.tipo}',
                    style: AppTextStyles.figure(context, size: 18),
                  ),
                  Text(
                    instrument.detalle,
                    style: TextStyle(fontSize: 12, height: 1.35, color: palette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StatusTag(instrument.estadoLabel, status: instrument.status),
          ],
        ),
      ),
    );
  }
}

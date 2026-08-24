import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/blueprint_card.dart';
import '../../../../shared/widgets/industry_icons.dart';
import '../../../../shared/widgets/proportion_bar.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/area.dart';
import '../providers/instruments_providers.dart';

/// Primer nivel del apartado Áreas: por donde esta repartido el parque.
///
/// Cada tarjeta lleva su reparto por estado en una barra de tres tramos, para
/// poder elegir a que area ir sin entrar en ninguna.
class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider);
    final cliente = ref.watch(clienteNombreProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Kicker(cliente),
          const SizedBox(height: 2),
          Text('Áreas', style: AppTextStyles.figure(context, size: 29)),
          const SizedBox(height: 16),
          for (final area in areas)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AreaCard(area: area),
            ),
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area});

  final Area area;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return BlueprintCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      onTap: () => context.go(AppRoutes.areaDetail(area.nombre)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(area.nombre, style: AppTextStyles.figure(context, size: 21)),
                    Text(area.resumen, style: TextStyle(fontSize: 12.5, color: palette.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${area.total}',
                style: AppTextStyles.figure(context, size: 28, color: palette.accentInk),
              ),
              const SizedBox(width: 8),
              IndustryIconView(
                IndustryIcon.chevronRight,
                size: 18,
                color: palette.text.withValues(alpha: 0.45),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatusBar(area: area),
        ],
      ),
    );
  }
}

/// Reparto del area en tres tramos: conforme, observado y no conforme.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.area});

  final Area area;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return ProportionBar(
      gap: 1,
      segments: <(int, Color)>[
        (area.conformes, palette.accentMid),
        (area.observados, palette.accentStrong),
        (area.noConformes, palette.failBar),
      ],
    );
  }
}

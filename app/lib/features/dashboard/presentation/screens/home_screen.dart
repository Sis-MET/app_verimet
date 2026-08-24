import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/compliance_status.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/blueprint_card.dart';
import '../../../../shared/widgets/industry_icons.dart';
import '../../../../shared/widgets/proportion_bar.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sync/presentation/providers/sync_providers.dart';
import '../../domain/entities/dashboard_overview.dart';
import '../providers/dashboard_providers.dart';

/// Inicio: el estado del parque de un vistazo.
///
/// El orden de la pantalla es el orden de urgencia — cuanto hay, que esta
/// roto, que vence, que se hizo y que viene — para que el jefe de calidad
/// sepa a donde ir sin abrir nada.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dashboardOverviewProvider);
    final cliente = ref.watch(clienteNombreProvider);
    final pendientes = ref.watch(pendingSyncCountProvider);
    final summary = overview.summary;

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
                    Kicker(cliente),
                    const SizedBox(height: 2),
                    Text('Estado del parque', style: AppTextStyles.figure(context, size: 29)),
                  ],
                ),
              ),
              if (pendientes > 0) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StatusTag('$pendientes por sincronizar'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          // Las dos tarjetas se igualan en alto: puestas una al lado de la otra,
          // una mas corta que la otra rompe la lectura de plano.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _EquiposCard(summary: summary)),
                const SizedBox(width: 10),
                Expanded(child: _ConformidadCard(summary: summary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          StatStrip(
            cells: [
              StatCell(value: '${summary.conformes}', label: 'Conformes'),
              StatCell(value: '${summary.observados}', label: 'Observados'),
              StatCell(
                value: '${summary.noConformes}',
                label: 'No conf.',
                valueColor: IndustryPalette.of(context).fail,
              ),
            ],
          ),
          const SectionLabel('Alertas críticas', padding: EdgeInsets.only(top: 26, bottom: 8)),
          for (final alerta in overview.alertas) _AlertRow(alerta: alerta),
          const SectionLabel('Vencidas y por vencer'),
          for (final vencimiento in overview.vencimientos) _DueRow(item: vencimiento),
          const SectionLabel('Últimas verificaciones'),
          for (final ultima in overview.ultimas) _RecentRow(item: ultima),
          const SectionLabel('Próximas calibraciones externas'),
          BlueprintCard(
            child: Column(
              children: [
                for (final calibracion in overview.calibraciones)
                  Padding(
                    padding: EdgeInsets.only(
                      top: calibracion == overview.calibraciones.first ? 0 : 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            calibracion.equipo,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          calibracion.fecha,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: IndustryPalette.of(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquiposCard extends StatelessWidget {
  const _EquiposCard({required this.summary});

  final ParkSummary summary;

  @override
  Widget build(BuildContext context) {
    return BlueprintCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('EQUIPOS', style: AppTextStyles.caption(context)),
          Text('${summary.equipos}', style: AppTextStyles.figure(context)),
          Text(
            'en ${summary.areas} áreas',
            style: TextStyle(fontSize: 11.5, color: IndustryPalette.of(context).muted),
          ),
        ],
      ),
    );
  }
}

class _ConformidadCard extends StatelessWidget {
  const _ConformidadCard({required this.summary});

  final ParkSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return BlueprintCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CONFORMIDAD', style: AppTextStyles.caption(context)),
          Text(
            '${summary.conformidad}%',
            style: AppTextStyles.figure(context, color: palette.accentInk),
          ),
          const SizedBox(height: 6),
          ProportionBar(
            segments: <(int, Color)>[
              (summary.conformidad, palette.accent),
              (100 - summary.conformidad, palette.track),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alerta critica: barra de oxido a la izquierda para que se encuentre sin
/// leer.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alerta});

  final CriticalAlert alerta;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.divider),
          right: BorderSide(color: palette.divider),
          bottom: BorderSide(color: palette.divider),
          left: BorderSide(color: palette.fail, width: 3),
        ),
      ),
      child: Row(
        children: [
          IndustryIconView(IndustryIcon.warning, size: 20, color: palette.fail),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(alerta.equipo, style: AppTextStyles.figure(context, size: 16)),
                Text(
                  alerta.detalle,
                  style: TextStyle(fontSize: 12, height: 1.35, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IndustryIconView(
            IndustryIcon.chevronRight,
            size: 18,
            color: palette.text.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item});

  final DueVerification item;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              item.codigo,
              style: AppTextStyles.reading(context, size: 12, color: palette.accentInk),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.descripcion, style: const TextStyle(fontSize: 13.5))),
          const SizedBox(width: 10),
          Text(
            item.plazo,
            style: TextStyle(fontSize: 12, color: item.vencida ? palette.fail : palette.muted),
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item});

  final RecentVerification item;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final isFail = item.veredicto == ComplianceStatus.noConforme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 66,
            child: Text(item.codigo, style: AppTextStyles.reading(context, size: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.fecha} · ${item.responsable}',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.veredicto.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 11 * 0.06,
              color: isFail ? palette.fail : palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

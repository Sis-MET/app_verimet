import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/domain/compliance_status.dart';
import '../../../../core/utils/measurement_format.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../../shared/widgets/status_tag.dart';
import '../../domain/entities/verification_history_entry.dart';
import '../providers/instruments_providers.dart';

/// Tercer nivel: la ficha de un equipo y su historico.
///
/// Una verificacion suelta dice poco; la serie dice si el equipo se esta
/// yendo. Por eso el historico guarda el error de cada prueba y no solo el
/// veredicto.
class InstrumentHistoryScreen extends ConsumerWidget {
  const InstrumentHistoryScreen({required this.area, required this.codigo, super.key});

  final String area;
  final String codigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final instrument = ref.watch(instrumentByCodeProvider(codigo));
    final history = ref.watch(instrumentHistoryProvider(codigo));

    final conformes = history.where((entry) => entry.veredicto == ComplianceStatus.conforme).length;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.areaDetail(area)),
              style: TextButton.styleFrom(padding: const EdgeInsets.only(right: 8)),
              child: Text('← $area'),
            ),
          ),
          const SizedBox(height: 6),
          Text(codigo, style: AppTextStyles.figure(context, size: 29)),
          const SizedBox(height: 2),
          Text(
            instrument == null
                ? 'Equipo no encontrado en la copia local.'
                : '${instrument.tipo} · ${instrument.detalle}',
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
          const SizedBox(height: 16),
          StatStrip(
            cells: [
              StatCell(value: '${history.length}', label: 'Verif.'),
              StatCell(value: '$conformes', label: 'Conformes'),
              StatCell(value: _maxError(history), label: 'Err. máx'),
            ],
          ),
          const SectionLabel('Histórico', padding: EdgeInsets.only(top: 20, bottom: 8)),
          for (final entry in history) _HistoryRow(entry: entry),
        ],
      ),
    );
  }

  /// Peor error registrado en todo el historico, sea de la prueba que sea: es
  /// la cifra que se mira para decidir si el equipo aguanta otra campana.
  String _maxError(List<VerificationHistoryEntry> history) {
    var maximum = 0.0;
    for (final entry in history) {
      for (final value in <String>[
        entry.errorExcentricidad,
        entry.desviacionRepetibilidad,
        entry.errorLinealidad,
      ]) {
        final parsed = MeasurementFormat.parse(value);
        if (parsed != null && parsed > maximum) maximum = parsed;
      }
    }
    return MeasurementFormat.format(maximum);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final VerificationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(entry.fecha, style: AppTextStyles.reading(context, size: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.responsable, style: const TextStyle(fontSize: 13.5)),
                Text(
                  'ecc ${entry.errorExcentricidad} · rep ${entry.desviacionRepetibilidad} · '
                  'lin ${entry.errorLinealidad}',
                  style: TextStyle(fontSize: 11.5, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          StatusTag.of(entry.veredicto),
        ],
      ),
    );
  }
}

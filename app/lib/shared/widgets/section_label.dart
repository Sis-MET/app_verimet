import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Rotulo de seccion (h6 del sistema): versalitas separadas, sin regla.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.padding, super.key});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text.toUpperCase(), style: AppTextStyles.sectionLabel(context)),
    );
  }
}

/// Linea corta sobre un titulo: nombre del cliente, codigo del equipo, prueba
/// en curso. Siempre en acero y muy espaciada.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: AppTextStyles.kicker(context));
  }
}

/// Fila de celdas con cifra y pie, separadas por el hairline del sistema.
///
/// Es el patron de "41 conformes / 5 observados / 2 no conformes": las celdas
/// se separan dejando ver 1 px del fondo divisor, no con bordes propios.
class StatStrip extends StatelessWidget {
  const StatStrip({required this.cells, super.key});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      color: palette.divider,
      // Las celdas comparten altura para que el hairline que las separa llegue
      // de arriba abajo aunque una etiqueta ocupe dos lineas.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 1),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Celda de [StatStrip]: una cifra grande y su etiqueta en versalitas.
class StatCell extends StatelessWidget {
  const StatCell({required this.value, required this.label, this.valueColor, super.key});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      color: palette.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AppTextStyles.figure(context, size: 24, color: valueColor)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: AppTextStyles.caption(context, size: 10.5)),
        ],
      ),
    );
  }
}

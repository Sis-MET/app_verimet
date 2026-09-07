import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
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
      padding: padding ?? const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.sectionLabel(context),
      ),
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

/// Fila de celdas con cifra y pie, dentro de una sola tarjeta.
///
/// Es el patron de "41 conformes / 5 observados / 2 no conformes". Antes eran
/// celdas sueltas puestas sobre un fondo divisor que asomaba 1 px entre ellas;
/// ahora comparten tarjeta y las separa un hairline corto, sin lineas que
/// lleguen al borde.
class StatStrip extends StatelessWidget {
  const StatStrip({required this.cells, super.key});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Material(
      color: palette.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: palette.divider),
      ),
      // Las celdas comparten altura para que el hairline que las separa llegue
      // de arriba abajo aunque una etiqueta ocupe dos lineas.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 12,
                  endIndent: 12,
                  color: palette.hairline,
                ),
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
  const StatCell({
    required this.value,
    required this.label,
    this.valueColor,
    super.key,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTextStyles.figure(context, size: 24, color: valueColor),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.caption(context, size: 10.5),
          ),
        ],
      ),
    );
  }
}

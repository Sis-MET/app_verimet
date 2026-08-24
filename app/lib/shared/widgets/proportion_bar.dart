import 'package:flutter/material.dart';

/// Barra de proporciones: tramos rectos de colores, sin bordes ni redondeos.
///
/// Es la regla graduada del sistema y sirve igual para el avance del asistente
/// que para el reparto por estado de un area. Los tramos vacios se descartan —
/// un tramo de peso cero no ocupa espacio, y dejarlo obligaria al `Row` a
/// repartir un ancho infinito entre nada.
class ProportionBar extends StatelessWidget {
  const ProportionBar({required this.segments, this.height = 4, this.gap = 0, super.key});

  /// Peso y color de cada tramo, en orden de izquierda a derecha.
  final List<(int weight, Color color)> segments;

  final double height;

  /// Aire entre tramos. En los repartos por estado deja ver el fondo y separa
  /// los colores; en una barra de avance va a cero.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((segment) => segment.$1 > 0).toList(growable: false);
    if (visible.isEmpty) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0 && gap > 0) SizedBox(width: gap),
            Expanded(
              flex: visible[i].$1,
              child: ColoredBox(color: visible[i].$2, child: const SizedBox.expand()),
            ),
          ],
        ],
      ),
    );
  }
}

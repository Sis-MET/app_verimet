import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';

/// Barra de proporciones: tramos de color con las puntas redondeadas.
///
/// Es la regla graduada del sistema y sirve igual para el avance del asistente
/// que para el reparto por estado de un area. Los tramos vacios se descartan —
/// un tramo de peso cero no ocupa espacio, y dejarlo obligaria al `Row` a
/// repartir un ancho infinito entre nada.
///
/// El redondeo depende de si hay aire entre tramos: sin aire se redondea la
/// barra entera (o quedarian muescas donde un tramo toca al siguiente), y con
/// aire se redondea cada tramo por separado.
class ProportionBar extends StatelessWidget {
  const ProportionBar({
    required this.segments,
    this.height = 6,
    this.gap = 0,
    super.key,
  });

  /// Peso y color de cada tramo, en orden de izquierda a derecha.
  final List<(int weight, Color color)> segments;

  final double height;

  /// Aire entre tramos. En los repartos por estado deja ver el fondo y separa
  /// los colores; en una barra de avance va a cero.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final visible = segments
        .where((segment) => segment.$1 > 0)
        .toList(growable: false);
    if (visible.isEmpty) return SizedBox(height: height);

    final corners = BorderRadius.circular(
      (height / 2).clamp(0, AppRadius.xs).toDouble(),
    );

    Widget fill(Color color) => gap > 0
        ? DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: corners),
            child: const SizedBox.expand(),
          )
        : ColoredBox(color: color, child: const SizedBox.expand());

    final Widget bar = SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0 && gap > 0) SizedBox(width: gap),
            Expanded(flex: visible[i].$1, child: fill(visible[i].$2)),
          ],
        ],
      ),
    );

    return gap > 0 ? bar : ClipRRect(borderRadius: corners, child: bar);
  }
}

import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';
import 'surface_card.dart';

/// Mosaico de modulos: el patron de "plano de planta" del sistema.
///
/// Las pantallas de entrada no son listas: son cuadros grandes puestos uno al
/// lado del otro, cada uno con una sola funcion. Un modulo ocupa una columna y
/// uno destacado ocupa la fila entera ([TileCell.span]).
///
/// La altura la fija el modulo mas alto de cada fila y no un numero cerrado:
/// con "Texto grande" activado los rotulos crecen y el cuadro crece con ellos
/// en vez de recortarlos.
class TileGrid extends StatelessWidget {
  const TileGrid({
    required this.cells,
    this.columns = 2,
    this.gap = 12,
    this.minTileHeight = 128,
    this.wideTileHeight = 100,
    super.key,
  });

  final List<TileCell> cells;
  final int columns;
  final double gap;

  /// Suelo del cuadro. Es lo que hace que se lea como modulo y no como fila.
  final double minTileHeight;

  /// Suelo de la fila entera. Un modulo ancho no necesita ser tan alto como
  /// uno de media fila: con la misma altura queda un hueco muerto en medio.
  final double wideTileHeight;

  List<List<TileCell>> _rows() {
    final rows = <List<TileCell>>[];
    var current = <TileCell>[];
    var used = 0;

    for (final cell in cells) {
      final span = cell.span.clamp(1, columns);
      if (used + span > columns) {
        rows.add(current);
        current = <TileCell>[];
        used = 0;
      }
      current.add(cell);
      used += span;
      if (used == columns) {
        rows.add(current);
        current = <TileCell>[];
        used = 0;
      }
    }
    if (current.isNotEmpty) rows.add(current);

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : gap),
            child: _row(rows[i]),
          ),
      ],
    );
  }

  Widget _row(List<TileCell> row) {
    var used = 0;
    var wide = false;
    for (final cell in row) {
      final span = cell.span.clamp(1, columns);
      used += span;
      if (span == columns) wide = true;
    }
    // Un modulo suelto conserva el ancho de su columna: la ultima fila no se
    // estira para rellenar, o el mosaico deja de leerse como retícula.
    final free = columns - used;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: wide ? wideTileHeight : minTileHeight,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < row.length; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(
                flex: row[j].span.clamp(1, columns),
                child: row[j].child,
              ),
            ],
            if (free > 0) ...[
              SizedBox(width: gap),
              Expanded(flex: free, child: const SizedBox.shrink()),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un modulo del mosaico y cuantas columnas ocupa.
class TileCell {
  const TileCell(this.child, {this.span = 1});

  /// Modulo destacado: ocupa la fila entera.
  const TileCell.wide(this.child) : span = 2;

  final Widget child;
  final int span;
}

/// Cuadro de accion: un icono, un rotulo grande y una linea de contexto.
///
/// Es el equivalente en modulo del boton del sistema. [primary] lo rellena de
/// acero y se reserva a la accion principal de la pantalla: solo puede haber
/// una a la vista.
class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    this.caption,
    this.onTap,
    this.primary = false,
    this.badge,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final bool primary;

  /// Etiqueta corta arriba a la derecha (un contador, un estado).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final enabled = onTap != null;

    final Color ink;
    if (primary) {
      ink = palette.card;
    } else if (enabled) {
      ink = palette.text;
    } else {
      ink = palette.muted;
    }
    final Color subInk = primary
        ? palette.card.withValues(alpha: 0.80)
        : palette.muted;

    return Opacity(
      // Lo deshabilitado no se esconde: se apaga. El operario tiene que ver
      // que la funcion existe y que ahora mismo no le toca.
      opacity: enabled ? 1 : 0.55,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        background: primary ? palette.accent : null,
        borderColor: primary ? palette.accent : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // El icono va sobre una pastilla del mismo acero rebajado: da
                // un punto de apoyo al modulo sin sumar otro contorno.
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary
                        ? palette.card.withValues(alpha: 0.16)
                        : palette.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 21,
                    color: primary ? palette.card : palette.accentInk,
                  ),
                ),
                // El badge cede ancho antes que desbordar: el rotulo del
                // modulo manda y la etiqueta es contexto.
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: badge!,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.figure(context, size: 19, color: ink),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    caption!,
                    style: TextStyle(fontSize: 12, height: 1.3, color: subInk),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuadro de cifra: el rotulo arriba, el numero grande abajo.
///
/// Se usa para lo que se mira de un vistazo (cuantas balanzas, cuantas
/// alertas). Si lleva [onTap] entra al detalle de esa cifra.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    this.caption,
    this.onTap,
    this.valueColor,
    this.footer,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final VoidCallback? onTap;
  final Color? valueColor;

  /// Se dibuja bajo la cifra (una barra de reparto, por ejemplo).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.caption(context)),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTextStyles.figure(
                  context,
                  size: 40,
                  color: valueColor,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: palette.muted,
                  ),
                ),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
            ],
          ),
        ],
      ),
    );
  }
}

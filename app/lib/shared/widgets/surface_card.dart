import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/industry_palette.dart';

/// Tarjeta del sistema: plano claro, esquinas redondeadas y un contorno muy
/// suave.
///
/// Sustituye a la antigua tarjeta de plano de taller, que era transparente,
/// recta y llevaba cruces de registro dibujadas *fuera* del borde. Aquellas
/// cruces se leian como raspaduras sueltas alrededor del cuadro y ensuciaban
/// cada pantalla: lo que separa una tarjeta del fondo ahora es que la tarjeta
/// es mas clara, no una marca añadida.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.onTap,
    this.background,
    this.borderColor,
    this.radius,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Si se pasa, toda la tarjeta es tocable (areas, equipos).
  final VoidCallback? onTap;

  /// Por defecto el plano de tarjeta del tema. Se pasa para la unica accion
  /// principal de una pantalla, que va rellena de acero.
  final Color? background;

  /// Contorno propio. Solo se pasa cuando la tarjeta va rellena y el divisor
  /// normal no contrastaria.
  final Color? borderColor;

  /// Radio propio. Por defecto [AppRadius.md].
  final double? radius;

  /// Despega la tarjeta del fondo con la sombra difusa del sistema. Se reserva
  /// a lo que se superpone al contenido.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final corners = BorderRadius.circular(radius ?? AppRadius.md);
    final fill = background ?? palette.card;

    final Widget surface = Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: corners,
        side: BorderSide(color: borderColor ?? palette.divider),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              splashColor: palette.accent.withValues(alpha: 0.10),
              highlightColor: palette.accent.withValues(alpha: 0.05),
              child: Padding(padding: padding, child: child),
            ),
    );

    if (!elevated) return surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: AppShadows.resting(palette.shadow),
      ),
      child: surface,
    );
  }
}

/// Lista agrupada: varias filas dentro de una sola tarjeta, separadas por un
/// hairline que no llega a los bordes.
///
/// Es el reemplazo de las filas sueltas con borde inferior. Aquel patron
/// dejaba lineas cortadas por toda la pantalla; agrupadas, las mismas filas se
/// leen como un bloque y el ojo solo tiene que seguir un contorno.
class SurfaceList extends StatelessWidget {
  const SurfaceList({
    required this.children,
    this.separatorIndent = 16,
    this.background,
    this.radius,
    super.key,
  });

  /// Filas de la lista. Cada una pone su propio relleno horizontal para que el
  /// toque cubra la fila entera.
  final List<Widget> children;

  /// Sangria del separador. Alinea la linea con el texto de la fila.
  final double separatorIndent;

  final Color? background;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    if (children.isEmpty) return const SizedBox.shrink();

    return Material(
      color: background ?? palette.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius ?? AppRadius.md),
        side: BorderSide(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: separatorIndent,
                endIndent: separatorIndent,
                color: palette.hairline,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

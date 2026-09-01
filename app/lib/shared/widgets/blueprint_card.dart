import 'package:flutter/material.dart';

import '../theme/industry_palette.dart';

/// Tarjeta del sistema "Industry": caja recta con hairline y marcas de
/// registro en las cuatro esquinas.
///
/// Las marcas son las cruces de un plano de taller y se dibujan *por fuera*
/// del borde, igual que en el design system; por eso la tarjeta necesita unos
/// milimetros de aire alrededor y no debe ir pegada al borde de la pantalla.
class BlueprintCard extends StatelessWidget {
  const BlueprintCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.onTap,
    this.background,
    this.markColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Si se pasa, toda la tarjeta es tocable (areas, equipos).
  final VoidCallback? onTap;

  /// Por defecto transparente: el sistema no rellena las tarjetas.
  final Color? background;

  /// Tinta de las marcas de registro. Solo se pasa cuando la tarjeta va
  /// rellena de acero y la tinta normal no contrastaria.
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    final Widget card = CustomPaint(
      foregroundPainter: _RegistrationMarks(
        color: markColor ?? palette.text.withValues(alpha: 0.55),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: palette.divider),
        ),
        padding: padding,
        child: child,
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: palette.accent.withValues(alpha: 0.12),
        highlightColor: palette.accent.withValues(alpha: 0.06),
        child: card,
      ),
    );
  }
}

/// Cruces de registro de 11 px centradas en cada esquina de la caja.
class _RegistrationMarks extends CustomPainter {
  const _RegistrationMarks({required this.color});

  final Color color;

  static const double _arm = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;

    for (final corner in <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      canvas.drawLine(
        Offset(corner.dx - _arm, corner.dy),
        Offset(corner.dx + _arm, corner.dy),
        paint,
      );
      canvas.drawLine(
        Offset(corner.dx, corner.dy - _arm),
        Offset(corner.dx, corner.dy + _arm),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RegistrationMarks oldDelegate) => oldDelegate.color != color;
}

import 'package:flutter/material.dart';

/// Iconografia del sistema "Industry".
///
/// No se usan los iconos de Material: son de esquinas redondeadas y trazo
/// variable, y aqui todo es hairline recto de 1,5 px sobre una retícula de 24.
/// Son pocos y simples, asi que se dibujan a mano en vez de arrastrar una
/// familia de iconos entera.
enum IndustryIcon {
  /// Inicio: tejado y puerta.
  home,

  /// Verificar: tablilla con visto.
  clipboardCheck,

  /// Areas: retícula de cuatro modulos.
  grid,

  /// Ajustes: tres correderas.
  sliders,

  /// Alerta critica.
  warning,

  /// Nota informativa.
  info,

  /// Entrar al detalle.
  chevronRight,
}

/// Dibuja un [IndustryIcon] al tamano pedido, heredando el color si no se
/// pasa uno.
class IndustryIconView extends StatelessWidget {
  const IndustryIconView(
    this.icon, {
    this.size = 22,
    this.color,
    this.strokeWidth = 1.5,
    super.key,
  });

  final IndustryIcon icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _IndustryIconPainter(icon: icon, color: resolved, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _IndustryIconPainter extends CustomPainter {
  const _IndustryIconPainter({required this.icon, required this.color, required this.strokeWidth});

  final IndustryIcon icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);

    // El trazo se pide en pixeles de pantalla, pero los trazados estan en la
    // retícula de 24: hay que descontarle la escala para que el hairline no
    // engorde en los tamanos grandes.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..color = color;

    switch (icon) {
      case IndustryIcon.home:
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 10.5)
            ..lineTo(12, 4)
            ..lineTo(20.5, 10.5)
            ..lineTo(20.5, 20)
            ..lineTo(3.5, 20)
            ..close(),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(9.5, 20)
            ..lineTo(9.5, 14)
            ..lineTo(14.5, 14)
            ..lineTo(14.5, 20),
          paint,
        );
      case IndustryIcon.clipboardCheck:
        canvas.drawRect(const Rect.fromLTWH(5, 4, 14, 17), paint);
        canvas.drawRect(const Rect.fromLTWH(9, 2, 6, 4), paint);
        canvas.drawPath(
          Path()
            ..moveTo(9, 13)
            ..lineTo(11.4, 15.4)
            ..lineTo(16, 11),
          paint,
        );
      case IndustryIcon.grid:
        for (final origin in const <Offset>[
          Offset(4, 4),
          Offset(13, 4),
          Offset(4, 13),
          Offset(13, 13),
        ]) {
          canvas.drawRect(Rect.fromLTWH(origin.dx, origin.dy, 7, 7), paint);
        }
      case IndustryIcon.sliders:
        for (final y in const <double>[7, 12, 17]) {
          canvas.drawLine(Offset(4, y), Offset(20, y), paint);
        }
        canvas.drawCircle(const Offset(9, 7), 2, paint);
        canvas.drawCircle(const Offset(15, 12), 2, paint);
        canvas.drawCircle(const Offset(8, 17), 2, paint);
      case IndustryIcon.warning:
        canvas.drawPath(
          Path()
            ..moveTo(12, 4)
            ..lineTo(2.5, 20)
            ..lineTo(21.5, 20)
            ..close(),
          paint,
        );
        canvas.drawLine(const Offset(12, 10), const Offset(12, 14.5), paint);
        canvas.drawLine(const Offset(12, 17.2), const Offset(12, 17.6), paint);
      case IndustryIcon.info:
        canvas.drawCircle(const Offset(12, 12), 9, paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 17), paint);
        canvas.drawLine(const Offset(12, 7.6), const Offset(12, 8), paint);
      case IndustryIcon.chevronRight:
        canvas.drawPath(
          Path()
            ..moveTo(9, 6)
            ..lineTo(15, 12)
            ..lineTo(9, 18),
          paint,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_IndustryIconPainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

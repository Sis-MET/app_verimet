import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import 'setup_guide.dart';

/// Escenas animadas de la guía de inicio: lo que pide cada paso, en pequeño.
///
/// Son dibujos con las piezas del sistema (acero, pastillas, el óxido solo
/// para lo que falla) y no ilustraciones: una planta que se divide en áreas,
/// una pesa que recorre la plataforma, la lectura que cae dentro o fuera de
/// la tolerancia. Se repiten en bucle mientras el paso está a la vista.
///
/// Con «Quitar animaciones» del sistema (`MediaQuery.disableAnimations`) se
/// dibuja el cuadro final, quieto. Son decorativas: no llevan semántica.

/// Duración de una vuelta de escena.
const guideSceneLoop = Duration(milliseconds: 4200);

/// Cuadro que se muestra quieto sin animaciones: todo ya aparecido.
const guideSceneRest = 0.82;

/// Progreso de [t] entre [start] y [end], suavizado.
double _p(
  double t,
  double start,
  double end, [
  Curve curve = Curves.easeOutCubic,
]) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return curve.transform((t - start) / (end - start));
}

/// Desvanece la escena al final de la vuelta para que reinicie sin salto.
double _fade(double t) => 1 - _p(t, 0.92, 1, Curves.easeIn);

class GuideSceneView extends StatelessWidget {
  const GuideSceneView({
    required this.scene,
    required this.animation,
    this.height = 164,
    super.key,
  });

  final GuideScene scene;
  final Animation<double> animation;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    // Es un dibujo de medidas fijas: el texto grande no lo deforma.
    child: MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              final size = Size(box.maxWidth, height);
              return Opacity(
                opacity: _fade(t),
                child: switch (scene) {
                  GuideScene.plants => _PlantsScene(t, size),
                  GuideScene.patterns => _PatternsScene(t, size),
                  GuideScene.scale => _ScaleScene(t, size),
                  GuideScene.tests => _TestsScene(t, size),
                  GuideScene.tolerance => _ToleranceScene(t, size),
                  GuideScene.users => _UsersScene(t, size),
                  GuideScene.assign => _AssignScene(t, size),
                  GuideScene.capture => _CaptureScene(t, size),
                  GuideScene.results => _ResultsScene(t, size),
                  GuideScene.agenda => _AgendaScene(t, size),
                  GuideScene.eccentricity => _EccentricityScene(t, size),
                  GuideScene.repeatability => _RepeatabilityScene(t, size),
                  GuideScene.linearity => _LinearityScene(t, size),
                  GuideScene.offline => _OfflineScene(t, size),
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

// ── Piezas ───────────────────────────────────────────────────────────────

/// Aparece creciendo un poco más de la cuenta y asentándose.
class _Pop extends StatelessWidget {
  const _Pop(this.progress, {required this.child});
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(progress);
    return Opacity(
      opacity: progress.clamp(0, 1),
      child: Transform.scale(scale: scale, child: child),
    );
  }
}

/// Círculo con un icono: el actor de la escena.
class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, {this.size = 64, this.filled = false});
  final IconData icon;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? palette.accent : palette.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: filled ? palette.card : palette.accentInk,
      ),
    );
  }
}

enum _Tone { steel, muted, ok, fail }

/// Pastilla de texto, en el tono que pida la escena.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.tone = _Tone.steel, this.icon, this.size = 12});
  final String text;
  final _Tone tone;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final (Color fill, Color ink, Color border) = switch (tone) {
      _Tone.steel => (palette.card, palette.accentInk, palette.divider),
      _Tone.muted => (palette.card, palette.muted, palette.divider),
      _Tone.ok => (palette.accent, palette.card, palette.accent),
      _Tone.fail => (palette.failSurface, palette.failInk, palette.fail),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.85,
        vertical: size * 0.4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size + 2, color: ink),
            SizedBox(width: size * 0.4),
          ],
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloca [child] centrado en [center], dentro de un [Stack].
Widget _at(Offset center, Widget child, {double box = 200}) => Positioned(
  left: center.dx - box / 2,
  top: center.dy - box / 2,
  width: box,
  height: box,
  child: Center(
    child: FittedBox(fit: BoxFit.scaleDown, child: child),
  ),
);

/// Líneas que se van trazando de un punto a otro.
class _Links extends CustomPainter {
  const _Links(this.links, this.color, {this.dashed = false});
  final List<(Offset, Offset, double)> links;
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (from, to, progress) in links) {
      if (progress <= 0) continue;
      final end = Offset.lerp(from, to, progress)!;
      if (!dashed) {
        canvas.drawLine(from, end, paint);
        continue;
      }
      final length = (end - from).distance;
      final direction = (to - from) / (to - from).distance;
      for (var d = 0.0; d < length; d += 9) {
        canvas.drawLine(
          from + direction * d,
          from + direction * math.min(d + 4.5, length),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Links old) => true;
}

// ── Escenas ──────────────────────────────────────────────────────────────

/// Una planta que se reparte en áreas.
class _PlantsScene extends StatelessWidget {
  const _PlantsScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    final plant = Offset(w * 0.22, h / 2);
    const areas = ['Producción', 'Despacho', 'Laboratorio'];
    final tags = [
      for (var i = 0; i < 3; i++) Offset(w * 0.68, h / 2 + (i - 1) * 46),
    ];
    final grow = [
      for (var i = 0; i < 3; i++) _p(t, 0.12 + i * 0.16, 0.3 + i * 0.16),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _Links([
              for (var i = 0; i < 3; i++)
                (
                  plant + const Offset(34, 0),
                  tags[i] - Offset(w * 0.14, 0),
                  grow[i],
                ),
            ], palette.accentMid),
          ),
        ),
        _at(
          plant,
          _Pop(
            _p(t, 0, 0.12),
            child: const _Glyph(Icons.factory_outlined, size: 68, filled: true),
          ),
        ),
        for (var i = 0; i < 3; i++)
          _at(
            tags[i],
            _Pop(grow[i], child: _Tag(areas[i], icon: Icons.grid_view_rounded)),
            box: w * 0.3 + 40,
          ),
      ],
    );
  }
}

/// Pesas que caen en fila y un certificado vigente.
class _PatternsScene extends StatelessWidget {
  const _PatternsScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    const weights = [('1 kg', 30.0), ('5 kg', 40.0), ('20 kg', 54.0)];
    final base = h * 0.78;
    final card = _p(t, 0.45, 0.62);
    return Stack(
      children: [
        Positioned(
          left: w * 0.06,
          width: w * 0.46,
          top: base,
          height: 2,
          child: ColoredBox(color: palette.divider),
        ),
        for (var i = 0; i < weights.length; i++)
          Builder(
            builder: (context) {
              final drop = _p(
                t,
                0.05 + i * 0.12,
                0.2 + i * 0.12,
                Curves.bounceOut,
              );
              final (label, side) = weights[i];
              return Positioned(
                left: w * 0.08 + i * (w * 0.15),
                top: base - side - (1 - drop) * 60,
                child: Opacity(
                  opacity: drop == 0 ? 0 : 1,
                  child: _Weight(label, side),
                ),
              );
            },
          ),
        Positioned(
          left: w * 0.56 + (1 - card) * 30,
          top: h * 0.16,
          width: w * 0.4,
          child: Opacity(
            opacity: card,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 20,
                    color: palette.accent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Certificado',
                    maxLines: 1,
                    style: AppTextStyles.figure(context, size: 15),
                  ),
                  Text(
                    'Vence 12/2027',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  const SizedBox(height: 8),
                  _Pop(
                    _p(t, 0.66, 0.78),
                    child: const _Tag(
                      'Vigente',
                      tone: _Tone.ok,
                      icon: Icons.check,
                      size: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Weight extends StatelessWidget {
  const _Weight(this.label, this.side);
  final String label;
  final double side;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: side * 0.34,
          height: side * 0.16,
          decoration: BoxDecoration(
            color: palette.accentStrong,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        Container(
          width: side,
          height: side * 0.84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(side * 0.22),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: side * 0.24,
              fontWeight: FontWeight.w700,
              color: palette.card,
            ),
          ),
        ),
      ],
    );
  }
}

/// Una balanza y su ficha, que se llena dato por dato.
class _ScaleScene extends StatelessWidget {
  const _ScaleScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    const rows = [
      ('Código', 'BAL-014'),
      ('Máx', '30 kg'),
      ('d', '0,01 kg'),
      ('e', '0,1 kg'),
    ];
    return Stack(
      children: [
        _at(
          Offset(w * 0.2, h / 2),
          _Pop(
            _p(t, 0, 0.14),
            child: const _Glyph(Icons.scale_outlined, size: 72, filled: true),
          ),
        ),
        Positioned(
          left: w * 0.42,
          right: w * 0.04,
          top: h * 0.1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            rows[i].$1,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: _p(
                                t,
                                0.14 + i * 0.13,
                                0.26 + i * 0.13,
                                Curves.linear,
                              ),
                              child: Text(
                                rows[i].$2,
                                maxLines: 1,
                                style: AppTextStyles.reading(
                                  context,
                                  size: 14,
                                  color: palette.accentInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: _p(t, 0.26 + i * 0.13, 0.3 + i * 0.13),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: palette.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Las tres pruebas se encienden y la periodicidad marca el calendario.
class _TestsScene extends StatelessWidget {
  const _TestsScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final w = size.width;
    const tests = ['Excentricidad', 'Repetibilidad', 'Linealidad'];
    return Row(
      children: [
        SizedBox(width: w * 0.04),
        Expanded(
          flex: 11,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      _Switch(_p(t, 0.08 + i * 0.13, 0.18 + i * 0.13)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tests[i],
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: AppTextStyles.figure(context, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: w * 0.04),
        Expanded(
          flex: 9,
          child: Opacity(
            opacity: _p(t, 0.48, 0.58),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _Tag(
                    'Semanal · lunes',
                    icon: Icons.event_repeat_outlined,
                    size: 11,
                  ),
                ),
                const SizedBox(height: 10),
                for (var week = 0; week < 3; week++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var day = 0; day < 7; day++)
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color:
                                  day == 0 &&
                                      _p(
                                            t,
                                            0.58 + week * 0.08,
                                            0.66 + week * 0.08,
                                          ) >
                                          0.5
                                  ? palette.accent
                                  : palette.track,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: w * 0.04),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(this.on);
  final double on;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      width: 34,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Color.lerp(palette.track, palette.accent, on),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Align(
        alignment: Alignment(-1 + 2 * on, 0),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: palette.card,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// La lectura cae dentro o fuera de la tolerancia.
class _ToleranceScene extends StatelessWidget {
  const _ToleranceScene(this.t, this.size);
  final double t;
  final Size size;

  // Error de cada lectura, en múltiplos del error permisible.
  static const _readings = [0.35, -0.55, 1.4, 0.1];
  static const _labels = ['+0,18 g', '−0,28 g', '+0,70 g', '+0,05 g'];

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    final axis = h * 0.62;
    final center = w / 2;
    final unit = w * 0.26; // un error permisible
    final band = _p(t, 0, 0.12);

    // Recorre las lecturas: viaja y se detiene en cada una.
    final slot = (t * _readings.length)
        .clamp(0.0, _readings.length - 0.001)
        .toDouble();
    final index = slot.floor();
    final local = slot - index;
    final from = index == 0 ? 0.0 : _readings[index - 1];
    final value =
        from +
        (_readings[index] - from) * _p(local, 0, 0.45, Curves.easeInOutCubic);
    final settled = local > 0.5;
    final inside = _readings[index].abs() <= 1;
    final x = center + value * unit;

    return Stack(
      children: [
        Positioned(
          left: center - unit * band,
          width: unit * 2 * band,
          top: axis - 26,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: palette.accentMid),
            ),
          ),
        ),
        Positioned(
          left: w * 0.04,
          right: w * 0.04,
          top: axis - 1,
          height: 2,
          child: ColoredBox(color: palette.divider),
        ),
        Positioned(
          left: center - 1,
          top: axis - 30,
          width: 2,
          height: 60,
          child: ColoredBox(color: palette.accentMid),
        ),
        for (final (dx, label) in [(-1.0, '−EMP'), (1.0, '+EMP')])
          _at(
            Offset(center + dx * unit, axis + 40),
            Opacity(
              opacity: band,
              child: Text(
                label,
                style: AppTextStyles.caption(context, size: 11),
              ),
            ),
            box: 80,
          ),
        _at(
          Offset(center, axis + 40),
          Text('0', style: AppTextStyles.caption(context, size: 11)),
          box: 40,
        ),
        // La lectura: un punto con su valor encima.
        Positioned(
          left: x - 7,
          top: axis - 7,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: settled && !inside ? palette.fail : palette.accentInk,
              shape: BoxShape.circle,
              border: Border.all(color: palette.card, width: 2),
            ),
          ),
        ),
        _at(
          Offset(x, axis - 44),
          Text(
            _labels[index],
            style: AppTextStyles.reading(
              context,
              size: 13,
              color: palette.text,
            ),
          ),
          box: 120,
        ),
        Positioned(
          right: w * 0.04,
          top: 6,
          child: _Pop(
            settled ? _p(local, 0.5, 0.62) : 0,
            child: inside
                ? const _Tag(
                    'Conforme',
                    tone: _Tone.ok,
                    icon: Icons.check,
                    size: 11,
                  )
                : const _Tag(
                    'No conforme',
                    tone: _Tone.fail,
                    icon: Icons.close,
                    size: 11,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Las cuentas del equipo, una por persona.
class _UsersScene extends StatelessWidget {
  const _UsersScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final w = size.width, h = size.height;
    const people = ['AQ', 'BM', 'CR'];
    return Stack(
      children: [
        for (var i = 0; i < 3; i++)
          _at(
            Offset(w * (0.2 + i * 0.3), h * 0.42),
            _Pop(
              _p(t, 0.05 + i * 0.14, 0.2 + i * 0.14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(people[i]),
                  const SizedBox(height: 8),
                  const _Tag('Operador', tone: _Tone.muted, size: 10.5),
                ],
              ),
            ),
            box: w * 0.3,
          ),
        _at(
          Offset(w * 0.5, h * 0.88),
          _Pop(
            _p(t, 0.58, 0.72),
            child: const _Tag(
              'Contraseña temporal',
              icon: Icons.key_outlined,
              size: 11,
            ),
          ),
          box: w,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.initials, {this.size = 52});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
      child: Text(
        initials,
        style: AppTextStyles.figure(
          context,
          size: size * 0.36,
          color: palette.card,
        ),
      ),
    );
  }
}

/// Un operador y las balanzas que le tocan.
class _AssignScene extends StatelessWidget {
  const _AssignScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final w = size.width, h = size.height;
    final person = Offset(w * 0.2, h / 2);
    const codes = ['BAL-014', 'BAL-020', 'BAL-031'];
    final rows = [
      for (var i = 0; i < 3; i++) Offset(w * 0.7, h / 2 + (i - 1) * 44),
    ];
    final links = [_p(t, 0.18, 0.38), _p(t, 0.38, 0.58), 0.0];
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _Links([
              for (var i = 0; i < 3; i++)
                (
                  person + const Offset(30, 0),
                  rows[i] - Offset(w * 0.13, 0),
                  links[i],
                ),
            ], palette.accent),
          ),
        ),
        _at(person, _Pop(_p(t, 0, 0.14), child: const _Avatar('AQ', size: 60))),
        for (var i = 0; i < 3; i++)
          _at(
            rows[i],
            _Pop(
              _p(t, 0.04 + i * 0.05, 0.16 + i * 0.05),
              child: _Tag(
                codes[i],
                tone: links[i] >= 1 ? _Tone.ok : _Tone.muted,
                icon: links[i] >= 1 ? Icons.check : Icons.scale_outlined,
              ),
            ),
            box: w * 0.3 + 30,
          ),
      ],
    );
  }
}

/// Los cinco pasos de la captura y su resultado.
class _CaptureScene extends StatelessWidget {
  const _CaptureScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    const steps = ['Pesas', 'Exc.', 'Rep.', 'Lin.', 'Resumen'];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: _p(
                            t,
                            0.04 + i * 0.1,
                            0.14 + i * 0.1,
                            Curves.linear,
                          ),
                          minHeight: 6,
                          color: palette.accent,
                          backgroundColor: palette.track,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[i],
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: AppTextStyles.caption(context, size: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Pop(
                _p(t, 0.58, 0.7),
                child: const _Tag(
                  'Conforme',
                  tone: _Tone.ok,
                  icon: Icons.check,
                  size: 13,
                ),
              ),
              const SizedBox(width: 10),
              _Pop(
                _p(t, 0.7, 0.82),
                child: Icon(
                  Icons.cloud_done_outlined,
                  size: 26,
                  color: palette.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resultados en el historial, uno con alerta.
class _ResultsScene extends StatelessWidget {
  const _ResultsScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    const rows = [
      ('BAL-014', 'Conforme', _Tone.ok),
      ('BAL-020', 'Conforme', _Tone.ok),
      ('BAL-031', 'No conforme', _Tone.fail),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: 10,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < rows.length; i++)
            Builder(
              builder: (context) {
                final show = _p(t, 0.06 + i * 0.14, 0.2 + i * 0.14);
                return Opacity(
                  opacity: show,
                  child: Transform.translate(
                    offset: Offset((1 - show) * 24, 0),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: palette.divider),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              rows[i].$1,
                              maxLines: 1,
                              style: AppTextStyles.reading(
                                context,
                                size: 13,
                                color: palette.accentInk,
                              ),
                            ),
                          ),
                          if (i == 0)
                            _Pop(
                              _p(t, 0.6, 0.72),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _Tag(
                                  'PDF',
                                  tone: _Tone.muted,
                                  icon: Icons.picture_as_pdf_outlined,
                                  size: 10,
                                ),
                              ),
                            ),
                          if (i == 2)
                            _Pop(
                              _p(t, 0.5, 0.62),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.notifications_active_outlined,
                                  size: 18,
                                  color: palette.fail,
                                ),
                              ),
                            ),
                          _Tag(rows[i].$2, tone: rows[i].$3, size: 10.5),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Un mes de agenda: los días que tocan, hoy y uno atrasado.
class _AgendaScene extends StatelessWidget {
  const _AgendaScene(this.t, this.size);
  final double t;
  final Size size;

  // Días (0 a 34) que llevan verificaciones.
  static const _due = [2, 7, 9, 14, 16, 21, 23, 28, 30];
  static const _late = 7;
  static const _today = 16;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final cell = math.min(22.0, (size.width * 0.6) / 7 - 4);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 6);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var week = 0; week < 5; week++)
              Row(
                children: [
                  for (var day = 0; day < 7; day++)
                    Builder(
                      builder: (context) {
                        final index = week * 7 + day;
                        final order = _due.indexOf(index);
                        final lit = order >= 0
                            ? _p(t, 0.06 + order * 0.06, 0.12 + order * 0.06)
                            : 0.0;
                        final late = index == _late && lit > 0;
                        final today = index == _today;
                        return Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.all(2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: late
                                ? Color.lerp(
                                    palette.track,
                                    palette.failSurface,
                                    lit,
                                  )
                                : Color.lerp(
                                    palette.track,
                                    palette.accentSoft,
                                    lit,
                                  ),
                            borderRadius: BorderRadius.circular(5),
                            border: today
                                ? Border.all(
                                    color: palette.accentInk.withValues(
                                      alpha: 0.4 + 0.6 * pulse,
                                    ),
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: lit > 0
                              ? Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: late ? palette.fail : palette.accent,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
        SizedBox(width: size.width * 0.05),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Pop(
              _p(t, 0.62, 0.72),
              child: const _Tag('Hoy', tone: _Tone.ok, size: 11),
            ),
            const SizedBox(height: 8),
            _Pop(
              _p(t, 0.7, 0.8),
              child: const _Tag('Atrasada', tone: _Tone.fail, size: 11),
            ),
            const SizedBox(height: 8),
            _Pop(_p(t, 0.78, 0.88), child: const _Tag('Próxima', size: 11)),
          ],
        ),
      ],
    );
  }
}

/// La pesa recorre la plataforma: centro y cuatro esquinas.
class _EccentricityScene extends StatelessWidget {
  const _EccentricityScene(this.t, this.size);
  final double t;
  final Size size;

  // Posiciones en la plataforma, de -1 a 1; la 1 es el centro.
  static const _spots = [
    Offset.zero,
    Offset(-1, -1),
    Offset(1, -1),
    Offset(1, 1),
    Offset(-1, 1),
  ];
  static const _readings = ['10,000', '10,002', '9,999', '10,001', '10,000'];

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    final side = h * 0.82;
    final origin = Offset(w * 0.08 + side / 2, h / 2);
    final reach = side * 0.31;
    final travel = (t / 0.86).clamp(0.0, 0.999).toDouble() * _spots.length;
    final index = travel.floor();
    final local = travel - index;
    final from = index == 0 ? _spots[0] : _spots[index - 1];
    final spot = Offset.lerp(
      from,
      _spots[index],
      _p(local, 0, 0.5, Curves.easeInOutCubic),
    )!;
    final visited = t >= 0.86
        ? _spots.length
        : (local > 0.5 ? index + 1 : index);
    return Stack(
      children: [
        Positioned(
          left: origin.dx - side / 2,
          top: origin.dy - side / 2,
          width: side,
          height: side,
          child: Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: palette.accentMid, width: 1.5),
            ),
          ),
        ),
        for (var i = 0; i < _spots.length; i++)
          _at(
            origin + _spots[i] * reach,
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i < visited ? palette.accentSoft : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: i < visited ? palette.accent : palette.divider,
                ),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: i < visited ? palette.accentInk : palette.muted,
                ),
              ),
            ),
            box: 40,
          ),
        _at(
          origin + spot * reach + const Offset(0, -2),
          const _Weight('10 kg', 34),
          box: 60,
        ),
        Positioned(
          left: origin.dx + side / 2 + w * 0.06,
          right: w * 0.03,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _spots.length; i++)
                Opacity(
                  opacity: i < visited ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Text(
                      '${i + 1} · ${_readings[i]}',
                      maxLines: 1,
                      style: AppTextStyles.reading(
                        context,
                        size: 13,
                        color: palette.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La misma carga, aplicada y retirada tres veces.
class _RepeatabilityScene extends StatelessWidget {
  const _RepeatabilityScene(this.t, this.size);
  final double t;
  final Size size;

  static const _readings = ['10,001', '10,000', '10,001'];

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    final cycle = (t / 0.84).clamp(0.0, 0.999).toDouble() * 3;
    final index = cycle.floor();
    final local = cycle - index;
    // Baja, se apoya, sube.
    final down = local < 0.35
        ? _p(local, 0, 0.35, Curves.easeInCubic)
        : local < 0.7
        ? 1.0
        : 1 - _p(local, 0.7, 1, Curves.easeOutCubic);
    final shown = t >= 0.84 ? 3 : (local >= 0.35 ? index + 1 : index);
    final platform = h * 0.72;
    final center = w * 0.3;
    return Stack(
      children: [
        Positioned(
          left: center - w * 0.16,
          width: w * 0.32,
          top: platform,
          height: 8,
          child: Container(
            decoration: BoxDecoration(
              color: palette.accentMid,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
        Positioned(
          left: center - 3,
          width: 6,
          top: platform + 8,
          height: h - platform - 14,
          child: ColoredBox(color: palette.divider),
        ),
        Positioned(
          left: center - 26,
          top: platform - 52 - (1 - down) * (h * 0.32),
          child: const _Weight('10 kg', 52),
        ),
        Positioned(
          left: w * 0.6,
          right: w * 0.04,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++)
                Opacity(
                  opacity: i < shown ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}',
                          style: AppTextStyles.caption(context, size: 11),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _readings[i],
                          maxLines: 1,
                          style: AppTextStyles.reading(
                            context,
                            size: 15,
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cargas crecientes en el rango, cada una con su indicación.
class _LinearityScene extends StatelessWidget {
  const _LinearityScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    const labels = ['20 %', '40 %', '60 %', '80 %', '100 %'];
    final barWidth = w * 0.1;
    final floor = h * 0.8;
    final top = h * 0.12;
    return Stack(
      children: [
        Positioned(
          left: w * 0.06,
          right: w * 0.06,
          top: floor,
          height: 2,
          child: ColoredBox(color: palette.divider),
        ),
        for (var i = 0; i < 5; i++)
          Builder(
            builder: (context) {
              final grow = _p(t, 0.06 + i * 0.13, 0.18 + i * 0.13);
              final full = (floor - top) * (i + 1) / 5;
              final left = w * 0.1 + i * (w * 0.17);
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    width: barWidth,
                    top: floor - full * grow,
                    height: full * grow,
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(
                          alpha: 0.35 + 0.13 * i,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: left - 12,
                    width: barWidth + 24,
                    top: floor + 6,
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: AppTextStyles.caption(context, size: 10.5),
                    ),
                  ),
                  if (grow >= 1)
                    Positioned(
                      left: left + barWidth / 2 - 5,
                      top: floor - full - 13,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: palette.accentInk,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.card, width: 2),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Sin señal se guarda en el teléfono; con señal, se envía solo.
class _OfflineScene extends StatelessWidget {
  const _OfflineScene(this.t, this.size);
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final h = size.height, w = size.width;
    final phone = Offset(w * 0.2, h / 2);
    final cloud = Offset(w * 0.8, h / 2);
    final online = t >= 0.4;
    // Dos envíos viajan, uno detrás del otro.
    final trips = [
      _p(t, 0.44, 0.62, Curves.easeInOutCubic),
      _p(t, 0.6, 0.78, Curves.easeInOutCubic),
    ];
    final pending = 2 - trips.where((trip) => trip >= 1).length;
    final from = phone + const Offset(36, 0), to = cloud - const Offset(36, 0);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _Links(
              [(from, to, 1)],
              online ? palette.accentMid : palette.divider,
              dashed: true,
            ),
          ),
        ),
        for (final trip in trips)
          if (trip > 0 && trip < 1)
            _at(
              Offset.lerp(from, to, trip)!,
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
              box: 20,
            ),
        _at(phone, const _Glyph(Icons.smartphone, size: 66, filled: true)),
        _at(
          phone + const Offset(0, -50),
          Icon(
            online
                ? Icons.signal_cellular_alt
                : Icons.signal_cellular_off_outlined,
            size: 20,
            color: online ? palette.accent : palette.fail,
          ),
          box: 40,
        ),
        _at(
          phone + const Offset(0, 54),
          _Tag(
            pending == 0 ? 'Enviado' : '$pending por enviar',
            tone: pending == 0 ? _Tone.ok : _Tone.steel,
            size: 10.5,
          ),
          box: 140,
        ),
        _at(
          cloud,
          _Glyph(
            pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_outlined,
            size: 66,
          ),
        ),
      ],
    );
  }
}

/// La ruta de un paso: pantallas y botones en orden, y un punto de luz que
/// la recorre como lo haría el dedo.
class GuideRouteView extends StatelessWidget {
  const GuideRouteView({
    required this.route,
    required this.animation,
    super.key,
  });
  final List<String> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Semantics(
      label: 'Dónde: ${route.join(', ')}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Cada tramo se enciende en orden y el último queda marcado.
          final lit =
              (_p(animation.value, 0.05, 0.75, Curves.linear) * route.length)
                  .floor();
          return Wrap(
            spacing: 4,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < route.length; i++) ...[
                if (i > 0)
                  Icon(Icons.chevron_right, size: 16, color: palette.muted),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: i <= lit
                        ? (i == route.length - 1
                              ? palette.accent
                              : palette.accentSoft)
                        : palette.card,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: i <= lit ? palette.accent : palette.divider,
                    ),
                  ),
                  child: Text(
                    route[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: i <= lit
                          ? (i == route.length - 1
                                ? palette.card
                                : palette.accentInk)
                          : palette.muted,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

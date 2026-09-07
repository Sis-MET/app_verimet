import 'package:flutter/material.dart';

import '../../core/domain/compliance_status.dart';
import '../../core/domain/test_verdict.dart';
import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Etiqueta corta de estado. Tres tratamientos, uno por nivel de gravedad:
/// neutro para lo conforme, acero para lo observado y oxido para lo que
/// bloquea el uso del equipo.
///
/// Va en pastilla completa: es lo mas pequeno de la pantalla y una caja recta
/// de 11 px se leia como un recorte, no como una etiqueta.
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {this.status, super.key});

  /// Etiqueta a partir del estado del instrumento, con su propio texto.
  StatusTag.of(ComplianceStatus this.status, {String? text, super.key})
    : text = text ?? status.label;

  final String text;

  /// Si es `null` se pinta en acero (uso informativo: "3 por sincronizar").
  final ComplianceStatus? status;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    final (Color background, Color ink) = switch (status) {
      ComplianceStatus.conforme => (
        palette.tagNeutralSurface,
        palette.tagNeutralInk,
      ),
      ComplianceStatus.observado => (palette.accentSoft, palette.accentDeep),
      ComplianceStatus.noConforme => (palette.failSurface, palette.failInk),
      null => (palette.accentSoft, palette.accentDeep),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.04 * 11,
          color: ink,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Veredicto de una prueba: pastilla con borde, en versalitas. Mas peso que
/// una [StatusTag] porque es la conclusion de la medicion, no una referencia.
///
/// Lo pendiente se pinta en neutro y no en oxido: una prueba a medias no es un
/// fallo, y tenirla de rojo haria dudar al operario de lo que lleva medido.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge({required this.verdict, this.text, super.key});

  final TestVerdict verdict;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    final (Color background, Color border, Color color) = switch (verdict) {
      TestVerdict.pass => (
        palette.accentSoft,
        palette.accent,
        palette.accentDeep,
      ),
      TestVerdict.fail => (
        palette.failBadgeSurface,
        palette.fail,
        palette.fail,
      ),
      TestVerdict.pending => (
        Colors.transparent,
        palette.divider,
        palette.muted,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border),
      ),
      child: Text(
        (text ?? verdict.label).toUpperCase(),
        style: TextStyle(
          fontFamily: AppFonts.heading,
          fontFamilyFallback: AppFonts.fallback,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 13 * 0.06,
          height: 1.2,
          color: color,
        ),
      ),
    );
  }
}

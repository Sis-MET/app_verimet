import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Roles de color del sistema "Industry", resueltos para un brillo concreto.
///
/// Se expone como [ThemeExtension] para que los widgets pidan el rol
/// (`palette.divider`) y no el valor (`AppColors.neutral300`): asi el tema
/// oscuro de Ajustes cambia toda la app sin tocar una sola pantalla.
@immutable
class IndustryPalette extends ThemeExtension<IndustryPalette> {
  const IndustryPalette({
    required this.bg,
    required this.card,
    required this.surface,
    required this.text,
    required this.divider,
    required this.hairline,
    required this.shadow,
    required this.accent,
    required this.accentSoft,
    required this.accentMid,
    required this.accentStrong,
    required this.accentInk,
    required this.accentDeep,
    required this.muted,
    required this.mutedStrong,
    required this.track,
    required this.success,
    required this.successSurface,
    required this.successInk,
    required this.fail,
    required this.failBar,
    required this.failSurface,
    required this.failInk,
    required this.failBadgeSurface,
    required this.navBackground,
    required this.tagNeutralSurface,
    required this.tagNeutralInk,
  });

  /// Variante clara: la de planta con luz de dia.
  factory IndustryPalette.light() => const IndustryPalette(
    bg: AppColors.bg,
    card: AppColors.card,
    surface: AppColors.surface,
    text: AppColors.text,
    divider: Color(0x141D1F20), // text al 8%
    hairline: Color(0x0F1D1F20), // text al 6%
    shadow: Color(0x0F1D1F20),
    accent: AppColors.accent,
    accentSoft: AppColors.accent100,
    accentMid: AppColors.accent300,
    accentStrong: AppColors.accent500,
    accentInk: AppColors.accent700,
    accentDeep: AppColors.accent800,
    muted: AppColors.neutral600,
    mutedStrong: AppColors.neutral700,
    track: AppColors.neutral300,
    success: AppColors.success,
    successSurface: AppColors.successSurface,
    successInk: AppColors.successInk,
    fail: AppColors.fail,
    failBar: AppColors.failBar,
    failSurface: AppColors.failSurface,
    failInk: AppColors.failInk,
    failBadgeSurface: AppColors.failBadgeSurface,
    navBackground: Color(0xF0FFFFFF), // tarjeta al 94%
    tagNeutralSurface: AppColors.neutral200,
    tagNeutralInk: AppColors.neutral800,
  );

  /// Variante oscura: pedida para naves con poca luz.
  factory IndustryPalette.dark() => const IndustryPalette(
    bg: AppColors.bgDark,
    card: AppColors.cardDark,
    surface: AppColors.surfaceDark,
    text: AppColors.textDark,
    divider: Color(0x1FE8EAEB), // text al 12%
    hairline: Color(0x14E8EAEB), // text al 8%
    shadow: Color(0x59000000),
    accent: AppColors.accentDark,
    accentSoft: AppColors.accent100Dark,
    accentMid: AppColors.accent500,
    accentStrong: AppColors.accent500,
    accentInk: AppColors.accent700Dark,
    accentDeep: AppColors.accent800Dark,
    muted: AppColors.neutral600Dark,
    mutedStrong: AppColors.neutral700Dark,
    track: AppColors.neutral300Dark,
    success: AppColors.successDark,
    successSurface: AppColors.successSurfaceDark,
    successInk: AppColors.successInkDark,
    fail: Color(0xFFE08A73),
    failBar: AppColors.failBar,
    failSurface: Color(0xFF3A241E),
    failInk: Color(0xFFF0B9AB),
    failBadgeSurface: Color(0xFF33201A),
    navBackground: Color(0xF01E2225), // tarjeta al 94%
    tagNeutralSurface: Color(0xFF2C3134),
    tagNeutralInk: AppColors.textDark,
  );

  /// Fondo de la app. Va un escalon por debajo de [card] para que un modulo se
  /// lea como pieza levantada y no necesite un borde marcado.
  final Color bg;

  /// Plano de una tarjeta, un modulo o una lista agrupada.
  final Color card;

  /// Segundo plano dentro de una tarjeta: campos de formulario, celdas.
  final Color surface;

  /// Tinta principal.
  final Color text;

  /// Contorno de tarjetas y controles. Apoya al contraste de valor, ya no es
  /// el recurso que separa: por eso es mucho mas suave que antes.
  final Color divider;

  /// Separador entre filas de una misma lista agrupada.
  final Color hairline;

  /// Sombra difusa de lo que flota o se apoya.
  final Color shadow;

  /// Acero. Es el unico color de marca y marca lo activo.
  final Color accent;

  /// Fondo de etiquetas y celdas resaltadas en acero.
  final Color accentSoft;

  /// Relleno de barras "conforme" en los graficos de estado.
  final Color accentMid;

  /// Relleno de barras "observado".
  final Color accentStrong;

  /// Texto en acero sobre fondo claro (kickers, cifras destacadas).
  final Color accentInk;

  /// Acero mas profundo: texto sobre [accentSoft].
  final Color accentDeep;

  /// Texto secundario.
  final Color muted;

  /// Texto secundario con mas presencia (valores en tablas).
  final Color mutedStrong;

  /// Riel de las barras de progreso.
  final Color track;

  /// Confirmación puntual de una tarea terminada.
  final Color success;

  /// Fondo de una ficha completada.
  final Color successSurface;

  /// Tinta sobre el fondo de una ficha completada.
  final Color successInk;

  /// Fuera de tolerancia.
  final Color fail;

  /// Barra de estado "no conforme" en los resumenes por area.
  final Color failBar;

  /// Fondo de etiqueta "no conforme".
  final Color failSurface;

  /// Tinta de etiqueta "no conforme".
  final Color failInk;

  /// Fondo del veredicto no conforme.
  final Color failBadgeSurface;

  /// Fondo translucido de la barra de navegacion flotante.
  final Color navBackground;

  /// Fondo de etiqueta neutra ("Conforme", "Al dia").
  final Color tagNeutralSurface;

  /// Tinta de etiqueta neutra.
  final Color tagNeutralInk;

  /// Acceso corto desde cualquier widget con `BuildContext`.
  static IndustryPalette of(BuildContext context) =>
      Theme.of(context).extension<IndustryPalette>() ?? IndustryPalette.light();

  @override
  IndustryPalette copyWith({
    Color? bg,
    Color? card,
    Color? surface,
    Color? text,
    Color? divider,
    Color? hairline,
    Color? shadow,
    Color? accent,
    Color? accentSoft,
    Color? accentMid,
    Color? accentStrong,
    Color? accentInk,
    Color? accentDeep,
    Color? muted,
    Color? mutedStrong,
    Color? track,
    Color? success,
    Color? successSurface,
    Color? successInk,
    Color? fail,
    Color? failBar,
    Color? failSurface,
    Color? failInk,
    Color? failBadgeSurface,
    Color? navBackground,
    Color? tagNeutralSurface,
    Color? tagNeutralInk,
  }) {
    return IndustryPalette(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      divider: divider ?? this.divider,
      hairline: hairline ?? this.hairline,
      shadow: shadow ?? this.shadow,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentMid: accentMid ?? this.accentMid,
      accentStrong: accentStrong ?? this.accentStrong,
      accentInk: accentInk ?? this.accentInk,
      accentDeep: accentDeep ?? this.accentDeep,
      muted: muted ?? this.muted,
      mutedStrong: mutedStrong ?? this.mutedStrong,
      track: track ?? this.track,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      successInk: successInk ?? this.successInk,
      fail: fail ?? this.fail,
      failBar: failBar ?? this.failBar,
      failSurface: failSurface ?? this.failSurface,
      failInk: failInk ?? this.failInk,
      failBadgeSurface: failBadgeSurface ?? this.failBadgeSurface,
      navBackground: navBackground ?? this.navBackground,
      tagNeutralSurface: tagNeutralSurface ?? this.tagNeutralSurface,
      tagNeutralInk: tagNeutralInk ?? this.tagNeutralInk,
    );
  }

  @override
  IndustryPalette lerp(covariant IndustryPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return IndustryPalette(
      bg: mix(bg, other.bg),
      card: mix(card, other.card),
      surface: mix(surface, other.surface),
      text: mix(text, other.text),
      divider: mix(divider, other.divider),
      hairline: mix(hairline, other.hairline),
      shadow: mix(shadow, other.shadow),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentMid: mix(accentMid, other.accentMid),
      accentStrong: mix(accentStrong, other.accentStrong),
      accentInk: mix(accentInk, other.accentInk),
      accentDeep: mix(accentDeep, other.accentDeep),
      muted: mix(muted, other.muted),
      mutedStrong: mix(mutedStrong, other.mutedStrong),
      track: mix(track, other.track),
      success: mix(success, other.success),
      successSurface: mix(successSurface, other.successSurface),
      successInk: mix(successInk, other.successInk),
      fail: mix(fail, other.fail),
      failBar: mix(failBar, other.failBar),
      failSurface: mix(failSurface, other.failSurface),
      failInk: mix(failInk, other.failInk),
      failBadgeSurface: mix(failBadgeSurface, other.failBadgeSurface),
      navBackground: mix(navBackground, other.navBackground),
      tagNeutralSurface: mix(tagNeutralSurface, other.tagNeutralSurface),
      tagNeutralInk: mix(tagNeutralInk, other.tagNeutralInk),
    );
  }
}

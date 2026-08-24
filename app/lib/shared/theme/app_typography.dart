import 'package:flutter/material.dart';

import 'industry_palette.dart';

/// Familias tipograficas del sistema "Industry".
///
/// Barlow Condensed para titulos, Barlow para texto y una monoespaciada para
/// todo lo que sea una lectura: codigos de equipo, kilos y errores. Los
/// numeros de una verificacion se comparan en columna, y con proporcional no
/// se alinean.
///
/// Las dos primeras familias no vienen empaquetadas todavia. Mientras no se
/// agreguen los .ttf a `app/fonts/` y su bloque `fonts:` en `pubspec.yaml`,
/// Flutter cae a [fallback] y la app se ve correcta pero sin la condensada.
abstract final class AppFonts {
  static const String heading = 'Barlow Condensed';
  static const String body = 'Barlow';

  static const List<String> fallback = <String>['Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'];

  /// Familia de lecturas. `monospace` resuelve en Android, `Menlo` en iOS.
  static const String mono = 'monospace';
  static const List<String> monoFallback = <String>['Menlo', 'Courier New'];
}

/// Estilos que no entran en el [TextTheme] de Material pero si en el sistema.
abstract final class AppTextStyles {
  /// h6: rotulo de seccion, en versalitas separadas.
  static TextStyle sectionLabel(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return TextStyle(
      fontFamily: AppFonts.heading,
      fontFamilyFallback: AppFonts.fallback,
      fontWeight: FontWeight.w600,
      fontSize: 13,
      height: 1.12,
      letterSpacing: 13 * 0.08,
      color: palette.text,
    );
  }

  /// Linea sobre el titulo: cliente, equipo, nombre de la prueba.
  static TextStyle kicker(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return TextStyle(
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: 10.5,
      height: 1.3,
      letterSpacing: 10.5 * 0.16,
      color: palette.accentInk,
    );
  }

  /// Lectura numerica: kilos, errores, codigos.
  static TextStyle reading(BuildContext context, {double size = 13, Color? color}) {
    return TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      fontSize: size,
      height: 1.2,
      color: color ?? IndustryPalette.of(context).text,
    );
  }

  /// Cifra grande de tarjeta (48 equipos, 91 %, error maximo).
  static TextStyle figure(BuildContext context, {double size = 40, Color? color}) {
    return TextStyle(
      fontFamily: AppFonts.heading,
      fontFamilyFallback: AppFonts.fallback,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.05,
      color: color ?? IndustryPalette.of(context).text,
    );
  }

  /// Pie de cifra: "en 4 areas", "Conformes".
  static TextStyle caption(BuildContext context, {double size = 11}) {
    final palette = IndustryPalette.of(context);
    return TextStyle(
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: size,
      height: 1.3,
      letterSpacing: size * 0.09,
      color: palette.muted,
    );
  }
}

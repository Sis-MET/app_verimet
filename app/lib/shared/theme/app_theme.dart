import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'industry_palette.dart';

/// Tema de la app segun el sistema visual "Industry".
///
/// Tres reglas heredadas del sistema, y una excepcion:
///
/// - esquinas rectas (`radius 0`) en todo control: cada componente es un
///   objeto de plano, no una pastilla;
/// - hairline de 1 px en vez de sombras para separar;
/// - acero como unico color de marca, oxido reservado al fuera de tolerancia.
///
/// La excepcion es la barra de navegacion inferior, que si es flotante y
/// redondeada — se pidio explicitamente en el diseno.
///
/// La UI se usa en planta, muchas veces con guantes y con mala iluminacion:
/// por eso los controles llegan a 44-50 px de alto y el texto de captura a 16.
abstract final class AppTheme {
  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? IndustryPalette.dark()
        : IndustryPalette.light();

    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.bg,
      secondary: palette.accentInk,
      onSecondary: palette.bg,
      error: palette.fail,
      onError: brightness == Brightness.dark ? AppColors.bgDark : AppColors.bg,
      surface: palette.bg,
      onSurface: palette.text,
      surfaceContainerHighest: palette.surface,
      outline: palette.divider,
      outlineVariant: palette.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.fallback,
      visualDensity: VisualDensity.comfortable,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: _textTheme(palette),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: palette.bg,
        foregroundColor: palette.text,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.heading,
          fontFamilyFallback: AppFonts.fallback,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: palette.text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: palette.text.withValues(alpha: 0.7),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        border: _inputBorder(palette.divider),
        enabledBorder: _inputBorder(palette.divider),
        focusedBorder: _inputBorder(palette.accent),
        errorBorder: _inputBorder(palette.fail),
        focusedErrorBorder: _inputBorder(palette.fail),
      ),
      // Primario del sistema: relleno acero, borde del mismo acero.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.bg,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: palette.accent),
          ),
          textStyle: _buttonTextStyle(),
        ),
      ),
      // Secundario: solo el hairline.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: palette.divider),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: _buttonTextStyle(),
        ),
      ),
      // Ghost: texto en acero, sin caja.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size(0, 40),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: _buttonTextStyle(),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: palette.divider),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.track,
        linearMinHeight: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.accentDeep,
        contentTextStyle: TextStyle(
          color: palette.bg,
          fontFamily: AppFonts.body,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: color),
  );

  static TextStyle _buttonTextStyle() => const TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.fallback,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: 0.4,
  );

  /// Escala tipografica del sistema: h1 42 / h2 32 / h3 25 / h4 20 / h5 16,
  /// cuerpo 15 con interlinea 1.55.
  static TextTheme _textTheme(IndustryPalette palette) {
    TextStyle heading(double size) => TextStyle(
      fontFamily: AppFonts.heading,
      fontFamilyFallback: AppFonts.fallback,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.12,
      letterSpacing: size * -0.015,
      color: palette.text,
    );

    TextStyle body(double size, {double height = 1.55, Color? color}) =>
        TextStyle(
          fontFamily: AppFonts.body,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: size,
          height: height,
          color: color ?? palette.text,
        );

    return TextTheme(
      displaySmall: heading(42),
      headlineMedium: heading(32),
      headlineSmall: heading(25),
      titleLarge: heading(20),
      titleMedium: heading(16),
      titleSmall: body(14, height: 1.3),
      bodyLarge: body(15),
      bodyMedium: body(13.5, height: 1.45),
      bodySmall: body(12, height: 1.4, color: palette.muted),
      labelLarge: TextStyle(
        fontFamily: AppFonts.heading,
        fontFamilyFallback: AppFonts.fallback,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        height: 1.2,
        color: palette.text,
      ),
      labelMedium: body(12, height: 1.3, color: palette.muted),
      labelSmall: body(11, height: 1.3, color: palette.muted),
    );
  }
}

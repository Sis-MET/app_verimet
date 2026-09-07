import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shapes.dart';
import 'app_typography.dart';
import 'industry_palette.dart';

/// Tema de la app segun el sistema visual "Industry".
///
/// El sistema se reviso para quitarle ruido. Las reglas hoy son:
///
/// - esquinas redondeadas en una sola escala ([AppRadius]): nada de cajas
///   rectas ni de marcas de registro asomando fuera del borde;
/// - la separacion la hace el valor — la tarjeta es mas clara que el fondo —
///   y el contorno queda como apoyo suave, no como el recurso principal;
/// - acero como unico color de marca, oxido reservado al fuera de tolerancia.
///
/// La UI se usa en planta, muchas veces con guantes y con mala iluminacion:
/// por eso los controles llegan a 46-50 px de alto y el texto de captura a 16.
abstract final class AppTheme {
  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? IndustryPalette.dark()
        : IndustryPalette.light();

    // Contorno de los controles que no llevan relleno. El divisor de las
    // tarjetas es demasiado tenue para un boton, que tiene que leerse como
    // area tocable aun sin fondo.
    final outline = palette.text.withValues(alpha: 0.16);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: brightness == Brightness.dark
          ? AppColors.bgDark
          : AppColors.card,
      secondary: palette.accentInk,
      onSecondary: palette.card,
      error: palette.fail,
      onError: brightness == Brightness.dark
          ? AppColors.bgDark
          : AppColors.card,
      surface: palette.bg,
      onSurface: palette.text,
      surfaceContainer: palette.card,
      surfaceContainerHighest: palette.surface,
      outline: outline,
      outlineVariant: palette.divider,
      shadow: palette.shadow,
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
      splashFactory: InkSparkle.splashFactory,
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
        color: palette.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.text,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.heading,
          fontFamilyFallback: AppFonts.fallback,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: palette.text,
        ),
      ),
      // Campo relleno y sin caja dura: el contorno solo aparece con fuerza
      // cuando el campo tiene el foco.
      //
      // Aqui no se configura el rotulo: en este sistema va *encima* de la caja
      // y lo pone `LabeledInput`, no `InputDecoration.labelText`. Un label
      // flotante desaparece o se encoge justo cuando el campo esta relleno,
      // que es cuando hay que comprobar que se escribio donde tocaba.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: palette.text.withValues(alpha: 0.7),
        ),
        helperStyle: TextStyle(fontSize: 11.5, color: palette.muted),
        border: _inputBorder(palette.divider),
        enabledBorder: _inputBorder(palette.divider),
        focusedBorder: _inputBorder(palette.accent, width: 1.5),
        errorBorder: _inputBorder(palette.fail),
        focusedErrorBorder: _inputBorder(palette.fail, width: 1.5),
      ),
      // Primario del sistema: relleno acero, sin contorno ni sombra.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: brightness == Brightness.dark
              ? AppColors.bgDark
              : AppColors.card,
          disabledBackgroundColor: palette.text.withValues(alpha: 0.08),
          disabledForegroundColor: palette.text.withValues(alpha: 0.32),
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: _buttonTextStyle(),
        ),
      ),
      // Secundario: contorno suave, sin relleno.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: _buttonTextStyle(),
        ),
      ),
      // Ghost: texto en acero, sin caja.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: _buttonTextStyle(),
        ),
      ),
      // Los IconButton se quedan redondos: son el unico control circular del
      // sistema y cuadrarlos los confundiria con un boton pequeno.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: palette.text),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: palette.divider),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        iconColor: palette.muted,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: palette.divider),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: palette.divider),
        ),
        iconColor: palette.accent,
        collapsedIconColor: palette.muted,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.accentSoft,
        side: BorderSide(color: palette.divider),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(fontSize: 12.5, color: palette.text),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: outline, width: 1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.floating),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: palette.divider),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.track,
        linearMinHeight: 5,
        borderRadius: BorderRadius.circular(3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.accentDeep,
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark
              ? AppColors.bgDark
              : AppColors.card,
          fontFamily: AppFonts.body,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: AppRadius.control,
        borderSide: BorderSide(color: color, width: width),
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

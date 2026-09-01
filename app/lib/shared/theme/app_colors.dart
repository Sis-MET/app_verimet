import 'package:flutter/material.dart';

/// Tokens crudos del sistema visual "Industry" (acero sobre fondo tecnico).
///
/// Son los mismos valores que el design system publica en
/// `_ds/industry-.../styles.css`. No se usan directamente en los widgets: la
/// UI lee [IndustryPalette] desde el tema, que elige la variante clara u
/// oscura. Estos constantes son la fuente de la que salen esas dos variantes.
abstract final class AppColors {
  // — fondo y tinta, tema claro —
  static const Color bg = Color(0xFFF2F2F3);
  static const Color surface = Color(0xFFE9E9EA);
  static const Color text = Color(0xFF1D1F20);

  // — fondo y tinta, tema oscuro (planta con poca luz) —
  static const Color bgDark = Color(0xFF15181A);
  static const Color surfaceDark = Color(0xFF1F2325);
  static const Color textDark = Color(0xFFE8EAEB);

  // — rampa neutra —
  static const Color neutral100 = Color(0xFFF5F5F8);
  static const Color neutral200 = Color(0xFFE7E7EA);
  static const Color neutral300 = Color(0xFFD4D4D7);
  static const Color neutral400 = Color(0xFFB7B7BA);
  static const Color neutral500 = Color(0xFF98989B);
  static const Color neutral600 = Color(0xFF7A7A7D);
  static const Color neutral700 = Color(0xFF5D5D60);
  static const Color neutral800 = Color(0xFF424244);
  static const Color neutral900 = Color(0xFF2B2B2D);

  // — rampa acento (acero) —
  static const Color accent = Color(0xFF5980A6);
  static const Color accent100 = Color(0xFFEEF6FF);
  static const Color accent200 = Color(0xFFD6EBFF);
  static const Color accent300 = Color(0xFFB5D9FD);
  static const Color accent400 = Color(0xFF94BCE3);
  static const Color accent500 = Color(0xFF749DC4);
  static const Color accent600 = Color(0xFF597EA3);
  static const Color accent700 = Color(0xFF416180);
  static const Color accent800 = Color(0xFF2C455D);
  static const Color accent900 = Color(0xFF1D2D3D);

  // — rampa acento, tema oscuro —
  static const Color accentDark = Color(0xFF94BCE3);
  static const Color accent100Dark = Color(0xFF22303C);
  static const Color accent700Dark = Color(0xFF94BCE3);
  static const Color accent800Dark = Color(0xFFBDD8F2);
  static const Color accent900Dark = Color(0xFF0F1519);
  static const Color neutral300Dark = Color(0xFF3A3F42);
  static const Color neutral500Dark = Color(0xFF8B9094);
  static const Color neutral600Dark = Color(0xFF9AA0A4);
  static const Color neutral700Dark = Color(0xFFC2C7CA);

  /// Confirmación de una tarea concluida. Es un verde industrial apagado:
  /// aparece solo cuando una captura está completa y no compite con el acero.
  static const Color success = Color(0xFF4F765E);
  static const Color successSurface = Color(0xFFE4EEE7);
  static const Color successInk = Color(0xFF31513D);
  static const Color successDark = Color(0xFF78A88A);
  static const Color successSurfaceDark = Color(0xFF203029);
  static const Color successInkDark = Color(0xFFB8D9C3);

  /// Fuera de tolerancia. El óxido queda reservado al fallo.
  static const Color fail = Color(0xFFA5442F);
  static const Color failBar = Color(0xFFC4735D);
  static const Color failSurface = Color(0xFFF4DCD5);
  static const Color failInk = Color(0xFF7D2F1C);
  static const Color failBadgeSurface = Color(0xFFF6E3DD);

  /// Verificacion capturada pero aun no sincronizada.
  static const Color pendingSync = accent500;
}

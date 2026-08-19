import 'package:flutter/material.dart';

/// Paleta base de IvMET.
///
/// PLACEHOLDER: reemplazar por los colores institucionales de Metrica Ltda
/// cuando se defina el manual de marca.
abstract final class AppColors {
  static const Color primary = Color(0xFF00558C);
  static const Color secondary = Color(0xFF0091D5);

  /// Veredicto de una prueba dentro de tolerancia.
  static const Color pass = Color(0xFF2E7D32);

  /// Veredicto fuera de tolerancia.
  static const Color fail = Color(0xFFC62828);

  /// Verificacion capturada pero aun no sincronizada.
  static const Color pendingSync = Color(0xFFEF6C00);
}

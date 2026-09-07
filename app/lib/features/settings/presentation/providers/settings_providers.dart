import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tema de la app.
///
/// El modo oscuro no es cosmetico: se pidio para naves con poca luz, donde la
/// pantalla clara encandila y cuesta leer la balanza. Arranca siguiendo al
/// sistema y Ajustes lo fija.
///
/// TODO(IvMET-settings): persistir la eleccion junto al resto de preferencias
/// del dispositivo.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  bool get isDark => state == ThemeMode.dark;

  void toggleDark() => state = isDark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Texto grande: el operario lee a un brazo de distancia, con el equipo en la
/// mano. Activado por defecto.
class LargeTextNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final largeTextProvider = NotifierProvider<LargeTextNotifier, bool>(
  LargeTextNotifier.new,
);

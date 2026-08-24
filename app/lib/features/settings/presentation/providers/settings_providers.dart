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

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Estado de la prueba de conexion contra el servidor de Metrica.
enum ConnectionCheck {
  idle('Probar conexión', 'Comprueba la VPN, la API y el reloj del servidor.'),
  testing('Probando…', 'Resolviendo api.metrica.local por el túnel corporativo.'),
  ok('Conexión correcta', 'VPN activa · API 200 en 148 ms · 3 lotes listos para enviar.'),
  failed(
    'Sin respuesta',
    'No se llegó a api.metrica.local. Revise que la VPN corporativa esté conectada.',
  );

  const ConnectionCheck(this.label, this.hint);

  final String label;
  final String hint;
}

/// Prueba de conexion de Ajustes.
///
/// DEMO: no hace la llamada todavia. Cuando exista el healthcheck, esto pasa
/// a pegarle a `GET /api/v1/health` a traves de `apiClientProvider` y a
/// traducir el fallo con [NetworkFailure], que ya dice "verifique la VPN".
class ConnectionCheckNotifier extends Notifier<ConnectionCheck> {
  @override
  ConnectionCheck build() => ConnectionCheck.idle;

  Future<void> run() async {
    if (state == ConnectionCheck.testing) return;
    state = ConnectionCheck.testing;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    state = ConnectionCheck.ok;
  }
}

final connectionCheckProvider = NotifierProvider<ConnectionCheckNotifier, ConnectionCheck>(
  ConnectionCheckNotifier.new,
);

/// Texto grande: el operario lee a un brazo de distancia, con el equipo en la
/// mano. Activado por defecto.
class LargeTextNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final largeTextProvider = NotifierProvider<LargeTextNotifier, bool>(LargeTextNotifier.new);

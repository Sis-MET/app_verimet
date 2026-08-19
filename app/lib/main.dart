import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Punto de entrada de IvMET.
///
/// La app asume que, para hablar con el servidor de Metrica, el dispositivo ya
/// tiene levantada la VPN corporativa (ver docs/vpn-install-guide.md). Sin VPN
/// sigue siendo usable: las verificaciones quedan guardadas localmente y la
/// feature `sync` las envia cuando haya conexion.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Las verificaciones se hacen con el equipo en la mano, junto a la balanza.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: IvmetApp()));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Punto de entrada de IvMET.
///
/// Requiere conexión con Supabase. No utiliza la API antigua, VPN ni cola offline.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Las verificaciones se hacen con el equipo en la mano, junto a la balanza.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: IvmetApp()));
}

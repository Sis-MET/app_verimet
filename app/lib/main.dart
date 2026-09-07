import 'package:flutter/foundation.dart' show kIsWeb;
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
  //
  // Solo en el equipo de planta: en web la API de orientacion exige pantalla
  // completa y devuelve un Future que no se resuelve, asi que esperarlo aqui
  // dejaba la app sin llegar nunca a `runApp`.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(const ProviderScope(child: IvmetApp()));
}

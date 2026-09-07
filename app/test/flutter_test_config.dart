import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Configuracion que `flutter test` aplica a todos los tests del directorio.
///
/// Carga las fuentes reales del sistema. Sin esto el motor de pruebas dibuja
/// una fuente de bloques: los tests siguen pasando, pero un golden no valdria
/// nada —no habria letras que comparar— y las medidas de texto no se
/// parecerian a las del dispositivo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await _load('Barlow', const [
    'assets/fonts/Barlow-Regular.ttf',
    'assets/fonts/Barlow-Bold.ttf',
  ]);
  await _load('Barlow Condensed', const [
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
  ]);
  await _loadMaterialIcons();

  await testMain();
}

/// La familia de iconos de Material no se versiona: la aporta el propio SDK
/// cuando `uses-material-design` esta activo. Sin cargarla, cada icono sale
/// como un cuadro vacio y un golden no dice nada de ellos.
Future<void> _loadMaterialIcons() async {
  const key = 'fonts/MaterialIcons-Regular.otf';
  try {
    final data = await rootBundle.load(key);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(data))).load();
  } catch (_) {
    // El bundle de assets no siempre esta montado. No es motivo para tumbar
    // toda la suite: los tests de comportamiento no dependen del glifo.
  }
}

/// Se lee del disco y no del `rootBundle`: los tests corren con el directorio
/// del paquete como raiz, y asi no dependemos de que el bundle de assets este
/// montado.
Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = await File(path).readAsBytes();
    loader.addFont(
      Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
  }
  await loader.load();
}

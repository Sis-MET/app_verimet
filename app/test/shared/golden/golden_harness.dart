import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/shared/theme/app_theme.dart';

/// Fotografia un grupo de componentes en los dos temas y la compara con la
/// imagen de referencia de `goldens/`.
///
/// Se hacen las dos variantes siempre: en oscuro la separacion entre tarjeta y
/// fondo la hace el valor, no el contorno, asi que un cambio de paleta puede
/// verse bien en claro y dejar la tarjeta invisible en oscuro.
///
/// El tamano es fijo y el `devicePixelRatio` es 1 para que la imagen no
/// dependa de la pantalla en la que se corrio el test.
Future<void> expectSpecimen(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
}) async {
  for (final variant in const <({String label, Brightness brightness})>[
    (label: 'claro', brightness: Brightness.light),
    (label: 'oscuro', brightness: Brightness.dark),
  ]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: variant.brightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light,
        home: Scaffold(
          body: SafeArea(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name-${variant.label}.png'),
    );
  }
}

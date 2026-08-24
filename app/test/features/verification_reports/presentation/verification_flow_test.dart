import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';

/// Recorrido de humo: login, los cuatro apartados y el asistente entero.
///
/// Cubre el cableado que `flutter analyze` no ve — router, tema y providers —
/// y que el veredicto que se pinta al final sea el que sale de las lecturas.
void main() {
  setUp(() {
    // Tamano del prototipo: iPhone 16 Pro en puntos logicos.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: IvmetApp()));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
  }

  testWidgets('sin sesion la app arranca en el login', (tester) async {
    await pumpApp(tester);

    expect(find.text('IvMET'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('al ingresar se llega al estado del parque', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    expect(find.text('Estado del parque'), findsOneWidget);
    expect(find.text('Embol S.A. — Planta Santa Cruz'.toUpperCase()), findsOneWidget);
    expect(find.text('3 por sincronizar'), findsOneWidget);
  });

  testWidgets('el asistente recorre los seis pasos y cierra en no conforme', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    expect(find.text('Equipo'), findsOneWidget);
    expect(find.text('BAL-014'), findsOneWidget);
    expect(find.text('Paso 1 de 6'), findsOneWidget);

    for (final paso in <String>[
      'Patrón y condiciones',
      'Excentricidad',
      'Repetibilidad',
      'Linealidad',
    ]) {
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text(paso), findsWidgets);
    }

    await tester.tap(find.text('Calcular resultado'));
    await tester.pumpAndSettle();

    // Las lecturas de arranque traen la linealidad fuera de tolerancia, asi
    // que el veredicto tiene que ser no conforme y la accion, retirar el
    // equipo.
    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text('No conforme'), findsOneWidget);
    expect(find.textContaining('Retirar el equipo de uso'), findsOneWidget);
  });

  testWidgets('corregir la lectura desviada vuelve conforme la verificación', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
    }

    // Paso de linealidad: el punto de 45 kg marca 45,05 con tolerancia 0,03.
    expect(find.text('45 kg — 75 %'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '45,05'), '45,02');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calcular resultado'));
    await tester.pumpAndSettle();

    expect(find.text('Conforme'), findsOneWidget);
    expect(find.textContaining('Próxima verificación intermedia en 30 días'), findsOneWidget);
  });

  testWidgets('áreas baja hasta el histórico de un equipo', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Áreas'));
    await tester.pumpAndSettle();
    expect(find.text('Almacén'), findsOneWidget);

    await tester.tap(find.text('Almacén'));
    await tester.pumpAndSettle();
    expect(find.text('6 equipos registrados'), findsOneWidget);

    await tester.tap(find.text('BAL-014 · Plataforma 60 kg'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico'.toUpperCase()), findsOneWidget);
    expect(find.text('← Almacén'), findsOneWidget);
  });

  testWidgets('ajustes cambia a tema oscuro', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('Tema oscuro'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Desactivado').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Activado'), findsWidgets);
  });
}

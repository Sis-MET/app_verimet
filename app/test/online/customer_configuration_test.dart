import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/customer_configuration.dart';
import 'package:ivmet/features/online/customer_plans.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/online_widgets.dart';
import 'customer_fakes.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openPage(context, child),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final vertical = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;
    await tester.scrollUntilVisible(finder, 300, scrollable: vertical);
    await tester.pumpAndSettle();
  }

  testWidgets('validar conserva cadenas y no ejecuta un envío a Métrica', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await show(
      tester,
      EquipmentValidation(session: session, equipmentId: 'equipment-fixture'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ubicación actual'),
      'Ubicación privada',
    );
    final confirm = find.byType(CheckboxListTile);
    await scrollTo(tester, confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final button = find.text('Guardar validación privada');
    await scrollTo(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final requests = server.requests
        .where((r) => r.path.contains('ivmet_customer_mutate'))
        .toList();
    expect(requests.length, 1);
    final body = object(requests.single.data);
    expect(body['action'], 'equipment.validate');
    expect(
      object(object(body['payload'])['data'])['ubicacion'],
      'Ubicación privada',
    );
    expect(object(body['payload'])['areaId'], 'area-fixture');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'compartir exige consentimiento y reintenta el mismo UUID y snapshot',
    (tester) async {
      final server = CustomerFixtureServer()..saveFailures = 1;
      final session = MobileSession(server.api);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      await show(
        tester,
        ShareEquipmentUpdate(
          session: session,
          equipmentId: 'equipment-fixture',
        ),
      );
      final message = find.widgetWithText(
        TextFormField,
        'Mensaje para Métrica',
      );
      await scrollTo(tester, message);
      await tester.enterText(message, 'Preparar la calibración');
      final send = find.text('Autorizar y enviar actualización');
      await scrollTo(tester, send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        server.requests.where((r) => r.path.contains('ivmet_customer_mutate')),
        isEmpty,
      );
      final confirm = find.byType(CheckboxListTile);
      await scrollTo(tester, confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await scrollTo(tester, send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final retry = find.text('Reintentar guardado');
      await scrollTo(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      final requests = server.requests
          .where((r) => r.path.contains('ivmet_customer_mutate'))
          .map((r) => object(r.data))
          .toList();
      expect(requests.length, 2);
      expect(requests[0], requests[1]);
      expect(object(requests[0]['payload'])['consent'], true);
      expect(object(requests[0]['payload'])['hash'], 'preview-fixture-hash');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'operador no ve alta de planes y puede consultar áreas por planta',
    (tester) async {
      final server = CustomerFixtureServer();
      final session = MobileSession(server.api);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      await show(
        tester,
        CustomerSetupScreen(session: session, initialSection: 'plans'),
      );
      expect(find.text('Nuevo plan metrológico'), findsNothing);
      expect(find.textContaining('jefe de calidad'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('plan no tiene tolerancias de muestra y requiere una prueba', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await show(tester, CustomerPlanEditor(session: session));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del plan'),
      'Mi procedimiento',
    );
    final button = find.text('Guardar borrador del plan');
    await scrollTo(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Incluye al menos una prueba.'), findsOneWidget);
    expect(
      server.requests.where((r) => r.path.contains('ivmet_customer_mutate')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

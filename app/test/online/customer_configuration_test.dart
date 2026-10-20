import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/customer_configuration.dart';
import 'package:ivmet/features/online/equipment_validation.dart';
import 'package:ivmet/features/online/equipment_check_configuration.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/online_widgets.dart';
import 'customer_fakes.dart';
import 'finders.dart';

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
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await show(
      tester,
      EquipmentValidation(session: session, equipmentId: 'equipment-fixture'),
    );
    await tester.enterText(
      fieldLabeled('Ubicación actual'),
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
      final session = MobileSession(server.api, recovery: server.recovery);
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
      final message = fieldLabeled('Mensaje para Métrica');
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
  testWidgets('la configuración general ya no expone planes metrológicos', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await show(
      tester,
      CustomerSetupScreen(session: session, initialSection: 'plans'),
    );
    expect(find.text('Nuevo plan metrológico'), findsNothing);
    expect(find.text('Planes metrológicos'), findsNothing);
    // Una sección desconocida cae en las áreas de la primera planta.
    expect(find.text('Áreas · Planta uno'), findsOneWidget);
    expect(find.text('Gestionar'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('plantas contiene sus áreas y patrones queda separado', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await show(
      tester,
      CustomerSetupScreen(session: session, plantId: 'plant-fixture'),
    );
    expect(find.text('Áreas · Planta uno'), findsOneWidget);
    expect(find.text('Nueva área'), findsOneWidget);
    expect(find.text('Producción'), findsOneWidget);
    expect(find.text('Nuevo patrón'), findsNothing);
    expect(find.text('Gestionar'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'los patrones se editan y muestran el estado de sus certificados',
    (tester) async {
      final server = CustomerFixtureServer();
      final session = MobileSession(server.api, recovery: server.recovery);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      await show(tester, Scaffold(body: PatternsPanel(session: session)));
      expect(find.text('JP-001 · Juego de pesas patrón'), findsOneWidget);
      // El servidor envía "20.000000000": en pantalla, sin ceros de relleno.
      expect(find.text('pesas · 20 kg'), findsOneWidget);
      expect(find.text('Editar patrón'), findsOneWidget);
      expect(find.text('Agregar certificado'), findsOneWidget);
      // Los certificados que ya existen se siguen viendo y se pueden anular.
      expect(
        find.text('CERT-2026-001 · Laboratorio acreditado'),
        findsOneWidget,
      );
      expect(find.byTooltip('Anular certificado'), findsOneWidget);
      // "Nuevo patrón" quedaba apoyado en la primera tarjeta.
      final button = tester.getRect(
        find.ancestor(
          of: find.text('Nuevo patrón'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      final card = tester.getRect(find.byType(Card).first);
      expect(card.top - button.bottom, greaterThanOrEqualTo(16));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'la capacidad de un patrón se escribe con coma y viaja con punto',
    (tester) async {
      final server = CustomerFixtureServer();
      final session = MobileSession(server.api, recovery: server.recovery);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      await show(tester, Scaffold(body: PatternsPanel(session: session)));
      await tester.tap(find.text('Editar patrón'));
      await tester.pumpAndSettle();

      final capacity = fieldLabeled('Capacidad');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: capacity,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '20',
      );
      await tester.enterText(capacity, '12,5');
      final save = find.text('Guardar');
      await scrollTo(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final sent = server.requests.singleWhere(
        (r) => r.path.contains('ivmet_customer_mutate'),
      );
      expect(object(object(sent.data)['payload'])['capacity'], '12.5');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('la rutina guiada guarda una sola configuración por balanza', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    session.user!['role'] = 'cliente_jefe_calidad';
    await show(
      tester,
      EquipmentCheckConfigurationScreen(
        session: session,
        bundle: const {
          'equipment': {
            'id': 'equipment-fixture',
            'cod_metrica': '0001-01-001',
            'tipo_balanza': 'Plataforma',
          },
          'ranges': [
            {
              'numero_rango': 1,
              'capacidad_max': '100',
              'division_escala': '0.1',
              'unidad': 'kg',
            },
          ],
          'plan': null,
        },
      ),
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Paso 2 de 2 · Errores permisibles'), findsOneWidget);
    expect(find.text('Linealidad'), findsOneWidget);
    expect(find.textContaining('Carga ('), findsNothing);
    for (final field
        in find.byType(TextFormField).evaluate().toList().asMap().keys) {
      await tester.enterText(find.byType(TextFormField).at(field), '0.5');
    }
    await tester.tap(find.text('Activar configuración'));
    await tester.pumpAndSettle();
    final requests = server.requests
        .where((r) => r.path.contains('ivmet_customer_configure_checks'))
        .toList();
    expect(requests, hasLength(1));
    final body = object(requests.single.data);
    final configuration = object(body['configuration']);
    expect(objects(configuration['tests']), hasLength(3));
    expect(configuration.containsKey('name'), false);
    expect(configuration.containsKey('procedureReference'), false);
    expect(
      objects(configuration['tests']).every(
        (test) =>
            !test.containsKey('frequencyDays') &&
            object(test['schedule'])['mode'] == 'fixed' &&
            object(test['schedule'])['unit'] == 'month' &&
            object(test['schedule'])['every'] == 1 &&
            test['tolerance'] == '0.5' &&
            !test.containsKey('loads') &&
            !test.containsKey('load') &&
            !test.containsKey('repetitions') &&
            !test.containsKey('positions'),
      ),
      true,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

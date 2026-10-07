import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/catalog_screen.dart';
import 'package:ivmet/features/online/equipment_registration.dart';
import 'package:ivmet/features/online/equipment_screen.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/online_widgets.dart';
import 'customer_fakes.dart';
import 'fakes.dart';
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

  Future<void> type(WidgetTester tester, Finder field, String text) async {
    await scrollTo(tester, field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  Future<MobileSession> signIn(
    WidgetTester tester,
    FixtureServer server, {
    bool quality = true,
  }) async {
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    if (quality) session.user!['role'] = 'cliente_jefe_calidad';
    return session;
  }

  /// Accion de la pildora flotante con ese rotulo.
  Finder pill(String label) => find.descendant(
    of: find.byKey(const ValueKey('wizard-next')),
    matching: find.text(label),
  );

  Future<void> nextStep(WidgetTester tester) async {
    await tester.tap(pill('Siguiente'));
    await tester.pumpAndSettle();
  }

  List<Json> mutations(FixtureServer server) => server.requests
      .where((r) => r.path.contains('ivmet_customer_mutate'))
      .map((r) => object(r.data))
      .toList();

  final registeredBundle = <String, dynamic>{
    ...fixtureBundle,
    'equipment': {
      'id': 'equipment-registered',
      'origen': 'CLIENTE',
      'cod_metrica': null,
      'cod_interno': 'BAL-NUEVA',
      'marca': 'Marca',
      'modelo': 'Modelo',
      'serie': 'S-1',
      'tipo_balanza': 'Báscula camionera',
      'clase': 'III',
      'source_version': 4,
    },
    'ranges': [
      {
        'numero_rango': 1,
        'unidad': 'kg',
        'capacidad_max': '150.000000000',
        'division_escala': '0.020000000',
        'intervalo_verificacion': null,
      },
    ],
    'registeredByCustomer': true,
    'registrationInUse': false,
    'registrationSharePending': true,
    'registrationShared': false,
  };

  testWidgets(
    'registrar envía el área nueva, el tipo y los rangos con punto decimal',
    (tester) async {
      final server = CustomerFixtureServer();
      final session = await signIn(tester, server);
      await show(
        tester,
        EquipmentRegistrationScreen.create(
          session: session,
          plantId: 'plant-fixture',
        ),
      );
      // La planta del fixture no tiene áreas: se pide directamente la primera.
      expect(find.text('Área existente'), findsNothing);
      expect(find.text('Paso 1 de 3 · Área'), findsOneWidget);
      // Sin area no avanza: lleva al campo y lo dice.
      await nextStep(tester);
      expect(find.text('Paso 1 de 3 · Área'), findsOneWidget);
      expect(find.text('Completa este campo.'), findsOneWidget);
      await type(tester, fieldLabeled('Nombre del área nueva'), 'Laboratorio');
      await nextStep(tester);
      await type(tester, fieldLabeled('Código interno'), 'BAL-NUEVA');
      await type(tester, fieldLabeled('Serie'), 'S-1');
      await nextStep(tester);
      expect(find.text('Paso 3 de 3 · Datos técnicos'), findsOneWidget);
      await scrollTo(tester, find.text('Báscula camionera'));
      await tester.tap(find.text('Báscula camionera'));
      await scrollTo(tester, find.text('III'));
      await tester.tap(find.text('III'));
      await tester.pump();
      await type(tester, fieldLabeled('Capacidad máxima (kg)'), '60');
      await type(tester, fieldLabeled('División de escala d (kg)'), '0,01');
      await type(
        tester,
        fieldLabeled('Intervalo de verificación e (kg, opcional)'),
        '0,01',
      );
      await scrollTo(tester, find.text('Agregar rango'));
      await tester.tap(find.text('Agregar rango'));
      await tester.pumpAndSettle();
      await type(tester, fieldLabeled('Capacidad máxima (kg)').at(1), '50');
      await type(
        tester,
        fieldLabeled('División de escala d (kg)').at(1),
        '0,02',
      );
      final confirm = find.byType(CheckboxListTile);
      await scrollTo(tester, confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final register = pill('Registrar balanza');
      await tester.tap(register);
      await tester.pumpAndSettle();
      expect(mutations(server), isEmpty);
      await scrollTo(
        tester,
        find.text('Debe superar la capacidad del rango 1.'),
      );

      await type(tester, fieldLabeled('Capacidad máxima (kg)').at(1), '150');
      await tester.tap(register);
      await tester.pumpAndSettle();

      final sent = mutations(server);
      expect(sent, hasLength(1));
      expect(sent.single['action'], 'equipment.register');
      final payload = object(sent.single['payload']);
      expect(payload['plantId'], 'plant-fixture');
      expect(payload['areaId'], '');
      expect(payload['areaName'], 'Laboratorio');
      expect(payload['data'], {
        'cod_interno': 'BAL-NUEVA',
        'marca': '',
        'modelo': '',
        'serie': 'S-1',
        'ubicacion': '',
        'tipo': 'TRUCK',
        'clase': 'III',
        'unidad': 'kg',
      });
      expect(payload['ranges'], [
        {'capacity': '60', 'division': '0.01', 'interval': '0.01'},
        {'capacity': '150', 'division': '0.02', 'interval': ''},
      ]);
      // Al confirmar se cierra el formulario.
      expect(find.text('Nombre del área nueva'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('editar una balanza en uso conserva sus datos técnicos', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = await signIn(tester, server);
    await show(
      tester,
      EquipmentRegistrationScreen.edit(
        session: session,
        equipmentId: 'equipment-registered',
      ),
    );
    // La identificación sigue editable; está en el paso anterior a los
    // datos técnicos.
    await nextStep(tester);
    await type(tester, fieldLabeled('Marca'), 'Otra marca');
    await nextStep(tester);
    final locked = find.textContaining(
      'sus datos técnicos no se pueden cambiar',
    );
    await scrollTo(tester, locked);
    expect(locked, findsOneWidget);
    final capacity = fieldLabeled('Capacidad máxima (kg)');
    await scrollTo(tester, capacity);
    final editable = tester.widget<EditableText>(
      find.descendant(of: capacity, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '60');
    expect(editable.readOnly, true);
    expect(find.text('Agregar rango'), findsNothing);

    final confirm = find.byType(CheckboxListTile);
    await scrollTo(tester, confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(pill('Guardar cambios'));
    await tester.pumpAndSettle();

    final sent = mutations(server).single;
    expect(sent['action'], 'equipment.edit');
    final payload = object(sent['payload']);
    expect(payload['id'], 'equipment-registered');
    expect(payload['version'], '4');
    expect(payload['areaId'], 'area-fixture');
    expect(object(payload['data'])['marca'], 'Otra marca');
    expect(payload['ranges'], [
      {'capacity': '60', 'division': '0.01', 'interval': '0.01'},
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'la ficha de una balanza registrada reserva editar, enviar y dar de baja al jefe de calidad',
    (tester) async {
      final server = CustomerFixtureServer()..bundle = registeredBundle;
      final session = await signIn(tester, server, quality: false);
      await show(
        tester,
        EquipmentScreen(session: session, equipmentId: 'equipment-registered'),
      );
      expect(find.text(registeredEquipmentLabel), findsOneWidget);
      expect(find.text('Código Métrica'), findsNothing);
      expect(find.text('150 kg · d 0,02 kg'), findsOneWidget);
      for (final action in [
        'Validar ficha',
        'Revisar ficha',
        'Editar balanza',
        'Enviar a Métrica',
        'Compartir con Métrica',
        'Dar de baja esta balanza',
      ]) {
        expect(find.text(action), findsNothing, reason: action);
      }
      await tester.pumpWidget(const SizedBox());

      session.user!['role'] = 'cliente_jefe_calidad';
      await show(
        tester,
        EquipmentScreen(session: session, equipmentId: 'equipment-registered'),
      );
      expect(find.text('Editar balanza'), findsOneWidget);
      expect(find.text('Enviar a Métrica'), findsOneWidget);
      expect(find.text('Validar ficha'), findsNothing);
      // Dar de baja es una accion rara: va en ⋮.
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      expect(find.text('Dar de baja esta balanza'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'el catálogo de la planta muestra el origen y solo el jefe de calidad registra',
    (tester) async {
      final server = CustomerFixtureServer()
        ..instruments = [
          {
            'id': 'equipment-registered',
            'origen': 'CLIENTE',
            'cod_metrica': null,
            'cod_interno': 'BAL-NUEVA',
            'marca': 'Marca',
            'modelo': 'Modelo',
            'planta': 'Planta uno',
            'area': 'Producción',
            'departamento': 'Producción',
          },
        ];
      final session = await signIn(tester, server, quality: false);
      Widget catalog() => Scaffold(
        body: CatalogScreen(session: session, plantId: 'plant-fixture'),
      );
      await show(tester, catalog());
      expect(find.text('BAL-NUEVA'), findsOneWidget);
      expect(find.text(registeredEquipmentLabel), findsOneWidget);
      expect(find.textContaining('Métrica ·'), findsNothing);
      expect(find.text('Registrar balanza'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      session.user!['role'] = 'cliente_jefe_calidad';
      await show(tester, catalog());
      expect(find.text('Registrar balanza'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('enviar una balanza a Métrica exige consentimiento', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = await signIn(tester, server);
    await show(
      tester,
      ShareEquipmentRegistration(
        session: session,
        equipmentId: 'equipment-registered',
      ),
    );
    expect(find.text('BAL-NUEVA · Planta uno'), findsOneWidget);
    await scrollTo(tester, find.text('150 kg · d 0,02 kg'));
    expect(find.text('60 kg · d 0,01 kg · e 0,01 kg'), findsOneWidget);
    await type(tester, fieldLabeled('Mensaje para Métrica'), 'Balanza nueva');
    final send = find.text('Autorizar y enviar');
    await scrollTo(tester, send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(mutations(server), isEmpty);

    final consent = find.byType(CheckboxListTile);
    await scrollTo(tester, consent);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await scrollTo(tester, send);
    await tester.tap(send);
    await tester.pumpAndSettle();

    final sent = mutations(server).single;
    expect(sent['action'], 'registration.share');
    expect(object(sent['payload']), {
      'id': 'equipment-registered',
      'hash': 'registration-fixture-hash',
      'consentVersion': 'equipment-registration-v1',
      'consent': true,
      'message': 'Balanza nueva',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

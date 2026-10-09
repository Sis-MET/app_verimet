import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/draft_screen.dart';
import 'package:ivmet/features/online/equipment_screen.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/verification_screen.dart';
import 'customer_fakes.dart';
import 'fakes.dart';
import 'finders.dart';

void main() {
  testWidgets('una verificación histórica permite generar su informe PDF', (
    tester,
  ) async {
    final server = FixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await tester.pumpWidget(
      MaterialApp(
        home: VerificationScreen(session: session, id: 'verification-fixture'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Generar informe PDF'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generate-verification-pdf')),
      findsOneWidget,
    );
    expect(find.text('Conforme'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Excentricidad'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Excentricidad'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Linealidad'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Repetibilidad'), findsOneWidget);
    expect(find.text('Linealidad'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'compartir requiere mensaje y consentimiento para el snapshot exacto',
    (tester) async {
      final server = FixtureServer();
      final session = MobileSession(server.api, recovery: server.recovery);
      await tester.runAsync(
        () => server.api.login('operador', 'fixture-password'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SharePreviewScreen(session: session, alertId: 'alert-fixture'),
        ),
      );
      await tester.pumpAndSettle();
      // La accion es la pildora fija: se habilita con mensaje y
      // consentimiento.
      InkWell share() => tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('wizard-next')),
          matching: find.byType(InkWell),
        ),
      );
      expect(find.text('Compartir expediente'), findsOneWidget);
      expect(share().onTap, isNull);
      await tester.enterText(
        find.byType(TextField),
        'Solicito revisar este caso.',
      );
      await tester.pump();
      expect(share().onTap, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(share().onTap, isNotNull);
      await tester.tap(find.text('Compartir expediente'));
      await tester.pumpAndSettle();
      final sent = server.requests.singleWhere(
        (r) => r.path.contains('confirm_ivmet_alert_share'),
      );
      expect(object(sent.data)['expected_snapshot_hash'], 'fixture-hash');
      expect(object(sent.data)['expected_row_version'], '7');
      expect(object(sent.data)['target_alert_id'], 'alert-fixture');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  Future<void> start(WidgetTester tester, FixtureServer server) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileApiProvider.overrideWithValue(server.api),
          draftRecoveryProvider.overrideWithValue(server.recovery),
        ],
        child: const IvmetApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(fieldLabeled('Usuario o correo'), 'operador');
    await tester.enterText(fieldLabeled('Contraseña'), 'fixture-password');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
  }

  Future<void> nextStep(WidgetTester tester) async {
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'login vacío, datos reales del contrato y navegación por plantas',
    (tester) async {
      final server = CustomerFixtureServer();
      await start(tester, server);
      expect(find.text('BAL-014'), findsNothing);
      expect(find.text('VPN'), findsNothing);
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa tu usuario o tu correo.'), findsOneWidget);
      await login(tester);
      expect(tester.takeException(), isNull, reason: 'Inicio');
      expect(find.text('Cliente aislado'), findsOneWidget);
      expect(find.text('Gestionar plantas'), findsOneWidget);
      expect(find.text('Gestionar patrones'), findsOneWidget);
      await tester.tap(find.text('Plantas'));
      await tester.pumpAndSettle();
      // Cada planta aparece una vez y sus áreas se gestionan dentro de ella.
      expect(find.text('Planta uno'), findsOneWidget);
      expect(find.text('Gestionar plantas'), findsNothing);
      await tester.tap(find.text('Planta uno'));
      await tester.pumpAndSettle();
      expect(find.text('Áreas · Planta uno'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pesas patrón'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo patrón'), findsOneWidget);
      expect(find.text('Selecciona una planta'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'Plantas');
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(find.text('Selecciona una planta'), findsOneWidget);
      expect(find.text('Planta uno'), findsOneWidget);
      await tester.tap(find.text('Lista completa'));
      await tester.pumpAndSettle();
      expect(find.text('BAL-014'), findsOneWidget);
      expect(find.text('Departamento · Producción'), findsOneWidget);
      expect(find.text('Métrica · 0001-01-001'), findsOneWidget);
      await tester.enterText(
        fieldLabeled('Código interno, departamento o marca', type: TextField),
        'Producción',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final searchRequest = server.requests.lastWhere(
        (request) =>
            request.path.contains('ivmet_mobile_read') &&
            object(request.data)['section'] == 'instruments',
      );
      expect(
        object(object(searchRequest.data)['filters'])['search'],
        'Producción',
      );
      await tester.tap(find.text('Por planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planta uno'));
      await tester.pumpAndSettle();
      expect(find.text('BAL-014'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Catálogo por planta');
      await tester.tap(find.text('BAL-014'));
      await tester.pumpAndSettle();
      expect(find.text('Código Métrica'), findsOneWidget);
      expect(find.text('0001-01-001'), findsOneWidget);
      // La ficha abre por las acciones; el plan queda debajo del mosaico.
      await tester.scrollUntilVisible(
        find.text('VERIFICACIONES ACTIVAS'),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('VERIFICACIONES ACTIVAS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Inicio abre Plantas en la pastilla de cada gestión', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    await start(tester, server);
    await login(tester);

    await tester.ensureVisible(find.text('Gestionar patrones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestionar patrones'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo patrón'), findsOneWidget);
    expect(find.text('Selecciona una planta'), findsNothing);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gestionar plantas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestionar plantas'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una planta'), findsOneWidget);
    expect(find.text('Nuevo patrón'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Atrás retrocede dentro de IvMET antes de ofrecer salir', (
    tester,
  ) async {
    final server = FixtureServer();
    await start(tester, server);
    await login(tester);

    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una planta'), findsOneWidget);
    await tester.tap(find.text('Planta uno'));
    await tester.pumpAndSettle();
    expect(find.text('Balanzas'), findsOneWidget);
    await tester.tap(find.text('BAL-014'));
    await tester.pumpAndSettle();
    expect(find.text('Ficha de la balanza'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ficha de la balanza'), findsNothing);
    expect(find.text('Balanzas'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una planta'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Cliente aislado'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Salir de IvMET?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente aislado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('licencia inactiva no muestra catálogo ni consulta bootstrap', (
    tester,
  ) async {
    final server = FixtureServer()..allowed = false;
    await start(tester, server);
    await login(tester);
    expect(find.textContaining('Tu acceso no está activo'), findsOneWidget);
    expect(server.bootstrapCalls, 0);
    expect(find.text('Cliente aislado'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('contraseña temporal obliga a cambiar antes de mostrar datos', (
    tester,
  ) async {
    final server = FixtureServer();
    server.user['mustChangePassword'] = true;
    await start(tester, server);
    await login(tester);
    expect(find.text('Define tu contraseña personal'), findsOneWidget);
    expect(server.bootstrapCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'la captura deja el AppBar limpio: pasos en el panel y acciones en ⋮',
    (tester) async {
      final server = FixtureServer();
      final session = MobileSession(server.api, recovery: server.recovery);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DraftScreen(session: session, bundle: fixtureWizardBundle),
        ),
      );
      await tester.pumpAndSettle();

      // Solo donde se esta, sin fila de pasos ni texto de guardado fijo.
      expect(find.byKey(const ValueKey('draft-step-header')), findsNothing);
      expect(
        find.text('Paso 1 de 5 · Pesas patrón y ambiente'),
        findsOneWidget,
      );
      expect(find.text('Guardar y salir'), findsNothing);
      expect(find.byKey(const ValueKey('wizard-nav')), findsOneWidget);

      // "Siguiente" con un dato invalido lleva al campo y no avanza.
      await tester.enterText(fieldLabeled('Temperatura (°C)'), '1,23456');
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(
        find.text('Completa los datos marcados para continuar.'),
        findsOneWidget,
      );
      expect(find.textContaining('Paso 1 de 5'), findsOneWidget);
      await tester.enterText(fieldLabeled('Temperatura (°C)'), '21,5');

      // Los pasos estan en el panel lateral y llevan a cualquiera.
      await tester.tap(find.byTooltip('Pasos'));
      await tester.pumpAndSettle();
      expect(find.text('Linealidad'), findsOneWidget);
      expect(find.text('1 certificado'), findsNothing);
      await tester.tap(find.text('Linealidad'));
      await tester.pumpAndSettle();
      expect(find.text('Paso 4 de 5 · Linealidad'), findsOneWidget);

      // Omitir la prueba es una accion de ⋮.
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      expect(find.text('Datos de la balanza'), findsOneWidget);
      expect(find.text('Guardar y salir'), findsOneWidget);
      await tester.tap(find.text('Omitir esta prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Prueba omitida'), findsOneWidget);
      await tester.tap(find.text('Volver a incluir la prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Prueba omitida'), findsNothing);

      // Atras retrocede un paso; en el primero no sale, avisa como salir.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('Paso 3 de 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Anterior'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('Paso 1 de 5'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('Es el primer paso'), findsOneWidget);
      expect(find.byType(DraftScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('el borrador guarda strings exactos y no finaliza ni comparte', (
    tester,
  ) async {
    final server = FixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureBundle),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Guardar borrador privado'), findsNothing);
    await nextStep(tester);
    await nextStep(tester);
    await nextStep(tester);
    final indication = fieldLabeled('Indicación');
    await tester.ensureVisible(indication);
    await tester.enterText(indication, '0,123456789');
    await nextStep(tester);
    expect(find.textContaining('Paso 5 de 5'), findsOneWidget);
    final save = find.text('Guardar borrador privado');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final request = server.requests.lastWhere(
      (r) => r.path.contains('ivmet_mobile_save_draft'),
    );
    final content = object(object(request.data)['content']);
    expect(
      objects(
        objects(content['tests']).single['readings'],
      ).single['indication'],
      '0.123456789',
    );
    expect(content.containsKey('verdict'), false);
    expect(
      server.requests.any(
        (r) => r.path.contains('share') || r.path.contains('finalize'),
      ),
      false,
    );
    expect(
      find.byTooltip('Guardado en este dispositivo y en el servidor'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('una configuración guiada puede finalizarse en Supabase', (
    tester,
  ) async {
    final server = FixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureNormativeBundle),
      ),
    );
    await tester.pumpAndSettle();
    await nextStep(tester);
    await nextStep(tester);
    await nextStep(tester);
    final indication = fieldLabeled('Indicación');
    await tester.ensureVisible(indication);
    await tester.enterText(indication, '10.1');
    await nextStep(tester);
    final save = find.text('Guardar borrador privado');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Finalizar verificación intermedia'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Finalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado guardado'), findsOneWidget);
    final request = server.requests.singleWhere(
      (r) => r.path.contains('ivmet_mobile_finalize_draft'),
    );
    final body = object(request.data);
    expect(body['draft_id'], 'draft-fixture');
    expect(
      body['expected_version'],
      server.savedDrafts.values.single['version'],
    );
    expect(body['finalize_id'], isNotEmpty);
    expect(body.containsKey('verdict'), false);
    await tester.tap(find.text('Ver historial'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('compartir la ficha solo aparece con correcciones pendientes', (
    tester,
  ) async {
    final server = FixtureServer();
    // Rangos con la escala completa que entrega Postgres, para comprobar como
    // se muestran. El fixture compartido los deja vacios.
    server.bundle = {
      ...fixtureBundle,
      'ranges': [
        {
          'numero_rango': 1,
          'unidad': 'kg',
          'capacidad_max': '20.000000000',
          'division_escala': '0.010000000',
          'cantidad_decimales': 2,
        },
        {
          'numero_rango': 2,
          'unidad': 'kg',
          'capacidad_max': '50.000000000',
          'division_escala': '0.100000000',
          'cantidad_decimales': 1,
        },
      ],
    };
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    session.user!['role'] = 'cliente_jefe_calidad';

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          session: session,
          equipmentId: 'equipment-fixture',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compartir con Métrica'), findsNothing);

    // El catalogo entrega `numeric` con toda su escala. En pantalla van los
    // decimales que la balanza resuelve, no los nueve de Postgres.
    expect(
      find.text('20,00 kg · división 0,01 kg', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('50,0 kg · división 0,1 kg', skipOffstage: false),
      findsOneWidget,
    );

    server.customerUpdatePending = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          session: session,
          equipmentId: 'equipment-fixture',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compartir con Métrica'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'reiniciar recupera automáticamente el paso y la captura incompleta',
    (tester) async {
      final server = FixtureServer()..bundle = fixtureWizardBundle;
      final session = MobileSession(server.api, recovery: server.recovery);
      await tester.runAsync(
        () => session.login('operador', 'fixture-password'),
      );
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DraftScreen(session: session, bundle: fixtureWizardBundle),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(fieldLabeled('Temperatura (°C)'), '23,125');
      final humidity = fieldLabeled('Humedad relativa (%)');
      await tester.ensureVisible(humidity);
      await tester.enterText(humidity, '48');
      await nextStep(tester);
      expect(find.text('Excentricidad'), findsOneWidget);
      await tester.enterText(fieldLabeled('Indicación'), '10,001');
      await nextStep(tester);
      expect(find.text('Repetibilidad'), findsOneWidget);
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Omitir esta prueba'));
      await tester.pumpAndSettle();
      await tester.enterText(
        fieldLabeled('Motivo de omisión'),
        'Carga no disponible',
      );
      await nextStep(tester);
      expect(find.textContaining('Paso 4 de 5'), findsOneWidget);
      final indication = fieldLabeled('Indicación');
      await tester.enterText(indication, '10,');
      await tester.pumpAndSettle();
      // Destroy both the widget tree and the session without saving or leaving.
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await start(tester, server);
      expect(find.textContaining('Paso 4 de 5'), findsOneWidget);
      expect(tester.widget<TextFormField>(indication).controller!.text, '10,');
      await tester.tap(find.byTooltip('Anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Prueba omitida'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(fieldLabeled('Motivo de omisión'))
            .controller!
            .text,
        'Carga no disponible',
      );
      await tester.tap(find.byTooltip('Pasos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pesas patrón y ambiente').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(fieldLabeled('Temperatura (°C)'))
            .controller!
            .text,
        '23,125',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      // Also exercise the summary with the real app theme at narrow width.
      tester.view.physicalSize = const Size(320, 740);
      await nextStep(tester);
      await nextStep(tester);
      await nextStep(tester);
      await tester.enterText(indication, '10,002');
      await nextStep(tester);
      expect(find.textContaining('Paso 5 de 5'), findsOneWidget);
      await tester.scrollUntilVisible(
        fieldLabeled('Observaciones'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        fieldLabeled('Observaciones'),
        'Verificación recuperada',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sin señal, la app abre con la copia y retoma la captura', (
    tester,
  ) async {
    final server = FixtureServer()..bundle = fixtureWizardBundle;
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureWizardBundle),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabeled('Temperatura (°C)'), '23,125');
    await tester.pumpAndSettle();

    // El operario cierra la app con la captura a medias y se queda sin
    // cobertura: al volver, la sesion no se puede validar contra Supabase.
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    server.online = false;
    await start(tester, server);

    // La cuenta se validó hace menos de 7 días: la app abre con la copia
    // del teléfono, avisa que no hay conexión y retoma la captura.
    expect(find.text('Acceso a IvMET'), findsNothing);
    expect(find.text('Tienes 1 captura sin enviar'), findsNothing);
    expect(find.textContaining('Sin conexión · datos del'), findsOneWidget);
    expect(find.textContaining('Paso 1 de 5'), findsOneWidget);
    final temperature = fieldLabeled('Temperatura (°C)');
    expect(
      tester.widget<TextFormField>(temperature).controller!.text,
      '23,125',
    );
    await tester.enterText(temperature, '23,500');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin borradores locales, sin señal se sigue bloqueando', (
    tester,
  ) async {
    final server = FixtureServer()..online = false;
    await start(tester, server);
    // No hay dueno anotado —nunca hubo sesion validada en este dispositivo—
    // asi que no hay nada que devolver.
    expect(find.text('Tienes 1 captura sin enviar'), findsNothing);
  });
}

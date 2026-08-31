import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/draft_screen.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/history_screen.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'compartir requiere mensaje y consentimiento para el snapshot exacto',
    (tester) async {
      final server = FixtureServer();
      final session = MobileSession(server.api);
      await tester.runAsync(
        () => server.api.login('operador', 'fixture-password'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SharePreviewScreen(session: session, alertId: 'alert-fixture'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        FilledButton,
        'Compartir expediente autorizado',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField),
        'Solicito revisar este caso.',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
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
        overrides: [mobileApiProvider.overrideWithValue(server.api)],
        child: const IvmetApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usuario'),
      'operador',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'fixture-password',
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'login vacío, datos reales del contrato y navegación por plantas',
    (tester) async {
      final server = FixtureServer();
      await start(tester, server);
      expect(find.text('BAL-014'), findsNothing);
      expect(find.text('VPN'), findsNothing);
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa tu usuario.'), findsOneWidget);
      await login(tester);
      expect(tester.takeException(), isNull, reason: 'Inicio');
      expect(find.text('Cliente aislado'), findsOneWidget);
      await tester.tap(find.text('Áreas'));
      await tester.pumpAndSettle();
      expect(find.text('Planta uno'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Plantas');
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(find.text('0001-01-001'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Catálogo');
      await tester.tap(find.text('0001-01-001'));
      await tester.pumpAndSettle();
      expect(find.text('Plan de prueba'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('licencia inactiva no muestra catálogo ni consulta bootstrap', (
    tester,
  ) async {
    final server = FixtureServer()..allowed = false;
    await start(tester, server);
    await login(tester);
    expect(find.textContaining('Tu licencia no está activa'), findsOneWidget);
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
  testWidgets('el borrador guarda strings exactos y no finaliza ni comparte', (
    tester,
  ) async {
    final server = FixtureServer();
    final session = MobileSession(server.api);
    await tester.runAsync(
      () => server.api.login('operador', 'fixture-password'),
    );
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureBundle),
      ),
    );
    await tester.pumpAndSettle();
    final indication = find.widgetWithText(TextFormField, 'Indicación');
    await tester.ensureVisible(indication);
    await tester.enterText(indication, '0,123456789');
    final save = find.text('Guardar borrador privado');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final request = server.requests.singleWhere(
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
    expect(find.textContaining('Guardado en Supabase'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('un plan normativo guardado puede finalizarse en Supabase', (
    tester,
  ) async {
    final server = FixtureServer();
    final session = MobileSession(server.api);
    await tester.runAsync(
      () => server.api.login('operador', 'fixture-password'),
    );
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureNormativeBundle),
      ),
    );
    await tester.pumpAndSettle();
    final indication = find.widgetWithText(TextFormField, 'Indicación');
    await tester.ensureVisible(indication);
    await tester.enterText(indication, '10.1');
    final save = find.text('Guardar borrador privado');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final finalize = find.text('Finalizar comprobación interna');
    await tester.ensureVisible(finalize);
    await tester.tap(finalize);
    await tester.pumpAndSettle();
    expect(find.text('Finalizar comprobación interna'), findsWidgets);
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado guardado'), findsOneWidget);
    final request = server.requests.singleWhere(
      (r) => r.path.contains('ivmet_mobile_finalize_draft'),
    );
    final body = object(request.data);
    expect(body['draft_id'], 'draft-fixture');
    expect(body['expected_version'], '1');
    expect(body['finalize_id'], isNotEmpty);
    expect(body.containsKey('verdict'), false);
    await tester.tap(find.text('Ver historial'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

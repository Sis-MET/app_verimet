import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/core/storage/draft_recovery_store.dart';
import 'package:ivmet/features/online/draft_controller.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/offline_copy.dart';

import 'fakes.dart';
import 'finders.dart';

/// El servidor rechaza la finalización con un código.
class RejectingServer extends FixtureServer {
  String? rejectFinalization;
  @override
  FutureOr<(int, Json)> handle(RequestOptions request) {
    final code = rejectFinalization;
    if (code != null &&
        online &&
        request.path.contains('ivmet_mobile_finalize_draft')) {
      requests.add(request);
      return (400, {'message': code});
    }
    return super.handle(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copia del teléfono', () {
    test('la clave no depende de la zona horaria ni de filtros vacíos', () {
      expect(
        OfflineCopy.key('equipment', {
          'utcOffsetMinutes': -240,
          'equipmentId': 'e1',
        }),
        OfflineCopy.key('equipment', {'equipmentId': 'e1'}),
      );
      expect(
        OfflineCopy.key('history', {'page': 1, 'equipmentId': null}),
        OfflineCopy.key('history', {'page': 1}),
      );
      expect(
        OfflineCopy.key('history', {'page': 1}),
        isNot(OfflineCopy.key('history', {'page': 2})),
      );
    });

    test('sin señal se busca en el catálogo descargado', () {
      final catalog = {
        'items': [
          {
            'id': 'a',
            'cod_interno': 'BAL-014',
            'marca': 'Ohaus',
            'planta_id': 'p1',
          },
          {
            'id': 'b',
            'cod_interno': 'BAL-020',
            'marca': 'Mettler',
            'planta_id': 'p2',
          },
        ],
      };
      expect(objects(searchCatalog(catalog, {'search': 'ohaus'})['items']), [
        catalog['items']!.first,
      ]);
      expect(searchCatalog(catalog, {'plantId': 'p2'})['total'], 1);
      expect(searchCatalog(catalog, {'search': 'bal'})['total'], 2);
      expect(searchCatalog(catalog, {'search': 'bal', 'page': 2})['items'], []);
    });

    test('en SQLite, olvidar la copia no toca los borradores', () async {
      final store = SqliteDraftRecoveryStore(NativeDatabase.memory());
      addTearDown(store.close);
      await store.write('["owner"]', 'borradores');
      await store.write('offline:v1|["owner"]|grant', 'permiso');
      await store.write('offline:v1|["otro"]|grant', 'otro permiso');
      await OfflineCopy(store).forget('["owner"]');
      expect(await store.read('["owner"]'), 'borradores');
      expect(await store.read('offline:v1|["owner"]|grant'), isNull);
      expect(await store.read('offline:v1|["otro"]|grant'), 'otro permiso');
    });

    test('el permiso vence a los 7 días y atrasar el reloj no lo alarga', () {
      final validated = DateTime.utc(2026, 10, 1, 8);
      final grant = OfflineGrant(
        user: const {'id': 'u'},
        access: const {},
        validatedAt: validated,
        lastSeen: validated.add(const Duration(days: 2)),
      );
      expect(grant.usableAt(validated.add(const Duration(days: 3))), true);
      expect(grant.usableAt(validated.add(const Duration(days: 7))), false);
      // El teléfono ya se usó el día 2: volver al día 1 no se acepta.
      expect(grant.usableAt(validated.add(const Duration(days: 1))), false);
      expect(
        grant
            .seenAt(validated.add(const Duration(days: 4)))
            .lastSeen
            .difference(validated)
            .inDays,
        4,
      );
    });
  });

  group('trabajo sin señal', () {
    late RejectingServer server;
    late MobileSession session;
    setUp(() async {
      server = RejectingServer();
      session = MobileSession(server.api, recovery: server.recovery);
      await session.login('operador', 'fixture-password');
    });
    tearDown(() {
      session.dispose();
      server.api.dispose();
    });

    DraftController capture() {
      final controller = DraftController(
        session: session,
        bundle: fixtureNormativeBundle,
      );
      final readings =
          controller.testInput('trial-normative-fixture')['readings'] as List;
      (readings.single as Json)['indication'] = '10,1';
      controller.changed();
      return controller;
    }

    List<Json> sent(String rpc) => server.requests
        .where((r) => r.path.contains(rpc))
        .map((r) => object(r.data))
        .toList();

    test('en línea guarda la copia; sin señal la app abre con ella', () async {
      expect(session.grant, isNotNull);
      await session.read('equipment', {
        'utcOffsetMinutes': -240,
        'equipmentId': 'equipment-fixture',
      });
      await pumpEventQueue();

      server.online = false;
      final cold = MobileSession(server.api, recovery: server.recovery);
      await cold.start();
      expect(cold.stage, SessionStage.ready);
      expect(cold.online, false);
      expect(cold.user!['id'], 'user-fixture');
      expect(object(cold.bootstrap['client'])['name'], 'Cliente aislado');
      expect(cold.copySavedAt, isNotNull);

      final copied = await cold.read('equipment', {
        'utcOffsetMinutes': 0,
        'equipmentId': 'equipment-fixture',
      });
      expect(object(copied['equipment'])['cod_interno'], 'BAL-014');
      expect(copied[OfflineCopy.savedAtKey], isNotNull);
      await expectLater(
        cold.read('agenda', {'from': '2026-01-01', 'to': '2026-01-31'}),
        throwsA(
          isA<MobileFailure>().having(
            (f) => f.code,
            'code',
            'OFFLINE_NOT_COPIED',
          ),
        ),
      );
      // Lo que no se copia (usuarios, plantas) exige señal.
      await expectLater(
        cold.read('team'),
        throwsA(isA<MobileFailure>().having((f) => f.offline, 'offline', true)),
      );
      cold.dispose();
    });

    test('pasados 7 días sin validar, solo quedan las capturas', () async {
      final owner = session.recoveryOwner;
      final old = DateTime.now().subtract(const Duration(days: 8));
      await session.copy.saveGrant(
        owner,
        OfflineGrant(
          user: session.user!,
          access: session.access,
          validatedAt: old,
          lastSeen: old,
        ),
      );
      server.online = false;
      final cold = MobileSession(server.api, recovery: server.recovery);
      await cold.start();
      expect(cold.stage, SessionStage.offline);
      expect(cold.user, isNull);
      expect(cold.error, contains('7 días'));
      cold.dispose();
    });

    test('se corta la señal: se sigue trabajando con lo que había', () async {
      server.online = false;
      await expectLater(
        session.read('drafts', {'page': 9}),
        throwsA(isA<MobileFailure>()),
      );
      expect(session.stage, SessionStage.ready);
      expect(session.online, false);
      server.online = true;
      await session.refresh();
      expect(session.online, true);
      expect(session.copySavedAt, isNull);
    });

    test(
      'finalizar sin señal la cierra en el teléfono y se envía sola al volver',
      () async {
        final controller = capture();
        server.online = false;
        session.connectionLost();
        expect(session.online, false);

        expect(await controller.finalize(), {'queued': true});
        expect(controller.locked, true);
        expect(controller.measuredAt, isNotNull);
        final finalizeId = controller.queuedFinalize!['finalizeId'];
        final measuredAt = controller.measuredAt;
        expect(sent('ivmet_mobile_finalize_draft'), isEmpty);
        controller.dispose();
        await session.uploads.load();
        expect(session.uploads.waiting, 1);
        expect(session.uploads.notOnServer, 1);

        server.online = true;
        await session.refresh();
        await session.uploads.run();
        final save = sent('ivmet_mobile_save_draft').single;
        expect(save['started_at'], isNotNull);
        expect(
          object(
            object(save['content'])['tests'][0],
          )['readings'][0]['indication'],
          '10.1',
        );
        final finalize = sent('ivmet_mobile_finalize_draft').single;
        expect(finalize['finalize_id'], finalizeId);
        expect(finalize['measured_at'], measuredAt);
        expect(finalize['device_clock'], isNotNull);
        expect(session.uploads.items, isEmpty);
        expect(session.uploads.sent, 1);
      },
    );

    test(
      'un rechazo del servidor queda para revisar y se puede corregir',
      () async {
        final controller = capture();
        server.online = false;
        session.connectionLost();
        await controller.finalize();
        final measuredAt = controller.measuredAt;
        controller.dispose();

        server.online = true;
        server.rejectFinalization = 'CERTIFICATE_NOT_ACCESSIBLE';
        await session.refresh();
        await session.uploads.run();
        expect(session.uploads.attention, 1);
        final rejected = session.uploads.items.single;
        expect(
          object(rejected['attention'])['code'],
          'CERTIFICATE_NOT_ACCESSIBLE',
        );

        // No se reintenta en cada vuelta: espera a que alguien la revise.
        final attempts = sent('ivmet_mobile_finalize_draft').length;
        await session.uploads.run();
        expect(sent('ivmet_mobile_finalize_draft').length, attempts);

        final reopened = DraftController(
          session: session,
          bundle: fixtureNormativeBundle,
          recovered: rejected,
        );
        expect(reopened.locked, true);
        expect(await reopened.reopen(), true);
        expect(reopened.locked, false);
        expect(reopened.attention, isNull);
        expect(reopened.measuredAt, measuredAt);
        reopened.dispose();
      },
    );

    test('cerrar sesión borra la copia y conserva las capturas', () async {
      final controller = capture();
      await controller.persist();
      controller.dispose();
      final owner = session.recoveryOwner;
      await session.logout();
      await pumpEventQueue();
      expect(await session.copy.grant(owner), isNull);
      expect(
        await session.copy.get(owner, OfflineCopy.key('bootstrap', const {})),
        isNull,
      );
      expect(await session.recovery.list(owner), hasLength(1));
    });

    test('las capturas empezadas sin señal ocupan su lugar del mes', () async {
      session.bootstrap = {
        ...session.bootstrap,
        'plan': {
          'limits': {'monthlyVerifications': 1},
          'usage': {'monthlyVerifications': 0, 'openDrafts': 0},
        },
      };
      expect(session.monthlyCapturesFull, false);
      server.online = false;
      session.connectionLost();
      final controller = capture();
      await controller.persist();
      controller.dispose();
      await session.uploads.load();
      expect(session.monthlyCapturesFull, true);
    });
  });

  testWidgets(
    'la franja avisa sin señal, cerrar sesión espera y el envío llega solo',
    (tester) async {
      final server = FixtureServer();
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
      await tester.enterText(fieldLabeled('Usuario o correo'), 'operador');
      await tester.enterText(fieldLabeled('Contraseña'), 'fixture-password');
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      // Con la app abierta y en línea se descarga lo necesario.
      expect(
        server.requests.any((r) => object(r.data)['section'] == 'instruments'),
        true,
      );
      final session = ProviderScope.containerOf(
        tester.element(find.byType(IvmetApp)),
      ).read(mobileSessionProvider);
      expect(find.byKey(const ValueKey('connection-strip')), findsNothing);

      server.online = false;
      session.connectionLost();
      final controller = DraftController(
        session: session,
        bundle: fixtureNormativeBundle,
      );
      ((controller.testInput('trial-normative-fixture')['readings'] as List)
                  .single
              as Json)['indication'] =
          '10,1';
      controller.changed();
      expect(await controller.finalize(), {'queued': true});
      controller.dispose();
      await session.uploads.load();
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin conexión · datos del'), findsOneWidget);
      expect(find.textContaining('· 1 por enviar'), findsOneWidget);

      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      final logout = find.byKey(const ValueKey('settings-logout'));
      await tester.scrollUntilVisible(
        logout,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Por encima de la barra flotante de navegación.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.text('Tienes 1 verificación sin enviar'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(session.stage, SessionStage.ready);

      server.online = true;
      unawaited(session.refresh());
      await tester.pumpAndSettle();
      final finalize = server.requests
          .where((r) => r.path.contains('ivmet_mobile_finalize_draft'))
          .map((r) => object(r.data))
          .single;
      expect(finalize['measured_at'], isNotNull);
      expect(session.uploads.items, isEmpty);
      expect(find.byKey(const ValueKey('connection-strip')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

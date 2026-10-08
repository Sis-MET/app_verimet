import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/catalog_screen.dart';
import 'package:ivmet/features/online/check_schedule.dart';
import 'package:ivmet/features/online/commercial_plan.dart';
import 'package:ivmet/features/online/company_users.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/plan_screen.dart';
import 'package:ivmet/features/online/schedule_editor.dart';
import 'package:ivmet/features/online/verification_report.dart';

import 'fakes.dart';
import 'finders.dart';

const _free = {
  'id': 'plan-free',
  'code': 'PLAN-000001',
  'name': 'Gratuito',
  'seats': 2,
  'catalog': {
    'visible': true,
    'order': 1,
    'selfService': true,
    'summary': 'Una planta, 5 balanzas y 2 usuarios para empezar.',
  },
  'limits': {
    'plants': 1,
    'equipment': 5,
    'monthlyVerifications': 20,
    'patterns': 3,
  },
  'features': {'fullReport': false, 'customSchedules': false},
};
const _professional = {
  'id': 'plan-pro',
  'code': 'PLAN-000002',
  'name': 'Profesional',
  'seats': 10,
  'catalog': {
    'visible': true,
    'order': 2,
    'selfService': false,
    'summary': 'Hasta 3 plantas y 50 balanzas.',
  },
  'limits': {
    'plants': 3,
    'equipment': 50,
    'monthlyVerifications': null,
    'patterns': null,
  },
  'features': {'fullReport': true, 'customSchedules': true},
};

/// Empresa autoregistrada en el plan gratuito, con el uso que se indique.
class SelfServiceServer extends FixtureServer {
  SelfServiceServer({int equipment = 2, int users = 1, bool quality = true}) {
    user = {
      ...fixtureUser,
      'id': 'owner-fixture',
      'username': 'ana@acme.example',
      'name': 'Ana Pérez',
      'role': quality ? 'cliente_jefe_calidad' : 'cliente_operador',
    };
    usage = {
      'plants': 1,
      'equipment': equipment,
      'patterns': 0,
      'monthlyVerifications': 3,
      'openDrafts': 1,
      'users': users,
    };
  }

  late Json usage;
  Json? upgradeRequest;
  final List<Json> signups = [];
  final List<Json> resets = [];
  final List<Json> accounts = [];
  final List<Json> mutations = [];

  Json get plan => {
    ..._free,
    'subscriptionId': 'subscription-fixture',
    'subscriptionStatus': 'ACTIVE',
    'periodEndsAt': null,
    'seatsAvailable': 2,
    'usage': usage,
    'selfService': true,
    'contactEmail': 'ana@acme.example',
    'upgradeRequest': upgradeRequest,
  };

  @override
  FutureOr<(int, Json)> handle(RequestOptions request) {
    final body = request.data is Map
        ? object(request.data)
        : <String, dynamic>{};
    const tokens = {
      'accessToken': 'fixture-access',
      'refreshToken': 'fixture-refresh',
    };
    if (request.path.contains('ivmet-signup')) {
      requests.add(request);
      signups.add(body);
      if (body['action'] == 'start') return (200, {'sent': true});
      if (body['code'] != '123456') return (422, {'error': 'INVALID_CODE'});
      return (200, tokens);
    }
    if (request.path.contains('ivmet-password-reset')) {
      requests.add(request);
      resets.add(body);
      return body['action'] == 'start' ? (200, {'sent': true}) : (200, tokens);
    }
    if (request.path.contains('ivmet-team-account')) {
      requests.add(request);
      accounts.add(body);
      return (200, {'id': 'member-new'});
    }
    if (request.path.contains('ivmet_customer_mutate')) {
      requests.add(request);
      mutations.add(body);
      return (200, {'id': 'request-fixture', 'version': '1'});
    }
    if (request.path.contains('ivmet_customer_read')) {
      requests.add(request);
      if (body['section'] == 'members') {
        return (
          200,
          {
            'seats': 2,
            'used': usage['users'],
            'plants': [
              {'id': 'plant-fixture', 'name': 'Planta uno'},
            ],
            'items': [
              {
                'id': 'owner-fixture',
                'name': 'Ana Pérez',
                'username': 'ana@acme.example',
                'role': 'cliente_jefe_calidad',
                'active': true,
                'mustChangePassword': false,
                'version': '1',
                'self': true,
                'owner': true,
                'licensed': true,
                'plantIds': ['plant-fixture'],
              },
            ],
          },
        );
      }
    }
    switch (body['section']) {
      case 'bootstrap':
        requests.add(request);
        bootstrapCalls++;
        return (
          200,
          {
            ...fixtureBootstrap,
            'client': {
              'id': 'client-fixture',
              'name': 'Acme Alimentos',
              'code': 'IV000001',
            },
            'plan': plan,
          },
        );
      case 'plan':
        requests.add(request);
        return (
          200,
          {
            ...plan,
            'offers': [_free, _professional],
          },
        );
    }
    return super.handle(request);
  }
}

Future<MobileSession> _signedIn(
  WidgetTester tester,
  FixtureServer server,
) async {
  final session = MobileSession(server.api, recovery: server.recovery);
  await tester.runAsync(() => session.login('operador', 'fixture-password'));
  return session;
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'una empresa nueva confirma su correo con un código y entra en el plan gratuito',
    (tester) async {
      await _phone(tester);
      final server = SelfServiceServer();
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
      await tester.tap(find.byKey(const ValueKey('access-signup')));
      await tester.pumpAndSettle();
      expect(find.text('Crear cuenta de empresa'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe el nombre de la empresa.'), findsOneWidget);
      await tester.enterText(
        fieldLabeled('Nombre de la empresa'),
        'Acme Alimentos',
      );
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldLabeled('Nombre y apellido'), 'Ana Pérez');
      await tester.enterText(
        fieldLabeled('Correo electrónico'),
        'Ana@Acme.example ',
      );
      await tester.enterText(fieldLabeled('Contraseña'), 'una-clave-larga-1');
      await tester.enterText(
        fieldLabeled('Confirmar contraseña'),
        'una-clave-larga-1',
      );
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(
        find.text('Acepta las condiciones de uso para continuar.'),
        findsOneWidget,
      );
      expect(server.signups, isEmpty);
      await tester.tap(find.byKey(const ValueKey('signup-terms')));
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(server.signups.single['action'], 'start');
      expect(server.signups.single['email'], 'Ana@Acme.example');
      expect(server.signups.single['termsVersion'], 'ivmet-terms-v1');
      expect(
        server.signups.single.containsKey('password'),
        isFalse,
        reason: 'la contraseña viaja solo al confirmar el código',
      );
      expect(
        find.textContaining('Enviamos un código de 6 dígitos'),
        findsOneWidget,
      );

      await tester.enterText(fieldLabeled('Código'), '000000');
      await tester.tap(find.text('Crear empresa'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El código no es válido'), findsOneWidget);

      await tester.enterText(fieldLabeled('Código'), '123456');
      await tester.tap(find.text('Crear empresa'));
      await tester.pumpAndSettle();
      final complete = server.signups.last;
      expect(complete['action'], 'complete');
      expect(complete['password'], 'una-clave-larga-1');
      expect(complete['company'], 'Acme Alimentos');
      expect(find.text('Crear cuenta de empresa'), findsNothing);
      expect(find.text('Acme Alimentos'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-plan')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Plan Gratuito'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mi plan muestra el uso y pide el plan superior a Métrica', (
    tester,
  ) async {
    await _phone(tester);
    final server = SelfServiceServer(equipment: 5);
    final session = await _signedIn(tester, server);
    await tester.pumpWidget(MaterialApp(home: PlanScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Gratuito'), findsWidgets);
    expect(find.text('5 de 5'), findsOneWidget);
    expect(
      find.text('4 de 20'),
      findsOneWidget,
      reason: 'cuenta lo que está en curso',
    );
    expect(find.text('1 en curso'), findsOneWidget);
    expect(find.text('Informe completo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plan-offer-Profesional')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('TU PLAN'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-request-upgrade')));
    await tester.pumpAndSettle();
    expect(
      find.text('Más balanzas'),
      findsOneWidget,
      reason: 'el motivo es el recurso lleno',
    );
    expect(find.text('Profesional'), findsOneWidget);
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
    final sent = server.mutations.single;
    expect(sent['action'], 'upgrade.request');
    expect(object(sent['payload']), {
      'planId': 'plan-pro',
      'reason': 'EQUIPMENT',
      'message': '',
      'phone': '',
    });
    session.dispose();
  });

  testWidgets(
    'registrar una balanza con el plan lleno ofrece pedir uno superior',
    (tester) async {
      await _phone(tester);
      final server = SelfServiceServer(equipment: 5);
      final session = await _signedIn(tester, server);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogScreen(session: session, plantId: 'plant-fixture'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar balanza'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-limit-sheet')), findsOneWidget);
      expect(find.text('Llegaste al límite de tu plan'), findsOneWidget);
      expect(find.textContaining('incluye 5 balanzas'), findsOneWidget);
      expect(find.text('Datos de la balanza'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('plan-limit-request')));
      await tester.pumpAndSettle();
      expect(find.text('Solicitar plan superior'), findsWidgets);
      expect(find.text('Más balanzas'), findsOneWidget);
      session.dispose();
    },
  );

  testWidgets('al operador se le indica que lo pida el jefe de calidad', (
    tester,
  ) async {
    await _phone(tester);
    final server = SelfServiceServer(quality: false);
    final session = await _signedIn(tester, server);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPlanLimit(
                  context,
                  session,
                  PlanLimit.fromCode('PLAN_LIMIT_VERIFICATIONS')!,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pide al jefe de calidad'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-limit-request')), findsNothing);
    expect(find.textContaining('el contador vuelve a cero'), findsOneWidget);
    session.dispose();
  });

  testWidgets('el jefe crea un usuario con contraseña temporal y la entrega', (
    tester,
  ) async {
    await _phone(tester);
    final server = SelfServiceServer();
    final session = await _signedIn(tester, server);
    await tester.pumpWidget(
      MaterialApp(home: CompanyUsersScreen(session: session)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 cupos en uso · plan Gratuito'), findsOneWidget);
    expect(find.text('Ana Pérez (tú)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('users-create')));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabeled('Nombre y apellido'), 'Beto Mamani');
    await tester.enterText(fieldLabeled('Usuario para ingresar'), 'Beto.Acme');
    await tester.tap(find.text('Crear usuario'));
    await tester.pumpAndSettle();

    final sent = server.accounts.single;
    expect(sent['action'], 'create');
    expect(sent['username'], 'beto.acme');
    expect(sent['role'], 'cliente_operador');
    expect(sent['plantIds'], [
      'plant-fixture',
    ], reason: 'con una planta se elige sola');
    expect(sent['password'], matches(RegExp(r'^Iv(-[A-Za-z0-9]{4}){3}$')));
    expect(sent['requestId'], isA<String>());
    expect(find.text('Entrega estos datos'), findsOneWidget);
    expect(find.text('beto.acme'), findsOneWidget);
    expect(find.text(sent['password'] as String), findsOneWidget);
    session.dispose();
  });

  testWidgets('sin cupos libres, crear un usuario ofrece un plan superior', (
    tester,
  ) async {
    await _phone(tester);
    final server = SelfServiceServer(users: 2);
    final session = await _signedIn(tester, server);
    await tester.pumpWidget(
      MaterialApp(home: CompanyUsersScreen(session: session)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('users-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-limit-sheet')), findsOneWidget);
    expect(find.textContaining('incluye 2 usuarios'), findsOneWidget);
    expect(server.accounts, isEmpty);
    session.dispose();
  });

  testWidgets('el plan gratuito usa las periodicidades predefinidas', (
    tester,
  ) async {
    await _phone(tester);
    final rolling = CheckSchedule.legacyDays(10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleEditor(
            initial: rolling,
            testLabel: 'Linealidad',
            customAllowed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Cada mes, el día ${DateTime.now().day}'),
      findsOneWidget,
      reason: 'una regla a medida arranca como mensual',
    );
    expect(find.byKey(const ValueKey('schedule-locked')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('preset-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-locked')), findsOneWidget);
    expect(find.text('Repetir cada'), findsNothing);
    await tester.tap(find.text('Desde la última'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cada verificación realizada fija'),
      findsNothing,
    );
  });

  testWidgets('recuperar la contraseña con un código entra con la nueva', (
    tester,
  ) async {
    await _phone(tester);
    final server = SelfServiceServer();
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
    await tester.enterText(
      fieldLabeled('Usuario o correo'),
      'ana@acme.example',
    );
    await tester.tap(find.byKey(const ValueKey('access-forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(server.resets.single, {
      'action': 'start',
      'email': 'ana@acme.example',
    });
    await tester.enterText(fieldLabeled('Código'), '654321');
    await tester.enterText(
      fieldLabeled('Contraseña nueva'),
      'otra-clave-larga-2',
    );
    await tester.enterText(
      fieldLabeled('Confirmar contraseña'),
      'otra-clave-larga-2',
    );
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();
    expect(server.resets.last, {
      'action': 'complete',
      'email': 'ana@acme.example',
      'code': '654321',
      'password': 'otra-clave-larga-2',
    });
    expect(find.text('Recuperar contraseña'), findsNothing);
    expect(find.text('Acme Alimentos'), findsWidgets);
  });

  test('el informe resumido deja fuera las lecturas de cada prueba', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final generatedAt = DateTime.utc(2026, 9, 4, 16);
    final full = await buildVerificationReport(
      fixtureVerificationData,
      generatedAt: generatedAt,
    );
    final summary = await buildVerificationReport(
      fixtureVerificationData,
      generatedAt: generatedAt,
      full: false,
    );
    int pages(List<int> bytes) =>
        RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;
    expect(ascii.decode(summary.take(4).toList()), '%PDF');
    expect(pages(summary), lessThan(pages(full)));
    expect(summary.length, lessThan(full.length));
  });
}

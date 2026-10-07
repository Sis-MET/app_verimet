import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/equipment_check_configuration.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/online_widgets.dart';

import 'customer_fakes.dart';
import 'fakes.dart';
import 'finders.dart';

void main() {
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
    await tester.enterText(fieldLabeled('Usuario'), 'operador');
    await tester.enterText(fieldLabeled('Contraseña'), 'fixture-password');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
  }

  Json lastRead(FixtureServer server, String section) => object(
    server.requests
        .map((r) => r.data)
        .whereType<Map<dynamic, dynamic>>()
        .lastWhere((body) => body['section'] == section)['filters'],
  );

  testWidgets('Inicio muestra lo de hoy y abre la agenda del operador', (
    tester,
  ) async {
    final server = FixtureServer()
      ..bootstrap = {
        ...fixtureBootstrap,
        'equipmentScope': 'ASSIGNED',
        'agenda': {'dueToday': 2, 'doneToday': 1, 'overdue': 1},
      };
    await start(tester, server);

    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('1 atrasada'), findsOneWidget);
    expect(lastRead(server, 'bootstrap').containsKey('utcOffsetMinutes'), true);
    await tester.tap(find.byKey(const ValueKey('home-today')));
    await tester.pumpAndSettle();

    expect(find.text('Agenda'), findsWidgets);
    expect(find.text('Tus balanzas asignadas'), findsOneWidget);
    expect(find.text('1 balanza atrasada'), findsOneWidget);
    expect(find.text('CAM-001'), findsOneWidget);
    // Hoy queda elegido: sus dos balanzas, con el estado de cada una.
    expect(find.text('BAL-014'), findsOneWidget);
    expect(find.text('BAL-020'), findsOneWidget);
    expect(find.text('Hecha'), findsOneWidget);
    // El operador no filtra por operador ni ve a quién se asignó cada una.
    expect(find.text('Sin operador'), findsNothing);
    expect(find.text('Sin operador asignado'), findsNothing);
    final filters = lastRead(server, 'agenda');
    expect(filters['from'], endsWith('-01'));
    expect(filters.containsKey('operatorId'), false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el jefe filtra la agenda por operador o sin asignar', (
    tester,
  ) async {
    final server = FixtureServer();
    server.user['role'] = 'cliente_jefe_calidad';
    await start(tester, server);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    expect(find.text('Sin operador asignado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-filter-user-Ana')));
    await tester.pumpAndSettle();
    expect(lastRead(server, 'agenda')['operatorId'], 'user-Ana');
    await tester.tap(find.byKey(const ValueKey('agenda-filter-unassigned')));
    await tester.pumpAndSettle();
    expect(lastRead(server, 'agenda')['operatorId'], 'unassigned');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el jefe asigna balanzas a un operador desde Plantas', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    server.user['role'] = 'cliente_jefe_calidad';
    await start(tester, server);
    await tester.tap(find.text('Plantas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Operadores'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Quispe'), findsOneWidget);
    expect(
      find.text('Sin balanzas asignadas · no verá ninguna'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ana Quispe'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assign-equipment-2')));
    await tester.pumpAndSettle();
    expect(find.text('3 de 3'), findsOneWidget);
    await tester.tap(find.text('Guardar · 3 balanzas'));
    await tester.pumpAndSettle();

    final assignment = object(server.assignments.single['assignment']);
    expect(assignment['userId'], 'user-ana');
    expect(assignment['plantId'], 'plant-fixture');
    expect(assignment['equipmentIds'], [
      'equipment-2',
      'equipment-3',
      'equipment-fixture',
    ]);
    expect(find.text('Ana Quispe'), findsOneWidget, reason: 'vuelve al panel');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la periodicidad se elige en palabras y viaja como regla', (
    tester,
  ) async {
    final server = CustomerFixtureServer();
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    session.user!['role'] = 'cliente_jefe_calidad';
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openPage(
              context,
              EquipmentCheckConfigurationScreen(
                session: session,
                bundle: const {
                  'equipment': {
                    'id': 'equipment-fixture',
                    'cod_metrica': '0001-01-001',
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
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-linearity')));
    await tester.pumpAndSettle();
    expect(find.text('Periodicidad'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preset-weekly')));
    await tester.pumpAndSettle();
    // Se suma el lunes al dia de hoy: dos dias por semana.
    final monday = find.byKey(const ValueKey('weekday-1'));
    final today = DateTime.now().weekday;
    await tester.ensureVisible(monday);
    if (today != 1) await tester.tap(monday);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar en todas las pruebas elegidas'));
    await tester.tap(find.text('Aplicar periodicidad'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cada semana'), findsNWidgets(3));

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    for (final field
        in find.byType(TextFormField).evaluate().toList().asMap().keys) {
      await tester.enterText(find.byType(TextFormField).at(field), '0.5');
    }
    await tester.tap(find.text('Activar configuración'));
    await tester.pumpAndSettle();
    final body = object(
      server.requests
          .lastWhere((r) => r.path.contains('ivmet_customer_configure_checks'))
          .data,
    );
    final schedule = object(
      objects(object(body['configuration'])['tests']).first['schedule'],
    );
    expect(schedule['mode'], 'fixed');
    expect(schedule['unit'], 'week');
    expect(schedule['weekdays'], ({1, today}.toList()..sort()));
    expect(schedule.containsKey('startsOn'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

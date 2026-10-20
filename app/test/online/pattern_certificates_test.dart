import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/utils/calendar_dates.dart';
import 'package:ivmet/features/online/customer_configuration.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/online_widgets.dart';

import 'customer_fakes.dart';
import 'fakes.dart';
import 'finders.dart';

/// Patrones con certificados fechados respecto de hoy: así el estado no
/// cambia con el paso del tiempo.
class _CertificatesServer extends CustomerFixtureServer {
  Json certificate(String number, int expiresInDays, {bool annulled = false}) =>
      {
        'id': 'certificate-$number',
        'numero': number,
        'laboratorio': 'Laboratorio acreditado',
        'calibrado_el': dayKey(addDays(today(), expiresInDays - 365)),
        'vence_el': dayKey(addDays(today(), expiresInDays)),
        'estado': annulled ? 'ANNULLED' : 'ACTIVE',
        'row_version': '1',
      };

  Json pattern(String id, String code, List<Json> certificates) => {
    'id': id,
    'codigo': code,
    'descripcion': 'Pesa',
    'tipo': 'pesas',
    'capacidad': '20.000000000',
    'unidad': 'kg',
    'activo': true,
    'plantIds': ['plant-fixture'],
    'row_version': '1',
    'canEdit': true,
    'certificates': certificates,
  };

  @override
  FutureOr<(int, Json)> handle(RequestOptions request) {
    final body = request.data is Map
        ? object(request.data)
        : <String, dynamic>{};
    if (request.path.contains('ivmet_customer_read') &&
        body['section'] == 'patterns') {
      requests.add(request);
      return (
        200,
        {
          'total': 2,
          'items': [
            pattern('pattern-ok', 'P-VIGENTE', [
              certificate('C-NUEVO', 300),
              certificate('C-ANULADO', 200, annulled: true),
            ]),
            pattern('pattern-late', 'P-VENCIDO', [certificate('C-VIEJO', -35)]),
          ],
        },
      );
    }
    return super.handle(request);
  }
}

void main() {
  Future<MobileSession> open(WidgetTester tester, FixtureServer server) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openPage(
                context,
                Scaffold(body: PatternsPanel(session: session)),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    return session;
  }

  /// Elige un día en la hoja del calendario: [months] meses desde el que
  /// muestra y el día [day], o el que ya trae si es null.
  Future<void> pickDate(
    WidgetTester tester,
    String key, {
    int months = 0,
    int? day,
  }) async {
    await tester.tap(find.byKey(ValueKey('date-$key')));
    await tester.pumpAndSettle();
    for (var i = 0; i < months.abs(); i++) {
      await tester.tap(
        find.byTooltip(months < 0 ? 'Mes anterior' : 'Mes siguiente'),
      );
      await tester.pumpAndSettle();
    }
    if (day != null) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('$day'),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Usar esta fecha'));
    await tester.pumpAndSettle();
  }

  testWidgets('cada certificado dice si está vigente, vencido o anulado', (
    tester,
  ) async {
    final session = await open(tester, _CertificatesServer());

    expect(find.text('Vigente'), findsOneWidget);
    expect(find.text('Anulado'), findsOneWidget);
    expect(find.text('Vencido'), findsOneWidget);
    // Solo la pesa sin certificado vigente avisa que sale «No trazable».
    expect(find.textContaining('Sin certificado vigente'), findsOneWidget);
    expect(find.text('Agregar certificado'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'un certificado nuevo se valida en el teléfono y viaja con sus fechas',
    (tester) async {
      final server = CustomerFixtureServer();
      final session = await open(tester, server);
      await tester.tap(
        find.byKey(const ValueKey('pattern-add-certificate-pattern-fixture')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo certificado'), findsOneWidget);

      // El número ya existe en el patrón (sin distinguir mayúsculas) y el
      // vencimiento queda antes de la calibración.
      await tester.enterText(
        fieldLabeled('Número de certificado'),
        ' cert-2026-001 ',
      );
      await tester.enterText(
        fieldLabeled('Laboratorio'),
        'Laboratorio acreditado',
      );
      await pickDate(tester, 'calibratedOn');
      await pickDate(tester, 'expiresOn', months: -1, day: 15);
      await tester.tap(find.text('Guardar certificado'));
      await tester.pumpAndSettle();
      expect(
        find.text('Este patrón ya tiene un certificado con ese número.'),
        findsOneWidget,
      );
      expect(
        find.text('El vencimiento no puede ser anterior a la calibración.'),
        findsOneWidget,
      );
      bool sent(RequestOptions r) => r.path.contains('ivmet_customer_mutate');
      expect(server.requests.where(sent), isEmpty);

      await tester.enterText(
        fieldLabeled('Número de certificado'),
        'CERT-2026-002',
      );
      await pickDate(tester, 'expiresOn', months: 2, day: 15);
      // Corregida la fecha, su error desaparece sin volver a guardar.
      expect(
        find.text('El vencimiento no puede ser anterior a la calibración.'),
        findsNothing,
      );
      final now = today();
      final expires = DateTime.utc(now.year, now.month + 1, 15);
      expect(find.text(numericDayLabel(expires)), findsOneWidget);
      await tester.tap(find.text('Guardar certificado'));
      await tester.pumpAndSettle();

      final body = object(server.requests.singleWhere(sent).data);
      expect(body['action'], 'certificate.create');
      expect(object(body['payload']), {
        'patternId': 'pattern-fixture',
        'number': 'CERT-2026-002',
        'lab': 'Laboratorio acreditado',
        'calibratedOn': dayKey(now),
        'expiresOn': dayKey(expires),
      });
      // Guardado, vuelve a la lista de patrones.
      expect(find.text('Nuevo certificado'), findsNothing);
      expect(find.text('Nuevo patrón'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('la calibración no puede ser una fecha futura', (tester) async {
    final server = CustomerFixtureServer();
    final session = await open(tester, server);
    await tester.tap(find.text('Agregar certificado'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabeled('Número de certificado'), 'C-1');
    await tester.enterText(fieldLabeled('Laboratorio'), 'Lab');
    await pickDate(tester, 'calibratedOn', months: 1, day: 1);
    await pickDate(tester, 'expiresOn', months: 1, day: 2);
    await tester.tap(find.text('Guardar certificado'));
    await tester.pumpAndSettle();
    expect(
      find.text('La calibración no puede ser una fecha futura.'),
      findsOneWidget,
    );
    expect(
      server.requests.where((r) => r.path.contains('ivmet_customer_mutate')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  test('el servidor explica por qué rechaza un certificado', () {
    expect(
      const MobileFailure('CERTIFICATE_EXISTS').message,
      contains('ya tiene un certificado con ese número'),
    );
    expect(
      const MobileFailure('INVALID_CERTIFICATE_DATES').message,
      contains('el vencimiento no puede ser anterior'),
    );
  });
}

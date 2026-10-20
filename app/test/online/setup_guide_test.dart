import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/setup_guide.dart';

import 'fakes.dart';
import 'finders.dart';
import 'guide_fakes.dart';

void main() {
  Future<void> start(
    WidgetTester tester,
    FixtureServer server, {
    Size size = const Size(430, 932),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Las escenas se repiten en bucle; sin animaciones quedan quietas y la
    // prueba puede esperar a que todo se asiente.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
  }

  Json? remembered(FixtureServer server) {
    final store = server.recovery.store as MemoryDraftStore;
    final key = store.documents.keys
        .where((k) => k.startsWith('guide:v1|'))
        .firstOrNull;
    return key == null ? null : object(jsonDecode(store.documents[key]!));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'el jefe de una empresa nueva ve la guía al entrar y sigue desde Inicio',
    (tester) async {
      final server = GuideServer();
      await start(tester, server);

      // Se abrió sola, con lo que ya existe marcado.
      expect(find.text('Deja IvMET listo para verificar'), findsOneWidget);
      expect(find.text('JEFE DE CALIDAD · 9 PASOS'), findsOneWidget);
      expect(find.text('0 de 9 pasos listos'), findsOneWidget);
      expect(find.text('1 planta · faltan las áreas'), findsOneWidget);
      expect(remembered(server)?['dismissed'], true);

      await tester.tap(find.byKey(const ValueKey('guide-start')));
      await tester.pumpAndSettle();
      expect(find.text('Paso 1 de 9 · Plantas y áreas'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guide-status-plantas')),
        findsOneWidget,
      );
      expect(find.text('Nueva planta'), findsWidgets);

      // Las pruebas y su tolerancia, con los nombres de la app.
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Paso 4 de 9 · Pruebas y periodicidad'), findsOneWidget);
      expect(find.text('Primero, las balanzas'), findsWidgets);
      await next(tester);
      expect(find.text('Paso 5 de 9 · Errores permisibles'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Toca «Activar configuración».'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        remembered(server)?['visited'],
        containsAll(['plantas', 'patrones', 'balanzas', 'pruebas']),
      );

      // «Ir a…» cierra la guía y abre la pestaña del paso.
      await tester.tap(find.byTooltip('Pasos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wizard-step-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('guide-go-plantas')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-go-plantas')));
      await tester.pumpAndSettle();
      expect(find.text('Selecciona una planta'), findsOneWidget);

      // Inicio la ofrece hasta terminarla, y vuelve al primer paso que falta.
      await tester.tap(find.text('Inicio'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-guide')), findsOneWidget);
      expect(
        find.text('0 de 9 pasos · sigue: Plantas y áreas'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('home-guide')));
      await tester.pumpAndSettle();
      expect(find.text('Paso 1 de 9 · Plantas y áreas'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('lo que el servidor confirma se marca solo y se termina', (
    tester,
  ) async {
    final server = GuideServer(
      setup: {
        ...freshSetup,
        'areas': 3,
        'patterns': 2,
        'tracedPatterns': 1,
        'equipment': 5,
        'validated': 5,
        'configured': 2,
        'operators': 2,
        'assigned': 5,
        'verifications': 4,
      },
    );
    await start(tester, server);

    expect(find.text('1 planta · 3 áreas'), findsOneWidget);
    expect(find.text('1 con certificado vigente'), findsOneWidget);
    expect(find.text('2 de 5 configuradas'), findsNWidgets(2));
    expect(find.text('6 de 9 pasos listos'), findsOneWidget);

    // «Continuar» no existe la primera vez: se empieza por el principio.
    expect(find.text('Empezar'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('guide-timeline-resultados')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guide-timeline-resultados')));
    await tester.pumpAndSettle();
    expect(find.text('Paso 9 de 9 · Resultados y alertas'), findsOneWidget);
    expect(find.text('Terminar'), findsOneWidget);
    await next(tester);
    expect(remembered(server)?['finished'], true);
    // Terminada, Inicio ya no la ofrece; queda en Ajustes › Ayuda.
    expect(find.byKey(const ValueKey('home-guide')), findsNothing);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-guide')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('settings-guide')));
    await tester.pumpAndSettle();
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('7 de 9 pasos listos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el operador aprende a verificar, prueba por prueba', (
    tester,
  ) async {
    final server = GuideServer(
      role: 'cliente_operador',
      selfService: false,
      setup: {
        ...freshSetup,
        'patterns': 1,
        'tracedPatterns': 1,
        'equipment': 2,
        'validated': 2,
        'configured': 2,
        'assigned': 2,
        'operators': null,
      },
    );
    await start(tester, server);

    expect(find.text('Así verificas con IvMET'), findsOneWidget);
    expect(find.text('OPERADOR · 8 PASOS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-start')));
    await tester.pumpAndSettle();
    expect(find.text('Listo · 2 balanzas asignadas'), findsOneWidget);

    // Se desliza de un paso a otro.
    await tester.fling(
      find.byKey(const ValueKey('guide-pages')),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Paso 2 de 8 · Tu agenda'), findsOneWidget);
    await next(tester);
    await next(tester);
    expect(find.text('Paso 4 de 8 · Excentricidad'), findsOneWidget);
    expect(
      find.text('La posición 1 es la referencia central.'),
      findsOneWidget,
    );
    // El operador no tiene pasos de configuración.
    expect(find.text('Errores permisibles'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'sin el resumen del servidor no se abre sola, pero está en Ajustes',
    (tester) async {
      final server = GuideServer(setup: null);
      await start(tester, server);

      expect(find.text('Deja IvMET listo para verificar'), findsNothing);
      expect(find.text('HOY'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-guide')), findsNothing);
      expect(remembered(server)?['dismissed'], isNot(true));

      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-guide')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('settings-guide')));
      await tester.pumpAndSettle();
      expect(find.text('Deja IvMET listo para verificar'), findsOneWidget);
      // Sin conteos, cada paso se marca al leerlo: los dos que se vieron.
      expect(find.text('0 de 9 pasos listos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-start')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-status-plantas')), findsNothing);
      await next(tester);
      await tester.tap(find.byTooltip('Pasos'));
      await tester.pumpAndSettle();
      expect(find.text('2 de 9 pasos completos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (audience, server) in [
    (GuideAudience.selfServiceQuality, () => GuideServer()),
    (GuideAudience.managedQuality, () => GuideServer(selfService: false)),
    (GuideAudience.operator, () => GuideServer(role: 'cliente_operador')),
  ]) {
    testWidgets(
      'cada paso de ${audience.name} cabe en un teléfono chico con texto grande',
      (tester) async {
        await start(tester, server(), size: const Size(360, 640));
        await tester.tap(find.byKey(const ValueKey('guide-start')));
        await tester.pumpAndSettle();
        final steps = guideSteps(audience);
        for (final (index, step) in steps.indexed) {
          expect(
            find.text('Paso ${index + 1} de ${steps.length} · ${step.title}'),
            findsOneWidget,
          );
          // Se recorre el paso entero: un desborde lanza una excepción.
          await tester.drag(
            find.byKey(ValueKey('guide-step-${step.id}')),
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: step.id);
          if (index < steps.length - 1) await next(tester);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

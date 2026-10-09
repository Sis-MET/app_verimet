import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/user_manual.dart';
import 'package:ivmet/features/online/user_manual_content.dart';

void main() {
  // El manual es un documento controlado: al subir la versión menor de la app
  // hay que revisarlo y actualizar «Aplica a».
  test('«Aplica a» coincide con la versión menor de pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(
      ivmetUserManual.control.appliesTo,
      '${version.group(1)}.${version.group(2)}.x',
    );
  });

  test('cada sección tiene un id único, contenido y está en su grupo', () {
    final ids = ivmetUserManual.sections.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final section in ivmetUserManual.sections) {
      expect(section.blocks, isNotEmpty, reason: section.id);
    }
    expect(
      ManualGroup.values.every(
        (g) => ivmetUserManual.sections.any((s) => s.group == g),
      ),
      isTrue,
    );
  });

  test('la búsqueda ignora mayúsculas y acentos', () {
    final found = ivmetUserManual.sections
        .where((s) => s.matches('MEDICION'))
        .map((s) => s.id);
    expect(found, contains('captura'));
    expect(ivmetUserManual.sections.where((s) => s.matches('xyzzy')), isEmpty);
  });

  testWidgets(
    'el manual se busca, se abre por sección y avanza a la siguiente',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ManualScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Manual de uso de IvMET'), findsOneWidget);
      expect(find.text('Pendiente de aprobación'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('manual-search')),
        'agenda',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('manual-control')), findsNothing);
      expect(
        find.byKey(const ValueKey('manual-section-agenda')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('manual-section-plan')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('manual-section-agenda')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Programada · Próxima'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('manual-next')));
      await tester.pumpAndSettle();
      expect(find.text('Historial, resultado y alertas'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'la copia controlada en PDF se genera con todas las secciones',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await buildUserManualPdf(ivmetUserManual);
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      final pages = RegExp(
        r'/Type\s*/Page[^s]',
      ).allMatches(latin1.decode(bytes)).length;
      expect(pages, greaterThan(ivmetUserManual.sections.length));
    },
  );
}

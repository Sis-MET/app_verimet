import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/draft_screen.dart';
import 'package:ivmet/features/online/mobile_session.dart';

import 'fakes.dart';

/// La captura se volvia lenta al desplazarse: cada pixel lanzaba una escritura
/// completa del borrador en disco y, al confirmarse, un redibujado de todo el
/// paso. Esta prueba fija el comportamiento: desplazar no escribe hasta que el
/// operario se detiene, y entonces escribe una sola vez.
void main() {
  testWidgets('desplazar la captura no escribe en disco por cada pixel', (
    tester,
  ) async {
    final server = FixtureServer();
    final store = server.recovery.store as MemoryDraftStore;
    final session = MobileSession(server.api, recovery: server.recovery);
    await tester.runAsync(() => session.login('operador', 'fixture-password'));
    tester.view.physicalSize = const Size(430, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DraftScreen(session: session, bundle: fixtureWizardBundle),
      ),
    );
    await tester.pumpAndSettle();
    // Deja pasar el primer envio al servidor, que escribe por su cuenta.
    await tester.pump(const Duration(seconds: 2));
    final opened = store.writes;

    final content = find.byKey(const ValueKey('draft-content'));
    final gesture = await tester.startGesture(tester.getCenter(content));
    for (var step = 0; step < 40; step++) {
      await gesture.moveBy(const Offset(0, -6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final whileScrolling = store.writes - opened;
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final afterStop = store.writes - opened;

    expect(whileScrolling, 0, reason: 'escrituras durante el desplazamiento');
    expect(afterStop, 1, reason: 'la posicion se guarda una vez al detenerse');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

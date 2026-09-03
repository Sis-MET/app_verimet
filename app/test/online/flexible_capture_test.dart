import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/draft_controller.dart';
import 'package:ivmet/features/online/draft_screen.dart';
import 'package:ivmet/features/online/flexible_trial_fields.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/trial_capture.dart';
import 'package:ivmet/shared/theme/app_theme.dart';

import 'fakes.dart';

Json flexibleBundle() => {
  ...fixtureNormativeBundle,
  'plan': {
    ...object(fixtureNormativeBundle['plan']),
    'captureVersion': 2,
    'captureEngineVersion': 'ivmet-internal-2.0.0',
    'tests': [
      for (final type in ['eccentricity', 'repeatability', 'linearity'])
        {
          'id': type,
          'type': type,
          'unit': 'kg',
          'points': [
            for (var i = 1; i <= 5; i++)
              {
                'id': '$type-$i',
                'order': i,
                'group': 1,
                'load': type == 'linearity' ? '${i * 10}' : '30',
                'tolerance': '0.5',
              },
          ],
        },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureServer server;
  late MobileSession session;
  final controllers = <DraftController>[];
  setUp(() async {
    server = FixtureServer()..bundle = flexibleBundle();
    session = MobileSession(server.api, recovery: server.recovery);
    await session.login('operador', 'fixture-password');
  });
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    session.dispose();
    server.api.dispose();
  });
  DraftController create({Json? recovered, Json? draft}) {
    final c = DraftController(
      session: session,
      bundle: server.bundle,
      recovered: recovered,
      draft: draft,
    );
    controllers.add(c);
    return c;
  }

  test(
    'suggestions never become measurements; resize and restart preserve exact input',
    () async {
      final c = create();
      final repeat = c.testInput('repeatability');
      final plan = c.tests.firstWhere((t) => t['type'] == 'repeatability');
      expect(
        activeReadings(
          repeat,
        ).every((r) => r['load'] == '' && r['indication'] == ''),
        true,
      );
      expect(activeReadings(repeat).first['suggestedLoad'], '30');
      trialSetup(repeat)['groupCount'] = 3;
      trialSetup(repeat)['measurementCount'] = 10;
      resizeTrial(repeat, plan);
      final last = activeReadings(repeat).last;
      last['indication'] = '45,123456789';
      last['zero'] = '-';
      setGroupLoad(repeat, 3, '45,');
      expect(last['indication'], '45,123456789');
      trialSetup(repeat)['groupCount'] = 1;
      trialSetup(repeat)['measurementCount'] = 3;
      resizeTrial(repeat, plan);
      expect(activeReadings(repeat), hasLength(3));
      expect(objects(repeat['retainedReadings']), hasLength(27));
      expect(
        c.draftIssue,
        isNull,
        reason: 'inactive partial text does not block a valid draft',
      );
      expect(await c.sync(), true);
      await c.goTo(2);
      c.dispose();
      controllers.remove(c);
      final recovered = create(
        recovered: await server.recovery.active(session.recoveryOwner),
      );
      final restored = recovered.testInput('repeatability');
      expect(recovered.step, 2);
      trialSetup(restored)['groupCount'] = 3;
      trialSetup(restored)['measurementCount'] = 10;
      resizeTrial(restored, plan);
      expect(activeReadings(restored).last, last);
      expect(recovered.draftIssue, isNotNull);
      setGroupLoad(restored, 3, '44,999999999');
      expect(activeReadings(restored).last['indication'], '45,123456789');
      final payload = objects(
        recovered.payload['tests'],
      ).firstWhere((t) => t['id'] == 'repeatability');
      expect(objects(payload['readings']).last['load'], '44.999999999');
      expect(
        objects(payload['readings']).last.containsKey('suggestedLoad'),
        false,
      );
    },
  );

  test(
    'server drafts restore active, omitted and retained data without regenerating point IDs',
    () {
      final c = create();
      final lin = c.testInput('linearity');
      activeReadings(lin)[4]['load'] = '49,';
      trialSetup(lin)['pointCount'] = 2;
      resizeTrial(lin, c.tests.last);
      lin['omitted'] = true;
      lin['reason'] = 'Sin carga';
      activeReadings(lin)[0]['indication'] = '12,';
      final saved = {
        'id': 'draft',
        'request_uuid': 'request',
        'version': '3',
        'payload': c.payload,
      };
      final resumed = create(draft: saved);
      expect(resumed.flexible, true);
      expect(resumed.payload, c.payload);
      expect(
        activeReadings(resumed.testInput('linearity')).first['indication'],
        '12,',
      );
      final oldDraft = {
        'id': 'legacy',
        'payload': {'tests': []},
      };
      expect(
        create(draft: oldDraft).flexible,
        false,
        reason: 'existing fixed captures retain their original protocol',
      );
    },
  );

  test(
    'substitution uses exact decimals and refreshes dependants without replacing indications',
    () {
      final c = create();
      final lin = c.testInput('linearity');
      final rows = activeReadings(lin);
      rows[0].addAll({'load': '10.000000001', 'indication': '10.100000001'});
      rows[1].addAll({'load': '20.000000001', 'indication': '20.2'});
      rows[2]['substitution'] = {
        'basePointId': rows[1]['pointId'],
        'referencePointId': rows[0]['pointId'],
        'indication': '15.100000001',
      };
      rows[2]['indication'] = '35,2';
      refreshSubstitutions(lin);
      expect(rows[2]['load'], '35.000000002');
      rows[0]['indication'] = '10.200000001';
      refreshSubstitutions(lin);
      expect(rows[2]['load'], '34.900000002');
      expect(rows[2]['indication'], '35,2');
      expect(indicationError('35.000000003', '35.000000002'), '0.000000001');
    },
  );

  testWidgets(
    'all trials accept custom loads and suggestions preserve measured indications at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = create();
      for (final plan in c.tests) {
        final input = c.testInput(plan['id'] as String);
        final id = activeReadings(input).first['pointId'];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: c,
                builder: (context, _) => Form(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: FlexibleTrialFields(
                        key: ValueKey(plan['id']),
                        capture: c,
                        plan: plan,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final load = find.byKey(ValueKey('$id:load'));
        await tester.ensureVisible(load);
        await tester.enterText(load, '17,25');
        await tester.pump();
        final indication = find.byKey(ValueKey('$id:indication'));
        await tester.ensureVisible(indication);
        await tester.enterText(indication, '17,251');
        await tester.pump();
        final use = find.text('Usar sugerencia').first;
        await tester.ensureVisible(use);
        await tester.tap(use);
        await tester.pump();
        expect(
          activeReadings(input).first['load'],
          activeReadings(input).first['suggestedLoad'],
        );
        expect(activeReadings(input).first['indication'], '17,251');
        await tester.enterText(load, '17,25');
        await tester.pump();
        expect(activeReadings(input).first['load'], '17,25');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      c.dispose();
      controllers.remove(c);
    },
  );

  testWidgets(
    'restart restores a partial substitution dialog and wizard step, then shows actual-load summary',
    (tester) async {
      final c = create();
      for (final plan in c.tests) {
        for (final r in activeReadings(c.testInput(plan['id'] as String))) {
          r['load'] = r['suggestedLoad'];
          r['indication'] = r['suggestedLoad'];
        }
      }
      final lin = c.testInput('linearity');
      trialSetup(lin)['substitutionMethod'] = 'method_1';
      lin['substitutionDraft'] = {
        'referencePointId': 'linearity-1',
        'basePointId': 'linearity-2',
        'indication': '15,',
      };
      await tester.runAsync(() => c.goTo(3));
      c.dispose();
      controllers.remove(c);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DraftScreen(session: session, bundle: server.bundle),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agregar carga por sustitución'), findsOneWidget);
      expect(find.text('15,'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('substitution-indication')),
        '15,123456789',
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DraftScreen(session: session, bundle: server.bundle),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('15,123456789'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Agregar'));
      await tester.pumpAndSettle();
      expect(find.text('Paso 4 de 5'), findsOneWidget);
      final local = await tester.runAsync(
        () => server.recovery.active(session.recoveryOwner),
      );
      final added = objects(
        objects(object(local!['raw'])['tests']).last['readings'],
      ).last;
      expect(added['load'], '35.123456789');
      final id = added['pointId'];
      final indication = find.byKey(ValueKey('$id:indication'));
      await tester.ensureVisible(indication);
      await tester.enterText(indication, '35,123456789');
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Paso 5 de 5'), findsOneWidget);
      expect(find.text('35.123456789'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

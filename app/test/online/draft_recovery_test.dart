import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/storage/draft_recovery_store.dart';
import 'package:ivmet/features/online/draft_controller.dart';
import 'package:ivmet/features/online/draft_recovery.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'fakes.dart';

class InterruptedServer extends FixtureServer {
  bool loseSaveResponse = false;
  bool loseFinalizationResponse = false;
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  @override
  Future<(int, Json)> handle(RequestOptions request) async {
    if (request.path.contains('ivmet_mobile_save_draft') && saveGate != null) {
      final gate = saveGate!;
      saveGate = null;
      saveStarted?.complete();
      await gate.future;
    }
    final response = await super.handle(request);
    if (request.path.contains('ivmet_mobile_save_draft') && loseSaveResponse) {
      loseSaveResponse = false;
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      );
    }
    if (request.path.contains('ivmet_mobile_finalize_draft') &&
        loseFinalizationResponse) {
      loseFinalizationResponse = false;
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InterruptedServer server;
  late MobileSession session;
  final controllers = <DraftController>[];
  setUp(() async {
    server = InterruptedServer();
    session = MobileSession(server.api, recovery: server.recovery);
    await session.login('operador', 'fixture-password');
  });
  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    session.dispose();
    server.api.dispose();
  });
  DraftController create({Json? recovered}) {
    final controller = DraftController(
      session: session,
      bundle: fixtureNormativeBundle,
      recovered: recovered,
    );
    controllers.add(controller);
    return controller;
  }

  void edit(DraftController controller, String value) {
    final readings =
        controller.testInput('trial-normative-fixture')['readings'] as List;
    (readings.single as Json)['indication'] = value;
    controller.changed();
  }

  List<Json> saves() => server.requests
      .where((r) => r.path.contains('ivmet_mobile_save_draft'))
      .map((r) => object(r.data))
      .toList();

  test(
    'raw partial input, omission, environment, certificates and step survive recreation',
    () async {
      final first = create();
      first.raw['temperature'] = '-';
      first.raw['humidity'] = '50,';
      first.raw['observations'] = 'Observación sin terminar  ';
      first.raw['certificates'] = ['certificate-a'];
      edit(first, '10,');
      first.testInput('trial-normative-fixture')['omitted'] = true;
      first.testInput('trial-normative-fixture')['reason'] = 'Pendiente  ';
      await first.goTo(3);
      first.setOffset(140);
      // La posicion se guarda cuando el operario deja de desplazar.
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final saved = await server.recovery.active(session.recoveryOwner);
      final restored = create(recovered: saved);
      expect(restored.raw, first.raw);
      expect(restored.step, 3);
      expect(restored.offset, 140);
      expect(restored.draftIssue, isNotNull);
      expect(await restored.sync(), false);
      expect(saves(), isEmpty);
      // Un-omitting recovers readings that were hidden, including incomplete text.
      restored.testInput('trial-normative-fixture')['omitted'] = false;
      expect(
        objects(
          restored.testInput('trial-normative-fixture')['readings'],
        ).single['indication'],
        '10,',
      );
    },
  );

  test('a scroll burst writes the position once, after it stops', () async {
    final controller = create();
    await controller.persist();
    final store = server.recovery.store as MemoryDraftStore;
    final before = store.writes;
    for (var pixel = 1; pixel <= 120; pixel++) {
      controller.setOffset(pixel.toDouble());
    }
    expect(store.writes, before, reason: 'no write per scrolled pixel');
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(store.writes, before + 1);
    final saved = await server.recovery.active(session.recoveryOwner);
    expect(create(recovered: saved).offset, 120);
  });

  test('a burst of keys queues one write, with the newest input', () async {
    final controller = create();
    await controller.persist();
    final store = server.recovery.store as MemoryDraftStore;
    final before = store.writes;
    for (final text in ['1', '10', '10,', '10,1', '10,12']) {
      edit(controller, text);
    }
    await controller.persist();
    expect(store.writes - before, 1);
    expect(controller.localSaved, true);
    final saved = await server.recovery.active(session.recoveryOwner);
    expect(
      objects(
        create(
          recovered: saved,
        ).testInput('trial-normative-fixture')['readings'],
      ).single['indication'],
      '10,12',
    );
  });

  test(
    'writes during a slow save are sent afterward with the acknowledged version',
    () async {
      final controller = create();
      edit(controller, '10.1');
      final gate = server.saveGate = Completer<void>();
      server.saveStarted = Completer<void>();
      final saving = controller.sync();
      await server.saveStarted!.future;
      edit(controller, '10.123456789');
      gate.complete();
      expect(await saving, true);
      expect(saves(), hasLength(2));
      expect(saves().last['expected_version'], '1');
      expect(controller.version, '2');
      expect(controller.dirty, false);
      expect(
        objects(
          objects(saves().last['content']['tests']).single['readings'],
        ).single['indication'],
        '10.123456789',
      );
    },
  );

  test(
    'restart replays an ambiguous save before new edits without duplicating the draft',
    () async {
      server.loseSaveResponse = true;
      final first = create();
      edit(first, '10,1');
      expect(await first.sync(), false);
      final original = saves().single;
      edit(first, '10,2');
      await first.persist();
      first.dispose();
      controllers.remove(first);
      final restored = create(
        recovered: await server.recovery.active(session.recoveryOwner),
      );
      await session.refresh();
      expect(await restored.sync(), true);
      expect(saves()[1], original);
      expect(saves().last['expected_version'], '1');
      expect(server.savedDrafts, hasLength(1));
      expect(restored.version, '2');
      expect(restored.dirty, false);
    },
  );

  test(
    'conflicts preserve local input and stop automatic overwrites',
    () async {
      final controller = create();
      edit(controller, '10.1');
      await controller.sync();
      server.savedDrafts[controller.requestId]!['version'] = '8';
      edit(controller, '10.2');
      expect(await controller.sync(), false);
      expect(controller.conflict, true);
      final restored = create(
        recovered: await server.recovery.active(session.recoveryOwner),
      );
      expect(restored.raw, controller.raw);
      expect(await restored.sync(), false);
      expect(server.savedDrafts[controller.requestId]!['version'], '8');
      expect(saves(), hasLength(2));
    },
  );

  test(
    'failed disk writes block leaving and never erase the last durable state',
    () async {
      final controller = create();
      edit(controller, '10.1');
      await controller.persist();
      final store = server.recovery.store as MemoryDraftStore;
      store.failWrites = true;
      edit(controller, '10.2');
      expect(await controller.pause(), false);
      expect(controller.localSaved, false);
      final stored = await server.recovery.active(session.recoveryOwner);
      expect(stored, isNotNull);
      expect(
        objects(
          objects(stored!['raw']['tests']).single['readings'],
        ).single['indication'],
        '10.1',
      );
      store.failWrites = false;
      expect(await controller.pause(), true);
      expect(await server.recovery.active(session.recoveryOwner), isNull);
      expect((await server.recovery.list(session.recoveryOwner)), hasLength(1));
    },
  );

  test(
    'finalization UUID survives a lost response; cleanup follows confirmation',
    () async {
      final first = create();
      edit(first, '10.1');
      await first.goTo(4);
      server.loseFinalizationResponse = true;
      expect(await first.finalize(), isNull);
      final pending = await server.recovery.active(session.recoveryOwner);
      expect(pending!['pendingFinalize'], isNotNull);
      first.dispose();
      controllers.remove(first);
      final restored = create(recovered: pending);
      expect(restored.locked, true);
      await session.refresh();
      expect(await restored.finalize(), isNotNull);
      final requests = server.requests
          .where((r) => r.path.contains('ivmet_mobile_finalize_draft'))
          .toList();
      expect(requests, hasLength(2));
      expect(requests.first.data, requests.last.data);
      expect(await server.recovery.active(session.recoveryOwner), isNull);
      expect(await server.recovery.list(session.recoveryOwner), isEmpty);
    },
  );

  test(
    'recovery is isolated by user, tenant and server; pausing keeps other drafts',
    () async {
      final first = create();
      final second = create();
      await first.persist();
      await second.persist();
      await first.pause();
      expect(
        (await server.recovery.active(session.recoveryOwner))!['requestId'],
        second.requestId,
      );
      expect(await server.recovery.list(session.recoveryOwner), hasLength(2));
      final owner = session.recoveryOwner;
      session.user = {...fixtureUser, 'id': 'other-user'};
      expect(await server.recovery.active(session.recoveryOwner), isNull);
      session.user = {...fixtureUser, 'clientId': 'other-client'};
      expect(await server.recovery.list(session.recoveryOwner), isEmpty);
      expect(await server.recovery.list(owner), hasLength(2));
    },
  );

  test(
    'a response from a closing screen cannot overwrite a reopened capture',
    () async {
      final first = create();
      edit(first, '10.1');
      final gate = server.saveGate = Completer<void>();
      server.saveStarted = Completer<void>();
      final saving = first.sync();
      await server.saveStarted!.future;
      expect(await first.pause(), true);
      final restored = create(
        recovered: (await server.recovery.list(session.recoveryOwner)).single,
      );
      edit(restored, '10.2');
      await restored.persist();
      gate.complete();
      await saving;
      final saved = (await server.recovery.active(session.recoveryOwner))!;
      expect(
        objects(
          objects(saved['raw']['tests']).single['readings'],
        ).single['indication'],
        '10.2',
      );
      expect(await restored.sync(), true);
      expect(restored.version, '2');
      expect(restored.dirty, false);
    },
  );

  test(
    'SQLite recovery is on disk and survives a fresh database connection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ivmet-recovery-test-',
      );
      final file = File('${directory.path}/recovery.sqlite');
      final first = SqliteDraftRecoveryStore(NativeDatabase(file));
      final repository = DraftRecovery(first);
      await repository.save('account', {
        'requestId': 'draft-a',
        'raw': {'temperature': '23,'},
        'step': 2,
      }, active: true);
      expect(
        (await first.customSelect('PRAGMA synchronous').getSingle())
            .data
            .values
            .single,
        2,
      );
      await first.close();
      final second = SqliteDraftRecoveryStore(NativeDatabase(file));
      try {
        final restored = await DraftRecovery(second).active('account');
        expect(restored!['step'], 2);
        expect(jsonEncode(restored['raw']), '{"temperature":"23,"}');
        expect(await DraftRecovery(second).active('another-account'), isNull);
      } finally {
        await second.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

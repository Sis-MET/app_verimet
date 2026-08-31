import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'package:ivmet/features/online/draft_screen.dart';
import 'fakes.dart';

void main() {
  test('la configuración rechaza claves privadas y URLs inseguras', () {
    expect(
      const MobileConfiguration(
        'http://example.com',
        'sb_publishable_public',
      ).error,
      isNotNull,
    );
    expect(
      const MobileConfiguration(
        'https://example.com',
        'sb_secret_private',
      ).error,
      isNotNull,
    );
    final claims = base64Url.encode(
      utf8.encode(jsonEncode({'role': 'service_role'})),
    );
    expect(
      MobileConfiguration('https://example.com', 'x.$claims.x').error,
      isNotNull,
    );
    expect(fixtureConfiguration.error, isNull);
  });
  test('las indicaciones se conservan como cadenas exactas', () {
    expect(normalizedDecimal('9999999999,123456789'), '9999999999.123456789');
    expect(decimalError('9999999999.123456789'), isNull);
    expect(decimalError('0.0000000001'), isNotNull);
    expect(decimalError('1,000.01'), isNotNull);
    expect(decimalError('NaN'), isNotNull);
    expect(decimalError('1e3'), isNotNull);
    expect(decimalError('101', environment: true, humidity: true), isNotNull);
  });
  test(
    'dos respuestas 401 rotan una sola vez y reutilizan el nuevo token',
    () async {
      final storage = MemoryTokens()
        ..access = 'old-access'
        ..refresh = 'old-refresh';
      int refreshes = 0;
      final released = Completer<void>();
      final api = MobileApi(
        fixtureConfiguration,
        storage,
        dio: Dio()
          ..httpClientAdapter = FakeAdapter((r) async {
            if (r.path.contains('/token?')) {
              refreshes++;
              await released.future;
              return (
                200,
                {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
              );
            }
            if (r.headers['Authorization'] == 'Bearer old-access') {
              return (401, <String, dynamic>{});
            }
            return (200, {'allowed': true});
          }),
      );
      await api.restore();
      final requests = [api.read('session'), api.read('session')];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      released.complete();
      await Future.wait(requests);
      expect(refreshes, 1);
      expect(storage.refresh, 'new-refresh');
      api.dispose();
    },
  );
  test('un refresh tardío no resucita una sesión cerrada', () async {
    final storage = MemoryTokens()
      ..access = 'old-access'
      ..refresh = 'old-refresh';
    final entered = Completer<void>(), released = Completer<void>();
    final api = MobileApi(
      fixtureConfiguration,
      storage,
      dio: Dio()
        ..httpClientAdapter = FakeAdapter((r) async {
          if (r.path.contains('/token?')) {
            entered.complete();
            await released.future;
            return (200, {'access_token': 'new', 'refresh_token': 'new'});
          }
          return (401, <String, dynamic>{});
        }),
    );
    await api.restore();
    final expectation = expectLater(
      api.read('session'),
      throwsA(isA<MobileFailure>()),
    );
    await entered.future;
    await api.clear();
    released.complete();
    await expectation;
    expect(storage.access, isNull);
    expect(api.hasSession, false);
    api.dispose();
  });
  test(
    'la sesión valida contraseña, licencia, revocación y salida offline',
    () async {
      final server = FixtureServer();
      final session = MobileSession(server.api);
      await session.start();
      expect(session.stage, SessionStage.login);
      server.user['mustChangePassword'] = true;
      await session.login('operador', 'fixture-password');
      expect(session.stage, SessionStage.password);
      expect(server.bootstrapCalls, 0);
      await session.password('fixture-new-password');
      expect(session.stage, SessionStage.ready);
      server.allowed = false;
      await session.refresh();
      expect(session.stage, SessionStage.blocked);
      expect(session.bootstrap, isEmpty);
      server.online = false;
      await session.logout();
      expect(session.stage, SessionStage.login);
      expect(server.api.hasSession, false);
      session.dispose();
      server.api.dispose();
    },
  );
}

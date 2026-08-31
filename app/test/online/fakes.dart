import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:ivmet/core/storage/token_storage.dart';
import 'package:ivmet/features/online/mobile_api.dart';

class MemoryTokens implements TokenStorage {
  String? access;
  String? refresh;
  @override
  Future<String?> readAccessToken() async => access;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handle);
  final FutureOr<(int, Json)> Function(RequestOptions request) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await handle(options);
    return ResponseBody.fromString(
      jsonEncode(response.$2),
      response.$1,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const fixtureConfiguration = MobileConfiguration(
  'https://fixture.invalid',
  'sb_publishable_fixture_only_no_network',
);
const fixtureUser = {
  'id': 'user-fixture',
  'name': 'Operador de prueba',
  'username': 'operador',
  'role': 'cliente_operador',
  'clientId': 'client-fixture',
  'mustChangePassword': false,
};
const fixtureBootstrap = {
  'client': {'id': 'client-fixture', 'name': 'Cliente aislado', 'code': '0001'},
  'plants': [
    {'id': 'plant-fixture', 'name': 'Planta uno', 'code': '0001-01'},
  ],
  'areas': [],
  'equipmentCount': 1,
  'openAlerts': 0,
};
const fixturePlan = {
  'id': 'version-fixture',
  'name': 'Plan de prueba',
  'version': 1,
  'state': 'PUBLISHED',
  'finalizationEnabled': false,
  'tests': [
    {
      'id': 'trial-fixture',
      'type': 'linearity',
      'unit': 'kg',
      'frequencyDays': 30,
      'points': [
        {
          'id': 'point-fixture',
          'order': 1,
          'label': 'Carga central',
          'load': '0.123456789',
          'tolerance': '0.000000001',
        },
      ],
    },
  ],
};
const fixtureBundle = {
  'equipment': {'id': 'equipment-fixture', 'cod_metrica': '0001-01-001'},
  'plan': fixturePlan,
  'ranges': [],
  'patterns': [],
};
const fixtureNormativeBundle = {
  'equipment': {'id': 'equipment-fixture', 'cod_metrica': '0001-01-001'},
  'plan': {
    'id': 'version-normative-fixture',
    'name': 'Control interno de prueba',
    'version': 1,
    'state': 'PUBLISHED',
    'procedure': 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
    'engineVersion': 'ivmet-internal-1.0.0',
    'claimScope': 'INTERNAL_CHECK_ONLY',
    'notice':
        'Comprobación interna. No constituye calibración acreditada ni verificación legal.',
    'finalizationEnabled': true,
    'tests': [
      {
        'id': 'trial-normative-fixture',
        'type': 'linearity',
        'unit': 'kg',
        'frequencyDays': 30,
        'points': [
          {
            'id': 'point-normative-fixture',
            'order': 1,
            'label': 'Carga central',
            'load': '10',
            'tolerance': '0.5',
          },
        ],
      },
    ],
  },
  'ranges': [],
  'patterns': [],
};

class FixtureServer {
  Json user = {...fixtureUser};
  bool allowed = true;
  bool online = true;
  int bootstrapCalls = 0;
  final List<RequestOptions> requests = [];
  late final api = MobileApi(
    fixtureConfiguration,
    MemoryTokens(),
    dio: Dio()..httpClientAdapter = FakeAdapter(handle),
  );
  FutureOr<(int, Json)> handle(RequestOptions request) {
    requests.add(request);
    if (!online) {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    final body = request.data is Map
        ? object(request.data)
        : <String, dynamic>{};
    if (request.path.contains('ivmet-login')) {
      if (body['username'] != 'operador' ||
          body['password'] != 'fixture-password') {
        return (401, {'error': 'INVALID_CREDENTIALS'});
      }
      return (
        200,
        {'accessToken': 'fixture-access', 'refreshToken': 'fixture-refresh'},
      );
    }
    if (request.path.contains('ivmet-change-password')) {
      user['mustChangePassword'] = false;
      return (200, {'changed': true});
    }
    if (request.path.contains('logout')) return (200, <String, dynamic>{});
    if (request.path.contains('preview_ivmet_alert_share')) {
      return (
        200,
        {
          'snapshot': {
            'verificacion': {'id': 'verification-fixture'},
            'lecturas': ['0.123456789'],
          },
          'snapshotHash': 'fixture-hash',
          'alertVersion': '7',
          'consentVersion': 'case-sharing-v1',
          'notice': 'Solo se enviará este expediente.',
        },
      );
    }
    if (request.path.contains('confirm_ivmet_alert_share')) {
      return (200, {'id': 'case-fixture', 'codigo': 'CASO-TEST'});
    }
    if (request.path.contains('ivmet_mobile_save_draft')) {
      return (
        200,
        {
          'id': 'draft-fixture',
          'requestId': body['request_id'],
          'version': '1',
          'savedAt': '2026-08-28T12:00:00Z',
        },
      );
    }
    if (request.path.contains('ivmet_mobile_finalize_draft')) {
      return (
        200,
        {
          'id': 'verification-finalized-fixture',
          'draftId': body['draft_id'],
          'version': '2',
          'verdict': 'pass',
          'traceability': 'non_traceable',
          'scope': 'complete',
          'alertCreated': true,
          'idempotent': false,
        },
      );
    }
    switch (body['section']) {
      case 'session':
        return (
          200,
          {
            'contractVersion': 1,
            'user': user,
            'access': {
              'allowed': allowed && user['mustChangePassword'] != true,
              'planName': 'Licencia de prueba',
            },
          },
        );
      case 'bootstrap':
        bootstrapCalls++;
        return (200, fixtureBootstrap);
      case 'instruments':
        return (
          200,
          {
            'total': 1,
            'items': [
              {
                'id': 'equipment-fixture',
                'cod_metrica': '0001-01-001',
                'planta': 'Planta uno',
                'area': 'Sin área',
              },
            ],
          },
        );
      case 'equipment':
        return (200, fixtureBundle);
      case 'drafts':
      case 'history':
        return (200, {'total': 0, 'items': []});
      default:
        return (400, {'message': 'UNEXPECTED_FIXTURE_REQUEST'});
    }
  }
}

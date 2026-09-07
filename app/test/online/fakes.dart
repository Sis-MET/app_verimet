import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:ivmet/core/storage/token_storage.dart';
import 'package:ivmet/core/storage/draft_recovery_store.dart';
import 'package:ivmet/features/online/draft_recovery.dart';
import 'package:ivmet/features/online/mobile_api.dart';

class MemoryDraftStore implements DraftRecoveryStore {
  final documents = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String owner) async => documents[owner];
  @override
  Future<void> write(String owner, String document) async {
    if (failWrites) throw StateError('Disk full');
    documents[owner] = document;
  }

  @override
  Future<void> close() async {}
}

class MemoryTokens implements TokenStorage {
  String? access;
  String? refresh;
  String? owner;
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
  Future<String?> readRecoveryOwner() async => owner;

  @override
  Future<void> saveRecoveryOwner(String value) async => owner = value;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    owner = null;
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
    {
      'id': 'plant-fixture',
      'name': 'Planta uno',
      'code': '0001-01',
      'equipmentCount': 1,
    },
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
  'equipment': {
    'id': 'equipment-fixture',
    'cod_metrica': '0001-01-001',
    'cod_interno': 'BAL-014',
    'marca': 'Marca',
    'modelo': 'Modelo',
    'serie': 'SERIE-1',
    'ubicacion': 'Producción',
  },
  'plan': fixturePlan,
  'ranges': [],
  'patterns': [],
};
const fixtureNormativeBundle = {
  'equipment': {
    'id': 'equipment-fixture',
    'cod_metrica': '0001-01-001',
    'cod_interno': 'BAL-014',
  },
  'plan': {
    'id': 'version-normative-fixture',
    'name': 'Control interno de prueba',
    'version': 1,
    'state': 'PUBLISHED',
    'procedure': 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
    'engineVersion': 'ivmet-internal-1.0.0',
    'claimScope': 'INTERNAL_CHECK_ONLY',
    'notice':
        'Verificación intermedia. No constituye calibración acreditada ni verificación legal.',
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

final fixtureWizardBundle = {
  ...fixtureBundle,
  'plan': {
    ...fixturePlan,
    'finalizationEnabled': true,
    'tests': [
      for (final type in ['linearity', 'repeatability', 'eccentricity'])
        {
          'id': 'test-$type',
          'type': type,
          'unit': 'kg',
          'frequencyDays': 30,
          'points': [
            {
              'id': 'point-$type',
              'order': 1,
              'label': 'Lectura de prueba',
              'load': '10',
              'tolerance': '0.5',
            },
          ],
        },
    ],
  },
  'patterns': [
    {
      'id': 'pattern-1',
      'code': 'JP-001',
      'description': 'Juego de pesas patrón',
      'certificates': [
        {
          'id': 'cert-1',
          'number': 'CERT-2026',
          'laboratory': 'Laboratorio',
          'expiresOn': '2027-09-01',
          'expired': false,
        },
      ],
    },
  ],
};

final fixtureVerificationData = <String, dynamic>{
  'verification': {
    'id': 'verification-fixture',
    'realizado_at': '2026-09-04T14:30:00Z',
    'recibido_at': '2026-09-04T14:31:00Z',
    'alcance': 'complete',
    'veredicto_global': 'pass',
    'trazabilidad': 'traceable',
    'temperatura_c': '21.500',
    'humedad_relativa_pct': '48.000',
    'observaciones': 'La balanza se encontraba limpia, nivelada y estable.',
    'estado': 'ACTIVE',
    'alcance_declaracion': 'INTERNAL_CHECK_ONLY',
    'motor_version': 'ivmet-internal-2.0.0',
    'regla_decision_resumen': 'direct',
    'app_version': '1.0.0',
    'equipo_snapshot': {
      'equipment': {
        'cod_metrica': '0001-01-001',
        'cod_interno': 'BAL-014',
        'instrumento': 'Balanza electrónica',
        'tipo_balanza': 'Plataforma',
        'marca': 'Marca',
        'modelo': 'Modelo X',
        'serie': 'SERIE-1',
        'ubicacion': 'Producción',
        'clase': 'III',
        'plataforma': 'Rectangular',
      },
      'ranges': [
        {
          'numero_rango': 1,
          'unidad': 'kg',
          'capacidad_max': '20.000000000',
          'division_escala': '0.010000000',
          'intervalo_verificacion': '0.010000000',
          'cantidad_decimales': 2,
        },
        {
          'numero_rango': 2,
          'unidad': 'kg',
          'capacidad_max': '50.000000000',
          'division_escala': '0.100000000',
          'intervalo_verificacion': '0.100000000',
          'cantidad_decimales': 1,
        },
      ],
    },
    'plan_snapshot': {
      'name': 'Control interno de balanza de plataforma',
      'version': 3,
      'procedure': 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
    },
  },
  'users': {
    'capture': 'Operador de producción',
    'finalization': 'Jefe de calidad',
  },
  'patterns': [
    {
      'snapshot': {
        'pattern': {'codigo': 'JP-001', 'descripcion': 'Juego de pesas patrón'},
        'certificate': {
          'numero': 'CERT-2026-001',
          'laboratorio': 'Laboratorio acreditado',
          'calibrado_el': '2026-01-15',
          'vence_el': '2027-01-15',
        },
        'validAtMeasurement': true,
      },
    },
  ],
  'tests': [
    {
      'tipo': 'eccentricity',
      'estado_ejecucion': 'executed',
      // Como se monto la prueba: de aqui sale el croquis del informe.
      'setup': {
        'platform': 'square',
        'pointCount': 5,
        'indicatorPosition': 'front',
      },
      'metodo_evaluacion': 'range',
      'metodo_codigo': 'EURAMET-CG18-V4-ECCENTRICITY',
      'unidad': 'kg',
      'regla_decision': 'direct',
      'fuente_tolerancia': 'configured',
      'tolerancia': '0.100000000',
      'veredicto': 'pass',
      'error_max_abs': '0.050000000',
      'rango': '0.080000000',
      'valor_metrica': '0.080000000',
      'readings': [
        for (var i = 0; i < 5; i++)
          {
            'grupo': 1,
            'orden': i + 1,
            'etiqueta': 'Posición ${i + 1}',
            'carga_nominal': '15.000000000',
            'indicacion': ['15.000', '15.020', '14.970', '15.050', '14.990'][i],
            'retorno_cero': '0.000000000',
            'error': ['0', '0.02', '-0.03', '0.05', '-0.01'][i],
            'tolerancia': '0.100000000',
            'veredicto': 'pass',
          },
      ],
    },
    {
      'tipo': 'repeatability',
      'estado_ejecucion': 'executed',
      'metodo_evaluacion': 'sample_standard_deviation',
      'metodo_codigo': 'EURAMET-CG18-V4-REPEATABILITY',
      'unidad': 'kg',
      'regla_decision': 'direct',
      'fuente_tolerancia': 'configured',
      'tolerancia': '0.050000000',
      'veredicto': 'pass',
      'media': '10.006000000',
      'desviacion_estandar': '0.015165751',
      'rango': '0.040000000',
      'valor_metrica': '0.015165751',
      'readings': [
        for (var i = 0; i < 5; i++)
          {
            'grupo': 1,
            'orden': i + 1,
            'etiqueta': 'Medición ${i + 1}',
            'carga_nominal': '10.000000000',
            'indicacion': ['10.000', '10.010', '10.020', '9.990', '10.010'][i],
            'retorno_cero': '0.000000000',
            'error': ['0', '0.01', '0.02', '-0.01', '0.01'][i],
            'tolerancia': '0.050000000',
            'veredicto': 'pass',
          },
      ],
    },
    {
      'tipo': 'linearity',
      'estado_ejecucion': 'executed',
      'metodo_evaluacion': 'absolute_error',
      'metodo_codigo': 'EURAMET-CG18-V4-ERROR-INDICATION',
      'unidad': 'kg',
      'regla_decision': 'direct',
      'fuente_tolerancia': 'configured',
      'tolerancia': '0.100000000',
      'veredicto': 'pass',
      'error_max_abs': '0.060000000',
      'valor_metrica': '0.060000000',
      'readings': [
        for (var i = 0; i < 5; i++)
          {
            'grupo': 1,
            'orden': i + 1,
            'etiqueta': 'Punto ${i + 1}',
            'carga_nominal': ['0', '10', '20', '30', '50'][i],
            'indicacion': ['0.00', '10.02', '19.97', '30.04', '50.06'][i],
            'retorno_cero': '0.000000000',
            'error': ['0', '0.02', '-0.03', '0.04', '0.06'][i],
            'tolerancia': '0.100000000',
            'veredicto': 'pass',
          },
      ],
    },
  ],
};

class FixtureServer {
  Json bundle = {...fixtureBundle};
  final recovery = DraftRecovery(MemoryDraftStore());
  final Map<String, Json> savedDrafts = {};
  final Map<String, Json> saveReceipts = {};
  Json user = {...fixtureUser};
  bool allowed = true;
  bool online = true;
  bool customerUpdatePending = false;
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
      final prior = saveReceipts[body['save_id']];
      if (prior != null) return (200, prior);
      final current = savedDrafts[body['request_id']];
      final version = int.parse(current?['version']?.toString() ?? '0');
      if (body['expected_version'].toString() != version.toString()) {
        return (409, {'message': 'ROW_VERSION_CONFLICT'});
      }
      final receipt = {
        'id': 'draft-fixture',
        'requestId': body['request_id'],
        'version': '${version + 1}',
        'savedAt': '2026-08-28T12:00:00Z',
      };
      savedDrafts[body['request_id'] as String] = {
        'id': 'draft-fixture',
        'request_uuid': body['request_id'],
        'version': '${version + 1}',
        'context_snapshot': bundle,
        'payload': body['content'],
      };
      saveReceipts[body['save_id'] as String] = receipt;
      return (200, receipt);
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
                'cod_interno': 'BAL-014',
                'marca': 'Marca',
                'modelo': 'Modelo',
                'planta': 'Planta uno',
                'area': 'Sin área',
                'departamento': 'Producción',
              },
            ],
          },
        );
      case 'equipment':
        return (
          200,
          {
            ...bundle,
            'customerValidated': true,
            'customerUpdatePending': customerUpdatePending,
          },
        );
      case 'drafts':
        return (
          200,
          {'total': savedDrafts.length, 'items': savedDrafts.values.toList()},
        );
      case 'draft':
        return (200, savedDrafts.values.first);
      case 'history':
        return (200, {'total': 0, 'items': []});
      case 'verification':
        return (200, fixtureVerificationData);
      default:
        return (400, {'message': 'UNEXPECTED_FIXTURE_REQUEST'});
    }
  }
}

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

  /// Escrituras pedidas al disco, para medir cuantas provoca la captura.
  int writes = 0;
  @override
  Future<String?> read(String owner) async => documents[owner];
  @override
  Future<void> write(String owner, String document) async {
    writes++;
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
      // Tal como lo devuelve `ivmet_mobile_read('verification')`: el montaje
      // viaja dentro de la evaluacion congelada. De aqui sale el croquis.
      'evaluacion_snapshot': {
        'claimScope': 'INTERNAL_CHECK_ONLY',
        'engineVersion': 'ivmet-internal-2.0.0',
        'setup': {
          'source': 'standard',
          'description': '',
          'notes': '',
          'platform': 'square',
          'indicatorPosition': 'front',
          'groupCount': 1,
          'measurementCount': 3,
          'pointCount': 5,
          'loadingMethod': 'none',
          'substitutionMethod': 'none',
        },
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

/// Agenda del mes en curso, relativa a [today]: una balanza hoy, otra la
/// semana que viene, una hecha ayer y una atrasada.
Json fixtureAgenda(DateTime today) {
  String key(int days) {
    final day = DateTime.utc(today.year, today.month, today.day + days);
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  Json equipment(String id, String code, String department, List<String> who) =>
      {
        'id': id,
        'cod_metrica': '0001-01-$id',
        'cod_interno': code,
        'planta': 'Planta uno',
        'plantId': 'plant-fixture',
        'departamento': department,
        'assignees': [
          for (final name in who) {'id': 'user-$name', 'name': name},
        ],
      };

  return {
    'today': key(0),
    'from': key(-40),
    'to': key(40),
    'equipmentCount': 4,
    'items': [
      {
        'date': key(0),
        'equipment': equipment('equipment-fixture', 'BAL-014', 'Producción', [
          'Ana',
        ]),
        'tests': [
          {'type': 'linearity', 'state': 'DUE_TODAY', 'doneOn': null},
          {'type': 'repeatability', 'state': 'DUE_TODAY', 'doneOn': null},
        ],
      },
      {
        'date': key(0),
        'equipment': equipment('equipment-2', 'BAL-020', 'Despacho', []),
        'tests': [
          {'type': 'eccentricity', 'state': 'DONE', 'doneOn': key(0)},
        ],
      },
      {
        'date': key(7),
        'equipment': equipment('equipment-fixture', 'BAL-014', 'Producción', [
          'Ana',
        ]),
        'tests': [
          {'type': 'linearity', 'state': 'SCHEDULED', 'doneOn': null},
        ],
      },
    ],
    'overdue': [
      {
        'dueOn': key(-3),
        'equipment': equipment('equipment-3', 'CAM-001', 'Báscula', ['Beto']),
        'tests': [
          {'type': 'linearity', 'dueOn': key(-3)},
        ],
      },
    ],
  };
}

const fixtureTeam = {
  'plantId': 'plant-fixture',
  'equipmentCount': 3,
  'unassignedCount': 1,
  'members': [
    {
      'id': 'user-ana',
      'name': 'Ana Quispe',
      'username': 'ana.quispe',
      'assignedCount': 2,
    },
    {
      'id': 'user-beto',
      'name': 'Beto Mamani',
      'username': 'beto.mamani',
      'assignedCount': 0,
    },
  ],
};

const fixtureTeamMember = {
  'plantId': 'plant-fixture',
  'member': {'id': 'user-ana', 'name': 'Ana Quispe', 'username': 'ana.quispe'},
  'items': [
    {
      'id': 'equipment-fixture',
      'cod_interno': 'BAL-014',
      'cod_metrica': '0001-01-001',
      'marca': 'Mettler',
      'modelo': 'IND570',
      'departamento': 'Producción',
      'assigned': true,
      'assigneeCount': 1,
    },
    {
      'id': 'equipment-2',
      'cod_interno': 'BAL-020',
      'cod_metrica': '0001-01-002',
      'marca': 'Ohaus',
      'modelo': 'Defender',
      'departamento': 'Despacho',
      'assigned': false,
      'assigneeCount': 0,
    },
    {
      'id': 'equipment-3',
      'cod_interno': 'CAM-001',
      'cod_metrica': '0001-01-003',
      'marca': 'Toledo',
      'modelo': 'Camionera',
      'departamento': 'Báscula',
      'assigned': true,
      'assigneeCount': 2,
    },
  ],
};

const fixtureEquipmentTeam = {
  'equipmentId': 'equipment-fixture',
  'plantId': 'plant-fixture',
  'members': [
    {
      'id': 'user-ana',
      'name': 'Ana Quispe',
      'username': 'ana.quispe',
      'assigned': true,
    },
    {
      'id': 'user-beto',
      'name': 'Beto Mamani',
      'username': 'beto.mamani',
      'assigned': false,
    },
  ],
};

class FixtureServer {
  Json bundle = {...fixtureBundle};
  Json bootstrap = {...fixtureBootstrap};
  late Json agenda = fixtureAgenda(DateTime.now());
  Json team = fixtureTeam;
  Json teamMember = fixtureTeamMember;
  Json equipmentTeam = fixtureEquipmentTeam;

  /// Cuerpos recibidos por `ivmet_customer_assign_equipment`.
  final List<Json> assignments = [];
  final recovery = DraftRecovery(MemoryDraftStore());
  final Map<String, Json> savedDrafts = {};
  final Map<String, Json> saveReceipts = {};
  Json user = {...fixtureUser};
  bool allowed = true;
  bool online = true;
  bool customerUpdatePending = false;

  /// Filas del catálogo; por defecto, una balanza del catálogo de Métrica.
  List<Json>? instruments;
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
    if (request.path.contains('ivmet_customer_assign_equipment')) {
      assignments.add(body);
      final assignment = object(body['assignment']);
      return (
        200,
        {
          ...assignment,
          'assigned':
              (assignment['equipmentIds'] ?? assignment['userIds']).length,
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
        return (200, bootstrap);
      case 'agenda':
        return (200, agenda);
      case 'team':
        return (200, team);
      case 'team-member':
        return (200, teamMember);
      case 'equipment-team':
        return (200, equipmentTeam);
      case 'instruments':
        final items =
            instruments ??
            [
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
            ];
        return (200, {'total': items.length, 'items': items});
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

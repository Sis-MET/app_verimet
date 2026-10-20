import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ivmet/features/online/mobile_api.dart';

import 'customer_fakes.dart';
import 'fakes.dart';

/// Resumen de configuración de una empresa recién registrada: la planta que
/// se creó al registrarse y nada más.
const freshSetup = {
  'plants': 1,
  'areas': 0,
  'patterns': 0,
  'tracedPatterns': 0,
  'equipment': 0,
  'validated': 0,
  'configured': 0,
  'assigned': 0,
  'operators': 0,
  'verifications': 0,
};

/// Servidor con `bootstrap.setup`; empresa autoregistrada si [selfService].
class GuideServer extends CustomerFixtureServer {
  GuideServer({
    String role = 'cliente_jefe_calidad',
    this.selfService = true,
    this.setup = freshSetup,
  }) {
    user = {...fixtureUser, 'role': role, 'name': 'Ana Pérez'};
  }

  final bool selfService;

  /// Null: un servidor anterior, sin resumen.
  Json? setup;

  @override
  FutureOr<(int, Json)> handle(RequestOptions request) {
    final body = request.data is Map
        ? object(request.data)
        : <String, dynamic>{};
    if (body['section'] == 'bootstrap') {
      requests.add(request);
      bootstrapCalls++;
      return (
        200,
        {
          ...bootstrap,
          'plan': {
            'id': 'plan-fixture',
            'name': selfService ? 'Gratuito' : 'Contrato',
            'selfService': selfService,
            'usage': {'plants': 1, 'equipment': 0, 'users': 1},
          },
          'setup': ?setup,
        },
      );
    }
    return super.handle(request);
  }
}

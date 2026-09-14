import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ivmet/features/online/mobile_api.dart';
import 'fakes.dart';

const equipmentUpdateFixture = {
  'code': '0001-01-001',
  'clientCode': '0001',
  'plantCode': '0001-01',
  'area': 'Producción',
  'catalog': {
    'ubicacion': 'Producción',
    'cod_interno': 'B-1',
    'marca': 'Marca',
    'modelo': 'Modelo',
    'serie': 'S-1',
  },
  'customer': {
    'ubicacion': 'Nueva ubicación',
    'cod_interno': 'B-1',
    'marca': 'Marca',
    'modelo': 'Modelo',
    'serie': 'S-1',
  },
};

class CustomerFixtureServer extends FixtureServer {
  int saveFailures = 0;
  @override
  FutureOr<(int, Json)> handle(RequestOptions request) {
    final body = request.data is Map
        ? object(request.data)
        : <String, dynamic>{};
    if (request.path.contains('ivmet_customer_configure_checks')) {
      requests.add(request);
      return (
        200,
        {
          'equipmentId': body['equipment_id'],
          'configurationId': 'configuration-fixture',
          'version': 1,
          'state': 'PUBLISHED',
        },
      );
    }
    if (request.path.contains('ivmet_customer_mutate')) {
      requests.add(request);
      if (saveFailures > 0) {
        saveFailures--;
        return (503, {'message': 'RETRY_TEST'});
      }
      return (200, {'id': 'saved-fixture'});
    }
    if (request.path.contains('ivmet_customer_read')) {
      requests.add(request);
      switch (body['section']) {
        case 'equipment':
          return (
            200,
            {
              'master': {
                'id': 'equipment-fixture',
                'source_hash': 'fixture-hash',
                'ubicacion': 'Producción',
                'cod_interno': 'B-1',
                'marca': 'Marca',
                'modelo': 'Modelo',
                'serie': 'S-1',
              },
              'customer': null,
              'areaId': null,
              'suggestedAreaId': 'area-fixture',
              'suggestedArea': 'Producción',
              'areas': [
                {'id': 'area-fixture', 'name': 'Producción'},
              ],
            },
          );
        case 'share-preview':
          return (
            200,
            {
              'snapshot': equipmentUpdateFixture,
              'hash': 'preview-fixture-hash',
              'consentVersion': 'equipment-sharing-v1',
              'notice':
                  'Solo se enviará la ficha mostrada. No se comparten pruebas.',
            },
          );
        case 'area-suggestions':
          return (
            200,
            {
              'total': 1,
              'items': [
                {
                  'name': 'Producción',
                  'key': 'produccion',
                  'equipment_count': 3,
                },
              ],
            },
          );
        case 'areas':
          return (
            200,
            {
              'total': 1,
              'items': [
                {
                  'id': 'area-fixture',
                  'name': 'Producción',
                  'active': true,
                  'version': '1',
                },
              ],
            },
          );
        case 'method-catalog':
          return (
            200,
            {
              'engineVersion': 'ivmet-internal-1.0.0',
              'claimScope': 'INTERNAL_CHECK_ONLY',
              'profiles': [
                {
                  'code': 'IVMET-CONTROL-INTERNO-PLATAFORMA-V1',
                  'name': 'Balanzas y plataformas estáticas',
                  'tests': [],
                },
              ],
            },
          );
        case 'patterns':
          return (
            200,
            {
              'total': 1,
              'items': [
                {
                  'id': 'pattern-fixture',
                  'codigo': 'JP-001',
                  'descripcion': 'Juego de pesas patrón',
                  'tipo': 'pesas',
                  'capacidad': '20',
                  'unidad': 'kg',
                  'activo': true,
                  'plantIds': ['plant-fixture'],
                  'row_version': '1',
                  'canEdit': true,
                  'certificates': [
                    {
                      'id': 'certificate-fixture',
                      'numero': 'CERT-2026-001',
                      'laboratorio': 'Laboratorio acreditado',
                      'calibrado_el': '2026-01-15',
                      'vence_el': '2027-01-15',
                      'estado': 'ACTIVE',
                      'row_version': '1',
                    },
                  ],
                },
              ],
            },
          );
        case 'plans':
        case 'updates':
          return (200, {'items': [], 'total': 0});
      }
    }
    return super.handle(request);
  }
}

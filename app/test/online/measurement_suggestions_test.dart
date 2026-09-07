import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/features/online/measurement_suggestions.dart';
import 'package:ivmet/features/online/trial_capture.dart';

void main() {
  const ranges = <Map<String, dynamic>>[
    {
      'numero_rango': 1,
      'unidad': 'kg',
      'capacidad_max': '20',
      'division_escala': '0.001000000',
      'cantidad_decimales': 3,
    },
    {
      'numero_rango': 2,
      'unidad': 'kg',
      'capacidad_max': '100',
      'division_escala': '0.100000000',
      'cantidad_decimales': 1,
    },
  ];

  test('la carga selecciona dec1, dec2 o dec3 según la capacidad', () {
    expect(indicationFromLoad(ranges, '19,5', 'kg'), '19,500');
    expect(indicationFromLoad(ranges, '20', 'kg'), '20,000');
    expect(indicationFromLoad(ranges, '20,1', 'kg'), '20,1');
    expect(indicationFromLoad(ranges, '150', 'kg'), '150,0');
  });

  test('la división determina los decimales cuando dec no está informado', () {
    const withoutDecimals = <Map<String, dynamic>>[
      {'unidad': 'kg', 'capacidad_max': '50', 'division_escala': '0.010000000'},
    ];
    final precision = indicationPrecisionForLoad(withoutDecimals, '12', 'kg');
    expect(precision?.decimals, 2);
    expect(precision?.divisionLabel, '0,01');
    expect(indicationFromLoad(withoutDecimals, '12', 'kg'), '12,00');
  });

  test('las sugerencias avanzan por divisiones alrededor de la carga', () {
    final values = indicationSuggestions(ranges, '20,1', 'kg', steps: 2);
    expect(values, ['20,3', '20,2', '20,1', '20,0', '19,9']);
  });

  test('conserva exactamente nueve decimales en cargas grandes', () {
    const preciseRange = <Map<String, dynamic>>[
      {
        'unidad': 'kg',
        'capacidad_max': '10000000000',
        'division_escala': '0.000000001',
        'cantidad_decimales': 9,
      },
    ];
    expect(
      indicationFromLoad(preciseRange, '9999999999,123456789', 'kg'),
      '9999999999,123456789',
    );
  });

  test('convierte capacidades y divisiones cuando las unidades difieren', () {
    const gramRange = <Map<String, dynamic>>[
      {
        'unidad': 'g',
        'capacidad_max': '2000',
        'division_escala': '1',
        'cantidad_decimales': 0,
      },
    ];
    final precision = indicationPrecisionForLoad(gramRange, '1.5', 'kg');
    expect(precision?.divisionLabel, '0,001');
    expect(indicationFromLoad(gramRange, '1.5', 'kg'), '1,500');
  });

  test('hereda la carga en todas las indicaciones sin borrar ediciones', () {
    final trial = <String, dynamic>{
      'readings': <Map<String, dynamic>>[
        {'pointId': 'one', 'group': 1, 'load': '', 'indication': ''},
        {'pointId': 'two', 'group': 1, 'load': '', 'indication': ''},
      ],
      'retainedReadings': <Map<String, dynamic>>[
        {'pointId': 'three', 'group': 1, 'load': '', 'indication': ''},
      ],
    };
    String format(String load) => indicationFromLoad(ranges, load, 'kg');
    final first = activeReadings(trial).first;
    setLoadAndInheritIndication(
      trial,
      first,
      '19,5',
      grouped: true,
      indicationFormatter: format,
    );
    expect(
      activeReadings(trial).map((reading) => reading['indication']),
      everyElement('19,500'),
    );
    expect((trial['retainedReadings'] as List).single['indication'], '19,500');

    activeReadings(trial).last['indication'] = '19.499';
    setLoadAndInheritIndication(
      trial,
      first,
      '25',
      grouped: true,
      indicationFormatter: format,
    );
    expect(activeReadings(trial).first['indication'], '25,0');
    expect(activeReadings(trial).last['indication'], '19.499');
    expect((trial['retainedReadings'] as List).single['indication'], '25,0');
  });

  test('un borrador legado conserva los valores y elimina la sustitución', () {
    final saved = <String, dynamic>{
      'id': 'linearity',
      'omitted': false,
      'reason': '',
      'setup': <String, dynamic>{
        'source': 'mixed',
        'description': '',
        'notes': '',
        'platform': 'square',
        'indicatorPosition': 'front',
        'groupCount': 1,
        'measurementCount': 3,
        'pointCount': 2,
        'loadingMethod': 'continuous',
        'substitutionMethod': 'method_2',
      },
      'readings': <Map<String, dynamic>>[
        {
          'pointId': 'one',
          'group': 1,
          'slot': 1,
          'load': '10',
          'indication': '10.01',
          'zero': '0',
        },
        {
          'pointId': 'two',
          'group': 1,
          'slot': 2,
          'load': '25.123456789',
          'indication': '25,12',
          'zero': '',
          'substitution': {
            'referencePointId': 'one',
            'basePointId': 'one',
            'indication': '15.113456789',
          },
        },
      ],
      'retainedReadings': <Map<String, dynamic>>[],
      'substitutionDraft': {
        'referencePointId': 'one',
        'basePointId': 'one',
        'indication': '5',
      },
    };
    final trial = restoreFlexibleTrial(const {
      'id': 'linearity',
      'type': 'linearity',
      'points': <Map<String, dynamic>>[],
    }, saved);
    expect(trialSetup(trial)['loadingMethod'], 'none');
    expect(trialSetup(trial)['substitutionMethod'], 'none');
    expect(trial.containsKey('substitutionDraft'), false);
    expect(activeReadings(trial).last['load'], '25.123456789');
    expect(activeReadings(trial).last['indication'], '25,12');
    expect(activeReadings(trial).last.containsKey('substitution'), false);
  });

  group('etiquetas de rango del catalogo', () {
    // Postgres entrega `numeric` con toda su escala. Es lo que llegaba a
    // pantalla: "6100.000000000 g · division 0.100000000".
    const crudo = <String, dynamic>{
      'numero_rango': 1,
      'capacidad_max': '6100.000000000',
      'division_escala': '0.100000000',
      'cantidad_decimales': 1,
      'unidad': 'g',
    };

    test('manda cantidad_decimales del catalogo', () {
      expect(rangeDecimals(crudo), 1);
      expect(rangeCapacityLabel(crudo), '6100,0');
      expect(rangeDivisionLabel(crudo), '0,1');
    });

    test('sin cantidad_decimales, los decimales salen de la division', () {
      const sinDeclarar = <String, dynamic>{
        'capacidad_max': '6100.000000000',
        'division_escala': '0.100000000',
        'unidad': 'g',
      };
      expect(rangeDecimals(sinDeclarar), 1);
      expect(rangeCapacityLabel(sinDeclarar), '6100,0');
    });

    test('una balanza sin decimales no gana ninguno', () {
      const entera = <String, dynamic>{
        'capacidad_max': '1500.000000000',
        'division_escala': '5.000000000',
        'cantidad_decimales': 0,
      };
      expect(rangeCapacityLabel(entera), '1500');
      expect(rangeDivisionLabel(entera), '5');
    });

    test('la division conserva los suyos aunque el rango declare menos', () {
      // Dato de catalogo incoherente: redondear la division la borraria.
      const incoherente = <String, dynamic>{
        'capacidad_max': '220.000000000',
        'division_escala': '0.001000000',
        'cantidad_decimales': 0,
      };
      expect(rangeCapacityLabel(incoherente), '220');
      expect(rangeDivisionLabel(incoherente), '0,001');
    });

    test('lo que no es un numero se devuelve tal cual', () {
      const roto = <String, dynamic>{
        'capacidad_max': 'sin dato',
        'division_escala': '',
      };
      expect(rangeCapacityLabel(roto), 'sin dato');
      expect(rangeDivisionLabel(roto), '');
    });
  });
}

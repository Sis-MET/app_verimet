import 'package:flutter/material.dart';

import '../../shared/widgets/blueprint_card.dart';
import 'draft_controller.dart';
import 'mobile_api.dart';
import 'online_widgets.dart';
import 'trial_capture.dart';

class FlexibleTrialFields extends StatefulWidget {
  const FlexibleTrialFields({
    required this.capture,
    required this.plan,
    super.key,
  });
  final DraftController capture;
  final Json plan;
  @override
  State<FlexibleTrialFields> createState() => _FlexibleTrialFieldsState();
}

class _FlexibleTrialFieldsState extends State<FlexibleTrialFields> {
  final fields = <String, TextEditingController>{};
  final desiredValues = <String, String>{};
  Json get trial => widget.capture.testInput(widget.plan['id'] as String);
  Json get setup => trialSetup(trial);
  List<Json> get readings => activeReadings(trial);
  String get type => widget.plan['type'] as String;
  String get unit => widget.plan['unit'] as String;
  bool get locked => widget.capture.locked;

  @override
  void initState() {
    super.initState();
    if (trial['substitutionDraft'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !locked) addSubstitution();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void changed() {
    refreshSubstitutions(trial);
    widget.capture.changed();
  }

  Widget field(
    String id,
    String value,
    String label,
    ValueChanged<String> update, {
    bool required = false,
    bool number = true,
    String? hint,
    bool readOnly = false,
    int? maxLength,
  }) {
    final controller = fields.putIfAbsent(
      id,
      () => TextEditingController(text: value),
    );
    desiredValues[id] = value;
    if (controller.text != value) {
      // Programmatic changes notify the ancestor Form. Apply them after build,
      // using the latest model value if another edit arrived in this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = desiredValues[id]!;
        if (controller.text != current) {
          controller.value = TextEditingValue(
            text: current,
            selection: TextSelection.collapsed(offset: current.length),
          );
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        key: ValueKey(id),
        controller: controller,
        enabled: !locked,
        readOnly: readOnly,
        maxLength: maxLength,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 3,
        ),
        validator: (text) => required && (text ?? '').trim().isEmpty
            ? 'Completa este dato.'
            : number
            ? decimalError(text)
            : null,
        onChanged: (text) {
          update(text);
          changed();
        },
      ),
    );
  }

  Widget select(
    String name,
    String label,
    Map<String, String> choices, {
    VoidCallback? after,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$name:${setup[name]}'),
      initialValue: setup[name] as String,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in choices.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 2)),
      ],
      onChanged: locked
          ? null
          : (value) {
              setup[name] = value!;
              after?.call();
              changed();
            },
    ),
  );

  Widget countChoice(String name, String label, List<int> counts) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Wrap(
          spacing: 8,
          children: [
            for (final count in counts)
              ChoiceChip(
                label: Text('$count'),
                selected: setup[name] == count,
                onSelected: locked
                    ? null
                    : (_) {
                        setup[name] = count;
                        resizeTrial(trial, widget.plan);
                        changed();
                      },
              ),
          ],
        ),
      ],
    ),
  );

  String suggestion(Json r) =>
      (r['suggestedLoad'] ??
              objects(
                widget.plan['points'],
              ).where((p) => p['id'] == r['pointId']).firstOrNull?['load'] ??
              objects(widget.plan['points']).firstOrNull?['load'] ??
              '')
          .toString();

  Widget loadField(Json r, {bool grouped = false}) {
    final hint = suggestion(r);
    final substituted = r['substitution'] != null;
    void update(String value) {
      if (grouped) {
        setGroupLoad(trial, r['group'] as int, value);
      } else {
        r['load'] = value;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(
          '${r['pointId']}:load',
          r['load'] as String,
          'Carga utilizada ($unit)',
          update,
          required: true,
          readOnly: substituted,
          hint: substituted
              ? 'Carga acumulada calculada por sustitución.'
              : hint.isEmpty
              ? null
              : 'Sugerida: $hint $unit. Puedes utilizar otra carga.',
        ),
        if (!substituted && hint.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: locked
                  ? null
                  : () {
                      update(hint);
                      changed();
                    },
              child: const Text('Usar sugerencia'),
            ),
          ),
        if (substituted) ...[
          Text(
            'Indicación de sustitución: ${object(r['substitution'])['indication']} $unit',
            style: const TextStyle(fontSize: 12),
          ),
          TextButton(
            onPressed: locked
                ? null
                : () {
                    r.remove('substitution');
                    changed();
                  },
            child: const Text('Usar carga manual'),
          ),
        ],
      ],
    );
  }

  Widget readingFields(Json r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      field(
        '${r['pointId']}:indication',
        r['indication'] as String,
        'Indicación ($unit)',
        (v) => r['indication'] = v,
        required: true,
      ),
      field(
        '${r['pointId']}:zero',
        r['zero'] as String,
        'Retorno a cero (opcional)',
        (v) => r['zero'] = v,
      ),
      if (type == 'linearity' &&
          indicationError(r['indication'] as String, r['load'] as String) !=
              null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Diferencia indicación − carga: ${indicationError(r['indication'] as String, r['load'] as String)} $unit',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
  );

  Future<void> addSubstitution() async {
    final valid = readings
        .where(
          (r) =>
              indicationError(r['indication'] as String, r['load'] as String) !=
              null,
        )
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero registra una carga y su indicación como referencia.',
          ),
        ),
      );
      return;
    }
    final draft =
        trial.putIfAbsent(
              'substitutionDraft',
              () => <String, dynamic>{
                'referencePointId': valid.last['pointId'],
                'basePointId': valid.last['pointId'],
                'indication': '',
              },
            )
            as Json;
    var reference = valid.any((r) => r['pointId'] == draft['referencePointId'])
        ? draft['referencePointId'] as String
        : valid.last['pointId'] as String;
    var base = valid.any((r) => r['pointId'] == draft['basePointId'])
        ? draft['basePointId'] as String
        : reference;
    var indication = draft['indication'] as String;
    widget.capture.changed();
    final key = GlobalKey<FormState>();
    final result = await showDialog<Json>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void updateDraft(VoidCallback change) {
            update(change);
            draft.addAll({
              'referencePointId': reference,
              'basePointId': base,
              'indication': indication,
            });
            widget.capture.changed();
          }

          final substitution = <String, dynamic>{
            'basePointId': base,
            'referencePointId': reference,
            'indication': indication,
          };
          final calculated = substitutionLoad(readings, substitution);
          Widget pointSelect(
            String label,
            String value,
            ValueChanged<String> change,
          ) => DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final r in valid)
                DropdownMenuItem(
                  value: r['pointId'] as String,
                  child: Text('Punto ${r['slot']} · ${r['load']} $unit'),
                ),
            ],
            onChanged: (v) => updateDraft(() => change(v!)),
          );
          return AlertDialog(
            title: const Text('Agregar carga por sustitución'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Form(
                  key: key,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Registra la indicación de la carga sustituta. Se corrige con el error de la referencia y se suma a la carga base.',
                      ),
                      const SizedBox(height: 16),
                      pointSelect(
                        'Referencia para corregir el error',
                        reference,
                        (v) => reference = v,
                      ),
                      const SizedBox(height: 16),
                      pointSelect(
                        'Carga base acumulada',
                        base,
                        (v) => base = v,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: indication,
                        key: const ValueKey('substitution-indication'),
                        decoration: InputDecoration(
                          labelText: 'Indicación de la sustitución ($unit)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Ingresa la indicación.'
                            : decimalError(v),
                        onChanged: (v) => updateDraft(() => indication = v),
                      ),
                      const SizedBox(height: 16),
                      Text('Carga acumulada: ${calculated ?? '—'} $unit'),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  trial.remove('substitutionDraft');
                  widget.capture.changed();
                  Navigator.pop(context);
                },
                child: const Text('Descartar sustitución'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continuar después'),
              ),
              TextButton(
                onPressed: () {
                  if (key.currentState!.validate() && calculated != null) {
                    Navigator.pop(context, substitution);
                  }
                },
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    // Append without reusing a retained row that could contain measured data.
    final occupied = [
      ...readings,
      ...objects(trial['retainedReadings']),
    ].map((r) => r['slot'] as int).fold(0, (a, b) => a > b ? a : b);
    if (occupied >= 60) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recupera o revisa los puntos retirados antes de agregar una sustitución.',
            ),
          ),
        );
      }
      return;
    }
    setup['pointCount'] = occupied + 1;
    resizeTrial(trial, widget.plan);
    readings.last['substitution'] = result;
    trial.remove('substitutionDraft');
    if (setup['source'] == 'standard') setup['source'] = 'mixed';
    changed();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Notice(
        'Las cargas son sugeridas. Registra la carga realmente utilizada; puede ser una pesa patrón, un producto o una carga de trabajo.',
      ),
      select('source', 'Origen de las cargas', loadSources),
      field(
        'description',
        setup['description'] as String,
        'Identificación de las cargas (opcional)',
        (v) => setup['description'] = v,
        number: false,
        maxLength: 1000,
        hint:
            'Ej.: sacos de producto, lote A; masa asignada mediante otra balanza.',
      ),
      if (setup['source'] != 'standard')
        const Notice(
          'La masa declarada de productos o cargas de trabajo se conserva como referencia de la comprobación interna, sin trazabilidad certificada.',
        ),
      if (type == 'eccentricity') ...[
        select(
          'platform',
          'Forma de la plataforma',
          platformLabels,
          after: () {
            final counts = eccentricityCounts(setup['platform'] as String);
            if (!counts.contains(setup['pointCount'])) {
              setup['pointCount'] = counts.first;
            }
            resizeTrial(trial, widget.plan);
          },
        ),
        countChoice(
          'pointCount',
          'Posiciones de ensayo',
          eccentricityCounts(setup['platform'] as String),
        ),
        select('indicatorPosition', 'Ubicación del indicador', const {
          'front': 'Frente',
          'back': 'Atrás',
          'left': 'Izquierda',
          'right': 'Derecha',
        }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(
            label: 'Posición 1 en el centro, referencia de excentricidad.',
            child: SizedBox(
              height: 190,
              child: CustomPaint(
                painter: _PlatformPainter(
                  setup['platform'] as String,
                  setup['pointCount'] as int,
                  setup['indicatorPosition'] as String,
                  Theme.of(context).colorScheme,
                ),
              ),
            ),
          ),
        ),
        const Text(
          'Aplica la misma carga en cada posición. La posición 1 es la referencia central.',
        ),
        loadField(readings.first, grouped: true),
        for (final r in readings)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BlueprintCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Posición ${r['slot']}${r['slot'] == 1 ? ' · referencia' : ''}',
                  ),
                  readingFields(r),
                ],
              ),
            ),
          ),
      ],
      if (type == 'repeatability') ...[
        countChoice('groupCount', 'Cantidad de cargas', [1, 2, 3]),
        countChoice('measurementCount', 'Mediciones por carga', [3, 5, 10]),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Retira y vuelve a aplicar la misma carga en cada repetición. Cada grupo se evalúa por separado.',
          ),
        ),
        for (var group = 1; group <= setup['groupCount']; group++)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: BlueprintCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Carga $group',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  loadField(
                    readings.firstWhere((r) => r['group'] == group),
                    grouped: true,
                  ),
                  for (final r in readings.where(
                    (r) => r['group'] == group,
                  )) ...[
                    const Divider(height: 24),
                    Text('Medición ${r['slot']}'),
                    readingFields(r),
                  ],
                ],
              ),
            ),
          ),
      ],
      if (type == 'linearity') ...[
        select('loadingMethod', 'Aplicación de las cargas', loadingMethods),
        if (setup['loadingMethod'] == 'return_zero')
          const Notice(
            'Retira la carga y registra el retorno a cero entre puntos.',
          ),
        if (setup['loadingMethod'] == 'continuous')
          const Notice(
            'Añade cargas de forma progresiva. El retorno a cero intermedio puede quedar vacío.',
          ),
        select(
          'substitutionMethod',
          'Método de sustitución',
          substitutionMethods,
        ),
        for (final r in readings)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BlueprintCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Punto ${r['slot']}'),
                  loadField(r),
                  readingFields(r),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: locked || readings.length >= 60
                    ? null
                    : () {
                        setup['pointCount'] = readings.length + 1;
                        resizeTrial(trial, widget.plan);
                        changed();
                      },
                child: const Text('Agregar punto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: locked || readings.length <= 2
                    ? null
                    : () {
                        setup['pointCount'] = readings.length - 1;
                        resizeTrial(trial, widget.plan);
                        changed();
                      },
                child: const Text('Retirar último'),
              ),
            ),
          ],
        ),
        if (setup['substitutionMethod'] != 'none')
          TextButton.icon(
            onPressed: locked || readings.length >= 60 ? null : addSubstitution,
            icon: const Icon(Icons.add),
            label: Text(
              trial['substitutionDraft'] == null
                  ? 'Agregar por sustitución'
                  : 'Continuar sustitución pendiente',
            ),
          ),
      ],
      if (objects(trial['retainedReadings']).isNotEmpty)
        Notice(
          '${objects(trial['retainedReadings']).length} mediciones retiradas conservadas. Aumenta la cantidad para recuperarlas; no intervienen en el resultado.',
        ),
      field(
        'notes',
        setup['notes'] as String,
        'Observaciones de la prueba (opcional)',
        (v) => setup['notes'] = v,
        number: false,
        maxLength: 2000,
      ),
    ],
  );
}

class _PlatformPainter extends CustomPainter {
  _PlatformPainter(this.platform, this.count, this.indicator, this.colors);
  final String platform, indicator;
  final int count;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: platform == 'rectangular' ? 240 : 155,
      height: platform == 'rectangular' ? 115 : 155,
    );
    final paint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (platform == 'circular') {
      canvas.drawOval(rect, paint);
    } else if (platform == 'triangular') {
      canvas.drawPath(
        Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close(),
        paint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
    }
    final positions = platform == 'triangular'
        ? [
            const Offset(.5, .53),
            const Offset(.5, .3),
            const Offset(.66, .66),
            const Offset(.34, .66),
          ]
        : count == 3
        ? [const Offset(.5, .5), const Offset(.22, .5), const Offset(.78, .5)]
        : count == 4
        ? [
            const Offset(.5, .5),
            const Offset(.69, .31),
            const Offset(.5, .77),
            const Offset(.31, .31),
          ]
        : [
            const Offset(.5, .5),
            const Offset(.73, .27),
            const Offset(.73, .73),
            const Offset(.27, .73),
            const Offset(.27, .27),
          ];
    for (var i = 0; i < positions.length; i++) {
      final point = Offset(
        rect.left + positions[i].dx * rect.width,
        rect.top + positions[i].dy * rect.height,
      );
      canvas.drawCircle(
        point,
        12,
        Paint()..color = i == 0 ? colors.primary : colors.secondaryContainer,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: i == 0 ? colors.onPrimary : colors.onSecondaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, point - Offset(label.width / 2, label.height / 2));
    }
    final marker = switch (indicator) {
      'back' => rect.topCenter - const Offset(0, 10),
      'left' => rect.centerLeft - const Offset(10, 0),
      'right' => rect.centerRight + const Offset(10, 0),
      _ => rect.bottomCenter + const Offset(0, 10),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: marker,
          width: indicator == 'left' || indicator == 'right' ? 6 : 30,
          height: indicator == 'left' || indicator == 'right' ? 30 : 6,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = colors.primary,
    );
  }

  @override
  bool shouldRepaint(_PlatformPainter oldDelegate) =>
      oldDelegate.platform != platform ||
      oldDelegate.count != count ||
      oldDelegate.indicator != indicator ||
      oldDelegate.colors != colors;
}

import 'package:flutter/material.dart';

import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/labeled_field.dart';
import 'draft_controller.dart';
import 'measurement_suggestions.dart';
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
  List<Json> get ranges => objects(widget.capture.bundle['ranges']);

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void changed() {
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
    Widget? suffixIcon,
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
      child: LabeledInput(
        label: label,
        child: TextFormField(
          key: ValueKey(id),
          controller: controller,
          enabled: !locked,
          readOnly: readOnly,
          maxLength: maxLength,
          keyboardType: number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          decoration: InputDecoration(
            helperText: hint,
            helperMaxLines: 3,
            suffixIcon: suffixIcon,
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
    child: LabeledInput(
      label: label,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$name:${setup[name]}'),
        initialValue: setup[name] as String,
        isExpanded: true,
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
    final rawHint = suggestion(r);
    final hint = indicationFromLoad(ranges, rawHint, unit);
    void update(String value) {
      setLoadAndInheritIndication(
        trial,
        r,
        value,
        grouped: grouped,
        indicationFormatter: (load) => indicationFromLoad(ranges, load, unit),
      );
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
          hint: rawHint.isEmpty
              ? null
              : 'Sugerida: $hint $unit. Puedes utilizar otra carga.',
        ),
        if (rawHint.isNotEmpty)
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
      ],
    );
  }

  String? _precisionHint(String load) {
    final precision = indicationPrecisionForLoad(ranges, load, unit);
    if (precision == null) return null;
    final decimalLabel = precision.decimals == 1 ? 'decimal' : 'decimales';
    return 'Precisión: ${precision.decimals} $decimalLabel · '
        'd = ${precision.divisionLabel} $unit';
  }

  Widget? _suggestionButton(Json reading) {
    final suggestions = indicationSuggestions(
      ranges,
      reading['load'] as String,
      unit,
    );
    if (locked || suggestions.isEmpty) return null;
    return IconButton(
      key: ValueKey('${reading['pointId']}:suggestions'),
      tooltip: 'Sugerir indicación según la división de escala',
      onPressed: () => _showIndicationSuggestions(reading),
      icon: const Icon(Icons.unfold_more_rounded),
    );
  }

  Future<void> _showIndicationSuggestions(Json reading) async {
    final load = reading['load'] as String;
    final precision = indicationPrecisionForLoad(ranges, load, unit);
    final suggestions = indicationSuggestions(ranges, load, unit);
    if (precision == null || suggestions.isEmpty) return;
    final base = indicationFromLoad(ranges, load, unit);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sugerir indicación',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Carga $load $unit · d = ${precision.divisionLabel} $unit',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final value = suggestions[index];
                    return ListTile(
                      leading: value == base
                          ? const Icon(Icons.arrow_forward_rounded)
                          : const SizedBox(width: 24),
                      title: Text('$value $unit'),
                      subtitle: value == base ? const Text('Carga base') : null,
                      onTap: () => Navigator.pop(context, value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    reading['indication'] = selected;
    changed();
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
        hint: _precisionHint(r['load'] as String),
        suffixIcon: _suggestionButton(r),
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
            child: SurfaceCard(
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
            child: SurfaceCard(
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
        for (final r in readings)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SurfaceCard(
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

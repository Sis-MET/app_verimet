import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'draft_controller.dart';
import 'flexible_trial_fields.dart';
import 'mobile_api.dart';
import 'online_widgets.dart';
import 'trial_capture.dart';

/// Contenido de cada paso del asistente de captura.
///
/// Va aparte de `draft_screen.dart` porque son dos cosas distintas: alli esta
/// la mecanica del asistente —navegar, autoguardar, comparar con el servidor,
/// finalizar— y aqui lo que el operario ve en cada paso. Juntas pasaban de
/// 950 lineas y no se podia tocar una sin leer la otra.
///
/// No guarda estado propio: depende de la captura y de los controladores de
/// texto que el asistente mantiene vivos entre pasos.
class DraftSteps {
  const DraftSteps({
    required this.capture,
    required this.fields,
    required this.onGoToStep,
    required this.onSaveDraft,
    required this.onToggleOmission,
  });

  final DraftController capture;

  /// Controladores de texto, indexados como los declara el asistente. Los
  /// mantiene el, no esta clase: al volver a un paso el texto sigue ahi.
  final Map<String, TextEditingController> fields;

  /// Volver a un paso anterior desde el resumen.
  final ValueChanged<int> onGoToStep;

  /// Guardar el borrador privado desde el resumen. La operacion es del
  /// asistente —toca red y estado de navegacion—, aqui solo esta el boton.
  final AsyncCallback onSaveDraft;

  /// Omitir o volver a incluir una prueba. Omitir vive en ⋮; volver a
  /// incluirla, tambien en la tarjeta de la prueba omitida.
  final ValueChanged<Json> onToggleOmission;

  List<Widget> preparation(BuildContext context) => [
    WizardStepHeading(
      title: draftStepTitles[0],
      caption:
          'Elige los certificados de las pesas que usarás y registra el ambiente. Sin pesas patrón, identifica las cargas en cada prueba.',
    ),
    const SectionLabel('Pesas patrón y certificados'),
    if (objects(capture.bundle['patterns']).isEmpty)
      const Notice(
        'No hay pesas patrón disponibles para esta planta. Puedes continuar con productos o cargas de trabajo e identificar su origen en cada prueba.',
      ),
    for (final pattern in objects(capture.bundle['patterns']))
      // El apartado lleva contorno redondeado: sin margen propio dos pesas
      // seguidas quedaban pegadas, y con `tilePadding` a cero el titulo se
      // apoyaba en el borde.
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ExpansionTile(
          key: PageStorageKey('pattern-${pattern['id']}'),
          initiallyExpanded: true,
          title: Text('${pattern['code']} · ${pattern['description']}'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            if (objects(pattern['certificates']).isEmpty)
              const Notice('Sin certificados disponibles.'),
            for (final cert in objects(pattern['certificates']))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(valueLabel(cert['number'])),
                subtitle: Text(
                  '${cert['laboratory']} · vence ${dateLabel(cert['expiresOn'])}${cert['expired'] == true ? ' · VENCIDO' : ''}',
                ),
                value: (capture.raw['certificates'] as List).contains(
                  cert['id'],
                ),
                onChanged: capture.locked
                    ? null
                    : (checked) {
                        final selected = capture.raw['certificates'] as List;
                        for (final certificate in objects(
                          pattern['certificates'],
                        )) {
                          selected.remove(certificate['id']);
                        }
                        if (checked == true) selected.add(cert['id']);
                        capture.changed();
                      },
              ),
          ],
        ),
      ),
    const SectionLabel('Condiciones ambientales'),
    LabeledInput(
      label: 'Temperatura (°C)',
      child: TextFormField(
        controller: fields['temperature'],
        enabled: !capture.locked,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        validator: (v) => decimalError(v, environment: true),
      ),
    ),
    const SizedBox(height: 12),
    LabeledInput(
      label: 'Humedad relativa (%)',
      child: TextFormField(
        controller: fields['humidity'],
        enabled: !capture.locked,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => decimalError(v, environment: true, humidity: true),
      ),
    ),
    const Notice(
      'Un certificado vencido no aporta trazabilidad a la verificación.',
    ),
  ];

  List<Widget> testStep(BuildContext context) {
    final tests = capture.tests
        .where((t) => t['type'] == draftStepTypes[capture.step])
        .toList();
    return [
      if (tests.isEmpty) ...[
        WizardStepHeading(title: draftStepTitles[capture.step]),
        const Notice(
          'Esta prueba no está incluida en la configuración de la balanza. Continúa al siguiente paso.',
        ),
      ],
      for (final test in tests) ..._trial(context, test),
    ];
  }

  /// Que hacer en la prueba, en una o dos lineas. Con cargas flexibles
  /// recuerda que la carga sugerida es orientativa: antes era un aviso aparte.
  String _instruction(Json test) {
    final action = switch (test['type']) {
      'eccentricity' => 'Registra la indicación en cada posición de la carga.',
      'repeatability' => 'Repite la misma carga y registra cada indicación.',
      _ => 'Registra la indicación para cada carga del rango.',
    };
    if (capture.flexible) {
      return '$action Anota la carga que usaste: la sugerida es orientativa.';
    }
    return '$action ${objects(test['points']).length} puntos · '
        '${valueLabel(test['unit'])}.';
  }

  /// Prueba omitida: el motivo y la vuelta atras, sin lecturas a la vista.
  /// Las lecturas ya escritas se conservan.
  Widget _omitted(BuildContext context, Json test, Json input) {
    final palette = IndustryPalette.of(context);
    return SurfaceCard(
      key: const ValueKey('omitted-test'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.do_not_disturb_on_outlined,
                size: 20,
                color: palette.accentInk,
              ),
              const SizedBox(width: 10),
              Text(
                'Prueba omitida',
                style: AppTextStyles.figure(context, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Indica por qué. Si la vuelves a incluir, recuperas las lecturas que ya registraste.',
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
          ),
          const SizedBox(height: 12),
          LabeledInput(
            label: 'Motivo de omisión',
            child: TextFormField(
              controller: fields['${test['id']}:reason'],
              enabled: !capture.locked,
              maxLength: 500,
              maxLines: 3,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Debes justificar la omisión.'
                  : null,
            ),
          ),
          if (!capture.locked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onToggleOmission(input),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Volver a incluir la prueba'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _trial(BuildContext context, Json test) {
    final input = capture.testInput(test['id'] as String);
    final unit = valueLabel(test['unit']);
    return [
      WizardStepHeading(
        title: draftStepTitles[capture.step],
        caption: input['omitted'] == true ? null : _instruction(test),
      ),
      if (input['omitted'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _omitted(context, test, input),
        )
      else if (capture.flexible)
        FlexibleTrialFields(
          key: ValueKey(test['id']),
          capture: capture,
          plan: test,
        )
      else
        for (final point in objects(test['points']))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${point['order']}. ${point['label']}',
                    style: AppTextStyles.figure(context, size: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Carga ${point['load']} $unit · tolerancia ${point['tolerance']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (point['position'] != null || point['direction'] != null)
                    Text(
                      '${point['position'] ?? ''} ${point['direction'] ?? ''} · grupo ${point['group']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  LabeledInput(
                    label: 'Indicación',
                    child: TextFormField(
                      key: ValueKey('${point['id']}:indication'),
                      controller:
                          fields['${test['id']}:${point['id']}:indication'],
                      enabled: !capture.locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Ingresa la indicación.'
                          : decimalError(value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LabeledInput(
                    label: 'Retorno a cero (opcional)',
                    child: TextFormField(
                      controller: fields['${test['id']}:${point['id']}:zero'],
                      enabled: !capture.locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: decimalError,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  Widget _heading(String title, int step) => Row(
    children: [
      Expanded(child: SectionLabel(title)),
      TextButton(
        onPressed: capture.locked ? null : () => onGoToStep(step),
        child: const Text('Editar'),
      ),
    ],
  );
  List<Widget> summary(BuildContext context) => [
    WizardStepHeading(
      title: draftStepTitles[4],
      caption:
          'Revisa las condiciones, las pesas patrón y todas las lecturas antes de finalizar.',
    ),
    _heading('Condiciones y pesas patrón', 0),
    SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailField('Balanza', customerEquipmentCode(capture.equipment)),
          DetailField(
            'Temperatura (°C)',
            valueLabel(capture.raw['temperature']),
          ),
          DetailField(
            'Humedad relativa (%)',
            valueLabel(capture.raw['humidity']),
          ),
          if ((capture.raw['certificates'] as List).isEmpty)
            const DetailField('Pesas patrón', 'Sin seleccionar'),
          for (final pattern in objects(capture.bundle['patterns']))
            for (final cert in objects(pattern['certificates']))
              if ((capture.raw['certificates'] as List).contains(cert['id']))
                DetailField(
                  '${pattern['code']}',
                  '${cert['number']}${cert['expired'] == true ? ' · VENCIDO' : ''}',
                ),
        ],
      ),
    ),
    for (var step = 1; step <= 3; step++) ...[
      _heading(draftStepTitles[step], step),
      if (!capture.tests.any((t) => t['type'] == draftStepTypes[step]))
        const Text('No incluida en la configuración.'),
      for (final test in capture.tests.where(
        (t) => t['type'] == draftStepTypes[step],
      ))
        _trialSummary(context, test),
    ],
    const SectionLabel('Observaciones'),
    LabeledInput(
      label: 'Observaciones',
      child: TextFormField(
        controller: fields['observations'],
        enabled: !capture.locked,
        maxLength: 4000,
        maxLines: 3,
      ),
    ),
    if (capture.completionIssue != null) Notice(capture.completionIssue!),
    const Notice(
      'Verificación intermedia, interna y privada. No equivale a una calibración acreditada ni a una verificación legal.',
      icon: Icons.shield_outlined,
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: capture.finalizing ? null : onSaveDraft,
      icon: const Icon(Icons.cloud_upload_outlined),
      label: const Text('Guardar borrador privado'),
    ),
    if (capture.plan['finalizationEnabled'] != true)
      const Notice('Esta configuración aún no admite finalización.'),
  ];
  Widget _trialSummary(BuildContext context, Json test) {
    final input = capture.testInput(test['id'] as String);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            input['omitted'] == true
                ? 'Omitida'
                : capture.testComplete(input)
                ? 'Completa'
                : 'Pendiente',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (input['omitted'] == true)
            Text(input['reason'] as String)
          else if (capture.flexible) ...[
            DetailField(
              'Origen de las cargas',
              loadSources[trialSetup(input)['source']],
            ),
            DetailField(
              'Identificación',
              valueLabel(trialSetup(input)['description']),
            ),
            if (test['type'] == 'eccentricity')
              DetailField(
                'Plataforma',
                platformLabels[trialSetup(input)['platform']],
              ),
            for (final reading in activeReadings(input)) ...[
              const Divider(height: 20),
              Text(
                '${test['type'] == 'repeatability' ? 'Carga ${reading['group']} · medición' : 'Punto'} ${reading['slot']}',
              ),
              DetailField(
                'Carga utilizada (${test['unit']})',
                valueLabel(reading['load']),
              ),
              DetailField('Indicación', valueLabel(reading['indication'])),
              DetailField('Retorno a cero', valueLabel(reading['zero'])),
            ],
            DetailField(
              'Observaciones',
              valueLabel(trialSetup(input)['notes']),
            ),
            if (objects(input['retainedReadings']).isNotEmpty)
              Text(
                '${objects(input['retainedReadings']).length} mediciones retiradas, excluidas del resultado.',
              ),
          ] else
            for (final point in objects(test['points'])) ...[
              const SizedBox(height: 8),
              Text(
                '${point['order']}. ${point['label']} · carga ${point['load']} ${test['unit']}',
                style: const TextStyle(fontSize: 12),
              ),
              for (final reading in objects(
                input['readings'],
              ).where((r) => r['pointId'] == point['id'])) ...[
                DetailField('Indicación', valueLabel(reading['indication'])),
                DetailField('Retorno a cero', valueLabel(reading['zero'])),
              ],
            ],
        ],
      ),
    );
  }
}

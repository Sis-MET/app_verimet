import 'package:flutter/material.dart';

import '../../core/domain/reading_evaluation.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';
import 'labeled_field.dart';

/// Tabla de captura de una prueba: una fila por posicion o punto, con la
/// lectura a la derecha y su error al lado.
///
/// El error se calcula mientras se escribe, no al terminar: si una esquina
/// esta fuera de tolerancia conviene verlo con la pesa todavia encima, para
/// poder repetir la lectura en el momento.
class ReadingsCapture extends StatefulWidget {
  const ReadingsCapture({
    required this.readings,
    required this.onChanged,
    required this.loadDescription,
    required this.toleranceLabel,
    required this.footer,
    super.key,
  });

  final List<ReadingEvaluation> readings;

  /// Nueva lectura para la fila `index`.
  final void Function(int index, String value) onChanged;

  /// Que carga se pone y donde ("Carga de prueba 20,00 kg (1/3 del alcance)").
  final Widget loadDescription;

  /// Criterio de aceptacion, arriba a la derecha ("Tol. ±0,02").
  final String toleranceLabel;

  /// Resumen de la prueba: dispersion o error maximo, y el veredicto.
  final Widget footer;

  @override
  State<ReadingsCapture> createState() => _ReadingsCaptureState();
}

class _ReadingsCaptureState extends State<ReadingsCapture> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = <TextEditingController>[
      for (final reading in widget.readings)
        TextEditingController(text: reading.rawValue),
    ];
  }

  @override
  void didUpdateWidget(ReadingsCapture oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Al empezar otra verificacion cambian las filas bajo los mismos
    // controladores: hay que reconstruirlos o el operario veria las lecturas
    // del equipo anterior.
    if (widget.readings.length != _controllers.length) {
      for (final controller in _controllers) {
        controller.dispose();
      }
      _controllers = <TextEditingController>[
        for (final reading in widget.readings)
          TextEditingController(text: reading.rawValue),
      ];
      return;
    }

    for (var i = 0; i < widget.readings.length; i++) {
      final value = widget.readings[i].rawValue;
      if (_controllers[i].text != value) _controllers[i].text = value;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: widget.loadDescription),
            const SizedBox(width: 10),
            Text(
              widget.toleranceLabel,
              style: TextStyle(fontSize: 11.5, color: palette.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < widget.readings.length; i++)
          _ReadingRow(
            reading: widget.readings[i],
            controller: _controllers[i],
            onChanged: (value) => widget.onChanged(i, value),
          ),
        const SizedBox(height: 14),
        widget.footer,
      ],
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.reading,
    required this.controller,
    required this.onChanged,
  });

  final ReadingEvaluation reading;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(reading.label, style: const TextStyle(fontSize: 13.5)),
          ),
          const SizedBox(width: 10),
          ReadingField(controller: controller, onChanged: onChanged),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Text(
              reading.formattedError,
              textAlign: TextAlign.right,
              style: AppTextStyles.reading(
                context,
                color: reading.isOutOfTolerance
                    ? palette.fail
                    : palette.mutedStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pie de una prueba: la cifra que decide y el veredicto al que lleva.
class ReadingsFooter extends StatelessWidget {
  const ReadingsFooter({required this.summary, required this.badge, super.key});

  final String summary;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            summary,
            style: TextStyle(
              fontSize: 12.5,
              color: IndustryPalette.of(context).muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        badge,
      ],
    );
  }
}

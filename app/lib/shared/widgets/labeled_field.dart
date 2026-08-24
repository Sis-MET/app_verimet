import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Campo del sistema: rotulo encima, caja recta debajo.
///
/// El rotulo va fuera y no flotando dentro del campo: con el equipo en la mano
/// y el campo ya relleno, un label flotante deja de leerse justo cuando hay
/// que comprobar que se escribio donde tocaba.
class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.onChanged,
    this.minHeight = 46,
    this.fontSize = 16,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;

  /// 46 px por defecto: se escribe de pie y con guantes.
  final double minHeight;

  /// 16 px por defecto, que es el minimo que iOS no amplia al enfocar.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, height: 1.3, color: palette.text.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 5),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textAlign: textAlign,
            onChanged: onChanged,
            style: TextStyle(fontSize: fontSize, color: palette.text),
          ),
        ),
      ],
    );
  }
}

/// Campo de lectura de balanza: monoespaciado, alineado a la derecha y con
/// teclado numerico con coma.
///
/// Va aparte de [LabeledField] porque su contenido se compara en columna con
/// las lecturas de arriba y abajo; con tipografia proporcional los decimales
/// no se alinean y la comparacion visual se pierde.
class ReadingField extends StatelessWidget {
  const ReadingField({
    required this.controller,
    required this.onChanged,
    this.width = 104,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        style: AppTextStyles.reading(context, size: 16, color: palette.text),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
      ),
    );
  }
}

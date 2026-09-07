import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/shared/widgets/labeled_field.dart';

/// Localiza el control de un campo a partir del rotulo que lleva encima.
///
/// El sistema pone el rotulo fuera de la caja (`LabeledInput`) en vez de en
/// `InputDecoration.labelText`, asi que el texto ya no es descendiente del
/// campo: hay que bajar desde el grupo que los contiene a los dos.
Finder fieldLabeled(String label, {Type type = TextFormField}) =>
    find.descendant(
      of: find.widgetWithText(LabeledInput, label),
      matching: find.byType(type),
    );

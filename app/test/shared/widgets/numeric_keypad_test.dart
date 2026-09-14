import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/shared/widgets/numeric_keypad.dart';

TextEditingValue _at(String text, [int? offset]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset ?? text.length),
);

void main() {
  group('teclas del teclado numerico', () {
    test('los digitos entran en el cursor y reemplazan lo seleccionado', () {
      expect(KeypadEdit.digit(_at('12', 1), '5').text, '152');
      final selected = const TextEditingValue(
        text: '12,34',
        selection: TextSelection(baseOffset: 3, extentOffset: 5),
      );
      expect(KeypadEdit.digit(selected, '9').text, '12,9');
    });

    test('la coma entra una sola vez y al principio escribe "0,"', () {
      expect(KeypadEdit.comma(_at('')).text, '0,');
      expect(KeypadEdit.comma(_at('-')).text, '-0,');
      expect(KeypadEdit.comma(_at('12')).text, '12,');
      expect(KeypadEdit.comma(_at('12,5')).text, '12,5');
      // Una lectura sugerida puede traer punto: tampoco admite otra coma.
      expect(KeypadEdit.comma(_at('12.5')).text, '12.5');
    });

    test('el signo va delante este donde este el cursor y se quita', () {
      final negative = KeypadEdit.toggleSign(_at('0,02', 2));
      expect(negative.text, '-0,02');
      expect(negative.selection.baseOffset, 3);
      expect(KeypadEdit.toggleSign(negative).text, '0,02');
      expect(KeypadEdit.toggleSign(_at('')).text, '-');
      expect(KeypadEdit.toggleSign(_at('-')).text, '');
    });

    test('borrar quita el caracter anterior o lo seleccionado', () {
      expect(KeypadEdit.backspace(_at('12,5')).text, '12,');
      expect(KeypadEdit.backspace(_at('12,5', 0)).text, '12,5');
      const selected = TextEditingValue(
        text: '12,5',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(KeypadEdit.backspace(selected).text, '5');
    });
  });
}

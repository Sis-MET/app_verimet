import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Teclado numerico propio para las lecturas de una verificacion.
///
/// El teclado del sistema lo decide cada fabricante: hay telefonos sin
/// separador decimal, otros con solo punto y otros sin signo menos. Este es
/// igual en todos: digitos, coma, signo y borrar, con teclas grandes para
/// usarlo de pie y con guantes.
///
/// Los campos que lo usan se declaran con [KeypadInput], que les pone
/// `TextInputType.none` para que el sistema no abra el suyo. No se cambia el
/// control de entrada global (`TextInput.setInputControl`): al devolverselo al
/// sistema, un campo de texto enfocado justo despues se quedaba sin teclado.
///
/// Cada tecla edita el campo enfocado a traves de su controlador y avisa con el
/// mismo `onChanged` que usa el teclado del sistema, asi que la validacion y el
/// autoguardado del borrador no distinguen de donde vino la pulsacion.
class NumericKeypadController extends ChangeNotifier {
  final Set<_KeypadInputState> _fields = <_KeypadInputState>{};
  _KeypadInputState? _active;
  bool _disposed = false;

  /// Hay un campo del teclado enfocado.
  bool get visible => _active != null;

  /// El campo enfocado admite valores negativos (indicacion, retorno a cero).
  bool get allowNegative => _active?.widget.allowNegative ?? false;

  void digit(String value) => _edit((v) => KeypadEdit.digit(v, value));
  void comma() => _edit(KeypadEdit.comma);
  void backspace() => _edit(KeypadEdit.backspace);
  void clear() => _edit((_) => TextEditingValue.empty);
  void toggleSign() {
    if (allowNegative) _edit(KeypadEdit.toggleSign);
  }

  /// Pasa al siguiente campo del teclado en orden de lectura, de arriba abajo.
  /// Despues del ultimo, cierra el teclado.
  void next() {
    final current = _active;
    if (current == null) return;
    final from = current.focusNode.rect;
    final following =
        _fields
            .where(
              (field) =>
                  field != current &&
                  field.focusNode.context != null &&
                  field.focusNode.canRequestFocus &&
                  _readingOrder(field.focusNode.rect, from) > 0,
            )
            .toList()
          ..sort((a, b) => _readingOrder(a.focusNode.rect, b.focusNode.rect));
    if (following.isEmpty) {
      close();
    } else {
      following.first.focusNode.requestFocus();
    }
  }

  /// Cierra el teclado quitando el foco al campo.
  void close() => _active?.focusNode.unfocus();

  static int _readingOrder(Rect a, Rect b) => (a.top - b.top).abs() > 1
      ? a.top.compareTo(b.top)
      : a.left.compareTo(b.left);

  void _edit(TextEditingValue Function(TextEditingValue) change) {
    final field = _active;
    if (field == null) return;
    final before = field.widget.controller.value;
    final after = change(before);
    if (after == before) return;
    field.widget.controller.value = after;
    if (after.text != before.text) field.widget.onChanged?.call(after.text);
  }

  void _register(_KeypadInputState field) => _fields.add(field);

  void _unregister(_KeypadInputState field) {
    _fields.remove(field);
    if (_active == field) {
      _active = null;
      // Se llega aqui al desmontar el campo, con el arbol bloqueado: el panel
      // se redibuja en el cuadro siguiente, si la pantalla sigue abierta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _focusChanged(_KeypadInputState field, bool focused) {
    if (focused) {
      _active = field;
      notifyListeners();
      // El panel aparece en este cuadro y le quita alto a la pantalla: el
      // campo se vuelve a mostrar cuando ya se sabe cuanto sitio queda. Va
      // despues de que el propio campo lleve el cursor a la vista.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(() => field._reveal()),
      );
    } else if (_active == field) {
      _active = null;
      notifyListeners();
    }
  }
}

/// Ediciones de cada tecla, sin estado, sobre el valor del campo.
abstract final class KeypadEdit {
  static TextEditingValue digit(TextEditingValue value, String digit) =>
      _replaceSelection(value, digit);

  /// La coma solo entra una vez. Al principio del numero entra como "0,",
  /// que es como se escribe una lectura menor que uno.
  static TextEditingValue comma(TextEditingValue value) {
    final selection = _selection(value);
    final kept =
        value.text.substring(0, selection.start) +
        value.text.substring(selection.end);
    if (kept.contains(',') || kept.contains('.')) return value;
    final before = value.text
        .substring(0, selection.start)
        .replaceFirst('-', '');
    return _replaceSelection(value, before.isEmpty ? '0,' : ',');
  }

  /// El signo va siempre delante, este donde este el cursor. Pulsarlo otra
  /// vez lo quita.
  static TextEditingValue toggleSign(TextEditingValue value) {
    final selection = _selection(value);
    if (value.text.startsWith('-')) {
      return TextEditingValue(
        text: value.text.substring(1),
        selection: TextSelection.collapsed(
          offset: (selection.end - 1).clamp(0, value.text.length - 1),
        ),
      );
    }
    return TextEditingValue(
      text: '-${value.text}',
      selection: TextSelection.collapsed(offset: selection.end + 1),
    );
  }

  static TextEditingValue backspace(TextEditingValue value) {
    final selection = _selection(value);
    if (!selection.isCollapsed) return _replaceSelection(value, '');
    if (selection.start == 0) return value;
    return TextEditingValue(
      text:
          value.text.substring(0, selection.start - 1) +
          value.text.substring(selection.start),
      selection: TextSelection.collapsed(offset: selection.start - 1),
    );
  }

  static TextSelection _selection(TextEditingValue value) =>
      value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);

  static TextEditingValue _replaceSelection(
    TextEditingValue value,
    String insert,
  ) {
    final selection = _selection(value);
    return TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, insert),
      selection: TextSelection.collapsed(
        offset: selection.start + insert.length,
      ),
    );
  }
}

/// Da acceso al teclado a los campos que cuelgan de una pantalla.
class NumericKeypadScope extends InheritedWidget {
  const NumericKeypadScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final NumericKeypadController controller;

  /// Sin dependencia: los campos no se reconstruyen con cada tecla.
  static NumericKeypadController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NumericKeypadScope>()?.controller;

  @override
  bool updateShouldNotify(NumericKeypadScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Conecta un campo de texto al teclado numerico de la pantalla.
///
/// [builder] recibe el [FocusNode] que lo conecta: el campo debe usarlo y
/// declararse con `TextInputType.none`. Sin [NumericKeypadScope] alrededor
/// recibe `null` y el campo se queda con el teclado del sistema.
class KeypadInput extends StatefulWidget {
  const KeypadInput({
    required this.controller,
    required this.builder,
    this.onChanged,
    this.allowNegative = true,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool allowNegative;
  final Widget Function(BuildContext context, FocusNode? keypadFocus) builder;

  @override
  State<KeypadInput> createState() => _KeypadInputState();
}

class _KeypadInputState extends State<KeypadInput> {
  final FocusNode focusNode = FocusNode(debugLabel: 'keypad');
  NumericKeypadController? keypad;

  @override
  void initState() {
    super.initState();
    // Se registra antes que el campo: el panel se pide en el mismo ciclo en
    // que el campo recibe el foco.
    focusNode.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = NumericKeypadScope.maybeOf(context);
    if (scope != keypad) {
      keypad?._unregister(this);
      keypad = scope?.._register(this);
    }
  }

  void _focusChanged() => keypad?._focusChanged(this, focusNode.hasFocus);

  /// Muestra el campo con su rotulo encima y aire debajo, sobre el panel.
  void _reveal() {
    final box = focusNode.context?.findRenderObject();
    if (!mounted || !focusNode.hasFocus || box is! RenderBox || !box.attached) {
      return;
    }
    box.showOnScreen(
      rect: Rect.fromLTRB(0, -36, box.size.width, box.size.height + 48),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    keypad?._unregister(this);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, keypad == null ? null : focusNode);
}

/// Panel de teclas. Ocupa el sitio de la barra de acciones mientras hay un
/// campo del teclado enfocado.
///
/// Distribucion de telefono, con el 1 arriba:
///
///     1  2  3  ⌫
///     4  5  6  −
///     7  8  9  Siguiente
///     ,  0  Listo
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({required this.controller, super.key});

  final NumericKeypadController controller;

  static const double _gap = 6;
  static const double _keyHeight = 52;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return TextFieldTapRegion(
      // Las teclas nunca le quitan el foco al campo que estan escribiendo.
      child: ExcludeFocus(
        child: ColoredBox(
          color: palette.bg,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - _gap * 3) / 4;
                    Widget digit(String value) => _KeypadKey(
                      key: ValueKey('keypad-$value'),
                      width: width,
                      label: value,
                      onTap: () => controller.digit(value),
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          spacing: _gap,
                          children: [
                            digit('1'),
                            digit('2'),
                            digit('3'),
                            _KeypadKey(
                              key: const ValueKey('keypad-backspace'),
                              width: width,
                              icon: Icons.backspace_outlined,
                              semanticLabel: 'Borrar',
                              onTap: controller.backspace,
                              onLongPress: controller.clear,
                            ),
                          ],
                        ),
                        const SizedBox(height: _gap),
                        Row(
                          spacing: _gap,
                          children: [
                            digit('4'),
                            digit('5'),
                            digit('6'),
                            _KeypadKey(
                              key: const ValueKey('keypad-sign'),
                              width: width,
                              label: '−',
                              glyph: true,
                              semanticLabel: 'Signo menos',
                              onTap: controller.allowNegative
                                  ? controller.toggleSign
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: _gap),
                        Row(
                          spacing: _gap,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Row(
                                  spacing: _gap,
                                  children: [
                                    digit('7'),
                                    digit('8'),
                                    digit('9'),
                                  ],
                                ),
                                const SizedBox(height: _gap),
                                Row(
                                  spacing: _gap,
                                  children: [
                                    _KeypadKey(
                                      key: const ValueKey('keypad-comma'),
                                      width: width,
                                      label: ',',
                                      glyph: true,
                                      semanticLabel: 'Coma decimal',
                                      onTap: controller.comma,
                                    ),
                                    digit('0'),
                                    _KeypadKey(
                                      key: const ValueKey('keypad-done'),
                                      width: width,
                                      label: 'Listo',
                                      small: true,
                                      semanticLabel: 'Ocultar teclado',
                                      onTap: controller.close,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _KeypadKey(
                              key: const ValueKey('keypad-next'),
                              width: width,
                              height: _keyHeight * 2 + _gap,
                              label: 'Siguiente',
                              small: true,
                              icon: Icons.arrow_downward_rounded,
                              semanticLabel: 'Siguiente campo',
                              primary: true,
                              onTap: controller.next,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.width,
    this.height = NumericKeypad._keyHeight,
    this.label,
    this.icon,
    this.semanticLabel,
    this.onTap,
    this.onLongPress,
    this.primary = false,
    this.small = false,
    this.glyph = false,
    super.key,
  });

  final double width;
  final double height;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool primary;

  /// Rotulo de palabra ("Listo") en vez de cifra: cuerpo mas pequeno.
  final bool small;

  /// Coma y signo: a cuerpo de cifra se quedaban en un punto casi invisible
  /// al lado de los digitos.
  final bool glyph;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final enabled = onTap != null;
    final ink = primary ? palette.card : palette.text;
    final corners = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Opacity(
        // Una tecla que no aplica se apaga, no desaparece: la distribucion no
        // cambia de un campo a otro.
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: primary ? palette.accent : palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: corners,
            side: BorderSide(color: primary ? palette.accent : palette.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            onLongPress: onLongPress,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null)
                    Icon(icon, size: small ? 20 : 24, color: ink),
                  if (icon != null && label != null) const SizedBox(height: 4),
                  if (label != null)
                    Text(
                      label!,
                      style: TextStyle(
                        fontFamily: AppFonts.heading,
                        fontFamilyFallback: AppFonts.fallback,
                        fontWeight: FontWeight.w600,
                        fontSize: small
                            ? 16
                            : glyph
                            ? 36
                            : 26,
                        height: 1,
                        color: ink,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

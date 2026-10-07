import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/measurement_format.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'draft_controller.dart' show normalizedDecimal;
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Motor de formularios del area de cliente.
///
/// Un formulario se declara como una lista de [CustomerField] y [CustomerForm]
/// se encarga del resto: pintar el control que toca segun `kind`, validar,
/// avisar al salir con cambios sin guardar y congelar UUID y payload cuando se
/// pierde una respuesta, para que reintentar no duplique.
///
/// Vivia dentro de `customer_configuration.dart`, mezclado con las pantallas
/// que lo usan. Esta aparte porque es infraestructura: quien anade un
/// formulario no deberia leer 1000 lineas de pantallas para encontrarlo.

Future<Json> customerRead(
  MobileSession session,
  String section, [
  Json filters = const {},
]) => session.api.rpc('ivmet_customer_read', {
  'section': section,
  'filters': filters,
});

class CustomerField {
  const CustomerField(
    this.keyName,
    this.label, {
    this.required = true,
    this.kind = 'text',
    this.options = const {},
    this.max = 150,
    this.readOnly = false,
  });
  final String keyName, label, kind;
  final bool required, readOnly;
  final int max;
  final Map<String, String> options;
}

/// UUID y payload congelados al perder una respuesta: reintentar no duplica.
class CustomerForm extends StatefulWidget {
  const CustomerForm({
    required this.session,
    required this.title,
    required this.action,
    required this.fields,
    required this.initial,
    this.payload,
    this.notice,
    this.preview,
    this.afterFields,
    this.submitLabel = 'Guardar',
    this.externalDirty = false,
    super.key,
  });
  final MobileSession session;
  final String title, action, submitLabel;
  final List<CustomerField> fields;
  final Json initial;
  final Json Function(Json)? payload;
  final String? notice;
  final Widget? preview;
  final Widget? afterFields;
  final bool externalDirty;
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final form = GlobalKey<FormState>();
  late Json values = Map.of(widget.initial);
  String requestId = const Uuid().v4();
  Json? pending;
  bool busy = false, dirty = false, leaving = false;
  String? error;
  Future<void> save() async {
    if (busy) return;
    if (!form.currentState!.validate()) {
      revealFirstFormError(context, form);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sent = _normalizedValues();
      pending ??= object(
        jsonDecode(jsonEncode(widget.payload?.call(sent) ?? sent)),
      );
      await widget.session.api.rpc('ivmet_customer_mutate', {
        'action': widget.action,
        'payload': pending,
        'request_id': requestId,
      });
      if (!mounted) return;
      setState(() {
        leaving = true;
        dirty = false;
        busy = false;
      });
      Navigator.of(context).pop(true);
    } on MobileFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message;
        if (!failure.offline && (failure.status ?? 0) < 500) {
          pending = null;
          requestId = const Uuid().v4();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No pudimos confirmar el guardado. Reintenta sin cambiar los datos.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Lo que viaja. Un decimal se teclea con coma o con punto, pero sale con
  /// punto: es lo que espera Supabase.
  Json _normalizedValues() => {
    for (final entry in values.entries)
      entry.key:
          entry.value is String &&
              widget.fields.any(
                (field) =>
                    field.keyName == entry.key && field.kind == 'decimal',
              )
          ? normalizedDecimal(entry.value as String)
          : entry.value,
  };

  Future<void> askLeave() async {
    if (busy) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir del formulario?'),
        content: Text(
          pending != null
              ? 'El guardado no está confirmado. Puedes reintentar aquí o revisar el registro al volver.'
              : 'Se perderán los cambios que no hayas guardado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        leaving ||
        (!busy && !dirty && !widget.externalDirty && pending == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) askLeave();
    },
    child: OnlinePage(
      title: widget.title,
      // La accion queda fija a la vista: antes habia que bajar hasta el final
      // del formulario para encontrarla.
      floating: WizardNavPill.action(
        label: busy
            ? 'Guardando…'
            : pending != null
            ? 'Reintentar guardado'
            : widget.submitLabel,
        icon: Icons.check_rounded,
        onNext: busy ? null : save,
      ),
      child: Form(
        key: form,
        onChanged: () {
          if (!dirty) setState(() => dirty = true);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            WizardNavPill.contentPadding,
          ),
          children: [
            if (widget.notice != null) Notice(widget.notice!),
            if (widget.preview != null) widget.preview!,
            if (error != null) Notice(error!, icon: Icons.error_outline),
            if (pending != null && !busy)
              const Notice(
                'Respuesta pendiente. Reintenta con los mismos datos para evitar duplicados.',
              ),
            for (final field in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: field.kind == 'bool'
                    ? FormField<bool>(
                        initialValue: values[field.keyName] == true,
                        validator: (_) =>
                            field.required && values[field.keyName] != true
                            ? 'Debes confirmar para continuar.'
                            : null,
                        builder: (state) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(field.label),
                              value: values[field.keyName] == true,
                              onChanged: busy || pending != null
                                  ? null
                                  : (v) => setState(() {
                                      values[field.keyName] = v;
                                      dirty = true;
                                      state.didChange(v);
                                    }),
                            ),
                            if (state.hasError)
                              // Mismo trato que el `errorText` de Material:
                              // cuerpo pequeno y separado del control. A
                              // tamano completo y pegado al checkbox se leia
                              // como una opcion mas de la lista.
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 2),
                                child: Text(
                                  state.errorText!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : field.kind == 'multi'
                    ? FormField<List<String>>(
                        validator: (_) =>
                            field.required &&
                                (values[field.keyName] as List? ?? []).isEmpty
                            ? 'Selecciona al menos una planta.'
                            : null,
                        builder: (state) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(field.label),
                            for (final option in field.options.entries)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(option.value),
                                value: (values[field.keyName] as List? ?? [])
                                    .contains(option.key),
                                onChanged: busy || pending != null
                                    ? null
                                    : (v) => setState(() {
                                        final selected = List<String>.from(
                                          values[field.keyName] as List? ?? [],
                                        );
                                        v == true
                                            ? selected.add(option.key)
                                            : selected.remove(option.key);
                                        values[field.keyName] = selected;
                                        dirty = true;
                                        state.didChange(selected);
                                      }),
                              ),
                            if (state.hasError)
                              // Mismo trato que el `errorText` de Material:
                              // cuerpo pequeno y separado del control. A
                              // tamano completo y pegado al checkbox se leia
                              // como una opcion mas de la lista.
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 2),
                                child: Text(
                                  state.errorText!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : field.kind == 'select'
                    ? LabeledInput(
                        label: field.label,
                        child: DropdownButtonFormField<String>(
                          initialValue: values[field.keyName]?.toString() ?? '',
                          isExpanded: true,
                          items: field.options.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy || pending != null
                              ? null
                              : (v) => setState(() {
                                  values[field.keyName] = v;
                                  dirty = true;
                                }),
                          validator: (v) =>
                              field.required && (v == null || v.isEmpty)
                              ? 'Selecciona una opción.'
                              : null,
                        ),
                      )
                    : LabeledInput(
                        label: field.label,
                        child: TextFormField(
                          // Hacia la pantalla, coma y sin ceros de relleno.
                          initialValue: field.kind == 'decimal'
                              ? MeasurementFormat.display(
                                  values[field.keyName]?.toString() ?? '',
                                )
                              : values[field.keyName]?.toString() ?? '',
                          readOnly: field.readOnly || busy || pending != null,
                          maxLength: field.max,
                          keyboardType: field.kind == 'decimal'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(
                            hintText: field.kind == 'date'
                                ? 'AAAA-MM-DD'
                                : null,
                          ),
                          onChanged: (v) {
                            values[field.keyName] = v;
                            if (!dirty) setState(() => dirty = true);
                          },
                          validator: (v) {
                            if (field.required && (v ?? '').trim().isEmpty) {
                              return 'Completa este campo.';
                            }
                            if (field.kind == 'decimal' &&
                                (v ?? '').trim().isNotEmpty &&
                                !RegExp(
                                  r'^(0|[1-9]\d{0,9})(\.\d{1,9})?$',
                                ).hasMatch(normalizedDecimal(v!))) {
                              return 'Usa hasta 9 decimales, sin miles.';
                            }
                            if (field.kind == 'date' &&
                                !RegExp(
                                  r'^\d{4}-\d{2}-\d{2}$',
                                ).hasMatch(v ?? '')) {
                              return 'Usa AAAA-MM-DD.';
                            }
                            return null;
                          },
                        ),
                      ),
              ),
            if (widget.afterFields != null)
              AbsorbPointer(
                absorbing: busy || pending != null,
                child: widget.afterFields!,
              ),
          ],
        ),
      ),
    ),
  );
}

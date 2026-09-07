import 'package:flutter/material.dart';
import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import 'mobile_api.dart';

Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

class OnlinePage extends StatelessWidget {
  const OnlinePage({
    required this.title,
    required this.child,
    this.actions,
    super.key,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(child: child),
  );
}

/// Nota al pie de una pantalla: alcance legal, privacidad, aviso de estado.
///
/// Es texto secundario y se pinta como tal — una regla de acero a la
/// izquierda y cuerpo pequeno, sin relleno. Antes iba en caja rellena y con
/// 16 px de aire: apiladas de tres en tres tapaban la pantalla y competian
/// con las acciones.
///
/// La regla se dibuja como una pastilla propia y no como borde del bloque:
/// asi tiene las puntas redondeadas del sistema en vez de cortarse en angulo
/// recto contra el texto.
///
/// Reserva su propio aire arriba y abajo. Solo llevaba relleno superior, y
/// como casi siempre precede a un campo, el aviso terminaba apoyado en la caja
/// del campo: los dos bloques se leian como uno solo.
class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    this.icon = Icons.info_outline,
    this.alert = false,
    super.key,
  });
  final String text;
  final IconData icon;

  /// Reserva el oxido a lo que bloquea trabajo (falta un dato para configurar).
  final bool alert;
  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final rule = alert ? palette.fail : palette.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: rule,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: alert ? palette.fail : palette.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemotePanel extends StatefulWidget {
  const RemotePanel({
    required this.load,
    required this.builder,
    this.dataKey = '',
    this.frameTitle,
    super.key,
  });
  final Future<Json> Function() load;
  final Widget Function(Json data) builder;
  final String dataKey;
  final String? frameTitle;
  @override
  State<RemotePanel> createState() => _RemotePanelState();
}

class _RemotePanelState extends State<RemotePanel> {
  late Future<Json> future = widget.load();
  @override
  void didUpdateWidget(RemotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataKey != widget.dataKey) future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) => widget.frameTitle == null
        ? child
        : OnlinePage(title: widget.frameTitle!, child: child);
    return FutureBuilder<Json>(
      future: future,
      builder: (context, snapshot) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: snapshot.connectionState != ConnectionState.done
            ? frame(
                const Center(
                  key: ValueKey('remote-loading'),
                  child: CircularProgressIndicator(),
                ),
              )
            : snapshot.hasError
            ? frame(
                Center(
                  key: const ValueKey('remote-error'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Notice(
                          snapshot.error is MobileFailure
                              ? (snapshot.error as MobileFailure).message
                              : 'No se pudo cargar la información.',
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => future = widget.load()),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : KeyedSubtree(
                key: ValueKey('remote-data-${widget.dataKey}'),
                child: widget.builder(snapshot.data!),
              ),
      ),
    );
  }
}

String valueLabel(Object? value) =>
    value == null || value == '' ? 'No registrado' : value.toString();
String customerEquipmentCode(Json equipment) {
  final code = equipment['cod_interno']?.toString().trim() ?? '';
  return code.isEmpty ? 'Sin código interno' : code;
}

String testLabel(Object? value) => switch (value) {
  'linearity' => 'Linealidad',
  'repeatability' => 'Repetibilidad',
  'eccentricity' => 'Excentricidad',
  _ => valueLabel(value),
};
String verdictLabel(Object? value) => switch (value) {
  'pass' => 'Conforme',
  'fail' => 'No conforme',
  'inconclusive' => 'No concluyente',
  _ => 'Sin evaluación',
};
String dateLabel(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'No registrado';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// Ficha de solo lectura: rotulo pequeno arriba, valor debajo.
///
/// El aire de dentro del par y el de fuera estaban casi igualados (3 px contra
/// 12 px, y el interlineado del valor se comia la diferencia): el rotulo
/// quedaba tan cerca del valor de la ficha anterior como del suyo propio y la
/// pantalla se leia como un bloque continuo. Ahora la separacion entre fichas
/// es varias veces la de dentro de la ficha, que es lo que agrupa cada par.
class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.caption(context, size: 11)),
          const SizedBox(height: 3),
          SelectableText(
            valueLabel(value),
            style: TextStyle(
              fontSize: 14.5,
              // Interlinea corta: el valor casi siempre es una linea, y con la
              // del cuerpo (1,55) el par se separaba por dentro tanto como por
              // fuera.
              height: 1.3,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Apartado plegable del expediente.
///
/// `ExpansionTile` no admite margen y el sistema le da contorno redondeado:
/// apiladas quedaban pegadas borde con borde y se leian como una sola caja
/// partida. Este envoltorio les pone el aire que les falta.
class EvidenceSection extends StatelessWidget {
  const EvidenceSection({
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ExpansionTile(
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      initiallyExpanded: initiallyExpanded,
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// Vista completa del expediente que será enviado. No oculta campos ni redondea
/// cadenas decimales; el consentimiento corresponde al snapshot mostrado.
class EvidenceTree extends StatelessWidget {
  const EvidenceTree(this.value, {super.key});
  final Object? value;
  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in (value as Map).entries)
            if (entry.value is Map || entry.value is List)
              EvidenceSection(
                title: _fieldLabel(entry.key),
                children: [EvidenceTree(entry.value)],
              )
            else
              DetailField(_fieldLabel(entry.key), entry.value),
        ],
      );
    }
    if (value is List) {
      final palette = IndustryPalette.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < (value as List).length; i++) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 8 : 20, bottom: 2),
              child: Text(
                'REGISTRO ${i + 1}',
                style: AppTextStyles.caption(context, size: 10.5),
              ),
            ),
            EvidenceTree((value as List)[i]),
            if (i < (value as List).length - 1)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Divider(height: 1, color: palette.hairline),
              ),
          ],
          if ((value as List).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Sin registros',
                style: TextStyle(fontSize: 13.5, color: palette.muted),
              ),
            ),
        ],
      );
    }
    return SelectableText(valueLabel(value));
  }
}

/// Clave cruda del expediente convertida en rotulo: `area_id` -> `Area id`.
///
/// Solo toca el rotulo. El valor se muestra tal cual llega, porque el
/// expediente es lo que se consiente enviar y no puede reescribirse.
String _fieldLabel(Object? key) {
  final words = key.toString().replaceAll('_', ' ').trim();
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

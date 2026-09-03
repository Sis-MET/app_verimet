import 'package:flutter/material.dart';
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
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: rule, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: alert ? palette.fail : palette.muted),
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

class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        SelectableText(valueLabel(value)),
      ],
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
        children: [
          for (final entry in (value as Map).entries)
            if (entry.value is Map || entry.value is List)
              ExpansionTile(
                title: Text(entry.key.toString().replaceAll('_', ' ')),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [EvidenceTree(entry.value)],
              )
            else
              DetailField(
                entry.key.toString().replaceAll('_', ' '),
                entry.value,
              ),
        ],
      );
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < (value as List).length; i++) ...[
            Text(
              'Registro ${i + 1}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            EvidenceTree((value as List)[i]),
            const Divider(),
          ],
          if ((value as List).isEmpty) const Text('Sin registros'),
        ],
      );
    }
    return SelectableText(valueLabel(value));
  }
}

import 'package:flutter/material.dart';
import 'mobile_api.dart';

Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => page,
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );

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

class Notice extends StatelessWidget {
  const Notice(this.text, {this.icon = Icons.info_outline, super.key});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
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
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return frame(const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return frame(
            Center(
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
                      onPressed: () => setState(() => future = widget.load()),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return widget.builder(snapshot.data!);
      },
    );
  }
}

String valueLabel(Object? value) =>
    value == null || value == '' ? 'No registrado' : value.toString();
String testLabel(Object? value) => switch (value) {
  'linearity' => 'Error de indicación',
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

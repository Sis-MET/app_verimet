import 'package:flutter/material.dart';
import 'draft_screen.dart';
import 'history_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'customer_configuration.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    required this.session,
    this.plantId,
    this.areaId,
    super.key,
  });
  final MobileSession session;
  final String? plantId;
  final String? areaId;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late String? plantId = widget.plantId;
  String search = '';
  int page = 1;
  int revision = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balanzas', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Código o marca',
                prefixIcon: Icon(Icons.search),
                helperText: 'Pulsa buscar en el teclado para consultar.',
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => setState(() {
                search = value.trim();
                page = 1;
              }),
            ),
            if (widget.plantId == null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: plantId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Planta'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todas mis plantas'),
                    ),
                    for (final p in objects(widget.session.bootstrap['plants']))
                      DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text(valueLabel(p['name'])),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    plantId = value == '' ? null : value;
                    page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: RemotePanel(
          dataKey: '$plantId|${widget.areaId}|$search|$page|$revision',
          load: () => widget.session.api.read('instruments', {
            'plantId': plantId,
            'areaId': widget.areaId,
            'search': search,
            'page': page,
          }),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 140),
            children: [
              Row(
                children: [
                  Expanded(child: Text('${data['total']} equipos autorizados')),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: () => setState(() => revision++),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (objects(data['items']).isEmpty)
                const Notice('No hay balanzas habilitadas para este filtro.'),
              for (final e in objects(data['items']))
                Card(
                  child: ListTile(
                    title: Text(valueLabel(e['cod_metrica'])),
                    subtitle: Text(
                      '${valueLabel(e['marca'])} · ${valueLabel(e['modelo'])}\n${e['planta']} · ${e['area']}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPage(
                      context,
                      EquipmentScreen(
                        session: widget.session,
                        equipmentId: e['id'] as String,
                      ),
                    ),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                    child: const Text('Anterior'),
                  ),
                  Text('Página $page'),
                  TextButton(
                    onPressed: page * 25 < (data['total'] as num)
                        ? () => setState(() => page++)
                        : null,
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({
    required this.session,
    required this.equipmentId,
    super.key,
  });
  final MobileSession session;
  final String equipmentId;
  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  int revision = 0;
  MobileSession get session => widget.session;
  String get equipmentId => widget.equipmentId;
  Future<void> configure(Widget page) async {
    await openPage(context, page);
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Ficha de la balanza',
    child: RemotePanel(
      dataKey: '$revision',
      load: () => session.api.read('equipment', {'equipmentId': equipmentId}),
      builder: (data) {
        final equipment = object(data['equipment']);
        final plan = data['plan'] == null ? null : object(data['plan']);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              valueLabel(equipment['cod_metrica']),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            DetailField(
              'Marca y modelo',
              '${valueLabel(equipment['marca'])} · ${valueLabel(equipment['modelo'])}',
            ),
            DetailField('Serie', equipment['serie']),
            DetailField('Ubicación', equipment['ubicacion']),
            for (final range in objects(data['ranges']))
              Notice(
                'Rango ${range['numero_rango']}: ${range['capacidad_max']} ${range['unidad']} · división ${range['division_escala']}',
              ),
            const Divider(),
            Notice(
              data['customerValidated'] == true
                  ? 'Ficha validada por tu empresa. Las correcciones permanecen privadas.'
                  : 'Revisa la ficha y confirma los datos antes de capturar. Si cambió el catálogo, vuelve a validarla.',
            ),
            FilledButton.icon(
              onPressed: () => configure(
                EquipmentValidation(session: session, equipmentId: equipmentId),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Validar o actualizar ficha'),
            ),
            OutlinedButton(
              onPressed: () => configure(
                CustomerSetupScreen(session: session, equipmentId: equipmentId),
              ),
              child: const Text('Gestionar mis áreas y patrones'),
            ),
            if (session.quality)
              OutlinedButton(
                onPressed: () => configure(
                  CustomerSetupScreen(
                    session: session,
                    initialSection: 'plans',
                    equipmentId: equipmentId,
                  ),
                ),
                child: const Text('Definir o asignar plan'),
              ),
            if (session.quality && data['customerValidated'] == true)
              OutlinedButton.icon(
                onPressed: () => configure(
                  ShareEquipmentUpdate(
                    session: session,
                    equipmentId: equipmentId,
                  ),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('¿Compartir actualización con Métrica?'),
              ),
            if (plan == null)
              const Notice(
                'No hay un plan publicado y asignado. Tu jefe de calidad lo define y asigna desde la app.',
              )
            else ...[
              Text(
                valueLabel(plan['name']),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DetailField('Versión', plan['version']),
              DetailField('Procedimiento', plan['procedure']),
              for (final test in objects(plan['tests']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(testLabel(test['type'])),
                  subtitle: Text(
                    'Cada ${test['frequencyDays']} días · ${objects(test['points']).length} puntos · ${test['unit']}',
                  ),
                ),
              if (objects(data['schedule']).isNotEmpty) ...[
                const Divider(),
                Text(
                  'Vigencia por prueba',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final due in objects(data['schedule']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      due['state'] == 'OVERDUE'
                          ? Icons.error_outline
                          : due['state'] == 'DUE_SOON'
                          ? Icons.schedule
                          : Icons.check_circle_outline,
                    ),
                    title: Text(testLabel(due['type'])),
                    subtitle: Text(
                      'Próxima: ${dateLabel(due['dueAt'])}${due['lastTraceableAt'] == null ? ' · sin ejecución trazable previa' : ''}',
                    ),
                  ),
              ],
              const Notice(
                'Control interno privado. IvMET recalcula el resultado en Supabase al finalizar y deriva el próximo vencimiento de cada prueba trazable.',
              ),
              FilledButton(
                onPressed:
                    data['customerValidated'] != true ||
                        plan['finalizationEnabled'] != true
                    ? null
                    : () => openPage(
                        context,
                        DraftScreen(session: session, bundle: data),
                      ),
                child: Text(
                  plan['finalizationEnabled'] == true
                      ? 'Iniciar comprobación'
                      : 'Plan no habilitado para cálculo',
                ),
              ),
            ],
            OutlinedButton(
              onPressed: () => openPage(
                context,
                HistoryScreen(session: session, equipmentId: equipmentId),
              ),
              child: const Text('Ver historial privado'),
            ),
            OutlinedButton(
              onPressed: () => openPage(
                context,
                HistoryScreen(
                  session: session,
                  equipmentId: equipmentId,
                  drafts: true,
                ),
              ),
              child: const Text('Ver mis borradores'),
            ),
          ],
        );
      },
    ),
  );
}

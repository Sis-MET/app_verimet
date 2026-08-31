import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/presentation/providers/settings_providers.dart';
import '../../shared/widgets/app_shell.dart';
import 'catalog_screen.dart';
import 'history_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'customer_configuration.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({required this.session, super.key});
  final MobileSession session;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  AppSection section = AppSection.inicio;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted && widget.session.stage == SessionStage.ready) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final bootstrap = session.bootstrap;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: switch (section) {
                AppSection.inicio => ListView(
                  padding: kShellContentPadding,
                  children: [
                    Text(
                      'IvMET',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      valueLabel(object(bootstrap['client'])['name']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('Hola, ${session.user!['name']}'),
                    const SizedBox(height: 24),
                    const Notice(
                      'Tus verificaciones son privadas. Métrica solo recibe el expediente que autorice el jefe de calidad.',
                      icon: Icons.shield_outlined,
                    ),
                    Card(
                      child: ListTile(
                        title: const Text('Balanzas habilitadas'),
                        trailing: Text('${bootstrap['equipmentCount']}'),
                        onTap: () =>
                            setState(() => section = AppSection.verificar),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: const Text('Alertas privadas abiertas'),
                        trailing: Text('${bootstrap['openAlerts']}'),
                        onTap: () =>
                            openPage(context, HistoryScreen(session: session)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => openPage(
                        context,
                        CustomerSetupScreen(session: session),
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Áreas, patrones y planes'),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          setState(() => section = AppSection.verificar),
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva captura'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          openPage(context, HistoryScreen(session: session)),
                      icon: const Icon(Icons.history),
                      label: const Text('Historial y alertas'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => openPage(
                        context,
                        HistoryScreen(session: session, drafts: true),
                      ),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Mis borradores'),
                    ),
                    const Notice(
                      'Supabase calcula las comprobaciones internas con el perfil exacto del plan. Los resultados no son certificados de calibración ni verificaciones legales.',
                    ),
                  ],
                ),
                AppSection.verificar => CatalogScreen(session: session),
                AppSection.areas => ListView(
                  padding: kShellContentPadding,
                  children: [
                    Text(
                      'Plantas y áreas',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => openPage(
                        context,
                        CustomerSetupScreen(session: session),
                      ),
                      icon: const Icon(Icons.edit_location_outlined),
                      label: const Text('Gestionar áreas y patrones'),
                    ),
                    if (objects(bootstrap['plants']).isEmpty)
                      const Notice(
                        'No tienes plantas asignadas. Solicita su habilitación en RimMET.',
                      ),
                    for (final plant in objects(bootstrap['plants']))
                      Card(
                        child: ExpansionTile(
                          title: Text(valueLabel(plant['name'])),
                          subtitle: Text(valueLabel(plant['code'])),
                          children: [
                            ListTile(
                              title: const Text(
                                'Todas las balanzas de esta planta',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => openPage(
                                context,
                                OnlinePage(
                                  title: valueLabel(plant['name']),
                                  child: CatalogScreen(
                                    session: session,
                                    plantId: plant['id'] as String,
                                  ),
                                ),
                              ),
                            ),
                            for (final area in objects(
                              bootstrap['areas'],
                            ).where((a) => a['plantId'] == plant['id']))
                              ListTile(
                                title: Text(valueLabel(area['name'])),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => openPage(
                                  context,
                                  OnlinePage(
                                    title: valueLabel(area['name']),
                                    child: CatalogScreen(
                                      session: session,
                                      plantId: plant['id'] as String,
                                      areaId: area['id'] as String,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                AppSection.ajustes => _Settings(session),
              },
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: FloatingNavBar(
                current: section,
                onSelect: (value) => setState(() => section = value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings(this.session);
  final MobileSession session;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: kShellContentPadding,
    children: [
      Text('Mi cuenta', style: Theme.of(context).textTheme.headlineSmall),
      DetailField('Usuario', session.user!['username']),
      DetailField('Rol', session.quality ? 'Jefe de calidad' : 'Operador'),
      DetailField('Plan', session.access['planName']),
      DetailField('Fin del período', dateLabel(session.access['periodEndsAt'])),
      if (session.access['subscriptionStatus'] == 'GRACE')
        DetailField(
          'Fin de la gracia',
          dateLabel(session.access['graceEndsAt']),
        ),
      const Notice(
        'La licencia y las plantas autorizadas se validan en cada consulta. No hay modo offline.',
      ),
      SwitchListTile(
        title: const Text('Modo oscuro'),
        value: ref.watch(themeModeProvider) == ThemeMode.dark,
        onChanged: (_) => ref.read(themeModeProvider.notifier).toggleDark(),
      ),
      SwitchListTile(
        title: const Text('Texto grande'),
        value: ref.watch(largeTextProvider),
        onChanged: (_) => ref.read(largeTextProvider.notifier).toggle(),
      ),
      OutlinedButton(
        onPressed: session.refresh,
        child: const Text('Comprobar acceso y licencia'),
      ),
      TextButton.icon(
        onPressed: session.logout,
        icon: const Icon(Icons.logout),
        label: const Text('Cerrar sesión'),
      ),
    ],
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/presentation/providers/settings_providers.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/blueprint_card.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/tile_grid.dart';
import 'catalog_screen.dart';
import 'history_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'customer_configuration.dart';
import 'draft_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({required this.session, super.key});
  final MobileSession session;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  AppSection section = AppSection.inicio;
  bool recoveryChecked = false;
  bool recovering = false;
  String? recoveryError;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_restoreDraft()),
    );
  }

  Future<void> _restoreDraft() async {
    final session = widget.session;
    if (!mounted ||
        recoveryChecked ||
        recovering ||
        session.stage != SessionStage.ready) {
      return;
    }
    recovering = true;
    final owner = session.recoveryOwner;
    try {
      final snapshot = await session.recovery.active(owner);
      if (!mounted ||
          session.stage != SessionStage.ready ||
          session.recoveryOwner != owner) {
        return;
      }
      recoveryChecked = true;
      recoveryError = null;
      if (snapshot != null) {
        await openPage(
          context,
          RecoveredDraftScreen(session: session, snapshot: snapshot),
        );
      }
    } catch (_) {
      recoveryError = 'No se pudo recuperar la comprobación pendiente.';
    } finally {
      recovering = false;
      if (mounted) setState(() {});
    }
  }

  void _sessionChanged() {
    if (mounted && widget.session.stage == SessionStage.ready) {
      setState(() {});
      unawaited(_restoreDraft());
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!recoveryChecked && recoveryError == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = widget.session;
    return PopScope(
      canPop: section == AppSection.inicio,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && section != AppSection.inicio) {
          setState(() => section = AppSection.inicio);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(section),
                    child: switch (section) {
                      AppSection.inicio => _Home(
                        session: session,
                        onSection: (value) => setState(() => section = value),
                      ),
                      AppSection.verificar => CatalogScreen(session: session),
                      AppSection.areas => _Plants(session: session),
                      AppSection.ajustes => _Settings(session),
                    },
                  ),
                ),
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
              if (recoveryError != null)
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: Material(
                    child: Column(
                      children: [
                        Notice(recoveryError!, alert: true),
                        TextButton(
                          onPressed: _restoreDraft,
                          child: const Text('Reintentar recuperación'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera de las pantallas raiz: linea de cliente, titulo grande y contexto.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.kicker,
    required this.title,
    this.subtitle,
    super.key,
  });
  final String kicker;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Kicker(kicker),
      const SizedBox(height: 2),
      Text(title, style: AppTextStyles.figure(context, size: 29)),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: IndustryPalette.of(context).muted,
            ),
          ),
        ),
    ],
  );
}

/// Inicio: el parque en dos cifras y las funciones como modulos del plano.
///
/// No hay listas aqui a proposito. La pantalla de entrada solo tiene que
/// decir cuanto hay, que esta abierto y por donde se empieza; el detalle vive
/// una pulsacion mas adentro.
class _Home extends StatelessWidget {
  const _Home({required this.session, required this.onSection});
  final MobileSession session;
  final ValueChanged<AppSection> onSection;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final bootstrap = session.bootstrap;
    final alerts = (bootstrap['openAlerts'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: kShellContentPadding,
      children: [
        ScreenHeader(
          kicker: 'IvMET · verificaciones intermedias',
          title: valueLabel(object(bootstrap['client'])['name']),
          subtitle:
              'Hola, ${session.user!['name']} · '
              '${session.quality ? 'Jefe de calidad' : 'Operador'}',
        ),
        const SizedBox(height: 18),
        TileGrid(
          cells: [
            TileCell(
              MetricTile(
                label: 'Balanzas',
                value: '${bootstrap['equipmentCount']}',
                caption: 'habilitadas',
                onTap: () => onSection(AppSection.verificar),
              ),
            ),
            TileCell(
              MetricTile(
                label: 'Alertas',
                value: '$alerts',
                caption: 'privadas abiertas',
                valueColor: alerts > 0 ? palette.fail : null,
                onTap: () => openPage(context, HistoryScreen(session: session)),
              ),
            ),
            TileCell.wide(
              ActionTile(
                icon: Icons.add,
                label: 'Nueva captura',
                caption: 'Elige la balanza y empieza la comprobación interna',
                primary: true,
                onTap: () => onSection(AppSection.verificar),
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.history,
                label: 'Historial',
                caption: 'Resultados y alertas privadas',
                onTap: () => openPage(context, HistoryScreen(session: session)),
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.edit_note,
                label: 'Borradores',
                caption: 'Capturas sin finalizar',
                onTap: () => openPage(
                  context,
                  HistoryScreen(session: session, drafts: true),
                ),
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.factory_outlined,
                label: 'Gestionar plantas',
                caption: 'Áreas organizadas dentro de cada planta',
                onTap: () => openPage(
                  context,
                  CustomerSetupScreen(
                    session: session,
                    initialSection: 'plants',
                  ),
                ),
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.straighten_outlined,
                label: 'Gestionar patrones',
                caption: 'Pesas patrón y certificados asociados',
                onTap: () => openPage(
                  context,
                  CustomerSetupScreen(
                    session: session,
                    initialSection: 'patterns',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SectionLabel('Alcance de la app'),
        const Notice(
          'Tus verificaciones son privadas. Métrica solo recibe el expediente que autorice el jefe de calidad.',
          icon: Icons.shield_outlined,
        ),
        const Notice(
          'Supabase calcula las comprobaciones internas con la configuración activa de cada balanza. Los resultados no son certificados de calibración ni verificaciones legales.',
        ),
      ],
    );
  }
}

/// Areas: el parque como plano de planta.
///
/// Cada planta es un modulo ancho y sus areas, modulos de media fila debajo.
/// Se ve de un vistazo por donde esta repartido el trabajo, y una pulsacion
/// entra al catalogo ya filtrado.
class _Plants extends StatelessWidget {
  const _Plants({required this.session});
  final MobileSession session;

  @override
  Widget build(BuildContext context) {
    final bootstrap = session.bootstrap;
    final plants = objects(bootstrap['plants']);
    final areas = objects(bootstrap['areas']);

    return ListView(
      padding: kShellContentPadding,
      children: [
        ScreenHeader(
          kicker: valueLabel(object(bootstrap['client'])['name']),
          title: 'Plantas y áreas',
          subtitle:
              '${plants.length} ${plants.length == 1 ? 'planta' : 'plantas'} · '
              '${areas.length} ${areas.length == 1 ? 'área' : 'áreas'}',
        ),
        const SizedBox(height: 18),
        TileGrid(
          cells: [
            TileCell(
              ActionTile(
                icon: Icons.edit_location_outlined,
                label: 'Gestionar plantas',
                caption: 'Crear y editar las áreas de cada planta',
                primary: true,
                onTap: () => openPage(
                  context,
                  CustomerSetupScreen(
                    session: session,
                    initialSection: 'plants',
                  ),
                ),
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.straighten_outlined,
                label: 'Gestionar patrones',
                caption: 'Pesas patrón y certificados de calibración',
                onTap: () => openPage(
                  context,
                  CustomerSetupScreen(
                    session: session,
                    initialSection: 'patterns',
                  ),
                ),
              ),
            ),
          ],
        ),
        if (plants.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Notice(
              'No tienes plantas asignadas. Solicita su habilitación en RimMET.',
            ),
          ),
        for (final plant in plants)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _PlantBlock(
              session: session,
              plant: plant,
              areas: areas.where((a) => a['plantId'] == plant['id']).toList(),
            ),
          ),
      ],
    );
  }
}

class _PlantBlock extends StatelessWidget {
  const _PlantBlock({
    required this.session,
    required this.plant,
    required this.areas,
  });
  final MobileSession session;
  final Json plant;
  final List<Json> areas;

  void _open(BuildContext context, String title, {String? areaId}) => openPage(
    context,
    OnlinePage(
      title: title,
      child: CatalogScreen(
        session: session,
        plantId: plant['id'] as String,
        areaId: areaId,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name = valueLabel(plant['name']);

    return TileGrid(
      cells: [
        TileCell.wide(
          ActionTile(
            icon: Icons.factory_outlined,
            label: name,
            caption:
                '${valueLabel(plant['code'])} · todas las balanzas de la planta',
            onTap: () => _open(context, name),
          ),
        ),
        for (final area in areas)
          TileCell(
            ActionTile(
              icon: Icons.grid_view_outlined,
              label: valueLabel(area['name']),
              caption: 'Balanzas del área',
              onTap: () => _open(
                context,
                valueLabel(area['name']),
                areaId: area['id'] as String,
              ),
            ),
          ),
      ],
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings(this.session);
  final MobileSession session;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final large = ref.watch(largeTextProvider);

    return ListView(
      padding: kShellContentPadding,
      children: [
        ScreenHeader(
          kicker: 'Mi cuenta',
          title: valueLabel(session.user!['name']),
          subtitle: session.quality ? 'Jefe de calidad' : 'Operador',
        ),
        const SectionLabel('Sesión y licencia'),
        BlueprintCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailField('Usuario', session.user!['username']),
              DetailField('Plan', session.access['planName']),
              DetailField(
                'Fin del período',
                dateLabel(session.access['periodEndsAt']),
              ),
              if (session.access['subscriptionStatus'] == 'GRACE')
                DetailField(
                  'Fin de la gracia',
                  dateLabel(session.access['graceEndsAt']),
                ),
            ],
          ),
        ),
        const SectionLabel('Cómo se ve la app'),
        TileGrid(
          minTileHeight: 110,
          cells: [
            TileCell(
              ActionTile(
                icon: dark ? Icons.dark_mode : Icons.light_mode_outlined,
                label: 'Modo oscuro',
                caption: dark ? 'Activado' : 'Desactivado',
                primary: dark,
                onTap: ref.read(themeModeProvider.notifier).toggleDark,
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.format_size,
                label: 'Texto grande',
                caption: large ? 'Activado' : 'Desactivado',
                primary: large,
                onTap: ref.read(largeTextProvider.notifier).toggle,
              ),
            ),
          ],
        ),
        const SectionLabel('Acceso'),
        TileGrid(
          minTileHeight: 110,
          cells: [
            TileCell(
              ActionTile(
                icon: Icons.verified_user_outlined,
                label: 'Comprobar acceso',
                caption: 'Revalida licencia y plantas',
                onTap: session.refresh,
              ),
            ),
            TileCell(
              ActionTile(
                icon: Icons.logout,
                label: 'Cerrar sesión',
                caption: 'Salir de esta cuenta',
                onTap: session.logout,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Notice(
          'La licencia y las plantas autorizadas se validan en cada consulta. No hay modo offline.',
        ),
      ],
    );
  }
}

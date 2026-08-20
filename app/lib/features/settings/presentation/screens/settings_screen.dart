import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../shared/theme/app_typography.dart';
import '../../../../shared/theme/industry_palette.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/blueprint_card.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sync/presentation/providers/sync_providers.dart';
import '../providers/settings_providers.dart';

/// Ajustes: apariencia, conexion, cola de envio y cuenta.
///
/// El orden no es el habitual — la conexion va antes que la cuenta — porque en
/// planta el problema tipico no es el usuario sino la VPN, y este es el sitio
/// al que se llega cuando algo no sincroniza.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = IndustryPalette.of(context);
    final user = ref.watch(authProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final largeText = ref.watch(largeTextProvider);
    final connection = ref.watch(connectionCheckProvider);
    final pendientes = ref.watch(syncQueueProvider);
    final codigos = ref.watch(pendingSyncCodesProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: kShellContentPadding,
        children: [
          Text('Ajustes', style: AppTextStyles.figure(context, size: 29)),
          const SectionLabel('Apariencia', padding: EdgeInsets.only(top: 16, bottom: 6)),
          _SettingRow(
            title: 'Tema oscuro',
            subtitle: 'Para planta con poca luz',
            trailing: OutlinedButton(
              onPressed: ref.read(themeModeProvider.notifier).toggleDark,
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
              child: Text(isDark ? 'Activado' : 'Desactivado'),
            ),
          ),
          _SettingRow(
            title: 'Texto grande',
            subtitle: 'Lecturas a un brazo de distancia',
            trailing: OutlinedButton(
              onPressed: ref.read(largeTextProvider.notifier).toggle,
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
              child: Text(largeText ? 'Activado' : 'Desactivado'),
            ),
          ),
          const SectionLabel('Conexión', padding: EdgeInsets.only(top: 24, bottom: 6)),
          BlueprintCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConnectionRow(label: 'Servidor', value: _host, mono: true),
                const _ConnectionRow(label: 'VPN', value: 'Activa (WireGuard)'),
                _ConnectionRow(
                  label: 'Última sincronización',
                  value: ref.watch(lastSyncLabelProvider),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: connection == ConnectionCheck.testing
                      ? null
                      : ref.read(connectionCheckProvider.notifier).run,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: Text(connection.label),
                ),
                const SizedBox(height: 8),
                Text(
                  connection.hint,
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ],
            ),
          ),
          const SectionLabel('Datos sin enviar', padding: EdgeInsets.only(top: 24, bottom: 6)),
          _SettingRow(
            title: pendientes.isEmpty
                ? 'Nada pendiente de envío'
                : '${pendientes.length} verificaciones en cola',
            subtitle: pendientes.isEmpty ? 'Todo sincronizado con Métrica' : codigos,
            trailing: OutlinedButton(
              onPressed: pendientes.isEmpty ? null : ref.read(syncQueueProvider.notifier).sendAll,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Enviar'),
            ),
          ),
          const SectionLabel('Cuenta', padding: EdgeInsets.only(top: 24, bottom: 6)),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user?.nombre ?? '—', style: const TextStyle(fontSize: 14.5)),
                Text(
                  user == null ? '' : '${user.role.label} · ${user.empresaNombre ?? 'Métrica'}',
                  style: TextStyle(fontSize: 11.5, color: palette.muted),
                ),
              ],
            ),
          ),
          _SettingRow(
            title: 'Versión',
            trailing: Text(
              '1.0.0 (build 1)',
              style: TextStyle(fontSize: 13.5, color: palette.muted),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: ref.read(authProvider.notifier).signOut,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

  /// Host de la API sin el esquema: es como lo nombra el instructivo de VPN.
  static String get _host => Uri.parse(AppConfig.apiBaseUrl).host;
}

/// Fila de ajuste: titulo, apoyo opcional y un control a la derecha.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 14.5)),
                if (subtitle case final String value when value.isNotEmpty)
                  Text(value, style: TextStyle(fontSize: 11.5, height: 1.35, color: palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13.5, color: palette.muted)),
          ),
          Text(
            value,
            style: mono
                ? AppTextStyles.reading(context, size: 12.5)
                : const TextStyle(fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

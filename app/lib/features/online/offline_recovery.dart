import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/surface_card.dart';
import 'draft_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'pending_captures.dart';

/// Lo que el operario dejo a medias, cuando la app no pudo validar la sesion.
///
/// La captura nunca se perdia —se guarda en este dispositivo en cada cambio—
/// pero no habia forma de llegar a ella: entrar exige validar la licencia
/// contra el servidor, y sin senal el operario veia una pantalla bloqueada con
/// su trabajo intacto a un centimetro.
///
/// Esta pantalla no habilita la app. No hay catalogo, ni historial, ni
/// finalizacion: solo se devuelve lo que ya estaba escrito para poder seguir
/// escribiendo. Finalizar sigue exigiendo servidor, que es donde se recalcula
/// el resultado y se revalida el contrato.
///
/// Solo se llega aqui si el servidor no se pudo consultar. Si denego el acceso
/// —un 401— la sesion se cierra y se borra el dueno de los borradores, asi que
/// quien perdio el acceso no ve nada.
class OfflineRecoveryScreen extends StatelessWidget {
  const OfflineRecoveryScreen({required this.session, super.key});

  final MobileSession session;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final drafts = session.offlineDrafts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sin conexión'),
        actions: [
          IconButton(
            tooltip: 'Reintentar conexión',
            onPressed: session.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              drafts.length == 1
                  ? 'Tienes 1 captura sin enviar'
                  : 'Tienes ${drafts.length} capturas sin enviar',
              style: AppTextStyles.figure(context, size: 25),
            ),
            const Notice(
              'Están guardadas en este dispositivo y no se han perdido. Puedes seguir capturando ahora; para finalizar las que faltan hace falta señal. Las ya finalizadas se envían solas al volver la conexión.',
            ),
            if (session.error case final String message)
              Notice(message, icon: Icons.wifi_off, alert: true),
            const SectionLabel('Capturas en este dispositivo'),
            SurfaceList(
              children: [
                for (final draft in drafts)
                  _OfflineDraftRow(
                    session: session,
                    snapshot: draft,
                    palette: palette,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: session.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar conexión'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => confirmLogout(context, session),
              child: const Text('Cerrar sesión'),
            ),
            const Notice(
              'Al cerrar sesión, las capturas de este dispositivo dejan de ser accesibles hasta que vuelvas a entrar con la misma cuenta.',
              icon: Icons.warning_amber_outlined,
              alert: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Una captura pendiente: que balanza, por que paso iba y cuando se toco.
class _OfflineDraftRow extends StatelessWidget {
  const _OfflineDraftRow({
    required this.session,
    required this.snapshot,
    required this.palette,
  });

  final MobileSession session;
  final Json snapshot;
  final IndustryPalette palette;

  @override
  Widget build(BuildContext context) {
    final equipment = object(object(snapshot['bundle'])['equipment']);
    final step = (snapshot['step'] as num?)?.toInt() ?? 0;

    return InkWell(
      // Se abre `DraftScreen` y no `RecoveredDraftScreen`: esa revalida el
      // acceso al equipo contra el servidor antes de mostrarlo, y aqui el
      // servidor es justo lo que no responde. La revalidacion vuelve a ocurrir
      // en cuanto haya senal, en el siguiente `refresh` de la sesion.
      onTap: () => openPage(
        context,
        DraftScreen(
          session: session,
          bundle: object(snapshot['bundle']),
          recovered: snapshot,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customerEquipmentCode(equipment),
                    style: AppTextStyles.reading(
                      context,
                      size: 15,
                      color: palette.accentInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Paso ${step + 1} de 5 · ${dateLabel(snapshot['updatedAt'])}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: palette.text.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

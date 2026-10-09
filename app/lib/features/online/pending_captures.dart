import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'capture_uploads.dart';
import 'draft_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Por enviar: lo capturado en este teléfono que todavía no llegó al
/// servidor, con su estado. Como los relojes de WhatsApp: en el teléfono,
/// enviándose o rechazada por el servidor.
class PendingCapturesScreen extends StatefulWidget {
  const PendingCapturesScreen({required this.session, super.key});
  final MobileSession session;

  @override
  State<PendingCapturesScreen> createState() => _PendingCapturesScreenState();
}

class _PendingCapturesScreenState extends State<PendingCapturesScreen> {
  MobileSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    unawaited(session.uploads.load());
  }

  Future<void> _open(Json snapshot) async {
    await openPage(
      context,
      DraftScreen(
        session: session,
        bundle: object(snapshot['bundle']),
        recovered: snapshot,
      ),
    );
    unawaited(session.uploads.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session, session.uploads]),
    builder: (context, _) {
      final uploads = session.uploads;
      final items = uploads.items;
      return OnlinePage(
        title: 'Por enviar',
        floating: session.online && items.isNotEmpty
            ? WizardNavPill.action(
                key: const ValueKey('send-pending'),
                label: uploads.sending ? 'Enviando…' : 'Enviar ahora',
                icon: Icons.cloud_upload_outlined,
                onNext: uploads.sending
                    ? null
                    : () => unawaited(uploads.run(force: true)),
              )
            : null,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            WizardNavPill.contentPadding,
          ),
          children: [
            Notice(
              session.online
                  ? 'Se envían solas mientras la app está abierta. El servidor calcula el resultado de cada verificación al recibirla.'
                  : 'Sin conexión. Se enviarán solas cuando vuelva la señal, con la app abierta.',
              icon: session.online ? Icons.cloud_sync_outlined : Icons.wifi_off,
            ),
            if (items.isEmpty)
              const Notice(
                'No hay nada por enviar: todo lo capturado en este teléfono está en el servidor.',
                icon: Icons.cloud_done_outlined,
              )
            else
              SurfaceList(
                children: [
                  for (final item in items)
                    _PendingRow(
                      snapshot: item,
                      sending: uploads.isSending(item['requestId'] as String),
                      onTap: () => _open(item),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.snapshot,
    required this.sending,
    required this.onTap,
  });
  final Json snapshot;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final equipment = object(object(snapshot['bundle'])['equipment']);
    final attention = snapshot['attention'] == null
        ? null
        : object(snapshot['attention']);
    final finished = CaptureUploads.finishedOnPhone(snapshot);
    final step = (snapshot['step'] as num?)?.toInt() ?? 0;
    final (IconData icon, Color color, String detail) = attention != null
        ? (
            Icons.error_outline,
            palette.fail,
            'Rechazada: ${attention['message']}',
          )
        : sending
        ? (Icons.cloud_upload_outlined, palette.accentInk, 'Enviando…')
        : finished
        ? (
            Icons.schedule,
            palette.accentInk,
            'Finalizada el ${dateTimeLabel(snapshot['measuredAt'] ?? snapshot['updatedAt'])} · por enviar',
          )
        : (
            Icons.edit_note,
            palette.muted,
            'Sin finalizar · paso ${step + 1} de 5 · ${dateTimeLabel(snapshot['updatedAt'])}',
          );
    return InkWell(
      key: ValueKey('pending-${snapshot['requestId']}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
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
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: attention != null
                          ? palette.failInk
                          : palette.muted,
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

/// Franja de conexión sobre toda la app, como «Conectando…» en WhatsApp:
/// sin señal, la fecha de la copia con la que se trabaja; con señal, lo que
/// se está enviando o lo que el servidor rechazó. Sin nada que decir, no se
/// ve.
class ConnectionStrip extends StatelessWidget {
  const ConnectionStrip({
    required this.session,
    required this.onTap,
    super.key,
  });
  final MobileSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session, session.uploads]),
    builder: (context, _) {
      final palette = IndustryPalette.of(context);
      final uploads = session.uploads;
      final waiting = uploads.waiting;
      final pending = waiting == 1
          ? '1 verificación por enviar'
          : '$waiting verificaciones por enviar';
      final saved = session.copySavedAt?.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      final (
        String? text,
        Color background,
        Color ink,
        IconData icon,
      ) = !session.online
          ? (
              'Sin conexión · datos del '
                  '${saved == null ? 'teléfono' : '${two(saved.day)}/${two(saved.month)} ${two(saved.hour)}:${two(saved.minute)}'}'
                  '${waiting > 0 ? ' · $waiting por enviar' : ''}',
              palette.tagNeutralSurface,
              palette.text,
              Icons.wifi_off,
            )
          : uploads.attention > 0
          ? (
              uploads.attention == 1
                  ? '1 verificación requiere atención'
                  : '${uploads.attention} verificaciones requieren atención',
              palette.failSurface,
              palette.failInk,
              Icons.error_outline,
            )
          : uploads.sending && waiting > 0
          ? (
              'Enviando $pending…',
              palette.accentSoft,
              palette.accentInk,
              Icons.cloud_upload_outlined,
            )
          : (null, palette.surface, palette.text, Icons.check);
      return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: text == null
            ? const SizedBox(width: double.infinity)
            : Material(
                key: const ValueKey('connection-strip'),
                color: background,
                child: InkWell(
                  onTap: onTap,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: ink),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                color: ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: ink.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );

  /// Si hay que dejar sitio arriba para la franja.
  static bool visible(MobileSession session) =>
      !session.online ||
      session.uploads.attention > 0 ||
      (session.uploads.sending && session.uploads.waiting > 0);
}

/// Cerrar sesión con verificaciones finalizadas sin enviar no se permite:
/// se enviarían recién al volver a entrar con esta cuenta.
Future<void> confirmLogout(BuildContext context, MobileSession session) async {
  await session.uploads.load();
  final waiting = session.uploads.waiting;
  if (waiting == 0) {
    await session.logout();
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        waiting == 1
            ? 'Tienes 1 verificación sin enviar'
            : 'Tienes $waiting verificaciones sin enviar',
      ),
      content: Text(
        session.online
            ? 'Están finalizadas en este teléfono y se están enviando. Cierra sesión cuando terminen; puedes verlas en Por enviar.'
            : 'Están finalizadas en este teléfono. Conéctate a internet para enviarlas antes de cerrar sesión.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

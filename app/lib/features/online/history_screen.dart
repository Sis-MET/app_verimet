import 'package:flutter/material.dart';
import '../../core/domain/compliance_status.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/surface_card.dart';
import 'draft_screen.dart';
import 'verification_screen.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    required this.session,
    this.equipmentId,
    this.drafts = false,
    super.key,
  });
  final MobileSession session;
  final String? equipmentId;
  final bool drafts;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int page = 1;
  int revision = 0;
  @override
  Widget build(BuildContext context) => OnlinePage(
    title: widget.drafts ? 'Mis borradores' : 'Historial privado',
    actions: [
      IconButton(
        tooltip: 'Actualizar',
        onPressed: () => setState(() => revision++),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: RemotePanel(
      dataKey: '$page|$revision',
      load: () async {
        // Lo local va primero y por separado: leia despues del servidor, sin
        // proteger, asi que un fallo de red se llevaba por delante la lista de
        // borradores que estaban en este mismo dispositivo.
        final local = widget.drafts ? await _localDrafts() : const <Json>[];
        try {
          final data = await widget.session.api.read(
            widget.drafts ? 'drafts' : 'history',
            {'page': page, 'equipmentId': widget.equipmentId},
          );
          if (widget.drafts) data['localDrafts'] = local;
          return data;
        } catch (_) {
          if (local.isEmpty) rethrow;
          return {'items': <Json>[], 'total': 0, 'localDrafts': local};
        }
      },
      builder: (data) {
        final items = objects(data['items']);
        final total = (data['total'] as num).toInt();
        final localDrafts = objects(data['localDrafts']);

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Text(
              '$total registros',
              style: AppTextStyles.caption(context, size: 12),
            ),
            const SizedBox(height: 10),
            SurfaceList(
              children: [
                for (final local in localDrafts)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.edit_note),
                    title: Text(
                      customerEquipmentCode(
                        object(object(local['bundle'])['equipment']),
                      ),
                    ),
                    subtitle: Text(
                      'En este dispositivo · paso ${(local['step'] as num).toInt() + 1} de 5',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await openPage(
                        context,
                        RecoveredDraftScreen(
                          session: widget.session,
                          snapshot: local,
                        ),
                      );
                      if (mounted) setState(() => revision++);
                    },
                  ),
              ],
            ),
            if (localDrafts.isNotEmpty) const SizedBox(height: 10),
            if (items.isEmpty && localDrafts.isEmpty)
              Notice(
                widget.drafts
                    ? 'No tienes borradores guardados.'
                    : 'Todavía no hay verificaciones finalizadas. Las capturas sin evaluación están en Mis borradores.',
              ),
            SurfaceList(
              children: [
                for (final item in items.where(
                  (item) => !localDrafts.any(
                    (d) => d['requestId'] == item['request_uuid'],
                  ),
                ))
                  _HistoryRow(
                    item: item,
                    draft: widget.drafts,
                    onTap: () => _open(item),
                  ),
              ],
            ),
            if (total > 25)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: page > 1 ? () => setState(() => page--) : null,
                      child: const Text('Anterior'),
                    ),
                    Text(
                      'Página $page',
                      style: AppTextStyles.caption(context, size: 12),
                    ),
                    TextButton(
                      onPressed: page * 25 < total
                          ? () => setState(() => page++)
                          : null,
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<List<Json>> _localDrafts() async {
    try {
      final drafts = await widget.session.recovery.list(
        widget.session.recoveryOwner,
      );
      return drafts
          .where(
            (d) =>
                widget.equipmentId == null ||
                object(object(d['bundle'])['equipment'])['id'] ==
                    widget.equipmentId,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _open(Json item) async {
    if (widget.drafts) {
      await openPage(
        context,
        Scaffold(
          body: RemotePanel(
            load: () => widget.session.api.read('draft', {'id': item['id']}),
            builder: (draft) => DraftScreen(
              session: widget.session,
              bundle: object(draft['context_snapshot']),
              draft: draft,
            ),
          ),
        ),
      );
    } else {
      await openPage(
        context,
        VerificationScreen(session: widget.session, id: item['id'] as String),
      );
    }
    if (mounted) setState(() => revision++);
  }
}

/// Fila del historial: el codigo manda a la izquierda, el veredicto cierra a
/// la derecha y en medio queda el contexto. Un hairline las separa, sin caja
/// por fila: son treinta registros seguidos y treinta cajas no se leen.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.draft,
    required this.onTap,
  });
  final Json item;
  final bool draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final annulled = item['estado'] == 'ANNULLED';
    final verdict = valueLabel(item['veredicto_global']);
    final failed = verdict == 'fail';

    final String meta = draft
        ? '${dateLabel(item['updated_at'])} · versión ${item['version']}'
        : '${dateLabel(item['realizado_at'])} · '
              '${annulled
                  ? 'Anulada'
                  : item['trazabilidad'] == 'non_traceable'
                  ? 'No trazable'
                  : 'Trazable'} · '
              '${item['alcance'] == 'partial' ? 'Parcial' : 'Completa'}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // Una balanza registrada por la empresa no tiene código
                    // de Métrica.
                    valueLabel(item['cod_metrica'] ?? item['cod_interno']),
                    style: AppTextStyles.reading(
                      context,
                      size: 15,
                      color: palette.accentInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
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
            if (draft)
              StatusTag('Borrador')
            else
              StatusTag(
                verdictLabel(item['veredicto_global']),
                status: annulled
                    ? ComplianceStatus.conforme
                    : failed
                    ? ComplianceStatus.noConforme
                    : verdict == 'pass'
                    ? ComplianceStatus.conforme
                    : ComplianceStatus.observado,
              ),
            const SizedBox(width: 6),
            Icon(
              item['alerta_id'] == null
                  ? Icons.chevron_right
                  : Icons.warning_amber_outlined,
              size: 20,
              color: item['alerta_id'] == null
                  ? palette.text.withValues(alpha: 0.45)
                  : palette.fail,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'draft_screen.dart';
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
      load: () => widget.session.api.read(
        widget.drafts ? 'drafts' : 'history',
        {'page': page, 'equipmentId': widget.equipmentId},
      ),
      builder: (data) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('${data['total']} registros'),
          if (objects(data['items']).isEmpty)
            Notice(
              widget.drafts
                  ? 'No tienes borradores guardados.'
                  : 'Todavía no hay verificaciones finalizadas. Las capturas sin evaluación están en Mis borradores.',
            ),
          for (final item in objects(data['items']))
            Card(
              child: ListTile(
                title: Text(valueLabel(item['cod_metrica'])),
                subtitle: Text(
                  widget.drafts
                      ? 'Borrador · ${dateLabel(item['updated_at'])} · versión ${item['version']}'
                      : '${dateLabel(item['realizado_at'])} · ${verdictLabel(item['veredicto_global'])}\n${item['estado'] == 'ANNULLED'
                            ? 'Anulada'
                            : item['trazabilidad'] == 'non_traceable'
                            ? 'No trazable'
                            : 'Trazable'} · ${item['alcance'] == 'partial' ? 'Parcial' : 'Completa'}',
                ),
                trailing: Icon(
                  widget.drafts
                      ? Icons.edit_note
                      : item['alerta_id'] == null
                      ? Icons.chevron_right
                      : Icons.warning_amber_outlined,
                ),
                onTap: () async {
                  if (widget.drafts) {
                    await openPage(
                      context,
                      Scaffold(
                        body: RemotePanel(
                          load: () => widget.session.api.read('draft', {
                            'id': item['id'],
                          }),
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
                      VerificationScreen(
                        session: widget.session,
                        id: item['id'] as String,
                      ),
                    );
                  }
                  if (mounted) setState(() => revision++);
                },
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
  );
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    required this.session,
    required this.id,
    super.key,
  });
  final MobileSession session;
  final String id;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  int revision = 0;
  bool busy = false;
  String? error;
  Future<void> action(String name, Json args, {String? question}) async {
    if (busy) return;
    if (question != null) {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => _ReasonDialog(question),
      );
      if (reason == null || !mounted) return;
      args[name == 'annul_ivmet_verification' ? 'annulment_reason' : 'reason'] =
          reason;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.api.rpc(name, args);
      if (mounted) setState(() => revision++);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure
              ? failure.message
              : 'No se pudo completar la operación.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Verificación privada',
    child: RemotePanel(
      dataKey: '$revision',
      load: () => widget.session.api.read('verification', {'id': widget.id}),
      builder: (data) {
        final v = object(data['verification']);
        final alert = data['alert'] == null ? null : object(data['alert']);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Notice(
              'Resultado de una comprobación interna. No constituye certificado de calibración ni verificación legal.',
              icon: Icons.science_outlined,
            ),
            Text(
              verdictLabel(v['veredicto_global']),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            DetailField('Capturado por', object(data['users'])['capture']),
            DetailField(
              'Finalizado por',
              object(data['users'])['finalization'],
            ),
            DetailField('Fecha de medición', v['realizado_at']),
            DetailField('Fecha de recepción', v['recibido_at']),
            DetailField(
              'Alcance',
              v['alcance'] == 'partial' ? 'Parcial' : 'Completa',
            ),
            DetailField(
              'Trazabilidad',
              v['trazabilidad'] == 'traceable' ? 'Trazable' : 'No trazable',
            ),
            DetailField(
              'Estado',
              v['estado'] == 'ANNULLED' ? 'Anulada' : 'Activa',
            ),
            if (v['motivo_anulacion'] != null)
              DetailField('Motivo de anulación', v['motivo_anulacion']),
            ExpansionTile(
              title: const Text('Equipo, plan y condiciones históricas'),
              children: [EvidenceTree(v)],
            ),
            ExpansionTile(
              title: const Text('Patrones utilizados'),
              children: [EvidenceTree(data['patterns'])],
            ),
            for (final t in objects(data['tests']))
              ExpansionTile(
                title: Text(testLabel(t['tipo'])),
                subtitle: Text(
                  t['estado_ejecucion'] == 'omitted'
                      ? 'Omitida: ${t['motivo_omision']}'
                      : verdictLabel(t['veredicto']),
                ),
                children: [EvidenceTree(t)],
              ),
            if (error != null) Notice(error!, icon: Icons.error_outline),
            if (alert != null) ...[
              Notice(
                valueLabel(alert['resumen']),
                icon: Icons.warning_amber_outlined,
              ),
              if (alert['visibilidad_metrica'] == 'PRIVATE')
                const Notice(
                  'Esta alerta no está compartida con Métrica.',
                  icon: Icons.lock_outline,
                ),
              if (widget.session.quality &&
                  alert['visibilidad_metrica'] == 'PRIVATE')
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await openPage(
                            context,
                            SharePreviewScreen(
                              session: widget.session,
                              alertId: alert['id'] as String,
                            ),
                          );
                          if (mounted) setState(() => revision++);
                        },
                  child: const Text('Revisar expediente para compartir'),
                ),
              if (!widget.session.quality)
                const Notice(
                  'Solo el jefe de calidad puede autorizar el envío a Métrica.',
                ),
            ],
            for (final shared in objects(data['cases']))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caso ${shared['code']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      DetailField(
                        'Acceso de Métrica',
                        shared['visibility'] == 'SHARED'
                            ? 'Compartido'
                            : 'Retirado',
                      ),
                      DetailField('Seguimiento', shared['state']),
                      DetailField('Mensaje enviado', shared['message']),
                      ExpansionTile(
                        title: const Text('Actividad del caso'),
                        children: [EvidenceTree(shared['events'])],
                      ),
                      if (widget.session.quality &&
                          shared['visibility'] == 'SHARED')
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  'withdraw_ivmet_case',
                                  {
                                    'target_case_id': shared['id'],
                                    'expected_row_version': shared['version'],
                                  },
                                  question:
                                      'Retirar el acceso de Métrica. Las copias ya entregadas no se eliminan. Indica el motivo.',
                                ),
                          child: const Text('Retirar acceso'),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.session.quality && v['estado'] == 'ACTIVE')
              TextButton(
                onPressed: busy
                    ? null
                    : () => action(
                        'annul_ivmet_verification',
                        {'target_verification_id': widget.id},
                        question:
                            'La anulación conservará toda la evidencia. Indica el motivo y realiza una nueva verificación cuando corresponda.',
                      ),
                child: const Text('Anular con motivo'),
              ),
          ],
        );
      },
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog(this.question);
  final String question;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirmar acción'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.question),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Confirmar'),
      ),
    ],
  );
}

class SharePreviewScreen extends StatefulWidget {
  const SharePreviewScreen({
    required this.session,
    required this.alertId,
    super.key,
  });
  final MobileSession session;
  final String alertId;
  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  final message = TextEditingController();
  bool consent = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> confirm(Json preview) async {
    if (!consent || busy || message.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.api.rpc('confirm_ivmet_alert_share', {
        'target_alert_id': widget.alertId,
        'expected_row_version': preview['alertVersion'],
        'expected_snapshot_hash': preview['snapshotHash'],
        'share_message': message.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure
              ? failure.message
              : 'No se pudo confirmar el envío.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OnlinePage(
    title: 'Autorizar envío a Métrica',
    child: RemotePanel(
      load: () => widget.session.api.rpc('preview_ivmet_alert_share', {
        'target_alert_id': widget.alertId,
      }),
      builder: (preview) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Notice(valueLabel(preview['notice']), icon: Icons.shield_outlined),
          const Text(
            'Este es el expediente completo que se enviará. Despliega las secciones para revisar todas las lecturas y sus datos históricos.',
          ),
          EvidenceTree(preview['snapshot']),
          const SizedBox(height: 16),
          TextField(
            controller: message,
            enabled: !busy,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Mensaje para Métrica',
            ),
            onChanged: (_) => setState(() {}),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: busy ? null : (v) => setState(() => consent = v == true),
            title: const Text(
              'Autorizo enviar únicamente este expediente a Métrica. Entiendo que retirar el acceso no elimina las copias ya entregadas.',
            ),
          ),
          if (error != null) Notice(error!, icon: Icons.error_outline),
          FilledButton(
            onPressed: consent && !busy && message.text.trim().isNotEmpty
                ? () => confirm(preview)
                : null,
            child: Text(
              busy ? 'Confirmando…' : 'Compartir expediente autorizado',
            ),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'verification_report.dart';

/// Una verificacion finalizada: su expediente, su informe y lo que se puede
/// hacer con ella.
///
/// Anular y compartir con Metrica son acciones sobre evidencia inmutable, por
/// eso piden motivo o consentimiento explicito. Vivia dentro de
/// `history_screen.dart`, que asi juntaba la lista y el detalle en un archivo.

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
  bool reporting = false;
  String? error;

  Future<void> generateReport(Json data) async {
    if (reporting) return;
    setState(() {
      reporting = true;
      error = null;
    });
    try {
      // Quien pulsa el boton queda anotado en el informe: el PDF sale del
      // dispositivo y circula fuera de la app, asi que tiene que decir quien lo
      // saco y cuando.
      final user = widget.session.user;
      final bytes = await buildVerificationReport(
        data,
        generatedBy: user == null
            ? null
            : '${valueLabel(user['name'] ?? user['username'])}'
                  ' (${valueLabel(user['username'])})',
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: verificationReportFilename(data),
        subject: 'Informe de verificación intermedia IvMET',
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo generar el informe PDF.');
      }
    } finally {
      if (mounted) setState(() => reporting = false);
    }
  }

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

  /// Anular es raro y destructivo: va en ⋮, no al pie del expediente.
  List<Widget> _menu(Json data) {
    final v = object(data['verification']);
    final menu = pageMenu([
      if (widget.session.quality && v['estado'] == 'ACTIVE')
        wizardMenuItem<VoidCallback>(
          () => action(
            'annul_ivmet_verification',
            {'target_verification_id': widget.id},
            question:
                'La anulación conservará toda la evidencia. Indica el motivo y realiza una nueva verificación cuando corresponda.',
          ),
          Icons.block_outlined,
          'Anular con motivo',
          enabled: !busy,
        ),
    ]);
    return [?menu];
  }

  @override
  Widget build(BuildContext context) => RemotePage(
    title: 'Verificación privada',
    dataKey: '$revision',
    load: () => widget.session.api.read('verification', {'id': widget.id}),
    actions: _menu,
    // El informe es lo que se viene a buscar: queda fijo a la vista.
    floating: (data) => WizardNavPill.action(
      key: const ValueKey('generate-verification-pdf'),
      label: reporting ? 'Generando informe…' : 'Generar informe PDF',
      icon: Icons.picture_as_pdf_outlined,
      onNext: reporting ? null : () => generateReport(data),
    ),
    builder: (data) {
      final v = object(data['verification']);
      final alert = data['alert'] == null ? null : object(data['alert']);
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          WizardNavPill.contentPadding,
        ),
        children: [
          const Notice(
            'Resultado de una verificación intermedia. No constituye certificado de calibración ni verificación legal.',
            icon: Icons.science_outlined,
          ),
          const SizedBox(height: 8),
          Text(
            verdictLabel(v['veredicto_global']),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          DetailField('Capturado por', object(data['users'])['capture']),
          DetailField('Finalizado por', object(data['users'])['finalization']),
          // La marca ISO cruda queda en el expediente de abajo; aqui va la
          // fecha como la lee quien revisa la verificacion.
          DetailField('Fecha de medición', dateLabel(v['realizado_at'])),
          DetailField('Fecha de recepción', dateLabel(v['recibido_at'])),
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
          EvidenceSection(
            title: 'Equipo, plan y condiciones históricas',
            children: [EvidenceTree(v)],
          ),
          EvidenceSection(
            title: 'Patrones utilizados',
            children: [EvidenceTree(data['patterns'])],
          ),
          for (final t in objects(data['tests']))
            EvidenceSection(
              title: testLabel(t['tipo']),
              subtitle: t['estado_ejecucion'] == 'omitted'
                  ? 'Omitida: ${t['motivo_omision']}'
                  : verdictLabel(t['veredicto']),
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
                    EvidenceSection(
                      title: 'Actividad del caso',
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
        ],
      );
    },
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
          LabeledInput(
            label: 'Motivo',
            child: TextField(
              controller: controller,
              maxLength: 2000,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
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
      builder: (preview) => FloatingActionLayout(
        action: WizardNavPill.action(
          label: busy ? 'Confirmando…' : 'Compartir expediente',
          icon: Icons.send_outlined,
          onNext: consent && !busy && message.text.trim().isNotEmpty
              ? () => confirm(preview)
              : null,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            WizardNavPill.contentPadding,
          ),
          children: [
            Notice(valueLabel(preview['notice']), icon: Icons.shield_outlined),
            const Text(
              'Este es el expediente completo que se enviará. Despliega las secciones para revisar todas las lecturas y sus datos históricos.',
            ),
            EvidenceTree(preview['snapshot']),
            const SizedBox(height: 16),
            LabeledInput(
              label: 'Mensaje para Métrica',
              child: TextField(
                controller: message,
                enabled: !busy,
                maxLength: 2000,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: busy
                  ? null
                  : (v) => setState(() => consent = v == true),
              title: const Text(
                'Autorizo enviar únicamente este expediente a Métrica. Entiendo que retirar el acceso no elimina las copias ya entregadas.',
              ),
            ),
            if (error != null) Notice(error!, icon: Icons.error_outline),
          ],
        ),
      ),
    ),
  );
}

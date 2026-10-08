import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'commercial_plan.dart';
import 'customer_form.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';

/// Lo que la empresa necesita, como motivo de la solicitud.
const upgradeReasons = {
  'EQUIPMENT': 'Más balanzas',
  'PLANTS': 'Más plantas',
  'USERS': 'Más usuarios',
  'VERIFICATIONS': 'Más verificaciones al mes',
  'PATTERNS': 'Más pesas patrón',
  'FULL_REPORT': 'Informe completo',
  'CUSTOM_SCHEDULES': 'Periodicidad a medida',
  'GENERAL': 'Otra necesidad',
};

/// "Pendiente" o "Contactada", y la frase que lo explica.
(String, String) upgradeRequestStatus(Json request) {
  final plan = request['requestedPlan'] == null
      ? 'asesoría'
      : 'el plan ${object(request['requestedPlan'])['name']}';
  return request['state'] == 'CONTACTED'
      ? (
          'Métrica ya te contactó',
          'Pediste $plan el ${dateLabel(request['createdAt'])}. El cambio se ve aquí apenas Métrica lo habilita.',
        )
      : (
          'Solicitud enviada',
          'Pediste $plan el ${dateLabel(request['createdAt'])}. Métrica te contactará.',
        );
}

/// Fin del periodo para mostrar: el plan gratuito no vence.
String periodLabel(Object? value) =>
    value == null || value == 'infinity' ? 'Sin vencimiento' : dateLabel(value);

/// La empresa intento algo que su plan no admite: lo dice y ofrece pedir uno
/// superior. Solo el jefe de calidad lo pide; al operador se le indica a
/// quien recurrir.
Future<void> showPlanLimit(
  BuildContext context,
  MobileSession session,
  PlanLimit limit,
) async {
  // El uso que llega en el bootstrap puede ser de hace unos segundos.
  unawaited(session.refresh());
  final next = await showModalBottomSheet<VoidCallback>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => _PlanLimitSheet(session: session, limit: limit),
  );
  if (next != null && context.mounted) next();
}

/// Abre "Mi plan" desde cualquier pantalla.
Future<void> openPlan(BuildContext context, MobileSession session) =>
    openPage<void>(context, PlanScreen(session: session));

/// Abre la solicitud de plan superior; al enviarla actualiza el bootstrap.
Future<bool> requestUpgrade(
  BuildContext context,
  MobileSession session, {
  String reason = 'GENERAL',
  String? planId,
}) async {
  final sent = await openPage<bool>(
    context,
    UpgradeRequestScreen(session: session, reason: reason, planId: planId),
  );
  if (sent == true) unawaited(session.refresh());
  return sent == true;
}

class _PlanLimitSheet extends StatelessWidget {
  const _PlanLimitSheet({required this.session, required this.limit});
  final MobileSession session;
  final PlanLimit limit;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final plan = session.plan;
    final resource = limit.resource;
    final feature = limit.feature;
    final maximum = resource == null ? null : plan.limit(resource);
    final request = plan.upgradeRequest;
    final title = feature != null
        ? '${feature.label}: en planes superiores'
        : 'Llegaste al límite de tu plan';
    final body = feature != null
        ? '${feature.detail} Tu plan ${plan.name} no la incluye.'
        : maximum == null
        ? 'Tu plan ${plan.name} no admite más ${resource!.plural}.'
        : 'Tu plan ${plan.name} incluye ${resource!.count(maximum)}'
              '${resource == PlanResource.monthlyVerifications ? '. Las capturas en curso cuentan hasta que se finalizan; el contador vuelve a cero el día 1.' : ' y ya están en uso.'}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Column(
          key: const ValueKey('plan-limit-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.trending_up_rounded, size: 34, color: palette.accent),
            const SizedBox(height: 10),
            Text(title, style: AppTextStyles.figure(context, size: 23)),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (!session.quality)
              const Notice(
                'Pide al jefe de calidad de tu empresa que solicite un plan superior.',
                icon: Icons.person_outline,
              )
            else if (request != null) ...[
              Notice(upgradeRequestStatus(request).$2, icon: Icons.schedule),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(() => openPlan(context, session)),
                child: const Text('Ver mi plan'),
              ),
            ] else ...[
              FilledButton(
                key: const ValueKey('plan-limit-request'),
                onPressed: () => Navigator.of(context).pop(
                  () => requestUpgrade(context, session, reason: limit.reason),
                ),
                child: const Text('Solicitar plan superior'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(() => openPlan(context, session)),
                child: const Text('Comparar planes'),
              ),
            ],
            if (!session.quality || request != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mi plan: lo que incluye, cuanto se usa, la solicitud abierta y los planes
/// que se pueden pedir. La app no muestra precios ni cobra: Metrica contacta
/// y habilita el cambio.
class PlanScreen extends StatefulWidget {
  const PlanScreen({required this.session, super.key});
  final MobileSession session;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int revision = 0;
  bool busy = false;
  MobileSession get session => widget.session;

  Future<void> _request(CommercialPlan plan, {String? planId}) async {
    final reason = plan.tightest != null && plan.full(plan.tightest!)
        ? plan.tightest!.code
        : 'GENERAL';
    if (await requestUpgrade(
          context,
          session,
          reason: reason,
          planId: planId,
        ) &&
        mounted) {
      setState(() => revision++);
    }
  }

  Future<void> _cancel(Json request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la solicitud?'),
        content: const Text(
          'Métrica dejará de verla como pendiente. Puedes pedir otra cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mantener'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar solicitud'),
          ),
        ],
      ),
    );
    if (confirm != true || busy || !mounted) return;
    setState(() => busy = true);
    try {
      await session.api.rpc('ivmet_customer_mutate', {
        'action': 'upgrade.cancel',
        'payload': {'id': request['id'], 'version': request['version']},
        'request_id': const Uuid().v4(),
      });
      unawaited(session.refresh());
    } on MobileFailure catch (failure) {
      if (mounted) showWizardMessage(context, failure.message);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          revision++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => RemotePage(
    title: 'Mi plan',
    dataKey: '$revision',
    load: () => session.api.read('plan'),
    actions: (data) {
      final request = CommercialPlan(data).upgradeRequest;
      final menu = pageMenu([
        if (session.quality && request != null)
          wizardMenuItem<VoidCallback>(
            () => _cancel(request),
            Icons.close_rounded,
            'Cancelar solicitud',
            enabled: !busy,
          ),
      ]);
      return [?menu];
    },
    floating: (data) {
      final plan = CommercialPlan(data);
      if (!session.quality || plan.upgradeRequest != null) return null;
      if (!plan.offers.any((offer) => offer.id != plan.id)) return null;
      return WizardNavPill.action(
        key: const ValueKey('plan-request-upgrade'),
        label: 'Solicitar plan superior',
        icon: Icons.trending_up_rounded,
        onNext: busy ? null : () => _request(plan),
      );
    },
    builder: (data) {
      final palette = IndustryPalette.of(context);
      final plan = CommercialPlan(data);
      final request = plan.upgradeRequest;
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          WizardNavPill.contentPadding,
        ),
        children: [
          const Kicker('Plan de tu empresa'),
          const SizedBox(height: 2),
          Text(plan.name, style: AppTextStyles.figure(context, size: 29)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                if (plan.summary.isNotEmpty) plan.summary,
                'Vigencia: ${periodLabel(plan.periodEndsAt)}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: palette.muted,
              ),
            ),
          ),
          if (request != null) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              key: const ValueKey('plan-open-request'),
              background: palette.accentSoft,
              borderColor: palette.accentSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule, color: palette.accentDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          upgradeRequestStatus(request).$1,
                          style: AppTextStyles.figure(
                            context,
                            size: 17,
                            color: palette.accentDeep,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          upgradeRequestStatus(request).$2,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: palette.accentDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('Uso'),
          SurfaceList(
            children: [
              for (final resource in PlanResource.values)
                PlanUsageRow(plan: plan, resource: resource),
            ],
          ),
          const SectionLabel('Incluye'),
          SurfaceList(
            children: [
              for (final feature in PlanFeature.values)
                _FeatureRow(feature: feature, included: plan.has(feature)),
            ],
          ),
          if (plan.offers.isNotEmpty) ...[
            const SectionLabel('Planes'),
            for (final offer in plan.offers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OfferCard(
                  offer: offer,
                  current: offer.id == plan.id,
                  onTap:
                      session.quality && request == null && offer.id != plan.id
                      ? () => _request(plan, planId: offer.id)
                      : null,
                ),
              ),
          ],
          const Notice(
            'Para cambiar de plan, Métrica te contacta y lo habilita. Tus balanzas, verificaciones e informes se conservan.',
            icon: Icons.support_agent_outlined,
          ),
        ],
      );
    },
  );
}

/// Una fila de uso: "3 de 5" con su barra, o "Sin límite".
class PlanUsageRow extends StatelessWidget {
  const PlanUsageRow({required this.plan, required this.resource, super.key});
  final CommercialPlan plan;
  final PlanResource resource;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final maximum = plan.limit(resource);
    final used = plan.used(resource);
    final full = plan.full(resource);
    final caption =
        resource == PlanResource.monthlyVerifications && plan.openDrafts > 0
        ? '${plan.openDrafts} en curso'
        : null;
    return Padding(
      key: ValueKey('plan-usage-${resource.key}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  resource.label,
                  style: TextStyle(fontSize: 14, color: palette.text),
                ),
              ),
              Text(
                maximum == null ? '$used · sin límite' : '$used de $maximum',
                style: AppTextStyles.figure(
                  context,
                  size: 16,
                  color: full ? palette.fail : null,
                ),
              ),
            ],
          ),
          if (maximum != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: maximum == 0 ? 1 : (used / maximum).clamp(0, 1),
                minHeight: 5,
                backgroundColor: palette.track,
                color: full ? palette.fail : palette.accent,
              ),
            ),
          ],
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption,
                style: TextStyle(fontSize: 11.5, color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.included});
  final PlanFeature feature;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            included ? Icons.check_circle_outline : Icons.lock_outline,
            size: 20,
            color: included ? palette.success : palette.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.label,
                  style: TextStyle(fontSize: 14, color: palette.text),
                ),
                Text(
                  included ? feature.detail : 'En planes superiores.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un plan ofrecido: su nombre, para quien es y lo que trae, en una linea.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.current, this.onTap});
  final CommercialPlan offer;
  final bool current;
  final VoidCallback? onTap;

  String get _includes {
    final parts = <String>[
      for (final resource in [
        PlanResource.plants,
        PlanResource.equipment,
        PlanResource.users,
        PlanResource.monthlyVerifications,
      ])
        if (offer.limit(resource) case final int maximum)
          resource.count(maximum)
        else if (resource != PlanResource.users)
          '${resource.plural} sin límite',
      for (final feature in PlanFeature.values)
        if (offer.has(feature)) feature.label.toLowerCase(),
    ];
    final text = parts.join(' · ');
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return SurfaceCard(
      key: ValueKey('plan-offer-${offer.name}'),
      onTap: onTap,
      borderColor: current ? palette.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.name,
                  style: AppTextStyles.figure(context, size: 19),
                ),
              ),
              if (current)
                Text(
                  'TU PLAN',
                  style: AppTextStyles.caption(
                    context,
                    size: 10.5,
                  ).copyWith(color: palette.accent),
                )
              else if (onTap != null)
                Icon(Icons.chevron_right, color: palette.muted),
            ],
          ),
          if (offer.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                offer.summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: palette.text,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _includes,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solicitud de plan superior: el plan que interesa, lo que se necesita y como
/// contactar. Metrica la atiende en RimMET.
class UpgradeRequestScreen extends StatelessWidget {
  const UpgradeRequestScreen({
    required this.session,
    this.reason = 'GENERAL',
    this.planId,
    super.key,
  });
  final MobileSession session;
  final String reason;
  final String? planId;

  @override
  Widget build(BuildContext context) => RemotePanel(
    frameTitle: 'Solicitar plan superior',
    load: () => session.api.read('plan'),
    builder: (data) {
      final plan = CommercialPlan(data);
      final offers = plan.offers.where((offer) => offer.id != plan.id).toList();
      final email = plan.contactEmail;
      final preferred = offers.any((offer) => offer.id == planId)
          ? planId!
          : offers.firstOrNull?.id ?? '';
      return CustomerForm(
        session: session,
        title: 'Solicitar plan superior',
        action: 'upgrade.request',
        submitLabel: 'Enviar solicitud',
        notice:
            'Métrica recibe tu solicitud con tu nombre'
            '${email == null ? '' : ' y el correo $email'}'
            ' y te contacta para habilitar el cambio. Mientras tanto sigues en el plan ${plan.name}.',
        initial: {
          'planId': preferred,
          'reason': upgradeReasons.containsKey(reason) ? reason : 'GENERAL',
          'message': '',
          'phone': '',
        },
        fields: [
          CustomerField(
            'planId',
            'Plan que te interesa',
            kind: 'select',
            required: false,
            options: {
              for (final offer in offers) offer.id: offer.name,
              '': 'No lo sé, quiero asesoría',
            },
          ),
          const CustomerField(
            'reason',
            'Qué necesitas',
            kind: 'select',
            options: upgradeReasons,
          ),
          const CustomerField(
            'message',
            'Mensaje para Métrica (opcional)',
            required: false,
            max: 2000,
          ),
          CustomerField(
            'phone',
            email == null ? 'Teléfono de contacto' : 'Teléfono (opcional)',
            required: email == null,
            max: 40,
          ),
        ],
      );
    },
  );
}

/// Franja de Inicio para el jefe de calidad: el recurso mas lleno del plan y
/// la entrada a "Mi plan". No es un cuadro mas del mosaico: una linea.
class PlanStrip extends StatelessWidget {
  const PlanStrip({required this.session, super.key});
  final MobileSession session;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final plan = session.plan;
    final resource = plan.tightest;
    final maximum = resource == null ? null : plan.limit(resource);
    final request = plan.upgradeRequest;
    final detail = request != null
        ? upgradeRequestStatus(request).$1
        : resource == null || maximum == null
        ? 'Ver lo que incluye'
        : '${plan.used(resource)} de ${resource.count(maximum)}';
    final full = resource != null && plan.full(resource);
    return SurfaceCard(
      key: const ValueKey('home-plan'),
      onTap: () => openPlan(context, session),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: palette.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan ${plan.name}',
                  style: AppTextStyles.figure(context, size: 16),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: full && request == null
                        ? palette.fail
                        : palette.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            request == null ? 'Mejorar' : 'Ver',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
          ),
          Icon(Icons.chevron_right, color: palette.accent),
        ],
      ),
    );
  }
}

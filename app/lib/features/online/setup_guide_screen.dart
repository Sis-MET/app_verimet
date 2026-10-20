import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/compliance_status.dart';
import '../../shared/theme/app_shapes.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/theme/industry_palette.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/status_tag.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/wizard_chrome.dart';
import 'mobile_session.dart';
import 'online_widgets.dart';
import 'setup_guide.dart';
import 'setup_guide_memory.dart';
import 'setup_guide_scenes.dart';
import 'user_manual.dart';
import 'user_manual_content.dart';

/// Guía de inicio: una portada con todos los pasos y, después, un paso por
/// página en el marco de los asistentes (≡ pasos, línea de progreso y
/// píldora Anterior/Siguiente). Se desliza de un paso a otro.
///
/// Devuelve a dónde ir si se toca «Ir a…»; null si se cierra o se termina.
class SetupGuideScreen extends StatefulWidget {
  const SetupGuideScreen({
    required this.session,
    required this.memory,
    this.resume = false,
    super.key,
  });

  final MobileSession session;
  final GuideMemory memory;

  /// Desde Inicio: directo al primer paso que falta, sin la portada.
  final bool resume;

  @override
  State<SetupGuideScreen> createState() => _SetupGuideScreenState();
}

class _SetupGuideScreenState extends State<SetupGuideScreen>
    with TickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  late final String owner = widget.session.recoveryOwner;
  late GuideMemory memory = widget.memory;
  late bool intro = !widget.resume;
  late int current;
  PageController? pages;

  /// Controladores de una vuelta anterior a la portada. Se liberan al cerrar:
  /// el PageView saliente puede seguir en pantalla durante la transición.
  final retired = <PageController>[];

  /// Vuelta de la escena del paso a la vista.
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: guideSceneLoop,
  );

  /// Entrada de la línea de pasos de la portada.
  late final AnimationController entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool still = false;

  SetupGuide get guide => SetupGuide.of(widget.session, memory);

  @override
  void initState() {
    super.initState();
    final opened = guide;
    current = opened.next;
    if (widget.resume) pages = PageController(initialPage: current);
    // Abierta una vez, ya no se abre sola.
    _remember(
      memory.copyWith(
        dismissed: true,
        visited: widget.resume
            ? {...memory.visited, opened.steps[current].id}
            : null,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      loop
        ..stop()
        ..value = guideSceneRest;
      entrance.value = 1;
    } else {
      if (!loop.isAnimating) unawaited(loop.repeat());
      if (entrance.isDismissed) unawaited(entrance.forward());
    }
  }

  @override
  void dispose() {
    loop.dispose();
    entrance.dispose();
    pages?.dispose();
    for (final old in retired) {
      old.dispose();
    }
    super.dispose();
  }

  void _remember(GuideMemory next) {
    memory = next;
    unawaited(
      widget.session.guideMemory.write(owner, next).catchError((Object _) {}),
    );
  }

  void _visit(int index) {
    final id = guide.steps[index].id;
    setState(() {
      current = index;
      if (!memory.visited.contains(id)) {
        _remember(memory.copyWith(visited: {...memory.visited, id}));
      }
    });
    if (!still) {
      loop.value = 0;
      unawaited(loop.repeat());
    }
  }

  void _goTo(int index) {
    if (intro) {
      if (pages case final old?) retired.add(old);
      pages = PageController(initialPage: index);
      setState(() => intro = false);
      _visit(index);
      return;
    }
    final controller = pages;
    if (controller == null || !controller.hasClients) return;
    if (still) {
      controller.jumpToPage(index);
    } else {
      unawaited(
        controller.animateToPage(
          index,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _next() {
    if (current < guide.steps.length - 1) {
      _goTo(current + 1);
      return;
    }
    _remember(memory.copyWith(finished: true));
    Navigator.of(context).pop();
  }

  void _close([GuideDestination? destination]) =>
      Navigator.of(context).pop(destination);

  void _back() {
    if (closeWizardDrawer(scaffoldKey)) return;
    if (!intro && current > 0) {
      _goTo(current - 1);
    } else if (!intro && !widget.resume) {
      setState(() => intro = true);
    } else {
      _close();
    }
  }

  Future<void> _openManual(String id) async {
    for (final section in ivmetUserManual.sections) {
      if (section.id != id) continue;
      await openPage<void>(
        context,
        ManualSectionScreen(manual: ivmetUserManual, section: section),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    // El servidor puede marcar un paso mientras la guía está abierta.
    child: ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final guide = this.guide;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: intro
              ? KeyedSubtree(
                  key: const ValueKey('guide-intro'),
                  child: _intro(guide),
                )
              : KeyedSubtree(
                  key: const ValueKey('guide-steps'),
                  child: _steps(guide),
                ),
        );
      },
    ),
  );

  Widget _intro(SetupGuide guide) {
    final palette = IndustryPalette.of(context);
    final (title, subtitle) = switch (guide.audience) {
      GuideAudience.selfServiceQuality => (
        'Deja IvMET listo para verificar',
        'Los pasos para configurar tu empresa, en el orden en que conviene hacerlos. Cada uno dice qué tocar y dónde.',
      ),
      GuideAudience.managedQuality => (
        'Deja IvMET listo para verificar',
        'Métrica ya habilitó tus plantas y balanzas. Estos son los pasos que te tocan, en el orden en que conviene hacerlos.',
      ),
      GuideAudience.operator => (
        'Así verificas con IvMET',
        'Lo que necesitas saber antes de tu primera verificación, paso a paso.',
      ),
    };
    // La primera vez se empieza por el principio, aunque haya pasos hechos.
    final started = memory.visited.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const ValueKey('guide-close'),
          tooltip: 'Cerrar la guía',
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        title: const Text('Guía de inicio'),
      ),
      body: SafeArea(
        top: false,
        child: FloatingActionLayout(
          action: WizardNavPill.action(
            key: const ValueKey('guide-start'),
            label: started ? 'Continuar' : 'Empezar',
            icon: Icons.arrow_forward_rounded,
            onNext: () => _goTo(started ? guide.next : 0),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              18,
              8,
              18,
              WizardNavPill.contentPadding,
            ),
            children: [
              Kicker('${guide.audience.label} · ${guide.steps.length} pasos'),
              const SizedBox(height: 2),
              Text(title, style: AppTextStyles.figure(context, size: 29)),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  guide.facts == null
                      ? subtitle
                      : '$subtitle Lo que ya está hecho se marca solo.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.muted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Progress(done: guide.done, total: guide.steps.length),
              const SizedBox(height: 10),
              _Timeline(
                entries: guide.entries,
                animation: entrance,
                onSelect: _goTo,
              ),
              const Notice(
                'Vuelve a esta guía cuando quieras desde Ajustes › Ayuda › «Guía de inicio».',
                icon: Icons.menu_book_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _steps(SetupGuide guide) {
    final last = current == guide.steps.length - 1;
    return WizardScaffold(
      scaffoldKey: scaffoldKey,
      kicker: 'Guía de inicio',
      title: 'Guía de inicio',
      drawerTitle: guide.audience.label,
      steps: [for (final entry in guide.entries) entry.wizard],
      current: current,
      onSelectStep: _goTo,
      actions: [
        IconButton(
          key: const ValueKey('guide-close'),
          tooltip: 'Cerrar la guía',
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ],
      body: PageView.builder(
        key: const ValueKey('guide-pages'),
        controller: pages,
        itemCount: guide.steps.length,
        onPageChanged: _visit,
        itemBuilder: (context, index) => _StepPage(
          key: ValueKey('guide-step-${guide.steps[index].id}'),
          entry: guide.entries[index],
          animation: loop,
          onGo: _close,
          onManual: _openManual,
        ),
      ),
      pill: WizardNavPill(
        label: last ? 'Terminar' : 'Siguiente',
        icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
        onBack: current > 0 ? () => _goTo(current - 1) : null,
        onNext: _next,
      ),
    );
  }
}

/// «4 de 9 pasos listos» y su barra.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          done == total
              ? 'Todo listo · $total de $total'
              : '$done de $total pasos listos',
          style: AppTextStyles.figure(context, size: 16),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : done / total),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 5,
              color: palette.accent,
              backgroundColor: palette.track,
            ),
          ),
        ),
      ],
    );
  }
}

/// Los pasos de la guía en una línea vertical que entra uno detrás de otro.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.entries,
    required this.animation,
    required this.onSelect,
  });
  final List<GuideEntry> entries;
  final Animation<double> animation;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final share = 1 / (entries.length + 3);
    return Column(
      children: [
        for (final (index, entry) in entries.indexed)
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final start = index * share;
              final appear = Curves.easeOutCubic.transform(
                ((animation.value - start) / (share * 4)).clamp(0.0, 1.0),
              );
              return Opacity(
                opacity: appear,
                child: Transform.translate(
                  offset: Offset(18 * (1 - appear), 0),
                  child: child,
                ),
              );
            },
            child: Semantics(
              button: true,
              label: 'Paso ${index + 1}: ${entry.step.title}, ${entry.label}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('guide-timeline-${entry.step.id}'),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => onSelect(index),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            _Badge(number: index + 1, progress: entry.progress),
                            if (index < entries.length - 1)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        entry.progress ==
                                            WizardProgress.complete
                                        ? palette.accent
                                        : palette.divider,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.step.title,
                                style: AppTextStyles.figure(context, size: 18),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.measured
                                    ? entry.label
                                    : entry.step.caption,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color:
                                      entry.measured &&
                                          entry.progress ==
                                              WizardProgress.review
                                      ? palette.fail
                                      : palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Círculo del paso en la portada: visto, «!» o su número.
class _Badge extends StatelessWidget {
  const _Badge({required this.number, required this.progress});
  final int number;
  final WizardProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final (Color? fill, Color border, Widget child) = switch (progress) {
      WizardProgress.complete => (
        palette.accent,
        palette.accent,
        Icon(Icons.check, size: 17, color: palette.card),
      ),
      WizardProgress.review => (
        palette.failSurface,
        palette.fail,
        Icon(Icons.priority_high, size: 16, color: palette.failInk),
      ),
      WizardProgress.pending => (
        null,
        palette.divider,
        Text(
          '$number',
          style: AppTextStyles.figure(context, size: 15, color: palette.muted),
        ),
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.4),
      ),
      child: child,
    );
  }
}

/// Un paso: la escena, cómo va, dónde se hace y qué hacer.
class _StepPage extends StatefulWidget {
  const _StepPage({
    required this.entry,
    required this.animation,
    required this.onGo,
    required this.onManual,
    super.key,
  });
  final GuideEntry entry;
  final Animation<double> animation;
  final ValueChanged<GuideDestination> onGo;
  final ValueChanged<String> onManual;

  @override
  State<_StepPage> createState() => _StepPageState();
}

class _StepPageState extends State<_StepPage> {
  /// Acciones que quien lee fue marcando, como en el manual.
  final ticked = <int>{};

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final entry = widget.entry;
    final step = entry.step;
    final destination = step.destination;
    final manual = step.manual;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        WizardNavPill.contentPadding,
      ),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: GuideSceneView(scene: step.scene, animation: widget.animation),
        ),
        const SizedBox(height: 16),
        if (entry.measured)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusTag(
                key: ValueKey('guide-status-${step.id}'),
                entry.progress == WizardProgress.complete
                    ? 'Listo · ${entry.label}'
                    : entry.label,
                status: switch (entry.progress) {
                  WizardProgress.complete => ComplianceStatus.conforme,
                  WizardProgress.review => ComplianceStatus.noConforme,
                  WizardProgress.pending => null,
                },
              ),
            ),
          ),
        WizardStepHeading(title: step.title, caption: step.caption),
        if (step.route.isNotEmpty) ...[
          const SectionLabel('Dónde'),
          GuideRouteView(route: step.route, animation: widget.animation),
        ],
        SectionLabel(
          ticked.isEmpty
              ? 'Qué hacer'
              : 'Qué hacer · ${ticked.length} de ${step.actions.length}',
        ),
        SurfaceList(
          children: [
            for (final (index, action) in step.actions.indexed)
              _ActionRow(
                number: index + 1,
                action: action,
                done: ticked.contains(index),
                onTap: () => setState(
                  () => ticked.contains(index)
                      ? ticked.remove(index)
                      : ticked.add(index),
                ),
              ),
          ],
        ),
        if (step.terms.isNotEmpty) ...[
          SectionLabel(step.termsTitle),
          SurfaceList(
            children: [
              for (final term in step.terms)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${term.term}  ',
                          style: AppTextStyles.figure(context, size: 15.5),
                        ),
                        TextSpan(
                          text: term.meaning,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        for (final note in step.notes)
          Notice(
            '${note.kind.label}: ${note.content}',
            icon: note.kind.icon,
            alert: note.kind == ManualNoteKind.important,
          ),
        if (destination != null || manual != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (destination != null)
                  OutlinedButton.icon(
                    key: ValueKey('guide-go-${step.id}'),
                    onPressed: () => widget.onGo(destination),
                    icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                    label: Text(step.destinationLabel ?? 'Ir ahora'),
                  ),
                if (manual != null)
                  TextButton.icon(
                    key: ValueKey('guide-manual-${step.id}'),
                    onPressed: () => widget.onManual(manual),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Ver en el manual'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.number,
    required this.action,
    required this.done,
    required this.onTap,
  });
  final int number;
  final ManualStep action;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Semantics(
      checked: done,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? palette.success : palette.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: done
                    ? Icon(Icons.check, size: 16, color: palette.card)
                    : Text(
                        '$number',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: palette.accentDeep,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.action,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    if (action.detail case final detail?)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: palette.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Franja de Inicio mientras la guía no se termine: cuánto falta y por dónde
/// seguir. Es una línea, no un cuadro más.
class GuideStrip extends StatelessWidget {
  const GuideStrip({required this.guide, required this.onTap, super.key});
  final SetupGuide guide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final total = guide.steps.length;
    final done = guide.done;
    return SurfaceCard(
      key: const ValueKey('home-guide'),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, color: palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guía de inicio',
                      style: AppTextStyles.figure(context, size: 16),
                    ),
                    Text(
                      done == total
                          ? 'Todo listo · repásala cuando quieras'
                          : '$done de $total pasos · sigue: ${guide.steps[guide.next].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ],
                ),
              ),
              Text(
                'Continuar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
              Icon(Icons.chevron_right, color: palette.accent),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 4,
              color: palette.accent,
              backgroundColor: palette.track,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';
import 'section_label.dart';

/// Piezas del marco de un asistente por pasos, el mismo de la calibracion de
/// ServiceMET: el AppBar solo dice donde se esta, los pasos viven en un panel
/// lateral que se abre con ≡, las acciones extra van en ⋮ y la navegacion es
/// una pildora flotante abajo a la derecha. Asi el paso tiene la pantalla para
/// el.

/// Como va un paso.
enum WizardProgress {
  /// Hecho, o no requiere nada.
  complete,

  /// Se paso por el pero le falta algo.
  review,

  /// Todavia no se lleno.
  pending,
}

@immutable
class WizardStep {
  const WizardStep({
    required this.title,
    required this.detail,
    required this.progress,
    this.enabled = true,
  });

  final String title;

  /// Una linea bajo el titulo en el panel: "3 de 5 lecturas", "Omitida".
  final String detail;
  final WizardProgress progress;
  final bool enabled;
}

/// "Paso 2 de 5 · Excentricidad", bajo el titulo del AppBar.
String wizardProgressLabel(List<WizardStep> steps, int current) =>
    'Paso ${current + 1} de ${steps.length} · ${steps[current].title}';

/// Titulo de dos lineas del AppBar: que se verifica y en que paso va.
class WizardTitle extends StatelessWidget {
  const WizardTitle({required this.title, required this.subtitle, super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.figure(context, size: 19),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption(context, size: 11.5),
      ),
    ],
  );
}

/// Linea de progreso bajo el AppBar: un tramo por paso. Ocupa 3 px y dice lo
/// que antes decia una fila de circulos numerados.
class WizardProgressBar extends StatelessWidget implements PreferredSizeWidget {
  const WizardProgressBar({
    required this.steps,
    required this.current,
    super.key,
  });
  final List<WizardStep> steps;
  final int current;

  @override
  Size get preferredSize => const Size.fromHeight(7);

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  color: i == current
                      ? palette.accentInk
                      : switch (steps[i].progress) {
                          WizardProgress.complete => palette.accent,
                          WizardProgress.review => palette.fail,
                          WizardProgress.pending => palette.track,
                        },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panel lateral con todos los pasos. Marca los completos, los que quedaron
/// por revisar y el actual, y lleva a cualquiera habilitado.
class WizardStepsDrawer extends StatelessWidget {
  const WizardStepsDrawer({
    required this.kicker,
    required this.title,
    required this.steps,
    required this.current,
    required this.onSelect,
    super.key,
  });

  final String kicker;
  final String title;
  final List<WizardStep> steps;
  final int current;

  /// Paso elegido, con el panel ya cerrandose. Quien lo recibe decide si se
  /// puede ir (validar el paso actual, guardar...).
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final done = steps
        .where((step) => step.progress == WizardProgress.complete)
        .length;

    return Drawer(
      backgroundColor: palette.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kicker(kicker),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.figure(context, size: 26),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$done de ${steps.length} pasos completos',
                    style: TextStyle(fontSize: 12.5, color: palette.muted),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: steps.isEmpty ? 0 : done / steps.length,
                      minHeight: 4,
                      color: palette.accent,
                      backgroundColor: palette.track,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: steps.length,
                itemBuilder: (context, index) => _StepTile(
                  index: index,
                  total: steps.length,
                  step: steps[index],
                  current: index == current,
                  onTap: () {
                    Scaffold.maybeOf(context)?.closeDrawer();
                    if (index != current) onSelect(index);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.total,
    required this.step,
    required this.current,
    required this.onTap,
  });
  final int index;
  final int total;
  final WizardStep step;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    // El paso actual nunca se muestra bloqueado: ya se esta en el.
    final locked = !step.enabled && !current;
    final review = step.progress == WizardProgress.review;
    final corners = BorderRadius.circular(AppRadius.sm);
    final status = locked
        ? 'bloqueado'
        : switch (step.progress) {
            WizardProgress.complete => 'completo',
            WizardProgress.review => 'falta completar',
            WizardProgress.pending => 'pendiente',
          };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        container: true,
        button: true,
        enabled: !locked,
        selected: current,
        label:
            'Paso ${index + 1} de $total: ${step.title}, $status'
            '${current ? ', paso actual' : ''}',
        excludeSemantics: true,
        onTap: locked ? null : onTap,
        child: Material(
          key: ValueKey('wizard-step-$index'),
          color: current ? palette.accentSoft : Colors.transparent,
          borderRadius: corners,
          child: InkWell(
            borderRadius: corners,
            onTap: locked ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _StepBadge(
                    number: index + 1,
                    progress: step.progress,
                    current: current,
                    locked: locked,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.figure(
                            context,
                            size: 17,
                            color: locked ? palette.muted : palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: review && !locked
                                ? palette.fail
                                : palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circulo del paso: visto si esta completo, "!" si le falta algo, candado si
/// no se puede abrir y, si no, su numero (con aro en el actual).
class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.progress,
    required this.current,
    required this.locked,
  });
  final int number;
  final WizardProgress progress;
  final bool current;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    Widget circle({Color? fill, Color? border, required Widget child}) =>
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border == null
                ? null
                : Border.all(color: border, width: current ? 2 : 1.4),
          ),
          child: child,
        );

    if (locked) {
      return circle(
        border: palette.divider,
        child: Icon(Icons.lock_outline, size: 14, color: palette.muted),
      );
    }
    return switch (progress) {
      WizardProgress.complete => circle(
        fill: palette.accent,
        border: current ? palette.accentInk : null,
        child: Icon(Icons.check, size: 17, color: palette.card),
      ),
      WizardProgress.review => circle(
        fill: palette.failSurface,
        border: palette.fail,
        child: Icon(Icons.priority_high, size: 16, color: palette.failInk),
      ),
      WizardProgress.pending => circle(
        border: current ? palette.accentInk : palette.divider,
        child: Text(
          '$number',
          style: AppTextStyles.figure(
            context,
            size: 15,
            color: current ? palette.accentInk : palette.muted,
          ),
        ),
      ),
    };
  }
}

/// Pildora flotante de navegacion: Anterior (circulo) y la accion del paso.
///
/// Va abajo a la derecha, al alcance del pulgar, sobre el contenido; el paso
/// deja [WizardNavPill.contentPadding] libre al final para que lo ultimo se
/// lea. El teclado numerico ocupa su lugar mientras esta abierto.
class WizardNavPill extends StatelessWidget {
  const WizardNavPill({
    required this.label,
    this.onNext,
    this.onBack,
    this.icon,
    this.showBack = true,
    super.key,
  });

  /// La misma pildora con solo la accion principal, para formularios de una
  /// pagina: la accion queda fija a la vista en lugar de al final de la lista.
  const WizardNavPill.action({
    required this.label,
    this.onNext,
    this.icon,
    super.key,
  }) : onBack = null,
       showBack = false;

  /// Espacio que el contenido deja libre bajo su ultimo elemento.
  static const double contentPadding = 104;

  final String label;
  final IconData? icon;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final shape = BorderRadius.circular(AppRadius.pill);
    final canGoBack = onBack != null;

    return DecoratedBox(
      key: const ValueKey('wizard-nav'),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: shape,
        border: Border.all(color: palette.divider),
        boxShadow: AppShadows.floating(palette.shadow),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack) ...[
              Tooltip(
                message: 'Anterior',
                child: Semantics(
                  button: true,
                  enabled: canGoBack,
                  label: 'Anterior',
                  excludeSemantics: true,
                  child: Material(
                    color: canGoBack ? palette.accentSoft : Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onBack,
                      child: SizedBox.square(
                        dimension: 46,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: canGoBack
                              ? palette.accentInk
                              : palette.divider,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Semantics(
              key: const ValueKey('wizard-next'),
              button: true,
              enabled: onNext != null,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: Material(
                  key: ValueKey(label),
                  color: onNext != null ? palette.accent : palette.track,
                  borderRadius: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onNext,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 13, 20, 13),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: AppFonts.heading,
                              fontFamilyFallback: AppFonts.fallback,
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              height: 1.1,
                              letterSpacing: 0.3,
                              color: onNext != null
                                  ? palette.card
                                  : palette.muted,
                            ),
                          ),
                          if (icon != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              icon,
                              size: 18,
                              color: onNext != null
                                  ? palette.card
                                  : palette.muted,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Encabezado de un paso dentro del contenido: el nombre y que hacer, en dos
/// lineas. Se desplaza con el paso; el AppBar ya recuerda donde se esta.
class WizardStepHeading extends StatelessWidget {
  const WizardStepHeading({required this.title, this.caption, super.key});
  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.figure(context, size: 25)),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              caption!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: IndustryPalette.of(context).muted,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Aviso breve de un asistente o formulario, flotando sobre la pildora para no
/// taparla.
void showWizardMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 86),
      ),
    );
}

/// Lleva al primer campo con error del formulario y lo dice. Sin esto, el
/// error quedaba marcado en un campo que podia estar fuera de la pantalla y
/// el boton parecia no responder.
void revealFirstFormError(
  BuildContext context,
  GlobalKey<FormState> form, {
  String message = 'Completa los datos marcados para continuar.',
}) {
  FormFieldState<dynamic>? first;
  void visit(Element element) {
    if (first != null) return;
    if (element is StatefulElement &&
        element.state is FormFieldState &&
        (element.state as FormFieldState).hasError) {
      first = element.state as FormFieldState;
      return;
    }
    element.visitChildren(visit);
  }

  form.currentContext?.visitChildElements(visit);
  final target = first;
  if (target != null) {
    unawaited(
      Scrollable.ensureVisible(
        target.context,
        alignment: 0.25,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }
  showWizardMessage(context, message);
}

/// Marco completo de un asistente: AppBar limpio con ≡, el titulo y "Paso N
/// de M", acciones a la derecha y la linea de progreso; el panel de pasos a
/// la izquierda; la pildora flotante abajo a la derecha.
///
/// El contenido deja [WizardNavPill.contentPadding] libre al final. [footer]
/// va bajo el contenido y fuera del area de la pildora (el teclado numerico
/// de la captura).
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    required this.scaffoldKey,
    required this.kicker,
    required this.title,
    required this.steps,
    required this.current,
    required this.onSelectStep,
    required this.body,
    required this.pill,
    this.drawerTitle,
    this.actions = const [],
    this.banner,
    this.footer,
    this.onDrawerOpened,
    super.key,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;

  /// Rotulo pequeno del panel: "Verificación intermedia".
  final String kicker;

  /// Primera linea del AppBar.
  final String title;

  /// Titulo grande del panel; por defecto, [title].
  final String? drawerTitle;
  final List<WizardStep> steps;
  final int current;
  final ValueChanged<int> onSelectStep;
  final Widget body;
  final Widget pill;
  final List<Widget> actions;

  /// Aviso fijo bajo el AppBar (un error de guardado).
  final Widget? banner;
  final Widget? footer;

  /// Al abrir el panel. Siempre se quita el foco: el teclado del sistema no
  /// queda abierto debajo del panel.
  final VoidCallback? onDrawerOpened;

  static const stepsTooltip = 'Pasos';

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    drawer: WizardStepsDrawer(
      kicker: kicker,
      title: drawerTitle ?? title,
      steps: steps,
      current: current,
      onSelect: onSelectStep,
    ),
    onDrawerChanged: (open) {
      if (!open) return;
      onDrawerOpened?.call();
      FocusManager.instance.primaryFocus?.unfocus();
    },
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: stepsTooltip,
        icon: const Icon(Icons.menu),
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      centerTitle: true,
      title: WizardTitle(
        title: title,
        subtitle: wizardProgressLabel(steps, current),
      ),
      actions: actions,
      bottom: WizardProgressBar(steps: steps, current: current),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          ?banner,
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(right: 16, bottom: 16, child: pill),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    ),
  );
}

/// Atras del sistema dentro de un asistente: cierra el panel si esta abierto
/// y si no, delega. Devuelve si lo atendio el panel.
bool closeWizardDrawer(GlobalKey<ScaffoldState> scaffold) {
  final state = scaffold.currentState;
  if (state != null && state.isDrawerOpen) {
    state.closeDrawer();
    return true;
  }
  return false;
}

/// Opcion del menu ⋮: icono y texto en una fila que no se desborda durante
/// la animacion del menu.
PopupMenuItem<T> wizardMenuItem<T>(
  T value,
  IconData icon,
  String label, {
  bool enabled = true,
}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 14),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  ),
);

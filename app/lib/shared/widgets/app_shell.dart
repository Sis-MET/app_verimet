import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';
import 'industry_icons.dart';

/// Margen de las pantallas que van bajo la barra flotante.
///
/// Los 132 px de abajo son el hueco de la barra mas su aire: la barra va
/// encima del contenido, asi que cada pantalla se aparta ella misma en vez de
/// que el marco le recorte el final del scroll.
const EdgeInsets kShellContentPadding = EdgeInsets.fromLTRB(18, 16, 18, 132);

/// Los cuatro apartados de la app.
///
/// El shell que los conmuta lo implementa `features/online/workspace_screen`,
/// que mantiene el apartado activo en su propio estado. Antes existia aqui un
/// `AppShell` montado sobre `StatefulNavigationShell` de go_router, para un
/// arbol de rutas que la app nunca llego a declarar.
enum AppSection {
  inicio('Inicio', IndustryIcon.home),
  verificar('Verificar', IndustryIcon.clipboardCheck),
  areas('Plantas', IndustryIcon.grid),
  ajustes('Ajustes', IndustryIcon.sliders);

  const AppSection(this.label, this.icon);

  final String label;
  final IndustryIcon icon;
}

/// Barra de navegacion flotante con icono y etiqueta.
///
/// El aire interior y el radio de la pastilla activa estan atados: la pastilla
/// usa [AppRadius.nested] sobre el radio de la barra, para que las dos curvas
/// sean concentricas y la esquina no se vea torcida.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.current,
    required this.onSelect,
    super.key,
  });

  /// Aire entre el borde de la barra y las pastillas.
  static const double _inset = 6;

  final AppSection current;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final corners = BorderRadius.circular(AppRadius.lg);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: AppShadows.floating(palette.shadow),
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(_inset),
            decoration: BoxDecoration(
              color: palette.navBackground,
              borderRadius: corners,
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                for (final section in AppSection.values) ...[
                  if (section.index > 0) const SizedBox(width: 2),
                  Expanded(
                    child: _NavButton(
                      section: section,
                      isActive: section == current,
                      onTap: () => onSelect(section),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.section,
    required this.isActive,
    required this.onTap,
  });

  final AppSection section;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final foreground = isActive ? palette.card : palette.muted;
    final corners = BorderRadius.circular(
      AppRadius.nested(AppRadius.lg, FloatingNavBar._inset),
    );

    return Semantics(
      button: true,
      selected: isActive,
      label: section.label,
      child: Material(
        color: isActive ? palette.accent : Colors.transparent,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners,
          child: SizedBox(
            height: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IndustryIconView(section.icon, color: foreground),
                const SizedBox(height: 4),
                Text(
                  section.label,
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    fontFamilyFallback: AppFonts.fallback,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    height: 1.1,
                    letterSpacing: 10.5 * 0.04,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

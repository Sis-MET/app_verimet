import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Selector de vista: modos excluyentes de una misma pantalla, en pastillas.
///
/// "Por planta" y "Lista completa" eran dos modulos del mosaico, y Verificar
/// quedaba hecha de cuadros de arriba abajo: el selector pesaba lo mismo que
/// el contenido que elige. Cambiar de vista no es una funcion aparte, asi que
/// va en un control compacto.
///
/// Es el `.seg` del design system —plano de tarjeta, contorno suave y la
/// opcion activa en acero— en pastilla completa. La activa va dentro del riel
/// con un aire fijo, como en la barra de navegacion.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    required this.segments,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// Aire entre el borde del riel y las pastillas.
  static const double _inset = 4;

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.divider),
      ),
      // Con "Texto grande" un rotulo puede partirse en dos lineas: las
      // pastillas se igualan a la mas alta en vez de quedar desparejas.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: _inset),
              Expanded(
                child: _Pill(
                  label: segments[i].label,
                  active: segments[i].value == selected,
                  onTap: () => onSelect(segments[i].value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una opcion del selector.
class PillSegment<T> {
  const PillSegment(this.value, this.label);

  final T value;
  final String label;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final shape = BorderRadius.circular(AppRadius.pill);

    return Semantics(
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: active ? palette.accent : Colors.transparent,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: ConstrainedBox(
            // El minimo tactil: se usa de pie, con el equipo en la otra mano.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    fontFamilyFallback: AppFonts.fallback,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.15,
                    letterSpacing: 16 * 0.02,
                    color: active ? palette.card : palette.mutedStrong,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

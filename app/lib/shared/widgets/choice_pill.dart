import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';
import '../theme/app_typography.dart';
import '../theme/industry_palette.dart';

/// Opcion de una lista corta que no cabe en [SegmentedPills]: accesos rapidos,
/// filtros, plantas. Pastilla rellena de acero cuando esta elegida.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = IndustryPalette.of(context);
    final shape = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.accent : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(color: selected ? palette.accent : palette.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? palette.card : palette.mutedStrong,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.heading,
                      fontFamilyFallback: AppFonts.fallback,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.1,
                      color: selected ? palette.card : palette.mutedStrong,
                    ),
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

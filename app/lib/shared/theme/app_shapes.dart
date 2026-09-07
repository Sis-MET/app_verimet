import 'package:flutter/material.dart';

/// Escala de redondeo del sistema.
///
/// Una sola escala para toda la app: si dos elementos se tocan, el de fuera
/// usa el escalon siguiente. Cuando algo va anidado (un boton dentro de una
/// tarjeta, la pastilla activa dentro de la barra) el radio interior se
/// calcula con [nested], que descuenta el aire — de lo contrario las dos
/// curvas no son concentricas y la esquina se ve torcida.
abstract final class AppRadius {
  /// Etiquetas de estado y celdas pequenas.
  static const double xs = 10;

  /// Botones, campos y chips.
  static const double sm = 14;

  /// Tarjetas, modulos del mosaico y filas agrupadas.
  static const double md = 18;

  /// Capas que flotan: barra de navegacion, dialogos, hojas.
  static const double lg = 26;

  /// Pastilla completa.
  static const double pill = 999;

  static BorderRadius get tag => BorderRadius.circular(xs);
  static BorderRadius get control => BorderRadius.circular(sm);
  static BorderRadius get card => BorderRadius.circular(md);
  static BorderRadius get floating => BorderRadius.circular(lg);

  /// Radio de un elemento metido dentro de otro con [inset] px de aire.
  static double nested(double outer, double inset) =>
      (outer - inset).clamp(0.0, outer);
}

/// Elevacion del sistema.
///
/// Es deliberadamente corta: una sombra suave y muy difusa para lo que flota,
/// y nada para lo que esta apoyado en el plano. En oscuro las sombras no se
/// leen, asi que la separacion la hace el valor de la tarjeta y no la sombra.
abstract final class AppShadows {
  /// Barra de navegacion y hojas: flotan por encima del contenido.
  static List<BoxShadow> floating(Color shadow) => <BoxShadow>[
    BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8)),
  ];

  /// Tarjeta apoyada: apenas un halo que despega el modulo del fondo.
  static List<BoxShadow> resting(Color shadow) => <BoxShadow>[
    BoxShadow(color: shadow, blurRadius: 10, offset: const Offset(0, 2)),
  ];
}

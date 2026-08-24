/// Estado de cumplimiento de un instrumento frente a su plan de
/// verificaciones intermedias.
///
/// No es lo mismo que [TestVerdict]: una prueba puede salir conforme y el
/// equipo seguir vencido porque la verificacion se hizo fuera de plazo.
enum ComplianceStatus {
  /// Dentro de tolerancia y al dia.
  conforme('Conforme'),

  /// Dentro de tolerancia pero rozando el limite, o proximo a vencer.
  observado('Observado'),

  /// Fuera de tolerancia o con la verificacion vencida. Bloquea el uso del
  /// equipo para pesaje fiscal hasta que se registre la correccion.
  noConforme('No conforme');

  const ComplianceStatus(this.label);

  final String label;
}

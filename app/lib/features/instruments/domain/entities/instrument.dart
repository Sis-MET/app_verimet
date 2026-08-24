import '../../../../core/domain/compliance_status.dart';

/// Instrumento de pesaje sujeto a verificaciones intermedias.
class Instrument {
  const Instrument({
    required this.codigo,
    required this.tipo,
    required this.detalle,
    required this.area,
    required this.status,
    required this.estadoLabel,
    this.marcaModelo,
    this.alcanceMaximo,
    this.division,
    this.clase,
    this.ultimaVerificacion,
  });

  /// Codigo de placa: es lo que el operario lee del QR pegado al equipo.
  final String codigo;

  final String tipo;

  /// Segunda linea de la lista ("Mettler ICS449 · verif. 14 may").
  final String detalle;

  final String area;

  final ComplianceStatus status;

  /// Texto del estado. No siempre coincide con `status.label`: un equipo
  /// puede estar "Vencida" y contar como no conforme.
  final String estadoLabel;

  final String? marcaModelo;

  /// Alcance maximo con su unidad, tal como se muestra ("60,00 kg").
  final String? alcanceMaximo;

  /// Division de escala (d).
  final String? division;

  /// Clase de exactitud OIML (III, IIII...).
  final String? clase;

  final String? ultimaVerificacion;
}

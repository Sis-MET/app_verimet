import '../../../../core/domain/compliance_status.dart';

/// Una verificacion intermedia ya cerrada, vista desde el historico del
/// equipo. Guarda el error de cada prueba para poder ver la deriva.
class VerificationHistoryEntry {
  const VerificationHistoryEntry({
    required this.fecha,
    required this.responsable,
    required this.errorExcentricidad,
    required this.desviacionRepetibilidad,
    required this.errorLinealidad,
    required this.veredicto,
  });

  final String fecha;
  final String responsable;
  final String errorExcentricidad;
  final String desviacionRepetibilidad;
  final String errorLinealidad;
  final ComplianceStatus veredicto;
}

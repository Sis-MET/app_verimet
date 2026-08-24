import '../../../../core/domain/compliance_status.dart';

/// Recuento del parque de equipos del cliente.
class ParkSummary {
  const ParkSummary({
    required this.equipos,
    required this.areas,
    required this.conformes,
    required this.observados,
    required this.noConformes,
    required this.pendientesDeSincronizar,
  });

  final int equipos;
  final int areas;
  final int conformes;
  final int observados;
  final int noConformes;

  /// Verificaciones capturadas en planta que todavia no llegaron al servidor.
  final int pendientesDeSincronizar;

  /// Porcentaje de equipos conformes, redondeado como se muestra en pantalla.
  int get conformidad => equipos == 0 ? 0 : (conformes / equipos * 100).round();
}

/// Equipo que necesita atencion hoy: fuera de tolerancia o con la
/// verificacion vencida.
class CriticalAlert {
  const CriticalAlert({required this.equipo, required this.detalle});

  final String equipo;
  final String detalle;
}

/// Verificacion vencida o por vencer.
class DueVerification {
  const DueVerification({
    required this.codigo,
    required this.descripcion,
    required this.plazo,
    required this.vencida,
  });

  final String codigo;

  /// Area y tipo de equipo ("Almacén · plataforma 60 kg").
  final String descripcion;

  /// Plazo ya redactado ("Vencida 8 d", "En 3 d").
  final String plazo;

  final bool vencida;
}

/// Ultima verificacion registrada sobre un equipo.
class RecentVerification {
  const RecentVerification({
    required this.codigo,
    required this.fecha,
    required this.responsable,
    required this.veredicto,
  });

  final String codigo;
  final String fecha;
  final String responsable;
  final ComplianceStatus veredicto;
}

/// Calibracion externa programada. No la hace la app: la hace un laboratorio
/// acreditado y aqui solo se avisa para que no se pase la fecha.
class ExternalCalibration {
  const ExternalCalibration({required this.equipo, required this.fecha});

  final String equipo;
  final String fecha;
}

/// Todo lo que se pinta en Inicio, resuelto de una sola vez.
class DashboardOverview {
  const DashboardOverview({
    required this.summary,
    required this.alertas,
    required this.vencimientos,
    required this.ultimas,
    required this.calibraciones,
  });

  final ParkSummary summary;
  final List<CriticalAlert> alertas;
  final List<DueVerification> vencimientos;
  final List<RecentVerification> ultimas;
  final List<ExternalCalibration> calibraciones;
}

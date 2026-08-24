import '../../../../core/domain/compliance_status.dart';
import '../../domain/entities/dashboard_overview.dart';

/// Estado del parque de referencia mientras no exista
/// `GET /api/v1/dashboard`.
///
/// Las cifras son las del prototipo de diseno y son coherentes con
/// `InstrumentsDemoData`: los mismos equipos, los mismos veredictos.
abstract final class DashboardDemoData {
  static const DashboardOverview overview = DashboardOverview(
    summary: ParkSummary(
      equipos: 48,
      areas: 4,
      conformes: 41,
      observados: 5,
      noConformes: 2,
      pendientesDeSincronizar: 3,
    ),
    alertas: <CriticalAlert>[
      CriticalAlert(
        equipo: 'PRO-007 · Plataforma 150 kg',
        detalle: 'Linealidad fuera de tolerancia el 11 ago (+0,05 kg)',
      ),
      CriticalAlert(
        equipo: 'BAL-014 · Plataforma 60 kg',
        detalle: 'Verificación intermedia vencida hace 8 días',
      ),
    ],
    vencimientos: <DueVerification>[
      DueVerification(
        codigo: 'BAL-014',
        descripcion: 'Almacén · plataforma 60 kg',
        plazo: 'Vencida 8 d',
        vencida: true,
      ),
      DueVerification(
        codigo: 'LAB-002',
        descripcion: 'Laboratorio · analítica 220 g',
        plazo: 'En 3 d',
        vencida: false,
      ),
      DueVerification(
        codigo: 'PRO-011',
        descripcion: 'Producción · dosificadora',
        plazo: 'En 9 d',
        vencida: false,
      ),
    ],
    ultimas: <RecentVerification>[
      RecentVerification(
        codigo: 'PRO-014',
        fecha: '19 ago',
        responsable: 'J. Morales',
        veredicto: ComplianceStatus.conforme,
      ),
      RecentVerification(
        codigo: 'PRO-007',
        fecha: '11 ago',
        responsable: 'R. Chávez',
        veredicto: ComplianceStatus.noConforme,
      ),
      RecentVerification(
        codigo: 'BAL-021',
        fecha: '02 ago',
        responsable: 'J. Morales',
        veredicto: ComplianceStatus.conforme,
      ),
    ],
    calibraciones: <ExternalCalibration>[
      ExternalCalibration(equipo: 'BAL-021 · Almacén', fecha: '12 sep 2026'),
      ExternalCalibration(equipo: 'LAB-002 · Laboratorio', fecha: '30 sep 2026'),
    ],
  );
}

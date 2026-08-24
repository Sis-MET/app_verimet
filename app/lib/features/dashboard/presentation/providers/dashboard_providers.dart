import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/dashboard_demo_data.dart';
import '../../domain/entities/dashboard_overview.dart';

/// Estado del parque para la pantalla de Inicio.
///
/// DEMO: sale de [DashboardDemoData]. El repositorio real leera primero la
/// copia local y solo despues intentara refrescar contra
/// `GET /api/v1/dashboard`: en planta lo habitual es entrar sin VPN, y una
/// pantalla vacia no sirve de nada.
final dashboardOverviewProvider = Provider<DashboardOverview>((ref) => DashboardDemoData.overview);

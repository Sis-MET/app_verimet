import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/placeholder_screen.dart';
import 'app_routes.dart';

/// Router de la app.
///
/// Scaffold: todas las rutas apuntan a [PlaceholderScreen]. Cada feature
/// reemplaza su `builder` por la pantalla real cuando la implemente, y aca se
/// agrega el redirect de sesion (si no hay token -> [AppRoutes.login]).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    // TODO(IvMET-auth): redirect basado en el estado de sesion de la feature auth.
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const PlaceholderScreen(title: 'IvMET'),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const PlaceholderScreen(title: 'Iniciar sesion', feature: 'auth'),
      ),
      GoRoute(
        path: AppRoutes.instruments,
        builder: (_, _) => const PlaceholderScreen(title: 'Instrumentos', feature: 'instruments'),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, _) =>
                const PlaceholderScreen(title: 'Detalle del instrumento', feature: 'instruments'),
            routes: [
              GoRoute(
                path: 'eccentricity',
                builder: (_, _) => const PlaceholderScreen(
                    title: 'Excentricidad', feature: 'eccentricity_test'),
              ),
              GoRoute(
                path: 'repeatability',
                builder: (_, _) => const PlaceholderScreen(
                    title: 'Repetibilidad', feature: 'repeatability_test'),
              ),
              GoRoute(
                path: 'linearity',
                builder: (_, _) =>
                    const PlaceholderScreen(title: 'Linealidad', feature: 'linearity_test'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.verificationReports,
        builder: (_, _) =>
            const PlaceholderScreen(title: 'Reportes', feature: 'verification_reports'),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const PlaceholderScreen(title: 'Dashboard', feature: 'dashboard'),
      ),
      GoRoute(
        path: AppRoutes.syncQueue,
        builder: (_, _) => const PlaceholderScreen(title: 'Sincronizacion', feature: 'sync'),
      ),
    ],
  );
});

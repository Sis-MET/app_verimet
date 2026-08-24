import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/dashboard/presentation/screens/home_screen.dart';
import '../../features/instruments/presentation/screens/area_instruments_screen.dart';
import '../../features/instruments/presentation/screens/areas_screen.dart';
import '../../features/instruments/presentation/screens/instrument_history_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/verification_reports/presentation/screens/verification_wizard_screen.dart';
import '../../shared/widgets/app_shell.dart';
import 'app_routes.dart';

/// Router de la app.
///
/// Dos zonas: el login, que ocupa la pantalla entera, y el marco con la barra
/// flotante, que agrupa los cuatro apartados. Cada apartado es una rama con su
/// propia pila, asi que salir de un equipo a Ajustes y volver deja el equipo
/// donde estaba.
final routerProvider = Provider<GoRouter>((ref) {
  // Puente entre el estado de sesion de Riverpod y el refresco del router.
  final sessionChanged = ValueNotifier<bool>(ref.read(isSignedInProvider));
  ref.onDispose(sessionChanged.dispose);
  ref.listen<bool>(isSignedInProvider, (_, next) => sessionChanged.value = next);

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    refreshListenable: sessionChanged,
    redirect: (context, state) {
      final signedIn = ref.read(isSignedInProvider);
      final goingToLogin = state.matchedLocation == AppRoutes.login;

      // Sin sesion no hay nada que mirar: la app no tiene modo invitado.
      if (!signedIn) return goingToLogin ? null : AppRoutes.login;
      if (goingToLogin || state.matchedLocation == AppRoutes.splash) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, redirect: (_, _) => AppRoutes.home),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.verification,
                builder: (_, _) => const VerificationWizardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.areas,
                builder: (_, _) => const AreasScreen(),
                routes: [
                  GoRoute(
                    path: ':area',
                    builder: (_, state) =>
                        AreaInstrumentsScreen(area: state.pathParameters['area']!),
                    routes: [
                      GoRoute(
                        path: ':codigo',
                        builder: (_, state) => InstrumentHistoryScreen(
                          area: state.pathParameters['area']!,
                          codigo: state.pathParameters['codigo']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.settings, builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
  );
});

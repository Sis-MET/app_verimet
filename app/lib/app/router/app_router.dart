import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/online/online_entry.dart';

/// La puerta online es el único acceso. El prototipo demo no tiene rutas.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const OnlineEntry())],
  );
  ref.onDispose(router.dispose);
  return router;
});

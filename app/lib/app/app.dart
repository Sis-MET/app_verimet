import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_config.dart';
import '../features/settings/presentation/providers/settings_providers.dart';
import '../shared/theme/app_theme.dart';
import 'router/app_router.dart';

/// Widget raiz de IvMET.
class IvmetApp extends ConsumerWidget {
  const IvmetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final largeText = ref.watch(largeTextProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // "Texto grande" sube el suelo del escalado un 12 %, y en todo caso se le
      // pone techo: por encima de ~1,35 las filas de lectura dejan de caber en
      // una linea y la comparacion en columna, que es para lo que estan, se
      // pierde.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: largeText ? 1.12 : 1,
        maxScaleFactor: 1.35,
        child: child!,
      ),
    );
  }
}

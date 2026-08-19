import 'package:flutter/material.dart';

/// Pantalla temporal usada por las rutas todavia no implementadas.
///
/// Se borra a medida que cada feature entrega su pantalla real en
/// `features/<feature>/presentation/screens/`.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, this.feature, super.key});

  final String title;

  /// Feature responsable de esta ruta (para orientar a quien la implemente).
  final String? feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                feature == null
                    ? 'Pantalla pendiente de implementacion.'
                    : 'Pendiente: features/$feature/presentation/screens/',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

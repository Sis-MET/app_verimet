import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/storage/draft_recovery_store.dart';
import 'mobile_api.dart';

/// Lo que el teléfono recuerda de la guía de inicio de cada cuenta.
@immutable
class GuideMemory {
  const GuideMemory({
    this.dismissed = false,
    this.finished = false,
    this.visited = const {},
  });

  /// Ya se abrió sola una vez: no vuelve a abrirse al entrar.
  final bool dismissed;

  /// Se recorrió hasta «Terminar»: Inicio deja de mostrar la franja.
  final bool finished;

  /// Pasos que ya se vieron. Un paso que el servidor no puede comprobar
  /// cuenta como hecho al leerlo.
  final Set<String> visited;

  GuideMemory copyWith({
    bool? dismissed,
    bool? finished,
    Set<String>? visited,
  }) => GuideMemory(
    dismissed: dismissed ?? this.dismissed,
    finished: finished ?? this.finished,
    visited: visited ?? this.visited,
  );

  Json toJson() => {
    'dismissed': dismissed,
    'finished': finished,
    'visited': visited.toList()..sort(),
  };

  factory GuideMemory.fromJson(Json json) => GuideMemory(
    dismissed: json['dismissed'] == true,
    finished: json['finished'] == true,
    visited: {
      for (final id in (json['visited'] as List?) ?? const []) id.toString(),
    },
  );
}

/// Guarda [GuideMemory] en el almacén de los borradores, por cuenta.
///
/// Va con su propio prefijo y no con el de la copia sin señal: cerrar sesión
/// borra la copia, pero quien vuelve a entrar no tiene por qué ver la guía
/// otra vez.
class GuideMemoryStore {
  GuideMemoryStore(this.store);
  final DraftRecoveryStore store;

  static String _key(String owner) => 'guide:v1|$owner';

  Future<GuideMemory> read(String owner) async {
    try {
      final value = await store.read(_key(owner));
      if (value == null) return const GuideMemory();
      return GuideMemory.fromJson(object(jsonDecode(value)));
    } catch (_) {
      // Ilegible es como no haberla visto.
      return const GuideMemory();
    }
  }

  Future<void> write(String owner, GuideMemory memory) =>
      store.write(_key(owner), jsonEncode(memory.toJson()));

  Future<void> forget(String owner) => store.deletePrefix(_key(owner));
}

import 'dart:convert';

import '../../core/storage/draft_recovery_store.dart';
import 'mobile_api.dart';

/// Lo que el teléfono guarda para trabajar sin señal: una copia de lo que el
/// servidor devolvió y el permiso de seguir trabajando sin validar la cuenta.
///
/// No es una réplica de las tablas de Supabase. Son las mismas respuestas que
/// la app ya mostraba, guardadas tal cual en el almacén de los borradores: el
/// servidor sigue decidiendo qué ve cada usuario, qué permite su plan y cuál
/// es el resultado de una verificación. Se borra al cerrar sesión.
class OfflineCopy {
  OfflineCopy(this.store);
  final DraftRecoveryStore store;

  /// Cuánto se trabaja sin validar la cuenta con el servidor. Pasado el
  /// plazo, la app pide señal; lo capturado no se pierde.
  static const validity = Duration(days: 7);

  /// Lo que se guarda al leerlo. Lo demás (usuarios, plantas, formularios de
  /// configuración) exige señal.
  static const sections = {
    'bootstrap',
    'plan',
    'instruments',
    'equipment',
    'agenda',
    'history',
    'drafts',
    'draft',
    'verification',
  };

  /// Clave de la respuesta guardada dentro de lo que devuelve la copia: la
  /// fecha en que se guardó.
  static const savedAtKey = 'offlineCopySavedAt';

  /// Todo el catálogo que el usuario puede verificar, para buscar sin señal.
  static const catalogKey = 'catalog';

  static String _prefix(String owner) => 'offline:v1|$owner|';

  /// La zona horaria no cambia lo que se pide, ni un filtro vacío.
  static String key(String section, Json filters) {
    final relevant =
        filters.entries
            .where((e) => e.key != 'utcOffsetMinutes' && e.value != null)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return '$section|${jsonEncode(Map.fromEntries(relevant))}';
  }

  Future<OfflineEntry?> get(String owner, String key) async {
    final value = await store.read('${_prefix(owner)}$key');
    if (value == null) return null;
    try {
      final document = object(jsonDecode(value));
      return OfflineEntry(
        object(document['body']),
        DateTime.parse(document['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String owner, String key, Json body, {DateTime? at}) =>
      store.write(
        '${_prefix(owner)}$key',
        jsonEncode({
          'savedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
          'body': body,
        }),
      );

  Future<OfflineGrant?> grant(String owner) async {
    final value = await store.read('${_prefix(owner)}grant');
    if (value == null) return null;
    try {
      return OfflineGrant.fromJson(object(jsonDecode(value)));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGrant(String owner, OfflineGrant grant) =>
      store.write('${_prefix(owner)}grant', jsonEncode(grant.toJson()));

  /// Borra la copia y el permiso de esa cuenta; los borradores no.
  Future<void> forget(String owner) => store.deletePrefix(_prefix(owner));
}

class OfflineEntry {
  const OfflineEntry(this.body, this.savedAt);
  final Json body;
  final DateTime savedAt;

  /// La respuesta, marcada como copia.
  Json get marked => {
    ...body,
    OfflineCopy.savedAtKey: savedAt.toUtc().toIso8601String(),
  };
}

/// Permiso de trabajar sin señal, renovado cada vez que el servidor valida la
/// cuenta. Guarda el usuario y su acceso tal como llegaron.
class OfflineGrant {
  const OfflineGrant({
    required this.user,
    required this.access,
    required this.validatedAt,
    required this.lastSeen,
  });

  factory OfflineGrant.fromJson(Json json) => OfflineGrant(
    user: object(json['user']),
    access: object(json['access']),
    validatedAt: DateTime.parse(json['validatedAt'] as String),
    lastSeen: DateTime.parse(json['lastSeen'] as String),
  );

  final Json user;
  final Json access;
  final DateTime validatedAt;

  /// La hora más tardía en que se usó sin señal.
  final DateTime lastSeen;

  DateTime get expiresAt => validatedAt.add(OfflineCopy.validity);

  /// Vigente, y con un reloj que no retrocedió: atrasar la hora del teléfono
  /// no alarga el plazo.
  bool usableAt(DateTime now) {
    const slack = Duration(minutes: 10);
    return now.isBefore(expiresAt) &&
        !now.isBefore(lastSeen.subtract(slack)) &&
        !now.isBefore(validatedAt.subtract(slack));
  }

  OfflineGrant seenAt(DateTime now) => now.isAfter(lastSeen)
      ? OfflineGrant(
          user: user,
          access: access,
          validatedAt: validatedAt,
          lastSeen: now,
        )
      : this;

  Json toJson() => {
    'user': user,
    'access': access,
    'validatedAt': validatedAt.toUtc().toIso8601String(),
    'lastSeen': lastSeen.toUtc().toIso8601String(),
  };
}

/// Búsqueda en la copia del catálogo, con los mismos campos y el mismo orden
/// que el servidor.
Json searchCatalog(Json catalog, Json filters) {
  final plantId = filters['plantId']?.toString() ?? '';
  final areaId = filters['areaId']?.toString() ?? '';
  final search = (filters['search'] ?? '').toString().trim().toLowerCase();
  final page = ((filters['page'] as num?)?.toInt() ?? 1).clamp(1, 100000);
  final pageSize = ((filters['pageSize'] as num?)?.toInt() ?? 25).clamp(1, 100);
  final items = objects(catalog['items']).where((item) {
    if (plantId.isNotEmpty && item['planta_id'] != plantId) return false;
    if (areaId.isNotEmpty && item['area_id'] != areaId) return false;
    if (search.isEmpty) return true;
    return [
      'cod_metrica',
      'cod_interno',
      'marca',
      'modelo',
      'departamento',
      'planta',
    ].any((k) => (item[k] ?? '').toString().toLowerCase().contains(search));
  }).toList();
  return {
    'total': items.length,
    'items': items.skip((page - 1) * pageSize).take(pageSize).toList(),
  };
}

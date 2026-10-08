import 'mobile_api.dart';

/// Lo que cuenta un plan y su rotulo. `code` es el motivo de una solicitud de
/// plan superior y el sufijo del error del servidor (`PLAN_LIMIT_EQUIPMENT`).
enum PlanResource {
  plants('plants', 'Plantas', 'PLANTS', 'planta', 'plantas'),
  equipment('equipment', 'Balanzas', 'EQUIPMENT', 'balanza', 'balanzas'),
  users('users', 'Usuarios', 'USERS', 'usuario', 'usuarios'),
  monthlyVerifications(
    'monthlyVerifications',
    'Verificaciones del mes',
    'VERIFICATIONS',
    'verificación al mes',
    'verificaciones al mes',
  ),
  patterns(
    'patterns',
    'Pesas patrón',
    'PATTERNS',
    'pesa patrón',
    'pesas patrón',
  );

  const PlanResource(
    this.key,
    this.label,
    this.code,
    this.singular,
    this.plural,
  );
  final String key, label, code, singular, plural;

  String count(int value) => '$value ${value == 1 ? singular : plural}';
}

/// Funciones que un plan incluye o no.
enum PlanFeature {
  fullReport(
    'fullReport',
    'Informe completo',
    'FULL_REPORT',
    'Lecturas de cada prueba, croquis, gráficos y trazabilidad de los patrones en el PDF.',
  ),
  customSchedules(
    'customSchedules',
    'Periodicidad a medida',
    'CUSTOM_SCHEDULES',
    'Cada N días, semanas o meses, y contar desde la última verificación.',
  );

  const PlanFeature(this.key, this.label, this.code, this.detail);
  final String key, label, code, detail;
}

/// Plan comercial de la empresa, tal como llega en `bootstrap.plan` o en la
/// seccion `plan`: limites, funciones, uso y la solicitud abierta.
///
/// Un limite ausente o nulo es "sin limite" y una funcion ausente esta
/// incluida: las empresas que incorporo Metrica no traen limites.
class CommercialPlan {
  const CommercialPlan(this.data);
  final Json data;

  String get id => data['id']?.toString() ?? '';
  String get name => data['name']?.toString() ?? 'Plan';
  String get summary =>
      object(
        data['catalog'] ?? const <String, dynamic>{},
      )['summary']?.toString() ??
      '';

  /// La empresa se registro desde la app y gestiona sus plantas y usuarios.
  bool get selfService => data['selfService'] == true;
  bool get known => data.isNotEmpty;
  Json get _usage => object(data['usage'] ?? const <String, dynamic>{});
  Json get _limits => object(data['limits'] ?? const <String, dynamic>{});
  Json get _features => object(data['features'] ?? const <String, dynamic>{});

  /// Tope del recurso, o null sin limite. Los usuarios los marcan los cupos
  /// de la suscripcion (con los adicionales), no una clave de `limits`; en un
  /// plan ofrecido, las cuentas que incluye.
  int? limit(PlanResource resource) => resource == PlanResource.users
      ? ((data['seatsAvailable'] ?? data['seats']) as num?)?.toInt()
      : (_limits[resource.key] as num?)?.toInt();

  /// Lo usado. Las capturas en curso ocupan su lugar del mes.
  int used(PlanResource resource) {
    int read(String key) => (_usage[key] as num?)?.toInt() ?? 0;
    return resource == PlanResource.monthlyVerifications
        ? read('monthlyVerifications') + read('openDrafts')
        : read(resource.key);
  }

  int get openDrafts => (_usage['openDrafts'] as num?)?.toInt() ?? 0;

  bool full(PlanResource resource) {
    final maximum = limit(resource);
    return maximum != null && used(resource) >= maximum;
  }

  bool has(PlanFeature feature) => _features[feature.key] != false;

  /// Algun tope o funcion de menos: el plan se puede mejorar.
  bool get limited =>
      PlanResource.values.any(
        (r) => r != PlanResource.users && limit(r) != null,
      ) ||
      PlanFeature.values.any((f) => !has(f));

  /// Fin del periodo; el plan gratuito no vence.
  String? get periodEndsAt => data['periodEndsAt']?.toString();

  Json? get upgradeRequest =>
      data['upgradeRequest'] == null ? null : object(data['upgradeRequest']);
  String? get contactEmail => data['contactEmail']?.toString();

  /// Planes que la app ofrece, en su orden comercial (solo en la seccion
  /// `plan`).
  List<CommercialPlan> get offers =>
      objects(data['offers']).map(CommercialPlan.new).toList();

  /// El recurso que pide mas atencion: el mas lleno de los que tienen tope.
  /// Entre dos igual de llenos, el que mas se usa: 5 de 5 balanzas dice mas
  /// que 1 de 1 planta. Un tope de uno (la unica planta del plan gratuito)
  /// siempre esta lleno y no mide nada: cuenta solo si no hay otro.
  PlanResource? get tightest {
    PlanResource? pick(bool includeSingles) {
      PlanResource? best;
      var ratio = -1.0;
      for (final resource in PlanResource.values) {
        final maximum = limit(resource);
        if (maximum == null || maximum == 0) continue;
        if (maximum == 1 && !includeSingles) continue;
        final share = used(resource) / maximum;
        if (share > ratio || (share == ratio && used(resource) > used(best!))) {
          ratio = share;
          best = resource;
        }
      }
      return best;
    }

    return pick(false) ?? pick(true);
  }
}

/// El motivo de un rechazo por plan: un recurso lleno o una funcion que no
/// incluye.
class PlanLimit {
  const PlanLimit({this.resource, this.feature});
  final PlanResource? resource;
  final PlanFeature? feature;

  /// Del codigo del servidor: `PLAN_LIMIT_EQUIPMENT`,
  /// `PLAN_FEATURE_CUSTOM_SCHEDULES`.
  static PlanLimit? fromCode(String code) {
    for (final resource in PlanResource.values) {
      if (code == 'PLAN_LIMIT_${resource.code}') {
        return PlanLimit(resource: resource);
      }
    }
    for (final feature in PlanFeature.values) {
      if (code == 'PLAN_FEATURE_${feature.code}') {
        return PlanLimit(feature: feature);
      }
    }
    return null;
  }

  /// Motivo de la solicitud de plan superior.
  String get reason => resource?.code ?? feature?.code ?? 'GENERAL';
}

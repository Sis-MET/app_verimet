import 'package:flutter/material.dart';

import '../../shared/widgets/wizard_chrome.dart';
import 'company_plants.dart';
import 'mobile_api.dart';
import 'mobile_session.dart';
import 'offline_copy.dart';
import 'setup_guide_memory.dart';
import 'user_manual.dart';

/// Guía de inicio: lo que cada rol tiene que hacer para usar IvMET, en orden.
///
/// Se abre sola la primera vez que se entra y vuelve desde Inicio (mientras
/// no se termine) y desde Ajustes › Ayuda. Cada paso dice qué hacer y dónde,
/// con los nombres de botones de la app, y cuando el servidor lo puede
/// comprobar (`bootstrap.setup`) marca si ya está hecho: «2 de 5 balanzas
/// configuradas». Los pasos que no se pueden comprobar cuentan como hechos al
/// leerlos.
///
/// Los textos siguen al manual (`user_manual_content.dart`): un cambio de
/// flujo que actualice allí una sección actualiza aquí su paso.

/// Para quién es la guía. El jefe de una empresa que se registró desde la app
/// crea plantas y usuarios; en las que gestiona Métrica, los habilita Métrica.
enum GuideAudience {
  selfServiceQuality('Jefe de calidad'),
  managedQuality('Jefe de calidad'),
  operator('Operador');

  const GuideAudience(this.label);
  final String label;

  static GuideAudience of(MobileSession session) => !session.quality
      ? GuideAudience.operator
      : managesPlants(session)
      ? GuideAudience.selfServiceQuality
      : GuideAudience.managedQuality;
}

/// A dónde lleva «Ir ahora».
enum GuideDestination {
  plants,
  patterns,
  operators,
  verify,
  agenda,
  users,
  history,
  pending,
}

/// Animación de cada paso (`setup_guide_scenes.dart`).
enum GuideScene {
  plants,
  patterns,
  scale,
  tests,
  tolerance,
  users,
  assign,
  capture,
  results,
  agenda,
  eccentricity,
  repeatability,
  linearity,
  offline,
}

/// Conteos de `bootstrap.setup`, del alcance de quien entra.
class GuideFacts {
  const GuideFacts(this.data);
  final Json data;

  /// Null si el servidor todavía no envía el resumen.
  static GuideFacts? of(MobileSession session) {
    final setup = session.bootstrap['setup'];
    return setup is Map ? GuideFacts(object(setup)) : null;
  }

  int _count(String key) => (data[key] as num?)?.toInt() ?? 0;
  int get plants => _count('plants');
  int get areas => _count('areas');
  int get patterns => _count('patterns');
  int get tracedPatterns => _count('tracedPatterns');
  int get equipment => _count('equipment');
  int get validated => _count('validated');
  int get configured => _count('configured');
  int get assigned => _count('assigned');
  int get operators => _count('operators');
  int get verifications => _count('verifications');
}

/// Cómo va un paso que el servidor puede comprobar.
@immutable
class GuideStatus {
  const GuideStatus(this.progress, this.label);
  final WizardProgress progress;

  /// «3 plantas · 5 áreas», «2 de 5 configuradas».
  final String label;
}

String _n(int value, String one, String many) =>
    '$value ${value == 1 ? one : many}';

/// Un término que el paso explica: las tres pruebas, los estados de la
/// agenda.
typedef GuideTerm = ({String term, String meaning});

@immutable
class GuideStep {
  const GuideStep({
    required this.id,
    required this.title,
    required this.caption,
    required this.scene,
    required this.actions,
    this.route = const [],
    this.terms = const [],
    this.termsTitle = 'Términos',
    this.notes = const [],
    this.destination,
    this.destinationLabel,
    this.manual,
    this.status,
  });

  final String id;
  final String title;

  /// Qué es y para qué, en una o dos líneas.
  final String caption;
  final GuideScene scene;

  /// Dónde se hace: la ruta de pantallas y botones, en orden.
  final List<String> route;

  /// Qué hacer, con el texto exacto de cada botón.
  final List<ManualStep> actions;
  final List<GuideTerm> terms;
  final String termsTitle;
  final List<ManualNote> notes;
  final GuideDestination? destination;

  /// Texto de «Ir ahora»: «Ir a Plantas».
  final String? destinationLabel;

  /// Sección del manual con el detalle.
  final String? manual;

  /// Cómo va, según el servidor. Null en los pasos que solo se leen.
  final GuideStatus Function(GuideFacts facts)? status;
}

/// Un paso con su estado ya resuelto para quien lo ve.
@immutable
class GuideEntry {
  const GuideEntry(
    this.step,
    this.progress,
    this.label, {
    this.measured = false,
  });
  final GuideStep step;
  final WizardProgress progress;

  /// Lo que se ve en el panel: el estado o «Leído»/«Por leer».
  final String label;

  /// El estado lo da el servidor y no la lectura.
  final bool measured;

  WizardStep get wizard =>
      WizardStep(title: step.title, detail: label, progress: progress);
}

/// La guía de un rol con lo que ya se hizo.
class SetupGuide {
  SetupGuide(this.audience, this.facts, this.memory)
    : steps = guideSteps(audience);

  factory SetupGuide.of(MobileSession session, GuideMemory memory) =>
      SetupGuide(GuideAudience.of(session), GuideFacts.of(session), memory);

  /// La guía se abre sola solo si el servidor dice qué falta: sin eso no
  /// podría marcar nada y sería un folleto.
  static bool measurable(MobileSession session) =>
      GuideFacts.of(session) != null;

  final GuideAudience audience;
  final GuideFacts? facts;
  final GuideMemory memory;
  final List<GuideStep> steps;

  late final List<GuideEntry> entries = [
    for (final step in steps) _entry(step),
  ];

  GuideEntry _entry(GuideStep step) {
    final facts = this.facts;
    final check = step.status;
    if (facts != null && check != null) {
      final status = check(facts);
      return GuideEntry(step, status.progress, status.label, measured: true);
    }
    return memory.visited.contains(step.id)
        ? GuideEntry(step, WizardProgress.complete, 'Leído')
        : GuideEntry(step, WizardProgress.pending, 'Por leer');
  }

  int get done =>
      entries.where((e) => e.progress == WizardProgress.complete).length;

  /// Primer paso por hacer; el primero si ya está todo.
  int get next {
    final index = entries.indexWhere(
      (e) => e.progress != WizardProgress.complete,
    );
    return index < 0 ? 0 : index;
  }
}

// ── Estados ──────────────────────────────────────────────────────────────

GuideStatus _plantsStatus(GuideFacts f) => f.plants == 0
    ? const GuideStatus(WizardProgress.pending, 'Sin plantas')
    : f.areas == 0
    ? GuideStatus(
        WizardProgress.review,
        '${_n(f.plants, 'planta', 'plantas')} · faltan las áreas',
      )
    : GuideStatus(
        WizardProgress.complete,
        '${_n(f.plants, 'planta', 'plantas')} · ${_n(f.areas, 'área', 'áreas')}',
      );

GuideStatus _patternsStatus(GuideFacts f) => f.patterns == 0
    ? const GuideStatus(WizardProgress.pending, 'Sin pesas patrón')
    : f.tracedPatterns == 0
    ? GuideStatus(
        WizardProgress.review,
        '${_n(f.patterns, 'pesa', 'pesas')} sin certificado vigente',
      )
    : GuideStatus(
        WizardProgress.complete,
        '${f.tracedPatterns} con certificado vigente',
      );

GuideStatus _registeredStatus(GuideFacts f) => f.equipment == 0
    ? const GuideStatus(WizardProgress.pending, 'Sin balanzas')
    : GuideStatus(
        WizardProgress.complete,
        _n(f.equipment, 'balanza registrada', 'balanzas registradas'),
      );

GuideStatus _validatedStatus(GuideFacts f) => f.equipment == 0
    ? const GuideStatus(WizardProgress.pending, 'Sin balanzas habilitadas')
    : f.validated < f.equipment
    ? GuideStatus(
        WizardProgress.review,
        '${f.validated} de ${f.equipment} validadas',
      )
    : GuideStatus(
        WizardProgress.complete,
        _n(f.equipment, 'balanza validada', 'balanzas validadas'),
      );

GuideStatus _configuredStatus(GuideFacts f) => f.equipment == 0
    ? const GuideStatus(WizardProgress.pending, 'Primero, las balanzas')
    : f.configured == 0
    ? const GuideStatus(WizardProgress.pending, 'Ninguna configurada')
    : f.configured < f.equipment
    ? GuideStatus(
        WizardProgress.review,
        '${f.configured} de ${f.equipment} configuradas',
      )
    : GuideStatus(
        WizardProgress.complete,
        f.equipment == 1 ? 'Configurada' : 'Las ${f.equipment} configuradas',
      );

GuideStatus _operatorsStatus(GuideFacts f) => f.operators == 0
    ? const GuideStatus(WizardProgress.pending, 'Sin operadores')
    : GuideStatus(
        WizardProgress.complete,
        _n(f.operators, 'operador', 'operadores'),
      );

GuideStatus _assignedStatus(GuideFacts f) => f.operators == 0
    ? const GuideStatus(WizardProgress.pending, 'Primero, los operadores')
    : f.equipment == 0
    ? const GuideStatus(WizardProgress.pending, 'Primero, las balanzas')
    : f.assigned == 0
    ? const GuideStatus(WizardProgress.pending, 'Ninguna asignada')
    : f.assigned < f.equipment
    ? GuideStatus(
        WizardProgress.review,
        '${f.assigned} de ${f.equipment} con operador',
      )
    : const GuideStatus(WizardProgress.complete, 'Todas con operador');

GuideStatus _verifiedStatus(GuideFacts f) => f.verifications == 0
    ? const GuideStatus(WizardProgress.pending, 'Aún sin verificaciones')
    : GuideStatus(
        WizardProgress.complete,
        _n(f.verifications, 'verificación', 'verificaciones'),
      );

GuideStatus _assignedToMeStatus(GuideFacts f) => f.equipment == 0
    ? const GuideStatus(
        WizardProgress.review,
        'Sin balanzas: pídelas al jefe de calidad',
      )
    : GuideStatus(
        WizardProgress.complete,
        _n(f.equipment, 'balanza asignada', 'balanzas asignadas'),
      );

GuideStatus _myVerificationsStatus(GuideFacts f) => f.verifications == 0
    ? const GuideStatus(WizardProgress.pending, 'Aún no finalizaste ninguna')
    : GuideStatus(
        WizardProgress.complete,
        _n(f.verifications, 'finalizada por ti', 'finalizadas por ti'),
      );

// ── Pasos ────────────────────────────────────────────────────────────────

const _testTerms = <GuideTerm>[
  (
    term: 'Excentricidad',
    meaning: 'Compara el centro y las posiciones de la plataforma.',
  ),
  (
    term: 'Repetibilidad',
    meaning: 'Repite una misma carga y evalúa su dispersión.',
  ),
  (term: 'Linealidad', meaning: 'Compara la indicación en diferentes cargas.'),
];

List<GuideStep> guideSteps(GuideAudience audience) => switch (audience) {
  GuideAudience.operator => _operatorSteps,
  GuideAudience.selfServiceQuality => _qualitySteps(selfService: true),
  GuideAudience.managedQuality => _qualitySteps(selfService: false),
};

List<GuideStep> _qualitySteps({required bool selfService}) => [
  selfService
      ? const GuideStep(
          id: 'plantas',
          title: 'Plantas y áreas',
          caption:
              'Ordena dónde están tus balanzas: cada planta con sus áreas. Todo lo demás cuelga de aquí.',
          scene: GuideScene.plants,
          route: ['Plantas', 'Áreas', 'Nueva planta'],
          actions: [
            ManualStep(
              'Ve a Plantas › «Áreas» y toca «Nueva planta».',
              'Al registrar la empresa se creó la primera. Agrega las demás sedes o naves.',
            ),
            ManualStep(
              'Escribe el nombre, la ciudad y la dirección, y toca «Crear planta».',
              'Quedas asignado a la planta. Si el plan no admite más, aparece el aviso del plan.',
            ),
            ManualStep(
              'Toca la planta y luego «Nueva área» para cada sector.',
              'Producción, despacho, laboratorio… En el menú ⋮, «Sugerir áreas desde Ubicación» las propone a partir de las balanzas.',
            ),
          ],
          notes: [
            ManualNote(
              ManualNoteKind.tip,
              'Para renombrar o desactivar una planta, entra a ella y usa el menú ⋮ › «Editar planta».',
            ),
          ],
          destination: GuideDestination.plants,
          destinationLabel: 'Ir a Plantas',
          manual: 'plantas',
          status: _plantsStatus,
        )
      : const GuideStep(
          id: 'plantas',
          title: 'Plantas y áreas',
          caption:
              'Métrica habilita las plantas de tu contrato. Tú las ordenas en áreas para encontrar cada balanza.',
          scene: GuideScene.plants,
          route: ['Plantas', 'Áreas', 'Tu planta', 'Nueva área'],
          actions: [
            ManualStep(
              'Ve a Plantas › «Áreas»: están las plantas que Métrica habilitó para ti.',
              'Si falta una, pide a Métrica que la habilite.',
            ),
            ManualStep(
              'Toca una planta y luego «Nueva área» para cada sector.',
              'Producción, despacho, laboratorio…',
            ),
            ManualStep(
              'En el menú ⋮, «Sugerir áreas desde Ubicación» las propone a partir de la ubicación de las balanzas.',
            ),
          ],
          destination: GuideDestination.plants,
          destinationLabel: 'Ir a Plantas',
          manual: 'plantas',
          status: _plantsStatus,
        ),
  const GuideStep(
    id: 'patrones',
    title: 'Pesas patrón',
    caption:
        'Registra las pesas con las que vas a verificar. Con un certificado vigente, la verificación es trazable.',
    scene: GuideScene.patterns,
    route: ['Plantas', 'Patrones', 'Nuevo patrón'],
    actions: [
      ManualStep('Ve a Plantas › «Patrones» y toca «Nuevo patrón».'),
      ManualStep(
        'Completa código, descripción, tipo, clase, unidad y capacidad.',
        'El código identifica la pesa en cada verificación.',
      ),
      ManualStep('Elige las «Plantas donde se utilizará» y guarda.'),
      ManualStep(
        'Revisa sus certificados: cada uno muestra la calibración y el vencimiento.',
        'Los certificados no se cargan desde la app: pídelos a Métrica.',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.important,
        'Sin pesas patrón, o con el certificado vencido, la verificación se registra igual pero sale «No trazable».',
      ),
    ],
    destination: GuideDestination.patterns,
    destinationLabel: 'Ir a Patrones',
    manual: 'patrones',
    status: _patternsStatus,
  ),
  selfService
      ? const GuideStep(
          id: 'balanzas',
          title: 'Balanzas',
          caption:
              'Registra cada balanza que vas a verificar, con sus rangos y su división.',
          scene: GuideScene.scale,
          route: ['Verificar', 'Por planta', 'Registrar balanza'],
          actions: [
            ManualStep(
              'Ve a Verificar › «Por planta», elige la planta y toca «Registrar balanza».',
            ),
            ManualStep(
              'Paso «Área»: elige un área existente o escribe una nueva.',
            ),
            ManualStep(
              'Paso «Identificación»: código interno (obligatorio), marca, modelo, serie y ubicación.',
              'El código interno no se repite dentro de la planta.',
            ),
            ManualStep(
              'Paso «Datos técnicos»: tipo, unidad, clase y hasta tres rangos con capacidad máxima, división d y, si lo conoces, intervalo e.',
              'Cada capacidad supera a la anterior; d es menor que la capacidad y e no es menor que d.',
            ),
            ManualStep(
              'Marca la confirmación y toca «Registrar balanza».',
              'Se abre su ficha: desde ahí sigues con el paso siguiente.',
            ),
          ],
          notes: [
            ManualNote(
              ManualNoteKind.tip,
              'Los datos técnicos se corrigen solo mientras la balanza no tenga verificaciones. La identificación y el área, siempre.',
            ),
          ],
          destination: GuideDestination.verify,
          destinationLabel: 'Ir a Verificar',
          manual: 'registrar-balanza',
          status: _registeredStatus,
        )
      : const GuideStep(
          id: 'balanzas',
          title: 'Validar balanzas',
          caption:
              'Métrica habilita las balanzas de tu contrato. Antes de configurarlas, confirma que su ficha es correcta.',
          scene: GuideScene.scale,
          route: ['Verificar', 'Balanza', 'Validar ficha'],
          actions: [
            ManualStep(
              'Ve a Verificar: «Por planta» o «Lista completa».',
              'Ahí están las balanzas que Métrica habilitó.',
            ),
            ManualStep(
              'Abre cada balanza y toca «Validar ficha».',
              'Revisa el área, el código interno, la marca, el modelo, la serie y la ubicación, y confirma.',
            ),
            ManualStep(
              'Si tu empresa incorporó una balanza nueva, entra a su planta y toca «Registrar balanza».',
              'Área, identificación y datos técnicos. Nace validada.',
            ),
          ],
          destination: GuideDestination.verify,
          destinationLabel: 'Ir a Verificar',
          manual: 'buscar',
          status: _validatedStatus,
        ),
  GuideStep(
    id: 'pruebas',
    title: 'Pruebas y periodicidad',
    caption:
        'Elige qué pruebas necesita cada balanza y cada cuánto tocan. Con esto se arma la agenda.',
    scene: GuideScene.tests,
    route: const ['Verificar', 'Balanza', 'Configurar pruebas'],
    actions: const [
      ManualStep(
        'Abre la ficha de la balanza y toca «Configurar pruebas».',
        'Paso «Pruebas y periodicidad».',
      ),
      ManualStep(
        'Marca las pruebas que necesita tu proceso.',
        'En balanzas de camión, la excentricidad se llama «Desplazamiento de carga».',
      ),
      ManualStep(
        'Toca la periodicidad de cada prueba: diaria, días hábiles, semanal, quincenal, mensual… o «Personalizada».',
        'El editor dice la regla en palabras y muestra las próximas fechas.',
      ),
      ManualStep(
        'Elige «Fechas fijas» o «Desde la última», y los días de aviso previo.',
        '«Fechas fijas» mantiene el calendario aunque una verificación se atrase; «Desde la última» cuenta desde la última hecha. Con el aviso (0 a 90 días) la balanza aparece como próxima.',
      ),
      ManualStep('Toca «Continuar» para pasar a los errores permisibles.'),
    ],
    terms: _testTerms,
    termsTitle: 'Las tres pruebas',
    notes: [
      if (selfService)
        const ManualNote(
          ManualNoteKind.tip,
          'En el plan Gratuito, «Personalizada» y «Desde la última» tienen candado: usa los accesos rápidos con fechas fijas.',
        ),
    ],
    destination: GuideDestination.verify,
    destinationLabel: 'Ir a Verificar',
    manual: 'configurar',
    status: _configuredStatus,
  ),
  const GuideStep(
    id: 'tolerancias',
    title: 'Errores permisibles',
    caption:
        'La tolerancia de cada prueba: el límite con el que el servidor decide si la balanza está conforme.',
    scene: GuideScene.tolerance,
    route: [
      'Configurar pruebas',
      'Errores permisibles',
      'Activar configuración',
    ],
    actions: [
      ManualStep(
        'En el paso «Errores permisibles», escribe el error permisible de cada prueba elegida.',
        'En la unidad de la balanza, con punto decimal y hasta 9 decimales. Mayor que cero y sin superar la capacidad.',
      ),
      ManualStep(
        'Un valor por prueba: se aplica a todos sus puntos.',
        'En linealidad es el error permisible de las indicaciones.',
      ),
      ManualStep(
        'Toca «Activar configuración».',
        'Queda disponible de inmediato y la balanza entra en la agenda.',
      ),
      ManualStep(
        'Para cambiarla después: «Actualizar pruebas» y «Guardar nueva versión».',
        'Las verificaciones anteriores no cambian.',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.important,
        'El límite pertenece al proceso interno de tu empresa: tómalo de tu procedimiento, no lo estimes en planta. Suele partir del error máximo permitido de la clase de la balanza o de un criterio más exigente.',
      ),
    ],
    destination: GuideDestination.verify,
    destinationLabel: 'Ir a Verificar',
    manual: 'configurar',
    status: _configuredStatus,
  ),
  selfService
      ? const GuideStep(
          id: 'usuarios',
          title: 'Tu equipo',
          caption:
              'Crea una cuenta personal para cada operador. Cada registro queda a nombre de quien lo hizo.',
          scene: GuideScene.users,
          route: ['Ajustes', 'Usuarios', 'Nuevo usuario'],
          actions: [
            ManualStep('Ve a Ajustes › «Usuarios» y toca «Nuevo usuario».'),
            ManualStep(
              'Completa nombre, usuario para ingresar, rol y plantas.',
              'El usuario es único en IvMET: agrégale algo de tu empresa, por ejemplo jperez.acme.',
            ),
            ManualStep(
              'Revisa la contraseña temporal propuesta y toca «Crear usuario».',
            ),
            ManualStep(
              'En «Entrega estos datos», copia el usuario y la contraseña y entrégalos por un canal privado.',
              'La app no los vuelve a mostrar. La persona define su contraseña en el primer acceso.',
            ),
          ],
          notes: [
            ManualNote(
              ManualNoteKind.tip,
              'Cada cuenta activa ocupa un cupo del plan. Cuando alguien se va, desactiva su cuenta: su historial se conserva.',
            ),
          ],
          destination: GuideDestination.users,
          destinationLabel: 'Ir a Usuarios',
          manual: 'usuarios',
          status: _operatorsStatus,
        )
      : const GuideStep(
          id: 'usuarios',
          title: 'Tu equipo',
          caption:
              'Las cuentas de tu equipo las crea Métrica. Cada persona que verifica necesita la suya.',
          scene: GuideScene.users,
          actions: [
            ManualStep(
              'Pide a Métrica una cuenta para cada operador, con las plantas donde trabaja.',
            ),
            ManualStep(
              'Cada persona ingresa con su usuario y la contraseña temporal, y define la suya.',
              'Al menos 12 caracteres. La cuenta es personal: no se comparte.',
            ),
          ],
          manual: 'acceso',
          status: _operatorsStatus,
        ),
  const GuideStep(
    id: 'asignar',
    title: 'Asignar balanzas',
    caption:
        'Cada operador ve y verifica solo las balanzas que le asignas, en Verificar y en su agenda.',
    scene: GuideScene.assign,
    route: ['Plantas', 'Operadores', 'Operador'],
    actions: [
      ManualStep('Ve a Plantas › «Operadores» y elige la planta.'),
      ManualStep(
        'Toca un operador, marca sus balanzas y guarda.',
        'Hay búsqueda y «marcar todas».',
      ),
      ManualStep(
        'También desde la ficha de una balanza › «Operadores».',
        'Una balanza puede tener varios operadores.',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.important,
        'Un operador sin asignaciones no ve ninguna balanza. Inicio avisa de las balanzas sin operador.',
      ),
    ],
    destination: GuideDestination.operators,
    destinationLabel: 'Ir a Operadores',
    manual: 'operadores',
    status: _assignedStatus,
  ),
  const GuideStep(
    id: 'verificar',
    title: 'Primera verificación',
    caption:
        'Con todo configurado, la agenda dice qué toca cada día. Haz una verificación para conocer el recorrido.',
    scene: GuideScene.capture,
    route: ['Agenda', 'Balanza', 'Iniciar verificación'],
    actions: [
      ManualStep(
        'En Inicio, «Hoy» lleva a la Agenda: arriba lo atrasado y abajo el detalle del día.',
      ),
      ManualStep(
        'Abre la balanza y toca «Iniciar verificación».',
        'Si no se puede, un aviso dice por qué.',
      ),
      ManualStep(
        'Recorre «Pesas patrón y ambiente», «Excentricidad», «Repetibilidad», «Linealidad» y «Resumen».',
        'El botón ≡ abre el panel de pasos; el menú ⋮, las opciones extra.',
      ),
      ManualStep(
        'En «Resumen», revisa y toca «Finalizar».',
        'El servidor calcula el resultado. Lo finalizado no se edita.',
      ),
    ],
    destination: GuideDestination.agenda,
    destinationLabel: 'Ir a la Agenda',
    manual: 'captura',
    status: _verifiedStatus,
  ),
  const GuideStep(
    id: 'resultados',
    title: 'Resultados y alertas',
    caption:
        'Revisa cada resultado, genera el informe y decide qué compartir con Métrica.',
    scene: GuideScene.results,
    route: ['Inicio', 'Historial'],
    actions: [
      ManualStep(
        '«Historial» y «Alertas», en Inicio, muestran las verificaciones finalizadas y las no conformes abiertas.',
      ),
      ManualStep(
        'Abre una verificación para ver resultado, trazabilidad y lecturas, y toca «Generar informe PDF».',
      ),
      ManualStep(
        'Si hubo un error: menú ⋮ › «Anular con motivo», y haz una verificación nueva.',
        'La anulada queda visible: nada se borra.',
      ),
      ManualStep(
        'En una alerta, «Revisar expediente para compartir» envía a Métrica solo ese expediente.',
        'Después puedes «Retirar acceso».',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.important,
        'Una verificación intermedia es un control interno: no es un certificado de calibración ni una verificación legal.',
      ),
    ],
    destination: GuideDestination.history,
    destinationLabel: 'Ir al Historial',
    manual: 'historial',
  ),
];

final _operatorSteps = <GuideStep>[
  const GuideStep(
    id: 'tus-balanzas',
    title: 'Tus balanzas',
    caption:
        'Ves y verificas solo las balanzas que te asignó el jefe de calidad.',
    scene: GuideScene.scale,
    route: ['Verificar', 'Por planta', 'Balanza'],
    actions: [
      ManualStep(
        'Ve a Verificar: «Por planta» o «Lista completa».',
        'Busca por código interno o marca.',
      ),
      ManualStep(
        'Abre una balanza: su ficha muestra la «Vigencia por prueba», es decir, cuándo toca cada una.',
      ),
      ManualStep('Desde la ficha empiezas con «Iniciar verificación».'),
    ],
    destination: GuideDestination.verify,
    destinationLabel: 'Ir a Verificar',
    manual: 'buscar',
    status: _assignedToMeStatus,
  ),
  const GuideStep(
    id: 'tu-agenda',
    title: 'Tu agenda',
    caption: 'Qué te toca hoy, lo que viene y lo atrasado.',
    scene: GuideScene.agenda,
    route: ['Inicio', 'Hoy', 'Agenda'],
    actions: [
      ManualStep(
        'En Inicio, «Hoy» dice cuántas balanzas te tocan y lleva a la Agenda.',
      ),
      ManualStep(
        'La Agenda muestra el mes con cuántas balanzas tocan cada día. Arriba, las atrasadas.',
      ),
      ManualStep('Toca un día para ver el detalle y abrir la balanza.'),
    ],
    termsTitle: 'Estados de cada balanza',
    terms: [
      (term: 'Próxima', meaning: 'Entró en los días de aviso previo.'),
      (term: 'Hoy', meaning: 'Toca verificarla hoy.'),
      (term: 'Atrasada', meaning: 'Pasó la fecha sin verificación.'),
      (term: 'Hecha', meaning: 'Se verificó en su ventana.'),
    ],
    destination: GuideDestination.agenda,
    destinationLabel: 'Ir a la Agenda',
    manual: 'agenda',
  ),
  const GuideStep(
    id: 'pesas-ambiente',
    title: 'Pesas patrón y ambiente',
    caption:
        'El primer paso de cada captura: qué pesas usas y en qué condiciones mides.',
    scene: GuideScene.patterns,
    route: ['Iniciar verificación', 'Pesas patrón y ambiente'],
    actions: [
      ManualStep(
        'Elige los certificados de las pesas que vas a usar.',
        'Su vencimiento se ve en Plantas › «Pesas patrón».',
      ),
      ManualStep('Registra la temperatura y la humedad del lugar.'),
      ManualStep(
        'Sin pesas patrón, continúa e identifica el origen de las cargas en cada prueba.',
        'La verificación se registra, pero sale «No trazable».',
      ),
    ],
    destination: GuideDestination.patterns,
    destinationLabel: 'Ver las pesas patrón',
    manual: 'captura',
    status: _patternsStatus,
  ),
  const GuideStep(
    id: 'excentricidad',
    title: 'Excentricidad',
    caption: 'La misma carga en distintas posiciones de la plataforma.',
    scene: GuideScene.eccentricity,
    route: ['Captura', 'Excentricidad'],
    actions: [
      ManualStep(
        'Elige la forma de la plataforma y las posiciones.',
        'La posición 1 es la referencia central.',
      ),
      ManualStep(
        'Aplica la misma carga en cada posición y registra la indicación.',
        'Escríbela en el momento en que la lees, con el teclado numérico de la app.',
      ),
      ManualStep(
        'Si hoy no corresponde: menú ⋮ › «Omitir esta prueba», con su motivo.',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.tip,
        'En balanzas de camión se llama «Desplazamiento de carga»: inicio, centro y final de la plataforma.',
      ),
    ],
    manual: 'captura',
  ),
  const GuideStep(
    id: 'repetibilidad',
    title: 'Repetibilidad',
    caption: 'La misma carga varias veces: la balanza debe repetir la lectura.',
    scene: GuideScene.repeatability,
    route: ['Captura', 'Repetibilidad'],
    actions: [
      ManualStep('Elige cuántas cargas y cuántas mediciones por carga.'),
      ManualStep('Retira la carga y vuelve a aplicarla en cada repetición.'),
      ManualStep('Registra cada indicación cuando se estabilice.'),
    ],
    manual: 'captura',
  ),
  const GuideStep(
    id: 'linealidad',
    title: 'Linealidad',
    caption: 'Cargas crecientes a lo largo del rango de la balanza.',
    scene: GuideScene.linearity,
    route: ['Captura', 'Linealidad'],
    actions: [
      ManualStep(
        'Registra la indicación para cada carga del rango.',
        '«Agregar punto» y «Retirar último» ajustan la cantidad de cargas.',
      ),
      ManualStep(
        '«Usar sugerencia» y «Sugerir indicación» proponen valores.',
        'Compáralos siempre con el indicador antes de aceptarlos.',
      ),
    ],
    manual: 'captura',
  ),
  const GuideStep(
    id: 'finalizar',
    title: 'Resumen y finalizar',
    caption:
        'Revisa todo y finaliza: el servidor calcula el resultado y el registro queda sin edición.',
    scene: GuideScene.capture,
    route: ['Captura', 'Resumen', 'Finalizar'],
    actions: [
      ManualStep(
        'En «Resumen», revisa condiciones, pesas y lecturas, y escribe las observaciones.',
      ),
      ManualStep(
        'Toca «Finalizar» y confirma.',
        'El resultado es Conforme, No conforme o No concluyente.',
      ),
      ManualStep(
        'Para seguir más tarde: menú ⋮ › «Guardar y salir».',
        'Mientras capturas, cada lectura queda guardada en el teléfono.',
      ),
    ],
    notes: [
      ManualNote(
        ManualNoteKind.important,
        'Lo finalizado no se edita ni se borra. Si hubo un error, se anula con motivo y se hace otra verificación.',
      ),
    ],
    destination: GuideDestination.verify,
    destinationLabel: 'Ir a Verificar',
    manual: 'captura',
    status: _myVerificationsStatus,
  ),
  GuideStep(
    id: 'sin-senal',
    title: 'Sin señal',
    caption:
        'Trabajas hasta ${OfflineCopy.validity.inDays} días sin conexión: lo finalizado se envía solo al volver la señal.',
    scene: GuideScene.offline,
    route: const ['Ajustes', 'Por enviar'],
    actions: const [
      ManualStep(
        'Sin señal, consultas lo descargado y capturas y finalizas como siempre.',
        'La franja de arriba avisa «Sin conexión» y cuántas quedan por enviar.',
      ),
      ManualStep('Al volver la señal se envían solas, con la app abierta.'),
      ManualStep('Para revisarlas: Ajustes › «Por enviar».'),
    ],
    notes: const [
      ManualNote(
        ManualNoteKind.important,
        'No borres los datos de la app ni la desinstales con verificaciones por enviar: se perderían.',
      ),
    ],
    destination: GuideDestination.pending,
    destinationLabel: 'Ver Por enviar',
    manual: 'sin-conexion',
  ),
];

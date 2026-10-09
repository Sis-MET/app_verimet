import 'package:flutter/material.dart';

import 'user_manual.dart';

/// Manual de uso de IvMET (NB/ISO/IEC 17025 7.11.5).
///
/// Los nombres de botones, pasos y mensajes se copian de la app tal como los
/// ve quien la usa. Un cambio que altere un flujo descrito aquí actualiza su
/// sección en el mismo cambio y agrega una revisión a [ManualControl.history].
/// `test/online/user_manual_test.dart` exige que «Aplica a» coincida con la
/// versión menor de `pubspec.yaml`.
const ivmetUserManual = UserManual(
  control: ManualControl(
    code: 'PENDIENTE: código asignado por Calidad',
    title: 'Manual de uso de IvMET',
    revision: '01 (borrador)',
    issuedOn: '2026-10-09',
    appliesTo: '1.0.x',
    preparedBy: 'Desarrollo IvMET',
    reviewedBy: 'PENDIENTE',
    approvedBy: 'PENDIENTE',
    history: [
      ManualRevision('00', '2026-10-09', 'Emisión inicial (borrador).'),
      ManualRevision(
        '01',
        '2026-10-09',
        'Trabajo sin conexión: copia del teléfono, finalizar sin señal y Por enviar.',
      ),
    ],
  ),
  sections: [
    // ── Primeros pasos ─────────────────────────────────────────────────
    ManualSection(
      id: 'acerca',
      group: ManualGroup.start,
      title: 'Acerca de IvMET',
      icon: Icons.info_outline,
      summary: 'Qué es una verificación intermedia y qué no es.',
      blocks: [
        ManualParagraph(
          'IvMET es la app de Métrica Ltda. con la que una empresa verifica '
          'sus balanzas entre calibraciones formales. Cada verificación '
          'intermedia combina hasta tres pruebas: excentricidad, '
          'repetibilidad y linealidad. Quien captura registra las lecturas en '
          'la planta y el servidor calcula el resultado al finalizar.',
        ),
        ManualList('Lo que conviene saber desde el inicio', [
          'Los datos viven en el servidor, pero la app trabaja también sin señal: consulta la copia que guardó en el teléfono y deja las verificaciones finalizadas ahí hasta que vuelve la conexión.',
          'Las verificaciones son privadas de tu empresa. Métrica solo recibe lo que el jefe de calidad autoriza enviar.',
          'Hay dos roles: jefe de calidad (configura, asigna y gestiona) y operador (verifica las balanzas que tiene asignadas).',
          'Una verificación finalizada no se edita ni se borra: si hay un error, se anula con motivo y se hace otra.',
        ]),
        ManualNote(
          ManualNoteKind.important,
          'Una verificación intermedia es un control interno. No es un '
          'certificado de calibración ni una verificación legal, y no sirve '
          'para demostrar conformidad ante IBMETRO ni ante otra autoridad.',
        ),
      ],
    ),
    ManualSection(
      id: 'requisitos',
      group: ManualGroup.start,
      title: 'Antes de empezar',
      icon: Icons.checklist_outlined,
      summary: 'Teléfono, conexión y cuenta que necesitas.',
      blocks: [
        ManualList('Necesitas', [
          'Un teléfono Android con la app IvMET instalada desde Play Store.',
          'Conexión a internet (datos móviles o wifi) para registrarte, ingresar y gestionar usuarios, plantas y plan. Para verificar basta con haberte conectado en los últimos 7 días.',
          'Una cuenta: la creas tú al registrar la empresa, te la da el jefe de calidad o, en empresas que gestiona Métrica, Métrica.',
          'Para verificar: las balanzas asignadas y, si las usas, las pesas patrón registradas en tu planta.',
        ]),
        ManualParagraph(
          'La versión instalada se ve en Ajustes › Sesión y licencia › '
          'Versión de la app. Cada verificación guarda esa versión.',
        ),
        ManualNote(
          ManualNoteKind.norm,
          'La versión del software y el entorno en que opera se registran '
          'para poder demostrar con qué se capturó cada registro.',
          reference: '7.11.3 c',
        ),
      ],
    ),
    ManualSection(
      id: 'registro',
      group: ManualGroup.start,
      title: 'Crear la cuenta de tu empresa',
      icon: Icons.add_business_outlined,
      audience: 'Jefe de calidad',
      summary: 'Registrar la empresa desde la app, con un código al correo.',
      blocks: [
        ManualSteps('Crear la cuenta', [
          ManualStep(
            'En el acceso, toca «Crear cuenta de empresa».',
            'Si tu empresa ya usa IvMET, no crees otra: pide tu usuario al jefe de calidad.',
          ),
          ManualStep(
            'Paso «Tu empresa»: escribe el nombre de la empresa.',
            'Opcional: nombre de la primera planta (si lo dejas vacío se llama «Planta principal»), ciudad, país y teléfono.',
          ),
          ManualStep(
            'Paso «Tu cuenta»: escribe tu nombre, tu correo y una contraseña de al menos 12 caracteres.',
            'Serás el jefe de calidad. Marca «Acepto las condiciones de uso de IvMET» (puedes leerlas antes).',
          ),
          ManualStep(
            'Toca «Enviar código».',
            'Llega un correo «Tu código de IvMET» con 6 dígitos. Revisa también el correo no deseado.',
          ),
          ManualStep(
            'Paso «Código»: escríbelo y toca «Crear empresa».',
            'Entras directamente. Si no llegó, «Reenviar código» se habilita al minuto.',
          ),
        ]),
        ManualNote(
          ManualNoteKind.tip,
          'Empiezas en el plan Gratuito. Sus límites se ven en Ajustes › Mi plan.',
        ),
      ],
    ),
    ManualSection(
      id: 'acceso',
      group: ManualGroup.start,
      title: 'Ingresar y recuperar la contraseña',
      icon: Icons.login,
      summary: 'Usuario o correo, contraseña temporal y recuperación.',
      blocks: [
        ManualSteps('Ingresar', [
          ManualStep(
            'Escribe tu usuario o tu correo en «Usuario o correo» y tu contraseña.',
            'Quien registró la empresa ingresa con su correo; el resto, con el usuario que le dio el jefe de calidad.',
          ),
          ManualStep('Toca «Ingresar».'),
          ManualStep(
            'Si es tu primer acceso con una contraseña temporal, define una nueva.',
            'Pantalla «Define tu contraseña personal»: al menos 12 caracteres, y confírmala.',
          ),
        ]),
        ManualSteps('¿Olvidaste tu contraseña?', [
          ManualStep('En el acceso, toca «¿Olvidaste tu contraseña?».'),
          ManualStep(
            'Escribe tu correo y toca «Enviar código».',
            'Solo para cuentas que ingresan con su correo.',
          ),
          ManualStep(
            'Escribe el código, la contraseña nueva y su confirmación, y toca «Guardar contraseña».',
          ),
        ]),
        ManualNote(
          ManualNoteKind.important,
          'Si ingresas con un usuario (no un correo), pide al jefe de calidad '
          'una contraseña temporal desde Ajustes › Usuarios. La cuenta es '
          'personal: no la compartas.',
        ),
        ManualNote(
          ManualNoteKind.norm,
          'Cada cuenta es individual y la sesión vence sola: así cada '
          'registro queda atribuido a quien lo hizo.',
          reference: '7.11.3 a',
        ),
      ],
    ),
    ManualSection(
      id: 'inicio',
      group: ManualGroup.start,
      title: 'La pantalla de inicio',
      icon: Icons.home_outlined,
      summary: 'Qué muestra Inicio y la barra de navegación.',
      blocks: [
        ManualList('Inicio', [
          '«Hoy»: lo que falta verificar hoy, lo hecho y lo atrasado. Lleva a la Agenda.',
          '«Alertas»: verificaciones con resultado no conforme o sin trazabilidad que siguen abiertas.',
          '«Nueva captura»: lleva a Verificar para elegir la balanza.',
          '«Historial» y «Borradores»: verificaciones finalizadas y capturas sin finalizar.',
          '«Gestionar plantas» y «Gestionar patrones»: áreas y pesas patrón de cada planta.',
          'Para el jefe de calidad, una franja con el plan y el recurso más usado (por ejemplo «4 de 5 balanzas»).',
        ]),
        ManualList('Barra inferior', [
          'Inicio · Verificar · Agenda · Plantas · Ajustes.',
        ]),
      ],
    ),
    // ── Configurar ─────────────────────────────────────────────────────
    ManualSection(
      id: 'plantas',
      group: ManualGroup.setup,
      title: 'Plantas y áreas',
      icon: Icons.factory_outlined,
      audience: 'Jefe de calidad',
      summary: 'Crear plantas (empresas registradas desde la app) y sus áreas.',
      blocks: [
        ManualSteps('Crear una planta', [
          ManualStep(
            'Ve a Plantas › «Áreas» y toca «Nueva planta».',
            'Solo en empresas registradas desde la app; en las que gestiona Métrica, las plantas vienen de Métrica.',
          ),
          ManualStep(
            'Escribe el nombre, la ciudad y la dirección, y toca «Crear planta».',
            'Quedas asignado a la planta. Si el plan no admite más, aparece el aviso del plan.',
          ),
        ]),
        ManualSteps('Crear un área', [
          ManualStep('Toca la planta y luego «Nueva área».'),
          ManualStep(
            'Escribe el «Nombre del área» y toca «Guardar».',
            'El menú de tres puntos › «Sugerir áreas desde Ubicación» propone áreas a partir de la ubicación de las balanzas.',
          ),
        ]),
        ManualNote(
          ManualNoteKind.tip,
          'Para renombrar o desactivar una planta: entra a la planta y usa el menú de tres puntos › '
          '«Editar planta». Una planta con balanzas activas no se desactiva.',
        ),
      ],
    ),
    ManualSection(
      id: 'patrones',
      group: ManualGroup.setup,
      title: 'Pesas patrón',
      icon: Icons.straighten_outlined,
      audience: 'Jefe de calidad',
      summary: 'Registrar las pesas patrón y en qué plantas se usan.',
      blocks: [
        ManualSteps('Registrar un patrón', [
          ManualStep('Ve a Plantas › «Patrones» y toca «Nuevo patrón».'),
          ManualStep(
            'Completa código, descripción, tipo, clase, unidad y capacidad, y elige las «Plantas donde se utilizará».',
          ),
          ManualStep('Toca «Guardar».'),
        ]),
        ManualParagraph(
          'Cada patrón muestra sus certificados con fecha de calibración y '
          'vencimiento. Un certificado se anula con «Anular conservando '
          'historial»: deja de estar disponible para nuevas verificaciones y '
          'las anteriores no cambian.',
        ),
        ManualNote(
          ManualNoteKind.important,
          'Una verificación es trazable solo si usa un certificado vigente. '
          'Con un certificado vencido, o sin pesas patrón, el resultado se '
          'marca «No trazable».',
        ),
      ],
    ),
    ManualSection(
      id: 'registrar-balanza',
      group: ManualGroup.setup,
      title: 'Registrar una balanza',
      icon: Icons.scale_outlined,
      audience: 'Jefe de calidad',
      summary: 'Incorporar una balanza que Métrica no tiene en su catálogo.',
      blocks: [
        ManualSteps('Registrar', [
          ManualStep(
            'Ve a Verificar › «Por planta», elige la planta y toca «Registrar balanza».',
          ),
          ManualStep(
            'Paso «Área»: elige un «Área existente» o escribe un «Área nueva».',
          ),
          ManualStep(
            'Paso «Identificación»: código interno (obligatorio), marca, modelo, serie y ubicación.',
            'No se admite otro código interno igual en la planta ni la misma marca y serie en la empresa.',
          ),
          ManualStep(
            'Paso «Datos técnicos»: tipo, unidad, clase y hasta tres rangos con capacidad máxima, división d y, si se conoce, intervalo e.',
            'Cada capacidad supera a la anterior; d es menor que la capacidad y e no es menor que d.',
          ),
          ManualStep(
            'Marca «Confirmo que estos datos corresponden a la balanza» y toca «Registrar balanza».',
            'Se abre su ficha para configurar las verificaciones.',
          ),
        ]),
        ManualParagraph(
          'La identificación y el área se corrigen siempre desde la ficha › '
          '«Editar balanza». Los datos técnicos solo mientras la balanza no '
          'tenga capturas ni verificaciones; al cambiarlos hay que volver a '
          'configurar las pruebas. Una balanza en uso se da de baja con motivo '
          '(menú de tres puntos › «Dar de baja esta balanza») y su historial se conserva.',
        ),
      ],
    ),
    ManualSection(
      id: 'configurar',
      group: ManualGroup.setup,
      title: 'Configurar las verificaciones',
      icon: Icons.tune,
      audience: 'Jefe de calidad',
      summary: 'Pruebas, periodicidad y error permisible de cada balanza.',
      blocks: [
        ManualSteps('Configurar', [
          ManualStep(
            'En la ficha de la balanza toca «Configurar pruebas» (o «Actualizar pruebas»).',
            'Si la balanza viene del catálogo de Métrica, antes hay que «Validar ficha».',
          ),
          ManualStep(
            'Paso «Pruebas y periodicidad»: elige las pruebas y toca la periodicidad de cada una.',
            'El editor muestra la regla en palabras y las próximas fechas.',
          ),
          ManualStep(
            'Paso «Errores permisibles»: escribe el error permisible de cada prueba.',
            'El límite pertenece al proceso interno de tu empresa.',
          ),
          ManualStep(
            'Toca «Activar configuración» (o «Guardar nueva versión»).',
            'Una configuración nueva no modifica las verificaciones anteriores.',
          ),
        ]),
        ManualList('Periodicidad', [
          'Accesos rápidos: diaria, días hábiles, semanal, quincenal, mensual, bimestral, trimestral, semestral y anual.',
          '«Personalizada»: cada N días, semanas, meses o años; en meses, un día fijo o «el primer lunes».',
          '«Fechas fijas» mantiene las fechas aunque una verificación se atrase; «Desde la última» cuenta desde la última verificación hecha.',
          'Aviso previo de 0 a 90 días: desde entonces la balanza aparece como próxima.',
        ]),
        ManualNote(
          ManualNoteKind.tip,
          'En el plan Gratuito, «Personalizada» y «Desde la última» tienen '
          'candado: se usan los accesos rápidos con fechas fijas.',
        ),
      ],
    ),
    ManualSection(
      id: 'operadores',
      group: ManualGroup.setup,
      title: 'Asignar balanzas a los operadores',
      icon: Icons.groups_outlined,
      audience: 'Jefe de calidad',
      summary: 'Qué balanzas ve y verifica cada operador.',
      blocks: [
        ManualSteps('Desde Plantas', [
          ManualStep('Ve a Plantas › «Operadores» y elige la planta.'),
          ManualStep(
            'Toca un operador, marca sus balanzas (hay búsqueda y «marcar todas») y guarda.',
          ),
        ]),
        ManualParagraph(
          'También desde la ficha de una balanza › «Operadores». Una balanza '
          'puede tener varios operadores.',
        ),
        ManualNote(
          ManualNoteKind.important,
          'Un operador sin asignaciones no ve ninguna balanza: ni en '
          'Verificar ni en la Agenda. Inicio avisa de las balanzas sin '
          'operador.',
        ),
      ],
    ),
    ManualSection(
      id: 'usuarios',
      group: ManualGroup.setup,
      title: 'Usuarios de la empresa',
      icon: Icons.manage_accounts_outlined,
      audience: 'Jefe de calidad',
      summary:
          'Crear cuentas, contraseñas temporales y desactivar (empresas registradas desde la app).',
      blocks: [
        ManualSteps('Crear un usuario', [
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
            'La app no los vuelve a mostrar. La persona debe cambiar la contraseña en su primer acceso.',
          ),
        ]),
        ManualList('En el menú de tres puntos de cada usuario', [
          '«Editar»: nombre, rol, plantas y si la cuenta está activa. Desactivar pide un motivo y libera el cupo.',
          '«Contraseña temporal»: pone una nueva y obliga a cambiarla en el próximo acceso.',
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'Solo el personal autorizado usa la app, cada uno con su cuenta. '
          'Al irse alguien, desactiva su cuenta: su historial se conserva.',
          reference: '6.2.6 · 7.11.3 a',
        ),
      ],
    ),
    // ── Verificar ──────────────────────────────────────────────────────
    ManualSection(
      id: 'buscar',
      group: ManualGroup.verify,
      title: 'Buscar una balanza y su ficha',
      icon: Icons.search,
      summary: 'Verificar, la ficha y la vigencia de cada prueba.',
      blocks: [
        ManualList('Verificar', [
          '«Por planta»: entra a una planta y busca por código interno o marca.',
          '«Lista completa»: todas tus balanzas habilitadas.',
          'El operador ve solo las balanzas que tiene asignadas.',
        ]),
        ManualList('Ficha de la balanza', [
          'Datos de identificación, rangos y área.',
          '«Vigencia por prueba»: cuándo toca cada prueba y si está al día.',
          '«Historial» y «Borradores» de esa balanza.',
          'La píldora «Iniciar verificación» queda fija abajo; si no se puede, un aviso dice por qué.',
        ]),
      ],
    ),
    ManualSection(
      id: 'captura',
      group: ManualGroup.verify,
      title: 'Capturar una verificación',
      icon: Icons.fact_check_outlined,
      summary: 'Los cinco pasos de la captura, de las pesas al resultado.',
      blocks: [
        ManualSteps('Paso a paso', [
          ManualStep(
            'En la ficha, toca «Iniciar verificación».',
            'El botón de arriba a la izquierda abre el panel de pasos; el menú de tres puntos, las opciones extra.',
          ),
          ManualStep(
            '«Pesas patrón y ambiente»: elige los certificados de las pesas que usarás y registra temperatura y humedad.',
            'Sin pesas patrón, continúa e identifica el origen de las cargas en cada prueba.',
          ),
          ManualStep(
            '«Excentricidad»: elige la forma de la plataforma y las posiciones, aplica la misma carga en cada una y registra la indicación.',
            'La posición 1 es la referencia central.',
          ),
          ManualStep(
            '«Repetibilidad»: elige cantidad de cargas y mediciones; retira y vuelve a aplicar la misma carga en cada repetición.',
          ),
          ManualStep(
            '«Linealidad»: registra la indicación para cada carga del rango («Agregar punto» / «Retirar último»).',
          ),
          ManualStep(
            '«Resumen»: revisa condiciones, pesas y lecturas, escribe las observaciones y toca «Finalizar».',
            'Confirma en «Finalizar verificación intermedia»: el servidor calcula el resultado y la verificación queda privada y sin edición.',
          ),
        ]),
        ManualList('Mientras capturas', [
          'Escribe cada lectura en el momento en que la lees, con el teclado numérico propio. La coma y el punto valen como decimal.',
          '«Usar sugerencia» y «Sugerir indicación» proponen valores: revísalos contra el indicador antes de aceptarlos.',
          'Para no ejecutar una prueba: menú de tres puntos › «Omitir esta prueba» y escribe el «Motivo de omisión».',
          'La línea bajo el título dice si la captura está guardada en el teléfono y en el servidor.',
          'Para salir sin perder nada: menú de tres puntos › «Guardar y salir».',
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'Las lecturas son observaciones originales: se registran en el '
          'momento, por quien las observó, y el servidor guarda quién capturó, '
          'quién finalizó, la fecha, la versión de la app y las condiciones.',
          reference: '7.5.1',
        ),
      ],
    ),
    ManualSection(
      id: 'agenda',
      group: ManualGroup.verify,
      title: 'Agenda',
      icon: Icons.calendar_month_outlined,
      summary: 'Qué toca verificar cada día y qué está atrasado.',
      blocks: [
        ManualParagraph(
          'La Agenda muestra el mes con cuántas balanzas tocan cada día y el '
          'color de la más urgente. Arriba van las atrasadas; abajo, el detalle '
          'del día elegido. El jefe de calidad ve las de sus plantas y filtra '
          'por operador o «Sin operador».',
        ),
        ManualList('Estados', [
          'Programada · Próxima · Hoy · Hecha · Atrasada · No realizada.',
        ]),
        ManualNote(
          ManualNoteKind.tip,
          'Cuenta como hecha cualquier verificación finalizada en la ventana '
          'de cada fecha, con o sin pesas patrón. La trazabilidad se indica en '
          'su resultado.',
        ),
      ],
    ),
    // ── Registros y datos ──────────────────────────────────────────────
    ManualSection(
      id: 'historial',
      group: ManualGroup.records,
      title: 'Historial, resultado y alertas',
      icon: Icons.history,
      summary:
          'Consultar una verificación, anularla o compartirla con Métrica.',
      blocks: [
        ManualList('La verificación muestra', [
          'Resultado (Conforme, No conforme o No concluyente), alcance y trazabilidad.',
          '«Capturado por», «Finalizado por», «Fecha de medición» y «Fecha de recepción».',
          'El expediente completo: equipo, plan, condiciones, patrones y lecturas tal como se registraron.',
        ]),
        ManualSteps('Anular una verificación', [
          ManualStep(
            'Abre la verificación y usa el menú de tres puntos › «Anular con motivo».',
          ),
          ManualStep(
            'Escribe el motivo y confirma. Después haz una nueva verificación si corresponde.',
            'La anulación conserva toda la evidencia: el registro queda visible como anulado.',
          ),
        ]),
        ManualSteps('Compartir una alerta con Métrica', [
          ManualStep(
            'En una alerta, toca «Revisar expediente para compartir».',
          ),
          ManualStep(
            'Revisa el expediente completo, escribe el «Mensaje para Métrica» y marca la autorización.',
          ),
          ManualStep(
            'Toca «Compartir expediente». Puedes «Retirar acceso» después.',
            'Retirar el acceso no elimina las copias ya entregadas.',
          ),
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'Un registro finalizado no se modifica: los cambios se hacen '
          'anulando con motivo y registrando de nuevo, y queda rastro de '
          'ambos.',
          reference: '7.5.2',
        ),
      ],
    ),
    ManualSection(
      id: 'informe',
      group: ManualGroup.records,
      title: 'Informe PDF',
      icon: Icons.picture_as_pdf_outlined,
      summary: 'Generar y compartir el informe de una verificación.',
      blocks: [
        ManualSteps(null, [
          ManualStep('Abre la verificación en el Historial.'),
          ManualStep(
            'Toca «Generar informe PDF» y elige dónde guardarlo o compartirlo.',
            'El nombre del archivo lleva el código de la balanza y la fecha.',
          ),
        ]),
        ManualList('Contenido', [
          'Completo: identificación, condiciones, resumen, lecturas de cada prueba, croquis de excentricidad, gráficos y trazabilidad de las pesas patrón.',
          'Resumido (plan Gratuito): identificación, condiciones y resumen de resultados.',
          'Siempre: aviso de alcance legal, quién lo generó y cuándo, y la procedencia del registro.',
        ]),
        ManualNote(
          ManualNoteKind.important,
          'El informe NO tiene validez legal ni es un certificado de '
          'calibración.',
        ),
      ],
    ),
    ManualSection(
      id: 'borradores',
      group: ManualGroup.records,
      title: 'Borradores',
      icon: Icons.edit_note,
      summary: 'Qué pasa con la captura si se cierra la app.',
      blocks: [
        ManualList(null, [
          'La captura se guarda sola en el teléfono y, con señal, en el servidor.',
          'Al volver a abrir la app, la captura pendiente se recupera en el paso y con las lecturas donde quedó.',
          'Las capturas sin finalizar están en Inicio › «Borradores» y vencen a los 30 días.',
          'Si el servidor tiene otra versión de la misma captura, la app no la sobrescribe: «Ver datos del servidor» muestra las diferencias.',
        ]),
      ],
    ),
    ManualSection(
      id: 'sin-conexion',
      group: ManualGroup.records,
      title: 'Trabajar sin señal',
      icon: Icons.wifi_off,
      summary: 'Qué se puede hacer sin conexión y cómo se envía después.',
      blocks: [
        ManualParagraph(
          'Cada vez que la app se conecta, descarga lo necesario para trabajar '
          'sin señal: Inicio, el catálogo de balanzas, la ficha de cada una '
          'con su configuración y sus pesas patrón, la agenda de este mes y '
          'del siguiente y el historial reciente. Sin conexión, una franja '
          'arriba dice «Sin conexión · datos del…» con la fecha de esa copia.',
        ),
        ManualList('Sin señal puedes', [
          'Consultar Inicio, Verificar, la ficha de las balanzas, la agenda y el historial descargados.',
          'Capturar una verificación y finalizarla: queda «Finalizada en el teléfono», con la hora en que la terminaste, y ya no se edita.',
        ]),
        ManualList('Necesitan señal', [
          'Registrarte, ingresar y recuperar la contraseña.',
          'Usuarios, plantas, áreas, pesas patrón, registrar o configurar balanzas, Mi plan y solicitudes.',
          'Anular una verificación, compartirla con Métrica y eliminar la cuenta.',
        ]),
        ManualSteps('Cuando vuelve la señal', [
          ManualStep(
            'No hagas nada: con la app abierta, cada verificación se envía sola, de la más antigua a la más nueva.',
            'La franja dice «Enviando…» y el servidor calcula el resultado de cada una al recibirla.',
          ),
          ManualStep(
            'Revisa Ajustes › «Por enviar» si quieres ver el estado de cada una o tocar «Enviar ahora».',
          ),
          ManualStep(
            'Si el servidor rechaza una (por ejemplo, porque su certificado se anuló), la franja lo avisa en rojo. Ábrela, lee el motivo y toca «Corregir la captura».',
          ),
        ]),
        ManualNote(
          ManualNoteKind.important,
          'La app trabaja sin conexión hasta 7 días desde la última vez que '
          'validó tu cuenta (lo ves en Ajustes › «Trabajo sin conexión»). '
          'Pasado ese plazo pide señal; lo capturado no se pierde. Mientras '
          'tengas verificaciones por enviar no puedes cerrar sesión.',
        ),
        ManualNote(
          ManualNoteKind.tip,
          'Antes de ir a una planta sin cobertura, abre la app con señal unos '
          'minutos: así descarga las fichas y la agenda al día.',
        ),
        ManualNote(
          ManualNoteKind.norm,
          'Una verificación hecha sin señal guarda la hora en que se midió '
          '(corregida si el reloj del teléfono estaba desfasado) y la hora en '
          'que llegó al servidor; el detalle y el informe muestran las dos.',
          reference: '7.5 · 7.11.3',
        ),
      ],
    ),
    ManualSection(
      id: 'privacidad',
      group: ManualGroup.records,
      title: 'Privacidad e integridad de los registros',
      icon: Icons.shield_outlined,
      summary: 'Quién ve tus datos y cómo se protegen.',
      blocks: [
        ManualList('Privacidad', [
          'Cada empresa ve solo sus balanzas, verificaciones y usuarios.',
          'Métrica no ve tus verificaciones: recibe solo lo que el jefe de calidad autoriza (un expediente o los datos de una balanza) y ese acceso se puede retirar.',
          'Las balanzas que registra tu empresa no llegan a los sistemas de Métrica salvo que autorices enviarlas.',
        ]),
        ManualList('Integridad', [
          'La conexión es cifrada (HTTPS) y cada cuenta es personal.',
          'Una verificación finalizada no se edita ni se borra; la anulación queda registrada con su motivo.',
          'Cada verificación guarda quién capturó, quién finalizó, la fecha de medición y de recepción, la versión de la app y una copia del equipo y de la configuración usados.',
          'El resultado lo calcula el servidor con la configuración activa, no el teléfono.',
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'Si tu empresa trabaja con la NB/ISO/IEC 17025 o con ISO 9001, '
          'estos registros sirven como evidencia de las verificaciones '
          'intermedias de tus equipos. El plazo de conservación lo define tu '
          'empresa en su procedimiento.',
          reference: '7.5 · 8.4',
        ),
      ],
    ),
    // ── Cuenta y plan ──────────────────────────────────────────────────
    ManualSection(
      id: 'plan',
      group: ManualGroup.account,
      title: 'Mi plan y solicitudes',
      icon: Icons.workspace_premium_outlined,
      summary: 'Límites, uso y cómo pedir un plan superior.',
      blocks: [
        ManualParagraph(
          'Ajustes › «Mi plan» muestra el uso de cada límite (plantas, '
          'balanzas, usuarios, verificaciones del mes y pesas patrón), lo que '
          'incluye el plan y los planes disponibles. Las verificaciones del '
          'mes cuentan las finalizadas desde el día 1 más las capturas en '
          'curso.',
        ),
        ManualSteps('Pedir un plan superior', [
          ManualStep(
            'Toca «Solicitar plan superior» (en Mi plan o en el aviso de límite).',
          ),
          ManualStep(
            'Elige el plan que te interesa y qué necesitas; agrega un mensaje y un teléfono si quieres.',
          ),
          ManualStep(
            'Toca «Enviar solicitud». Métrica te contacta y habilita el cambio.',
            'Tus balanzas, verificaciones e informes se conservan. Puedes cancelar la solicitud desde el menú de tres puntos.',
          ),
        ]),
      ],
    ),
    ManualSection(
      id: 'eliminar',
      group: ManualGroup.account,
      title: 'Eliminar la cuenta o la empresa',
      icon: Icons.person_remove_outlined,
      summary: 'Qué se elimina, qué se conserva y cómo hacerlo.',
      blocks: [
        ManualSteps(null, [
          ManualStep(
            'Ve a Ajustes › menú de tres puntos › «Eliminar mi cuenta» (o «Eliminar la empresa», si eres su jefe de calidad y la registraste desde la app).',
          ),
          ManualStep(
            'Lee qué se elimina y qué se conserva, escribe tu contraseña y marca que entiendes que es definitivo.',
          ),
          ManualStep('Toca «Eliminar definitivamente».'),
        ]),
        ManualList(null, [
          'Se eliminan el acceso, el nombre, el correo y el teléfono; donde aparecían queda «Usuario eliminado».',
          'Se conservan, sin datos personales, las verificaciones finalizadas y la auditoría.',
          'Si eres el único jefe de calidad, nombra a otro en Usuarios o elimina la empresa completa.',
          'Si tienes verificaciones por enviar, envíalas antes: al eliminar la cuenta se descartan.',
          'Sin la app: https://metrica.com.bo/ivmet/eliminar-cuenta.',
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'La eliminación no borra evidencia: queda una constancia de quién la '
          'pidió y cuándo, y los registros técnicos se conservan desvinculados '
          'de las personas.',
          reference: '8.4',
        ),
      ],
    ),
    // ── Ayuda ──────────────────────────────────────────────────────────
    ManualSection(
      id: 'mensajes',
      group: ManualGroup.help,
      title: 'Mensajes frecuentes',
      icon: Icons.help_outline,
      summary: 'Qué significa un mensaje y qué hacer.',
      blocks: [
        ManualList(null, [
          '«Sin conexión. Esto necesita internet…»: esa acción necesita señal. Las verificaciones que capturas se guardan en el teléfono y se envían solas.',
          '«Sin conexión, y esto no está en la copia del teléfono.»: ábrelo una vez con señal y después quedará disponible sin conexión.',
          '«Pasaron más de 7 días sin validar tu cuenta.»: conéctate a internet para seguir; tus capturas se conservan.',
          '«El registro cambió en otro dispositivo…»: vuelve a abrir el registro antes de guardar.',
          '«Justifica cada prueba omitida.»: escribe el motivo de omisión.',
          '«Un certificado ya no está disponible para esta planta.»: el certificado se anuló o venció; elige otro.',
          '«El borrador venció. Inicia uno nuevo.»: pasaron 30 días sin finalizar.',
          '«Tu plan no admite más balanzas.» (u otro límite): revisa Mi plan o pide uno superior.',
          '«Tu acceso no está activo…»: tu cuenta no tiene cupo vigente; avisa al jefe de calidad.',
          '«Demasiados intentos…»: espera unos minutos antes de volver a intentar.',
        ]),
      ],
    ),
    ManualSection(
      id: 'soporte',
      group: ManualGroup.help,
      title: 'Soporte y reporte de fallas',
      icon: Icons.support_agent_outlined,
      summary: 'A quién avisar si la app falla y qué informar.',
      blocks: [
        ManualSteps('Si algo falla', [
          ManualStep(
            'Anota qué estabas haciendo, el mensaje exacto y la hora.',
            'Si puedes, toma una captura de pantalla.',
          ),
          ManualStep(
            'Indica la versión de la app (Ajustes › Versión de la app) y la balanza o verificación afectada.',
          ),
          ManualStep(
            'Escribe a sistemas@metrica.com.bo y dile a tu jefe de calidad si la falla pudo afectar un resultado.',
          ),
        ]),
        ManualNote(
          ManualNoteKind.norm,
          'Las fallas del sistema y lo que se hizo para resolverlas deben '
          'quedar registradas; si una falla pudo afectar un resultado, tu '
          'empresa decide si anular la verificación y repetirla.',
          reference: '7.11.3 e',
        ),
      ],
    ),
  ],
);

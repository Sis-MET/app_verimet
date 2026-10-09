# Marco de pantallas de la app

Las pantallas de trabajo siguen el marco de la calibración de ServiceMET: el
AppBar solo dice dónde se está, lo raro va en ⋮ y la acción principal queda
fija a la vista. Las piezas están en `app/lib/shared/widgets/wizard_chrome.dart`
y en `OnlinePage`/`RemotePage` (`app/lib/features/online/online_widgets.dart`).

## Asistentes por pasos

`WizardScaffold`: ≡ a la izquierda abre el panel de pasos; al centro, el título
y «Paso N de M · nombre»; a la derecha, las acciones extra (⋮); bajo el AppBar,
una línea de 3 px con un tramo por paso; abajo a la derecha, la píldora
`WizardNavPill` con Anterior y la acción del paso.

- El panel marca cada paso como completo, por revisar (en óxido) o pendiente,
  con una línea de detalle, y lleva a cualquiera sin validar.
- «Siguiente» valida el paso; si falta algo, `revealFirstFormError` lleva al
  primer campo marcado y lo dice.
- Atrás del sistema cierra el panel, retrocede un paso y, en el primero,
  pregunta antes de perder lo no guardado (la captura, que se autoguarda, no
  sale: avisa cómo salir con ⋮).
- Los avisos breves (`showWizardMessage`) flotan sobre la píldora.

| Pantalla | Pasos | ⋮ |
| --- | --- | --- |
| Captura de la verificación | Pesas patrón y ambiente · Excentricidad · Repetibilidad · Linealidad · Resumen | Omitir o incluir la prueba, datos de la balanza, ver datos del servidor, guardar y salir |
| Configurar verificaciones | Pruebas y periodicidad · Errores permisibles | Salir (sin guardar) |
| Registrar o editar balanza | Área · Identificación · Datos técnicos | Salir (sin guardar) |
| Crear cuenta de empresa | Tu empresa · Tu cuenta · Código | — |

## Páginas de una sola vista

`OnlinePage(floating: WizardNavPill.action(...))` deja la acción principal fija
abajo a la derecha, en lugar de al final de la lista; `pageMenu` arma ⋮ solo si
hay opciones. `RemotePage` carga los datos y con ellos arma también ⋮ y la
píldora. El contenido deja `WizardNavPill.contentPadding` libre al final.

| Pantalla | Píldora | ⋮ |
| --- | --- | --- |
| Ficha de la balanza | Iniciar verificación (si no se puede, un aviso dice por qué) | Ver envíos a Métrica, dar de baja |
| Verificación finalizada | Generar informe PDF | Anular con motivo |
| Formularios (`CustomerForm`): áreas, patrones, certificados, validar ficha, envíos, baja | La acción del formulario | — |
| Autorizar envío de una alerta | Compartir expediente | — |
| Áreas de una planta | Nueva área | Sugerir áreas desde Ubicación |
| Balanzas de una planta (jefe) | Registrar balanza | — |
| Balanzas de un operador / operadores de una balanza | Guardar | — |
| Mi plan | Solicitar plan superior (jefe, sin solicitud abierta) | Cancelar solicitud |
| Usuarios (empresa autoregistrada) | Nuevo usuario | Editar y contraseña temporal, en cada fila |
| Plantas › Plantas y áreas (empresa autoregistrada) | Nueva planta | Editar planta, dentro de cada planta |
| Recuperar contraseña | Enviar código · Guardar contraseña | — |
| Eliminar mi cuenta / Eliminar la empresa | Eliminar definitivamente (con contraseña y casilla) | — |
| Manual de uso | — | Exportar PDF |
| Sección del manual | Siguiente: _sección_ | — |

El aviso de límite del plan es una hoja inferior con una sola acción
(«Solicitar plan superior»), no un cuadro más en la pantalla.

Las pestañas de la barra inferior (Inicio, Verificar, Agenda, Plantas,
Ajustes) no llevan píldora: la barra flotante ocupa ese lugar. Ajustes sí tiene
⋮, con lo que no se hace a diario: Eliminar mi cuenta y, para el jefe de una
empresa autoregistrada, Eliminar la empresa.

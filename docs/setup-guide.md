# Guía de inicio

La primera vez que alguien ingresa, la app abre una guía con lo que su rol
tiene que hacer, en orden, para no entrar a ciegas. Cada paso trae una
animación corta, la ruta de pantallas y botones («Plantas › Patrones › Nuevo
patrón»), las acciones numeradas con el texto exacto de cada botón, notas y un
botón «Ir a…» que cierra la guía y abre esa pantalla.

Código: `app/lib/features/online/setup_guide.dart` (pasos y estados),
`setup_guide_screen.dart` (portada, pasos y franja de Inicio),
`setup_guide_scenes.dart` (animaciones) y `setup_guide_memory.dart` (lo que
recuerda el teléfono).

## Pasos por rol

| Jefe de calidad (empresa autoregistrada) | Jefe de calidad (empresa de Métrica) | Operador |
| --- | --- | --- |
| Plantas y áreas | Plantas y áreas (las habilita Métrica) | Tus balanzas |
| Pesas patrón | Pesas patrón | Tu agenda |
| Balanzas (registrarlas) | Validar balanzas | Pesas patrón y ambiente |
| Pruebas y periodicidad | Pruebas y periodicidad | Excentricidad |
| Errores permisibles | Errores permisibles | Repetibilidad |
| Tu equipo (Ajustes › Usuarios) | Tu equipo (cuentas que crea Métrica) | Linealidad |
| Asignar balanzas | Asignar balanzas | Resumen y finalizar |
| Primera verificación | Primera verificación | Sin señal |
| Resultados y alertas | Resultados y alertas | |

Los textos siguen al manual de uso (`user_manual_content.dart`): un cambio de
flujo que actualice allí una sección actualiza aquí su paso.

## Cómo se marca cada paso

El servidor envía en `bootstrap` un resumen, `setup`, con conteos del mismo
alcance que el resto de la lectura: el jefe cuenta sus plantas; el operador,
lo que tiene asignado y lo que capturó él.

| Campo | Qué cuenta |
| --- | --- |
| `plants`, `areas` | Plantas y áreas activas a las que se tiene acceso |
| `patterns`, `tracedPatterns` | Pesas patrón activas de esas plantas, y las que tienen un certificado vigente |
| `equipment` | Balanzas habilitadas en el alcance (todas las de sus plantas para el jefe; las asignadas para el operador) |
| `validated` | De ellas, con la ficha validada por la empresa |
| `configured` | De ellas, con una configuración de pruebas publicada y vigente |
| `assigned` | De ellas, con al menos un operador |
| `operators` | Operadores activos en las plantas del jefe; `null` para el operador |
| `verifications` | Verificaciones finalizadas, anuladas incluidas (el operador, solo las suyas) |

Un paso medido queda completo, «por revisar» (en óxido: «1 de 3
configuradas») o pendiente. Los pasos que solo se leen (excentricidad, la
agenda…) cuentan como hechos al verlos.

## Cuándo se abre

- Sola, una vez por cuenta y teléfono: después del ingreso, si no se reabrió
  una captura a medias, hay conexión y el servidor envía `setup`.
- Desde Inicio, con una franja («2 de 9 pasos · sigue: Pesas patrón») hasta
  que se toca «Terminar» en el último paso. Lleva directo al primer paso que
  falta.
- Desde Ajustes › Ayuda › «Guía de inicio», siempre.

Lo que recuerda (abierta, terminada, pasos leídos) se guarda en el almacén
local de los borradores con la clave `guide:v1|<cuenta>`. Cerrar sesión no lo
borra; eliminar la cuenta, sí.

Con «Quitar animaciones» del sistema, las escenas se dibujan quietas en su
cuadro final.

## Despliegue

1. Aplicar la migración `202610200001_setup_guide.sql` (solo lectura y
   aditiva: envuelve `ivmet_mobile_read` y agrega `setup` a `bootstrap`).

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

2. Compilar la app (`pnpm app:aab`).

Una app anterior ignora `setup`. Una app nueva contra un servidor sin la
migración no abre la guía sola ni muestra la franja; desde Ajustes se puede
abrir igual, sin marcas.

## Pruebas

```bash
node --test scripts/test-operator-agenda-db.mjs
```

```bash
cd app && flutter test test/online/setup_guide_test.dart
```

La prueba de la app recorre cada paso de los tres roles en un teléfono de
360 × 640 con texto grande: un desborde la hace fallar.

## Vista previa

`app/test/online/guide_preview.dart` levanta la app con un servidor sintético.
Corre en debug o profile, nunca en release; en el navegador hace falta
profile, porque el servidor web de debug espera la extensión de depuración:

```bash
cd app && flutter run -d web-server --profile --web-port 8421 -t test/online/guide_preview.dart
```

Se ingresa con `operador` / `fixture-password`. `?rol=operador` muestra la
guía del operador; `?rol=metrica`, la del jefe de una empresa de Métrica.

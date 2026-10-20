# Certificados de las pesas patrón

Una verificación es trazable solo si usa una pesa patrón con un certificado de
calibración vigente. Los patrones los administra la empresa desde la app, y
sus certificados también: RimMET no los crea (`ivmet_admin_mutate` responde
`CUSTOMER_MANAGED_CONFIGURATION`). Hasta esta entrega la app tampoco los
creaba, porque el formulario se había retirado, así que nadie podía volver
trazable una verificación sin tocar la base.

## En la app

Plantas › «Patrones» (el operador lo ve como «Pesas patrón»). Cada tarjeta de
patrón:

- dice el estado de cada certificado: **Vigente**, **Vencido** (en óxido) o
  **Anulado**;
- avisa «Sin certificado vigente: las verificaciones con esta pesa salen «No
  trazable»» cuando no tiene ninguno vigente;
- lleva «Agregar certificado» junto a «Editar patrón», con las mismas
  condiciones: acceso a todas las plantas del patrón.

El formulario pide número, laboratorio, fecha de calibración y vencimiento.
Las fechas se eligen en el calendario de la agenda, no se teclean. Antes de
enviar, el teléfono comprueba que el número no repita otro certificado del
patrón (aunque esté anulado), que la calibración no sea futura y que el
vencimiento no sea anterior a ella. Un certificado mal cargado se anula con
motivo; no se borra.

El estado que muestra la lista se calcula en el teléfono con la fecha de hoy
y solo orienta. La trazabilidad la decide el servidor al finalizar.

## En el servidor

La acción `certificate.create` de `ivmet_customer_mutate` ya existía. La
migración `202610200002_pattern_certificates.sql` la envuelve para que la app
reciba un motivo que sabe explicar, en lugar de la violación de una
restricción:

| Código | Cuándo |
| --- | --- |
| `INVALID_CERTIFICATE` | Falta el patrón, el número o el laboratorio, o las fechas no son `AAAA-MM-DD` |
| `INVALID_CERTIFICATE_DATES` | Fecha imposible, vencimiento anterior a la calibración o calibración futura (un día de margen por la zona horaria) |
| `CERTIFICATE_EXISTS` | El patrón ya tiene ese número, aunque esté anulado, sin distinguir mayúsculas ni espacios |
| `PATTERN_NOT_ACCESSIBLE` | El patrón no es de la empresa o no está en las plantas de quien lo pide |

Número y laboratorio se guardan sin espacios sobrantes. Un reintento con el
mismo `request_id` devuelve el recibo de la primera vez.

## Despliegue y pruebas

Aplicar la migración antes de distribuir la app:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

Una app anterior no ofrece agregar certificados. Una app nueva contra un
servidor sin la migración los crea igual; solo pierde los mensajes
específicos.

```bash
node --test scripts/test-mobile-db.mjs
```

```bash
cd app && flutter test test/online/pattern_certificates_test.dart
```

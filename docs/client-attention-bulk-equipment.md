# Avisos por cliente y habilitación de balanzas en lote

Entrega del 16/09/2026 para Gestión IvMET en RimMET. Migración:
`202609160001_client_attention_bulk_equipment.sql`.

## Resultado funcional

- **Casos y actualizaciones** se atienden dentro de la ficha de cada cliente.
  El directorio muestra en cada tarjeta cuántos casos compartidos siguen en
  estado *Recibido* y cuántas actualizaciones de balanzas esperan revisión, y
  las pestañas de la ficha repiten esos números. Solo se cuenta lo que el
  cliente mantiene compartido; lo retirado no aparece.
- **Habilitar balanzas**: en **Balanzas** de la ficha, un botón con el número de
  pendientes abre un diálogo con las balanzas de DataMET activas y validadas
  que aún no están habilitadas, agrupadas por planta y con búsqueda. Se eligen
  una por una, por planta o todas, y se habilitan juntas. Las suspendidas van
  en una sección plegada fuera de «seleccionar todas»: fueron una decisión
  explícita y solo se reactivan si se marcan a propósito. Las que requieren
  revisión en DataMET no aparecen.
- El lote se aplica completo o no se aplica: si una balanza no es del cliente,
  fue registrada por la empresa o necesita revisión, ninguna cambia.
- La habilitación sigue siendo comercial: soporte y metrología no pueden
  ejecutarla. La importación desde DataMET no habilita balanzas por sí sola.

## Cómo está construido

- `ivmet_admin_read('clients')` agrega `newCases` y `pendingUpdates` por
  cliente; `client` agrega `attention` con los mismos conteos, y `equipment`
  agrega `pendingEnable`. Dos índices parciales mantienen baratos los conteos
  que RimMET consulta cada 10 segundos.
- `private.equipment_pending_enable` define qué balanzas cuentan como
  pendientes: validadas, activas y sin habilitar ni suspender.
- `ivmet_admin_mutate` suma `equipment.bulk-configure` (`clientId`, `enabled`,
  `ids`, hasta 500 por solicitud; RimMET divide selecciones mayores). Exige
  permiso `commercial`, es idempotente por `requestId`, serializa los lotes de
  un mismo cliente y bloquea las balanzas igual que `equipment.configure`.
- Solo cambian las balanzas que no estaban en el estado pedido: no suben
  versiones ni generan eventos de más. Cada balanza cambiada deja su registro en
  `public.auditoria`. `equipos_ivmet` no se exporta al espejo SQL Server.

## Despliegue

No cambia SQL Server, el worker ni su contrato (sigue siendo la versión 4).

1. Validar en el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:admin
pnpm db:test:mobile
```

`pnpm db:test:admin` incluye `scripts/test-bulk-equipment-db.mjs`.
`pnpm db:test:operations` mantiene sus dos fallos previos, ajenos a esta
entrega.

2. Aplicar la migración en Supabase. El ensayo debe mostrar solo
   `202609160001_client_attention_bulk_equipment.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

```powershell
pnpm dlx supabase db lint --linked --level warning
```

3. Publicar RimMET (frontend y backend juntos). La migración va antes: con la
   versión anterior de Supabase, RimMET no muestra contadores ni pendientes, y
   la habilitación en lote falla. Un RimMET anterior sigue
   funcionando con la migración aplicada.

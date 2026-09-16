# Balanzas registradas por el cliente

Entrega del 15/09/2026. Permite que una empresa incorpore en IvMET las balanzas
que compra o adquiere y a las que Métrica todavía no tiene acceso.

## Resultado funcional

- Solo el jefe de calidad registra, desde **Verificar → planta → Registrar
  balanza**. Indica el área (una existente o una nueva, que se crea en esa
  planta), el código interno, marca, modelo, serie y ubicación, el tipo
  (balanza o plataforma / báscula camionera), la unidad (kg, g, t o mg), la
  clase opcional (I a IIII) y hasta tres rangos: capacidad máxima, división *d*
  y, si se conoce, intervalo de verificación *e*.
- La balanza queda disponible al instante: ficha validada, habilitada en IvMET
  y lista para **Configurar pruebas**. El tipo camionero elige el perfil de
  báscula camionera.
- Reglas: cada capacidad supera a la anterior, *d* es mayor que cero y menor
  que la capacidad, y *e*, si se declara, no es menor que *d*. No se admite otro
  código interno igual en la planta ni la misma marca y serie en la empresa,
  entre las balanzas que la empresa ve. Una balanza del catálogo que no está
  habilitada en IvMET no bloquea el alta ni se revela.
- **Correcciones**: la identificación y el área se corrigen siempre. Los datos
  técnicos solo mientras la balanza no tenga capturas abiertas ni
  verificaciones; al cambiarlos se retira la configuración activa y hay que
  volver a configurar las pruebas. Con uso, la alternativa es dar de baja y
  registrarla de nuevo.
- **Baja**: solo el jefe de calidad, con motivo y sin capturas abiertas. El
  historial se conserva; la balanza deja de aparecer para capturar.
- **Privacidad**: la balanza no existe en DataMET ni se exporta al espejo SQL
  Server. RimMET no la ve en el listado de balanzas ni en los conteos, y no
  puede habilitarla ni suspenderla.
- **Envío a Métrica**: si la empresa lo decide, el jefe de calidad revisa la
  vista previa (identificación, área y datos técnicos) y autoriza con un mensaje
  y consentimiento explícito. El envío llega a **Actualizaciones de balanzas**,
  en la ficha del cliente en RimMET, donde Métrica lo marca como revisado. Un cambio posterior requiere
  otra autorización, y el acceso se puede retirar desde **Ver envíos a
  Métrica**.
- Si Métrica calibra después esa balanza y entra desde DataMET, aparece como
  otra balanza. No se fusionan solas porque la evidencia es inmutable; vincular
  ambas queda para una etapa posterior.

## Cómo está construido

- `public.equipos.origen` distingue `DATAMET` de `CLIENTE`, con
  `registrado_por` y `registrado_at`. Una balanza registrada no tiene
  `legacy_equipo_id` ni `cod_metrica` (restricción `equipos_origen_ck`). El
  worker sigue importando DataMET por `cod_metrica` y nunca la toca.
- Reutiliza áreas, `equipos_ivmet`, `equipos_cliente`, configuración guiada,
  borradores, finalización y alertas. La ficha nace validada porque la empresa
  es la fuente, y `source_hash` se recalcula con cada corrección.
- Un trigger en `private.sync_outbox` retiene (`privacy_blocked`) los eventos de
  `equipos`, `equipo_rangos`, `actualizaciones_compartidas` y
  `casos_compartidos` de estas balanzas. El espejo exige código de Métrica y
  enlaza expedientes y fichas con `mirror.equipos`: exportarlas dejaría eventos
  muertos que bloquean toda la cola del worker.
- `ivmet_admin_read` las excluye de `equipment`, `overview` y `clients`, e
  `ivmet_admin_mutate('equipment.configure')` las rechaza.
- El contrato móvil está en [API móvil](mobile-online-api.md#balanzas-registradas-por-el-cliente).

## Despliegue

No cambia SQL Server, el worker ni su contrato (sigue siendo la versión 4).

1. Validar en el equipo de desarrollo:

```powershell
Set-Location 'C:\Users\jhona\IvMET'
pnpm db:test:mobile
pnpm db:test:admin
pnpm test:mobile-auth
```

`pnpm db:test:mobile` incluye `scripts/test-registered-equipment-db.mjs`.
`pnpm db:test:operations` tiene dos pruebas que ya fallaban antes de esta
entrega (configuración guiada con decimales exactos y exportación de
evidencia); no dependen de esta migración.

```powershell
Set-Location .\app
flutter analyze
flutter test
```

2. Aplicar la migración en Supabase. El ensayo debe mostrar
   `202609150001_customer_registered_equipment.sql`:

```powershell
pnpm dlx supabase db push --linked --dry-run
```

```powershell
pnpm dlx supabase db push --linked
```

```powershell
pnpm dlx supabase db lint --linked --level warning
```

3. Publicar RimMET con la bandeja que muestra una balanza registrada. Sin esa
   versión, la bandeja enseña la identificación pero no los rangos, y los casos
   de esas balanzas aparecen sin código.
4. Compilar y distribuir la app (`pnpm app:apk` o `pnpm app:aab`).

La migración va antes que la app: la app nueva la necesita para registrar. Una
app anterior sigue funcionando con la migración aplicada.

## Validación manual antes de distribuir

- Registrar una balanza con un área nueva y otra con un área existente; ambas
  aparecen en Verificar como **Registrada por la empresa**.
- Configurar sus pruebas, capturar y finalizar una verificación.
- Corregir la identificación de una balanza con verificaciones e intentar
  cambiar su capacidad: la app lo impide.
- Enviarla a Métrica, revisarla en RimMET y retirar el acceso desde la app.
- Dar de baja una balanza sin capturas abiertas.
- Confirmar en SQL Server `IvMET` que no llegó ninguna fila de esas balanzas y
  que la cola del worker no tiene eventos muertos.

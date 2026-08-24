begin;

create or replace function private.user_has_active_license(
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (target_user_id = auth.uid() or auth.role() = 'service_role')
    and exists (
      select 1
      from public.perfiles p
      join public.licencias_usuario l
        on l.usuario_id = p.id and l.estado = 'ACTIVE'
      join public.suscripciones s
        on s.id = l.suscripcion_id
      join public.contratos c
        on c.id = s.contrato_id and c.cliente_id = p.cliente_id
      where p.id = target_user_id
        and p.activo
        and not p.debe_cambiar_password
        and c.estado = 'ACTIVE'
        and c.vigente_desde <= current_date
        and (c.vigente_hasta is null or c.vigente_hasta >= current_date)
        and (
          (s.estado = 'ACTIVE' and s.inicio_periodo <= now() and s.fin_periodo > now())
          or (s.estado = 'GRACE' and s.gracia_hasta is not null and s.gracia_hasta > now())
        )
    );
$$;

create or replace function private.current_profile_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol
  from public.perfiles p
  where p.id = auth.uid() and p.activo;
$$;

create or replace function private.current_cliente_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.cliente_id
  from public.perfiles p
  where p.id = auth.uid() and p.activo;
$$;

create or replace function private.user_has_plant(target_plant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuario_plantas up
    join public.plantas pl on pl.id = up.planta_id
    join public.perfiles p on p.id = up.usuario_id
    where up.usuario_id = auth.uid()
      and up.planta_id = target_plant_id
      and up.activa
      and p.activo
      and p.cliente_id = pl.cliente_id
  );
$$;

create or replace function private.can_access_client(target_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.user_has_active_license(auth.uid())
    and private.current_cliente_id() = target_cliente_id;
$$;

create or replace function private.can_access_plant(target_plant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.user_has_active_license(auth.uid())
    and private.user_has_plant(target_plant_id);
$$;

create or replace function private.can_read_verification(target_verification_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.verificaciones v
    where v.id = target_verification_id
      and (
        (
          private.current_profile_role() like 'cliente_%'
          and private.can_access_client(v.cliente_id)
          and private.can_access_plant(v.planta_id)
        )
        or (
          private.current_profile_role() in ('metrica_tecnico', 'metrica_admin')
          and exists (
            select 1
            from public.alertas a
            where a.verificacion_id = v.id
              and a.visibilidad_metrica = 'SHARED'
          )
        )
      )
  );
$$;

revoke all on function private.user_has_active_license(uuid) from public, anon;
revoke all on function private.current_profile_role() from public, anon;
revoke all on function private.current_cliente_id() from public, anon;
revoke all on function private.user_has_plant(uuid) from public, anon;
revoke all on function private.can_access_client(uuid) from public, anon;
revoke all on function private.can_access_plant(uuid) from public, anon;
revoke all on function private.can_read_verification(uuid) from public, anon;
grant execute on function private.user_has_active_license(uuid) to authenticated, service_role;
grant execute on function private.current_profile_role() to authenticated, service_role;
grant execute on function private.current_cliente_id() to authenticated, service_role;
grant execute on function private.user_has_plant(uuid) to authenticated, service_role;
grant execute on function private.can_access_client(uuid) to authenticated, service_role;
grant execute on function private.can_access_plant(uuid) to authenticated, service_role;
grant execute on function private.can_read_verification(uuid) to authenticated, service_role;

grant select on public.clientes, public.plantas, public.equipos, public.equipo_rangos
  to authenticated;
grant select on public.usuario_plantas to authenticated;
grant select on public.planes_comerciales to authenticated;
grant select on public.areas, public.equipos_ivmet, public.patrones,
  public.patron_plantas, public.patron_certificados, public.planes,
  public.plan_versiones, public.plan_pruebas, public.plan_puntos,
  public.equipo_planes, public.verificacion_borradores, public.verificaciones,
  public.verificacion_patrones, public.pruebas, public.lecturas, public.alertas
  to authenticated;
grant insert (
  request_uuid, cliente_id, planta_id, area_id, equipo_id,
  plan_version_id, usuario_id, estado, paso_actual, payload, expires_at
) on public.verificacion_borradores to authenticated;
grant update (paso_actual, payload, estado, expires_at)
  on public.verificacion_borradores to authenticated;

create policy clientes_select_licensed
on public.clientes for select to authenticated
using (private.can_access_client(id));

create policy plantas_select_assigned
on public.plantas for select to authenticated
using (activo and private.can_access_plant(id));

create policy equipos_select_assigned
on public.equipos for select to authenticated
using (
  activo
  and estado_catalogo = 'READY'
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
);

create policy equipo_rangos_select_assigned
on public.equipo_rangos for select to authenticated
using (
  exists (
    select 1 from public.equipos e
    where e.id = equipo_rangos.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
  )
);

create policy usuario_plantas_select_self
on public.usuario_plantas for select to authenticated
using (usuario_id = auth.uid() and activa);

create policy planes_comerciales_select_subscribed
on public.planes_comerciales for select to authenticated
using (
  exists (
    select 1
    from public.suscripciones s
    join public.contratos c on c.id = s.contrato_id
    where s.plan_id = planes_comerciales.id
      and c.cliente_id = private.current_cliente_id()
  )
);

create policy areas_select_assigned
on public.areas for select to authenticated
using (
  activa
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
);

create policy equipos_ivmet_select_assigned
on public.equipos_ivmet for select to authenticated
using (
  habilitado
  and estado_configuracion = 'READY'
  and exists (
    select 1 from public.equipos e
    where e.id = equipos_ivmet.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
  )
);

create policy patrones_select_assigned
on public.patrones for select to authenticated
using (
  activo
  and private.can_access_client(cliente_id)
  and exists (
    select 1 from public.patron_plantas pp
    where pp.patron_id = patrones.id
      and private.can_access_plant(pp.planta_id)
  )
);

create policy patron_plantas_select_assigned
on public.patron_plantas for select to authenticated
using (
  private.can_access_plant(planta_id)
  and exists (
    select 1 from public.patrones p
    where p.id = patron_plantas.patron_id
      and p.activo
      and private.can_access_client(p.cliente_id)
  )
);

create policy patron_certificados_select_assigned
on public.patron_certificados for select to authenticated
using (
  estado = 'ACTIVE'
  and exists (
    select 1 from public.patrones p
    where p.id = patron_certificados.patron_id
      and p.activo
      and private.can_access_client(p.cliente_id)
      and exists (
        select 1 from public.patron_plantas pp
        where pp.patron_id = p.id
          and private.can_access_plant(pp.planta_id)
      )
  )
);

create policy planes_select_licensed
on public.planes for select to authenticated
using (
  activo
  and private.user_has_active_license(auth.uid())
  and (cliente_id is null or cliente_id = private.current_cliente_id())
);

create policy plan_versiones_select_published
on public.plan_versiones for select to authenticated
using (
  estado in ('PUBLISHED', 'RETIRED')
  and exists (
    select 1 from public.planes p
    where p.id = plan_versiones.plan_id
      and p.activo
      and private.user_has_active_license(auth.uid())
      and (p.cliente_id is null or p.cliente_id = private.current_cliente_id())
  )
);

create policy plan_pruebas_select_published
on public.plan_pruebas for select to authenticated
using (
  exists (
    select 1
    from public.plan_versiones pv
    join public.planes p on p.id = pv.plan_id
    where pv.id = plan_pruebas.plan_version_id
      and pv.estado in ('PUBLISHED', 'RETIRED')
      and p.activo
      and private.user_has_active_license(auth.uid())
      and (p.cliente_id is null or p.cliente_id = private.current_cliente_id())
  )
);

create policy plan_puntos_select_published
on public.plan_puntos for select to authenticated
using (
  exists (
    select 1
    from public.plan_pruebas pt
    join public.plan_versiones pv on pv.id = pt.plan_version_id
    join public.planes p on p.id = pv.plan_id
    where pt.id = plan_puntos.plan_prueba_id
      and pv.estado in ('PUBLISHED', 'RETIRED')
      and p.activo
      and private.user_has_active_license(auth.uid())
      and (p.cliente_id is null or p.cliente_id = private.current_cliente_id())
  )
);

create policy equipo_planes_select_assigned
on public.equipo_planes for select to authenticated
using (
  exists (
    select 1 from public.equipos e
    where e.id = equipo_planes.equipo_id
      and e.activo
      and e.estado_catalogo = 'READY'
      and private.can_access_client(e.cliente_id)
      and private.can_access_plant(e.planta_id)
  )
);

create policy verificacion_borradores_select_own
on public.verificacion_borradores for select to authenticated
using (
  usuario_id = auth.uid()
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
);

create policy verificacion_borradores_insert_own
on public.verificacion_borradores for insert to authenticated
with check (
  usuario_id = auth.uid()
  and estado = 'DRAFT'
  and version = 1
  and finalized_at is null
  and verificacion_id is null
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
  and exists (
    select 1
    from public.equipos e
    join public.equipos_ivmet ei on ei.equipo_id = e.id
    where e.id = verificacion_borradores.equipo_id
      and e.cliente_id = verificacion_borradores.cliente_id
      and e.planta_id = verificacion_borradores.planta_id
      and e.activo and e.estado_catalogo = 'READY'
      and ei.habilitado and ei.estado_configuracion = 'READY'
  )
  and exists (
    select 1
    from public.equipo_planes ep
    join public.plan_versiones pv on pv.id = ep.plan_version_id
    where ep.equipo_id = verificacion_borradores.equipo_id
      and ep.plan_version_id = verificacion_borradores.plan_version_id
      and ep.vigente_desde <= now()
      and (ep.vigente_hasta is null or ep.vigente_hasta > now())
      and pv.estado = 'PUBLISHED'
  )
);

create policy verificacion_borradores_update_own
on public.verificacion_borradores for update to authenticated
using (
  usuario_id = auth.uid()
  and estado = 'DRAFT'
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
)
with check (
  usuario_id = auth.uid()
  and estado in ('DRAFT', 'ABANDONED')
  and finalized_at is null
  and verificacion_id is null
  and private.can_access_client(cliente_id)
  and private.can_access_plant(planta_id)
);

create policy verificaciones_select_authorized
on public.verificaciones for select to authenticated
using (private.can_read_verification(id));

create policy verificacion_patrones_select_authorized
on public.verificacion_patrones for select to authenticated
using (private.can_read_verification(verificacion_id));

create policy pruebas_select_authorized
on public.pruebas for select to authenticated
using (private.can_read_verification(verificacion_id));

create policy lecturas_select_authorized
on public.lecturas for select to authenticated
using (
  exists (
    select 1 from public.pruebas p
    where p.id = lecturas.prueba_id
      and private.can_read_verification(p.verificacion_id)
  )
);

create policy alertas_select_authorized
on public.alertas for select to authenticated
using (private.can_read_verification(verificacion_id));

create or replace function public.share_ivmet_alert(
  target_alert_id uuid,
  expected_row_version bigint,
  share_message text default null
)
returns public.alertas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.alertas%rowtype;
begin
  if private.current_profile_role() <> 'cliente_jefe_calidad' then
    raise exception using errcode = '42501', message = 'QUALITY_MANAGER_REQUIRED';
  end if;

  select * into target from public.alertas a
  where a.id = target_alert_id for update;

  if not found
     or not private.can_access_client(target.cliente_id)
     or not private.can_access_plant(target.planta_id) then
    raise exception using errcode = '42501', message = 'ALERT_NOT_ACCESSIBLE';
  end if;
  if target.row_version <> expected_row_version then
    raise exception using errcode = '40001', message = 'ROW_VERSION_CONFLICT';
  end if;
  if target.visibilidad_metrica <> 'PRIVATE' then
    raise exception using errcode = 'P0001', message = 'ALERT_ALREADY_SHARED';
  end if;

  update public.alertas
  set visibilidad_metrica = 'SHARED',
      compartida_at = now(),
      compartida_por = auth.uid(),
      mensaje_compartido = nullif(btrim(share_message), '')
  where id = target_alert_id
  returning * into target;

  insert into public.auditoria (actor_id, cliente_id, entidad, entidad_id, accion, despues)
  values (auth.uid(), target.cliente_id, 'alerta', target.id::text, 'SHARED_WITH_METRICA', to_jsonb(target));
  return target;
end;
$$;

create or replace function public.close_ivmet_alert(
  target_alert_id uuid,
  expected_row_version bigint
)
returns public.alertas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.alertas%rowtype;
begin
  if private.current_profile_role() <> 'cliente_jefe_calidad' then
    raise exception using errcode = '42501', message = 'QUALITY_MANAGER_REQUIRED';
  end if;
  select * into target from public.alertas a where a.id = target_alert_id for update;
  if not found
     or not private.can_access_client(target.cliente_id)
     or not private.can_access_plant(target.planta_id) then
    raise exception using errcode = '42501', message = 'ALERT_NOT_ACCESSIBLE';
  end if;
  if target.row_version <> expected_row_version then
    raise exception using errcode = '40001', message = 'ROW_VERSION_CONFLICT';
  end if;
  if target.estado_cliente <> 'OPEN' then
    raise exception using errcode = 'P0001', message = 'ALERT_ALREADY_CLOSED';
  end if;
  update public.alertas set estado_cliente = 'CLOSED'
  where id = target_alert_id returning * into target;
  insert into public.auditoria (actor_id, cliente_id, entidad, entidad_id, accion, despues)
  values (auth.uid(), target.cliente_id, 'alerta', target.id::text, 'CLOSED_BY_CLIENT', to_jsonb(target));
  return target;
end;
$$;

create or replace function public.acknowledge_ivmet_alert(
  target_alert_id uuid,
  expected_row_version bigint
)
returns public.alertas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.alertas%rowtype;
begin
  if private.current_profile_role() not in ('metrica_tecnico', 'metrica_admin') then
    raise exception using errcode = '42501', message = 'METRICA_ROLE_REQUIRED';
  end if;
  select * into target from public.alertas a where a.id = target_alert_id for update;
  if not found or target.visibilidad_metrica <> 'SHARED' then
    raise exception using errcode = '42501', message = 'ALERT_NOT_ACCESSIBLE';
  end if;
  if target.row_version <> expected_row_version then
    raise exception using errcode = '40001', message = 'ROW_VERSION_CONFLICT';
  end if;
  if target.estado_metrica <> 'PENDING' then
    raise exception using errcode = 'P0001', message = 'INVALID_ALERT_TRANSITION';
  end if;
  update public.alertas
  set estado_metrica = 'ACKNOWLEDGED',
      reconocida_at = now(),
      reconocida_por = auth.uid()
  where id = target_alert_id returning * into target;
  insert into public.auditoria (actor_id, cliente_id, entidad, entidad_id, accion, despues)
  values (auth.uid(), target.cliente_id, 'alerta', target.id::text, 'ACKNOWLEDGED_BY_METRICA', to_jsonb(target));
  return target;
end;
$$;

create or replace function public.attend_ivmet_alert(
  target_alert_id uuid,
  expected_row_version bigint,
  attention_note text
)
returns public.alertas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.alertas%rowtype;
begin
  if private.current_profile_role() not in ('metrica_tecnico', 'metrica_admin') then
    raise exception using errcode = '42501', message = 'METRICA_ROLE_REQUIRED';
  end if;
  if attention_note is null or btrim(attention_note) = '' then
    raise exception using errcode = '22023', message = 'ATTENTION_NOTE_REQUIRED';
  end if;
  select * into target from public.alertas a where a.id = target_alert_id for update;
  if not found or target.visibilidad_metrica <> 'SHARED' then
    raise exception using errcode = '42501', message = 'ALERT_NOT_ACCESSIBLE';
  end if;
  if target.row_version <> expected_row_version then
    raise exception using errcode = '40001', message = 'ROW_VERSION_CONFLICT';
  end if;
  if target.estado_metrica <> 'ACKNOWLEDGED' then
    raise exception using errcode = 'P0001', message = 'INVALID_ALERT_TRANSITION';
  end if;
  update public.alertas
  set estado_metrica = 'ATTENDED',
      atendida_at = now(),
      atendida_por = auth.uid(),
      nota_atencion = btrim(attention_note)
  where id = target_alert_id returning * into target;
  insert into public.auditoria (actor_id, cliente_id, entidad, entidad_id, accion, despues)
  values (auth.uid(), target.cliente_id, 'alerta', target.id::text, 'ATTENDED_BY_METRICA', to_jsonb(target));
  return target;
end;
$$;

create or replace function public.annul_ivmet_verification(
  target_verification_id uuid,
  annulment_reason text
)
returns public.verificaciones
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.verificaciones%rowtype;
begin
  if private.current_profile_role() <> 'cliente_jefe_calidad' then
    raise exception using errcode = '42501', message = 'QUALITY_MANAGER_REQUIRED';
  end if;
  if annulment_reason is null or btrim(annulment_reason) = '' then
    raise exception using errcode = '22023', message = 'ANNULMENT_REASON_REQUIRED';
  end if;
  select * into target from public.verificaciones v
  where v.id = target_verification_id for update;
  if not found
     or not private.can_access_client(target.cliente_id)
     or not private.can_access_plant(target.planta_id) then
    raise exception using errcode = '42501', message = 'VERIFICATION_NOT_ACCESSIBLE';
  end if;
  if target.estado <> 'ACTIVE' then
    raise exception using errcode = 'P0001', message = 'VERIFICATION_ALREADY_ANNULLED';
  end if;
  update public.verificaciones
  set estado = 'ANNULLED',
      anulada_at = now(),
      anulada_por = auth.uid(),
      motivo_anulacion = btrim(annulment_reason)
  where id = target_verification_id returning * into target;
  insert into public.auditoria (actor_id, cliente_id, entidad, entidad_id, accion, despues)
  values (auth.uid(), target.cliente_id, 'verificacion', target.id::text, 'ANNULLED', to_jsonb(target));
  return target;
end;
$$;

revoke all on function public.share_ivmet_alert(uuid, bigint, text)
  from public, anon;
revoke all on function public.close_ivmet_alert(uuid, bigint)
  from public, anon;
revoke all on function public.acknowledge_ivmet_alert(uuid, bigint)
  from public, anon;
revoke all on function public.attend_ivmet_alert(uuid, bigint, text)
  from public, anon;
revoke all on function public.annul_ivmet_verification(uuid, text)
  from public, anon;
grant execute on function public.share_ivmet_alert(uuid, bigint, text) to authenticated;
grant execute on function public.close_ivmet_alert(uuid, bigint) to authenticated;
grant execute on function public.acknowledge_ivmet_alert(uuid, bigint) to authenticated;
grant execute on function public.attend_ivmet_alert(uuid, bigint, text) to authenticated;
grant execute on function public.annul_ivmet_verification(uuid, text) to authenticated;

commit;

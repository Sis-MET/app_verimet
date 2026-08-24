begin;

create or replace function public.resolve_ivmet_login_alias(target_username text)
returns table (auth_user_id uuid, auth_email_interno varchar)
language sql
stable
security definer
set search_path = ''
as $$
  select la.auth_user_id, la.auth_email_interno
  from private.login_aliases la
  join public.perfiles p on p.id = la.auth_user_id
  where la.usuario_normalizado = lower(btrim(target_username))
    and la.activo
    and p.activo;
$$;

create or replace function public.ivmet_access_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  profile public.perfiles%rowtype;
  license_record record;
begin
  select * into profile
  from public.perfiles p
  where p.id = auth.uid();

  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'PROFILE_MISSING');
  end if;
  if not profile.activo then
    return jsonb_build_object('allowed', false, 'reason', 'USER_DISABLED');
  end if;
  if profile.debe_cambiar_password then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'PASSWORD_CHANGE_REQUIRED',
      'role', profile.rol,
      'clientId', profile.cliente_id
    );
  end if;

  select s.id as subscription_id,
         s.estado as subscription_status,
         s.fin_periodo,
         s.gracia_hasta,
         pc.codigo as plan_code,
         pc.nombre as plan_name
    into license_record
  from public.licencias_usuario l
  join public.suscripciones s on s.id = l.suscripcion_id
  join public.contratos c on c.id = s.contrato_id
  join public.planes_comerciales pc on pc.id = s.plan_id
  where l.usuario_id = profile.id
    and l.estado = 'ACTIVE'
    and c.cliente_id = profile.cliente_id
  order by l.asignada_at desc
  limit 1;

  if not found or not private.user_has_active_license(profile.id) then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'LICENSE_INACTIVE',
      'role', profile.rol,
      'clientId', profile.cliente_id,
      'subscriptionStatus', license_record.subscription_status,
      'periodEndsAt', license_record.fin_periodo,
      'graceEndsAt', license_record.gracia_hasta
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'reason', 'ACTIVE',
    'role', profile.rol,
    'clientId', profile.cliente_id,
    'subscriptionId', license_record.subscription_id,
    'subscriptionStatus', license_record.subscription_status,
    'periodEndsAt', license_record.fin_periodo,
    'graceEndsAt', license_record.gracia_hasta,
    'planCode', license_record.plan_code,
    'planName', license_record.plan_name
  );
end;
$$;

create or replace function public.complete_ivmet_password_change(target_user_id uuid)
returns public.perfiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.perfiles%rowtype;
begin
  update public.perfiles p
  set debe_cambiar_password = false
  where p.id = target_user_id
    and p.activo
  returning * into target;

  if not found then
    raise exception using errcode = '42501', message = 'ACTIVE_PROFILE_REQUIRED';
  end if;

  insert into public.auditoria (
    actor_id, cliente_id, entidad, entidad_id, accion, despues
  ) values (
    target_user_id, target.cliente_id, 'perfil', target.id::text,
    'PASSWORD_CHANGED',
    jsonb_build_object('debe_cambiar_password', false)
  );

  return target;
end;
$$;

revoke all on function public.resolve_ivmet_login_alias(text)
  from public, anon, authenticated;
revoke all on function public.ivmet_access_status()
  from public, anon;
revoke all on function public.complete_ivmet_password_change(uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_ivmet_login_alias(text) to service_role;
grant execute on function public.ivmet_access_status() to authenticated;
grant execute on function public.complete_ivmet_password_change(uuid) to service_role;

commit;

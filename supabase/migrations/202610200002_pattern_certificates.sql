begin;

-- Certificados de las pesas patrón desde la app.
--
-- La empresa administra sus patrones y RimMET no puede crear certificados
-- (`ivmet_admin_mutate` responde CUSTOMER_MANAGED_CONFIGURATION), así que la
-- app es el único camino para que una verificación sea trazable. La acción
-- `certificate.create` ya existía; esta entrega le da errores que la app sabe
-- explicar en lugar de la violación de restricción de la base:
--
-- - INVALID_CERTIFICATE_DATES: fecha imposible, vencimiento anterior a la
--   calibración o calibración en el futuro (un día de margen por la zona
--   horaria del teléfono).
-- - CERTIFICATE_EXISTS: el patrón ya tiene ese número, aunque esté anulado,
--   sin distinguir mayúsculas ni espacios.
--
-- Número y laboratorio se guardan sin espacios sobrantes. Se normaliza
-- siempre, también al reintentar: el recibo idempotente se compara con la
-- huella del payload ya normalizado.
alter function public.ivmet_customer_mutate(text,jsonb,uuid) rename to customer_mutate_before_certificates;
alter function public.customer_mutate_before_certificates(text,jsonb,uuid) set schema private;
do $migration$
begin
  execute replace(pg_get_functiondef('private.customer_mutate_before_certificates(text,jsonb,uuid)'::regprocedure),
    'ivmet_customer_mutate.','customer_mutate_before_certificates.');
end;
$migration$;

create function public.ivmet_customer_mutate(action text,payload jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pattern_id uuid; calibrated date; expires date;
begin
  if action='certificate.create' and jsonb_typeof(payload)='object' then
    if jsonb_typeof(payload->'number')='string' and jsonb_typeof(payload->'lab')='string' then
      payload:=payload||jsonb_build_object('number',btrim(payload->>'number'),'lab',btrim(payload->>'lab'));
    end if;
    -- Solo una solicitud nueva: un reintento recupera su recibo aunque el
    -- número ya exista, porque lo creó ella misma.
    if request_id is not null and not exists(select 1 from private.admin_requests r
        where r.request_id=ivmet_customer_mutate.request_id and r.action='customer.certificate.create') then
      perform private.mobile_require();
      perform private.admin_assert(coalesce(payload->>'patternId','')
        ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$','INVALID_CERTIFICATE');
      pattern_id:=(payload->>'patternId')::uuid;
      -- Alcance del patrón y su cerrojo: dos altas a la vez no repiten número.
      perform private.customer_pattern(pattern_id,true);
      perform private.admin_assert(length(payload->>'number') between 1 and 150
        and length(payload->>'lab') between 1 and 250
        and payload->>'calibratedOn' ~ '^\d{4}-\d{2}-\d{2}$' and payload->>'expiresOn' ~ '^\d{4}-\d{2}-\d{2}$',
        'INVALID_CERTIFICATE');
      begin
        calibrated:=(payload->>'calibratedOn')::date;
        expires:=(payload->>'expiresOn')::date;
      exception when others then
        raise exception 'INVALID_CERTIFICATE_DATES';
      end;
      perform private.admin_assert(expires>=calibrated and calibrated<=current_date+1,'INVALID_CERTIFICATE_DATES');
      perform private.admin_assert(not exists(select 1 from public.patron_certificados c
        where c.patron_id=pattern_id and lower(btrim(c.numero))=lower(payload->>'number')),'CERTIFICATE_EXISTS');
    end if;
  end if;
  return private.customer_mutate_before_certificates(action,payload,request_id);
end; $$;

revoke all on function private.customer_mutate_before_certificates(text,jsonb,uuid)
from public,anon,authenticated,service_role;

revoke all on function public.ivmet_customer_mutate(text,jsonb,uuid) from public,anon,service_role;
grant execute on function public.ivmet_customer_mutate(text,jsonb,uuid) to authenticated;

commit;

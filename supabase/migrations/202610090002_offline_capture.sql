begin;

-- Captura sin señal. La app trabaja con la copia que descargó y, al volver la
-- conexión, envía en segundo plano lo que se midió: primero el borrador y
-- después la finalización, con los mismos identificadores de siempre.
--
-- El servidor sigue calculando el resultado. Cambian dos cosas:
--
-- - La verificación lleva la hora en que se midió, no la de llegada. El
--   teléfono manda su hora al finalizar y su hora al enviar; la diferencia con
--   el reloj del servidor corrige un reloj mal puesto. Lo que mandó el
--   teléfono queda en private.capturas_sin_conexion y la llegada, en
--   verificaciones.recibido_at.
-- - El primer guardado acepta la configuración que la balanza tenía cuando el
--   operador descargó su copia, aunque el jefe de calidad la haya cambiado
--   mientras tanto: la app trabaja hasta 7 días sin validar la cuenta, y la
--   ventana es de 8 días antes de empezar la captura.
--
-- Los certificados se evalúan en la fecha en que se midió.

create table private.capturas_sin_conexion (
  verificacion_id uuid primary key references public.verificaciones(id),
  medida_en_dispositivo_at timestamptz not null,
  desfase_reloj_s integer not null default 0
);
revoke all on private.capturas_sin_conexion from public,anon,authenticated,service_role;

-- Hora de inicio y de medición enviadas por el teléfono. Viven en ajustes
-- locales de la transacción para no cambiar la firma de las funciones internas.
create function private.capture_window_start() returns timestamptz
language sql stable set search_path='' as $$
  select nullif(current_setting('ivmet.capture_started_at',true),'')::timestamptz-interval '8 days'
$$;

create function private.capture_measured_at() returns timestamptz
language sql stable set search_path='' as $$
  select nullif(current_setting('ivmet.capture_measured_at',true),'')::timestamptz
$$;

-- El cuerpo que valida un borrador y el que finaliza se recompilan con esas
-- horas. Cada reemplazo se comprueba: si el texto cambió, la migración falla.
do $migration$
declare source text; target text;
begin
  source:=pg_get_functiondef('private.mobile_save_before_validation(uuid,uuid,uuid,bigint,jsonb,uuid)'::regprocedure);
  target:=replace(source,
    '(ep.vigente_hasta is null or ep.vigente_hasta>coalesce(d.created_at,now()))',
    '(ep.vigente_hasta is null or ep.vigente_hasta>coalesce(private.capture_window_start(),d.created_at,now()))');
  target:=replace(target,
    '(v.estado=''PUBLISHED'' or (d.id is not null and v.estado=''RETIRED''))',
    '(v.estado=''PUBLISHED'' or ((d.id is not null or private.capture_window_start() is not null) and v.estado=''RETIRED''))');
  if target=source or length(target)-length(source)<>
      length('private.capture_window_start(),')+length('( or private.capture_window_start() is not null)') then
    raise exception 'OFFLINE_SAVE_PATCH_FAILED';
  end if;
  execute target;

  source:=pg_get_functiondef('private.mobile_finalize_before_operator_scope(uuid,bigint,uuid,text,text)'::regprocedure);
  target:=replace(source,'verification_time timestamptz:=clock_timestamp();',
    'verification_time timestamptz:=coalesce(private.capture_measured_at(),clock_timestamp());');
  if target=source then raise exception 'OFFLINE_FINALIZE_PATCH_FAILED'; end if;
  execute target;
end;
$migration$;

-- Se envuelven las funciones públicas como en entregas anteriores.
alter function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid) rename to mobile_save_before_offline;
alter function public.mobile_save_before_offline(uuid,uuid,uuid,bigint,jsonb,uuid) set schema private;
alter function public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text) rename to mobile_finalize_before_offline;
alter function public.mobile_finalize_before_offline(uuid,bigint,uuid,text,text) set schema private;
alter function public.ivmet_mobile_read(text,jsonb) rename to mobile_read_before_offline;
alter function public.mobile_read_before_offline(text,jsonb) set schema private;
do $migration$
declare item record;
begin
  for item in select * from (values
    ('private.mobile_save_before_offline(uuid,uuid,uuid,bigint,jsonb,uuid)','ivmet_mobile_save_draft.','mobile_save_before_offline.'),
    ('private.mobile_finalize_before_offline(uuid,bigint,uuid,text,text)','ivmet_mobile_finalize_draft.',
      'mobile_finalize_before_offline.'),
    ('private.mobile_read_before_offline(text,jsonb)','ivmet_mobile_read.','mobile_read_before_offline.')
  ) v(signature,previous_name,next_name) loop
    execute replace(pg_get_functiondef(item.signature::regprocedure),item.previous_name,item.next_name);
  end loop;
end;
$migration$;

-- `started_at`: cuándo empezó la captura en el teléfono. Solo la envía una
-- captura hecha sin señal.
create function public.ivmet_mobile_save_draft(request_id uuid,equipment_id uuid,version_id uuid,
  expected_version bigint,content jsonb,save_id uuid,started_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if started_at is not null then
    perform private.admin_assert(started_at<=clock_timestamp()+interval '1 day','INVALID_CAPTURE_TIME');
    perform set_config('ivmet.capture_started_at',started_at::text,true);
  end if;
  result:=private.mobile_save_before_offline(request_id,equipment_id,version_id,expected_version,content,save_id);
  perform set_config('ivmet.capture_started_at','',true);
  return result;
end; $$;

-- `measured_at`: la hora del teléfono al finalizar sin señal; `device_clock`:
-- su hora al enviar. Un reintento devuelve el recibo de la primera vez.
create function public.ivmet_mobile_finalize_draft(draft_id uuid,expected_version bigint,finalize_id uuid,
  app_version_value text default null,device_id_value text default null,
  measured_at timestamptz default null,device_clock timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; skew integer:=0;
begin
  if measured_at is not null then
    if device_clock is not null then
      skew:=round(extract(epoch from clock_timestamp()-device_clock))::integer;
    end if;
    -- Nunca en el futuro: un reloj adelantado no fecha una medición después
    -- de su llegada.
    perform set_config('ivmet.capture_measured_at',
      least(measured_at+make_interval(secs=>skew),clock_timestamp())::text,true);
  end if;
  result:=private.mobile_finalize_before_offline(draft_id,expected_version,finalize_id,
    app_version_value,device_id_value);
  perform set_config('ivmet.capture_measured_at','',true);
  if measured_at is not null and not coalesce((result->>'idempotent')::boolean,false) then
    insert into private.capturas_sin_conexion(verificacion_id,medida_en_dispositivo_at,desfase_reloj_s)
      values((result->>'id')::uuid,measured_at,skew) on conflict (verificacion_id) do nothing;
  end if;
  return result;
end; $$;

create function public.ivmet_mobile_read(section text,filters jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb:=private.mobile_read_before_offline(section,filters);
begin
  if section='verification' then
    result:=result||jsonb_build_object('offlineCapture',(select jsonb_build_object(
        'deviceMeasuredAt',c.medida_en_dispositivo_at,'clockSkewSeconds',c.desfase_reloj_s)
      from private.capturas_sin_conexion c where c.verificacion_id=nullif(filters->>'id','')::uuid));
  end if;
  return result;
end; $$;

revoke all on function private.capture_window_start(),private.capture_measured_at(),
  private.mobile_save_before_offline(uuid,uuid,uuid,bigint,jsonb,uuid),
  private.mobile_finalize_before_offline(uuid,bigint,uuid,text,text),
  private.mobile_read_before_offline(text,jsonb)
from public,anon,authenticated,service_role;

revoke all on function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid,timestamptz),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text,timestamptz,timestamptz),
  public.ivmet_mobile_read(text,jsonb)
from public,anon,service_role;
grant execute on function public.ivmet_mobile_save_draft(uuid,uuid,uuid,bigint,jsonb,uuid,timestamptz),
  public.ivmet_mobile_finalize_draft(uuid,bigint,uuid,text,text,timestamptz,timestamptz),
  public.ivmet_mobile_read(text,jsonb)
to authenticated;

commit;

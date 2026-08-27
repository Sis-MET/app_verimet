begin;

-- El código es una referencia legible, no el identificador relacional (UUID).
-- No se modifica ningún código existente ni la RPC ya desplegada.
lock table public.planes_comerciales in share row exclusive mode;
create sequence private.plan_code_seq as bigint start with 1;

-- Evita colisiones con códigos manuales anteriores que ya usen este formato.
select pg_catalog.setval('private.plan_code_seq'::regclass,
  coalesce((select max(substring(codigo from 6)::bigint) + 1
    from public.planes_comerciales
    where codigo ~ '^PLAN-[0-9]{1,18}$'), 1), false);

create function private.assign_plan_code()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  number_text text;
begin
  if tg_op = 'UPDATE' then
    if new.codigo is distinct from old.codigo then
      raise exception 'PLAN_CODE_IMMUTABLE' using errcode = 'P0001';
    end if;
    return new;
  end if;
  -- nextval es atómico entre sesiones; no se usa COUNT ni MAX al dar de alta.
  -- Se ignora cualquier código enviado por una versión antigua del panel.
  loop
    number_text := pg_catalog.nextval('private.plan_code_seq'::regclass)::text;
    new.codigo := 'PLAN-' || pg_catalog.lpad(number_text, greatest(6, length(number_text)), '0');
    exit when not exists(select 1 from public.planes_comerciales p where p.codigo = new.codigo);
  end loop;
  return new;
end;
$$;

revoke all on sequence private.plan_code_seq from public, anon, authenticated, service_role;
revoke all on function private.assign_plan_code() from public, anon, authenticated, service_role;

create trigger planes_comerciales_system_code
before insert or update of codigo on public.planes_comerciales
for each row execute function private.assign_plan_code();

comment on function private.assign_plan_code() is
  'Código comercial autogenerado e inmutable. Puede haber saltos por transacciones revertidas; no es una numeración fiscal.';

commit;

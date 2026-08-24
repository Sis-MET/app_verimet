begin;

select plan(22);

select has_schema('private', 'private schema exists');
select has_table('public', 'clientes', 'client catalog exists');
select has_table('public', 'plantas', 'plant catalog exists');
select has_table('public', 'equipos', 'equipment catalog exists');
select has_table('public', 'contratos', 'contracts exist');
select has_table('public', 'suscripciones', 'subscriptions exist');
select has_table('public', 'licencias_usuario', 'user licenses exist');
select has_table('public', 'verificacion_borradores', 'online drafts exist');
select has_table('public', 'verificaciones', 'accepted evidence exists');
select has_table('private', 'sync_outbox', 'SQL Server mirror outbox exists');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.clientes'::regclass),
  'RLS is enabled on clients'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.equipos'::regclass),
  'RLS is enabled on equipment'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.verificacion_borradores'::regclass),
  'RLS is enabled on drafts'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.verificaciones'::regclass),
  'RLS is enabled on evidence'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.alertas'::regclass),
  'RLS is enabled on alerts'
);

select ok(
  not has_table_privilege('anon', 'public.clientes', 'SELECT'),
  'anonymous users cannot read clients'
);
select ok(
  not has_table_privilege('anon', 'public.verificaciones', 'SELECT'),
  'anonymous users cannot read evidence'
);
select ok(
  not has_table_privilege('authenticated', 'public.verificaciones', 'INSERT'),
  'mobile users cannot insert accepted evidence directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.verificaciones', 'UPDATE'),
  'mobile users cannot update accepted evidence directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.verificaciones', 'DELETE'),
  'mobile users cannot delete accepted evidence'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_ivmet_login_alias(text)',
    'EXECUTE'
  ),
  'login aliases are not exposed to anonymous database calls'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_ivmet_sync_outbox(text,integer)',
    'EXECUTE'
  ),
  'only the trusted mirror worker can claim outbox events'
);

select * from finish();
rollback;

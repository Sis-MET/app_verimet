begin;

-- 202608310002 ya puede estar aplicada. Recompila únicamente instalaciones
-- que conservan la variable declarada que era sombreada por los bucles FOR.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'public.ivmet_customer_configure_checks(uuid,jsonb,uuid)'::regprocedure
  ) into definition;

  if strpos(definition,'sequence_value integer;')>0 then
    definition:=replace(
      definition,
      'sequence_value integer;',
      'point_sequence integer;'
    );
    definition:=replace(definition,'sequence_value:=0;','point_sequence:=0;');
    definition:=replace(
      definition,
      'sequence_value:=sequence_value+1;',
      'point_sequence:=point_sequence+1;'
    );
    definition:=replace(
      definition,
      'test_id,1,sequence_value,''L''||lpad(sequence_value::text,2,''0''),',
      'test_id,1,point_sequence,''L''||lpad(point_sequence::text,2,''0''),'
    );
    execute definition;
  end if;
end;
$migration$;

commit;

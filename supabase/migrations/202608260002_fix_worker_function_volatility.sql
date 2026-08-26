begin;

/*
 * to_jsonb(anyelement) es STABLE en PostgreSQL. Declarar como IMMUTABLE una
 * funcion que lo utiliza promete una volatilidad mas estricta que la real y
 * hace que plpgsql_check emita una advertencia.
 */
alter function private.stringify_ivmet_outbox_numbers(text, jsonb) stable;

commit;

-- Match the displayed legacy profile count to the existing admission guard.
-- Version matches the successfully applied remote migration.
-- Retained/replaced rows already consume slots; report them too. Preserve the
-- current RPC body, membership checks, grants and every other usage value.
do $migration$
declare
  definition text := pg_get_functiondef('public.get_family_entitlements_and_usage(uuid)'::regprocedure);
  old_predicate text := E'where lfm.family_id = p_family_id\n       and coalesce(lfm.replaced_by_vault_id::text, \'\') = \'\';';
begin
  if length(definition) - length(replace(definition, old_predicate, '')) <> length(old_predicate) then
    raise exception 'Unexpected legacy profile usage query; inspect before applying';
  end if;
  execute replace(definition, old_predicate, 'where lfm.family_id = p_family_id;');
end;
$migration$;

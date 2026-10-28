-- Search context is derived by trusted indexing functions, never client input.
-- Preserve existing reads, source memories, policies and service-role indexing.
revoke insert, update, delete, truncate, references, trigger
  on public.memory_chunks, public.legacy_memory_chunks
  from public, anon, authenticated;

-- Table revocation alone does not remove independently granted column writes.
do $$
declare relation_name text; column_list text;
begin
  foreach relation_name in array array['memory_chunks','legacy_memory_chunks'] loop
    select string_agg(quote_ident(attname),', ' order by attnum) into column_list
      from pg_attribute where attrelid=format('public.%I',relation_name)::regclass
        and attnum>0 and not attisdropped;
    execute format('revoke insert (%s), update (%s), references (%s) on public.%I from public, anon, authenticated',
      column_list,column_list,column_list,relation_name);
  end loop;
end;
$$;

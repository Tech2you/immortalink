select
  p.proname,
  pg_get_functiondef(p.oid) like '%for update%' as locks_invite_or_vault_rows,
  pg_get_functiondef(p.oid) like '%used_at is null%' as checks_unused_invite,
  pg_get_functiondef(p.oid) like '%already used%' as has_repeat_use_error
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'join_family_by_invite',
    'join_family_by_relationship_invite'
  )
order by p.proname;

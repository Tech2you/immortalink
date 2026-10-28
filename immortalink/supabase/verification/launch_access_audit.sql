-- Read-only catalog audit. Run with an authorized database administrator.
-- This detects access-surface drift, not correctness of every function/policy.
-- Expected signatures reflect the 24 October 2026 client contract, not blanket
-- security clearance. Investigate findings; never automatically grant/revoke.
-- This includes LOCAL pending screening permission, sharing and publication migrations. Until
-- deployed, four missing RPCs and four missing policy helpers in live are expected, not permission to
-- grant them or claim the complete candidate is already deployed.
with
client_roles(role_name) as (values ('anon'::text), ('authenticated'::text)),
expected_app(signature) as (values
  ('public.begin_family_sponsorship(uuid)'),
  ('public.can_access_legacy_family(uuid)'),
  ('public.can_access_legacy_media_from_path(text)'),
  ('public.can_access_legacy_member(uuid)'),
  ('public.can_manage_retained_legacy_media(text,text)'),
  ('public.can_read_legacy_gallery_object(text,text)'),
  ('public.can_read_shared_media_object(text,text)'),
  ('public.can_read_vault_media(uuid)'),
  ('public.create_family_group_and_link_vault(text)'),
  ('public.create_legacy_predecessor(uuid,text,text,text,integer,integer,text)'),
  ('public.create_legacy_relative(uuid,text,uuid,text,text,text,integer,integer,text)'),
  ('public.delete_legacy_predecessor(uuid)'),
  ('public.everroot_consume_ai_usage(uuid,uuid,integer)'),
  ('public.everroot_consume_transcription_usage(uuid,uuid,integer)'),
  ('public.get_family_account_successors(uuid)'),
  ('public.get_family_entitlements_and_usage(uuid)'),
  ('public.get_family_leave_impact(uuid)'),
  ('public.get_family_sponsorship(uuid)'),
  ('public.get_content_screening_permission()'),
  ('public.get_content_sharing_status(text,uuid,uuid)'),
  ('public.get_join_context(uuid)'),
  ('public.has_ai_processing_consent()'),
  ('public.is_family_member(uuid,uuid)'),
  ('public.join_family_by_invite(text)'),
  ('public.join_family_by_relationship_invite(text)'),
  ('public.leave_family(uuid)'),
  ('public.leave_family_confirmed(uuid)'),
  ('public.list_safety_members()'),
  ('public.read_shared_vault_media(uuid)'),
  ('public.release_family_sponsorship(uuid,uuid)'),
  ('public.rename_family(uuid,text)'),
  ('public.report_family_content(text,uuid,text,text,uuid)'),
  ('public.request_content_screening(text,uuid,uuid)'),
  ('public.reserve_family_sponsorship(uuid)'),
  ('public.set_ai_processing_consent(boolean)'),
  ('public.set_content_screening_permission(boolean,text,uuid)'),
  ('public.set_family_account_successor(uuid,uuid)'),
  ('public.set_member_block(uuid,boolean)'),
  ('public.set_primary_family(uuid)'),
  ('public.shares_family_with_vault(uuid)')
),
expected_policy_helper(signature) as (values
  ('content_safety.legacy_memory_visible(uuid)'),
  ('content_safety.legacy_visible(uuid)'),
  ('content_safety.memory_visible(uuid)'),
  ('content_safety.object_visible(text,text)'),
  ('content_safety.publication_allowed()'),
  ('content_safety.screening_object_mutable(text,text)'),
  ('content_safety.screening_object_readable(text,text)'),
  ('content_safety.screening_personal_readable(uuid,uuid)'),
  ('content_safety.screening_readable(text,uuid,uuid,uuid[])'),
  ('content_safety.vault_visible(uuid)'),
  ('content_safety.visible(text,uuid,uuid)')
),
expected_client_function as (
  select signature from expected_app
  union all select signature from expected_policy_helper
),
definers as (
  select p.oid, p.proconfig, p.oid::regprocedure::text as signature
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prosecdef and n.nspname in ('public','content_safety')
    and not exists (select 1 from pg_depend d where d.classid='pg_proc'::regclass
      and d.objid=p.oid and d.deptype='e')
),
relations as (
  select c.oid,c.relkind,c.relrowsecurity,c.reloptions,n.nspname,
    format('%I.%I',n.nspname,c.relname) as identity
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','content_safety','storage')
    and c.relkind in ('r','p','v','m')
    and not exists (select 1 from pg_depend d where d.classid='pg_class'::regclass
      and d.objid=c.oid and d.deptype='e')
),
checks(check_name) as (values
  ('anonymous_privileged_functions'),
  ('unexpected_client_privileged_functions'),
  ('expected_client_functions_unavailable'),
  ('privileged_functions_without_fixed_search_path'),
  ('client_writable_schemas'),
  ('client_tables_without_rls'),
  ('client_views_bypassing_rls'),
  ('private_review_relations_accessible'),
  ('client_writable_derived_indexes'),
  ('public_storage_buckets')
),
findings(check_name,object_identity) as (
  select 'anonymous_privileged_functions', signature
    from definers where has_function_privilege('anon',oid,'EXECUTE')
  union all
  select 'unexpected_client_privileged_functions',signature from definers f
    where has_function_privilege('authenticated',f.oid,'EXECUTE')
      and not exists (select 1 from expected_client_function e
        where to_regprocedure(e.signature)=f.oid)
  union all
  select 'expected_client_functions_unavailable',signature from expected_client_function
    where to_regprocedure(signature) is null
      or not has_function_privilege('authenticated',to_regprocedure(signature),'EXECUTE')
  union all
  select 'privileged_functions_without_fixed_search_path',signature from definers
    where not exists (select 1 from unnest(proconfig) setting where setting like 'search_path=%')
  union all
  select 'client_writable_schemas',r.role_name || ':' || n.nspname
    from pg_namespace n cross join client_roles r
    where n.nspname in ('public','content_safety','storage')
      and has_schema_privilege(r.role_name,n.oid,'CREATE')
  union all
  select 'client_tables_without_rls',r.role_name || ':' || t.identity
    from relations t cross join client_roles r
    where t.relkind in ('r','p') and not t.relrowsecurity
      and (has_table_privilege(r.role_name,t.oid,'SELECT,INSERT,UPDATE,DELETE')
        or has_any_column_privilege(r.role_name,t.oid,'SELECT,INSERT,UPDATE'))
  union all
  select 'client_views_bypassing_rls',r.role_name || ':' || t.identity
    from relations t cross join client_roles r
    where (t.relkind='m' or (t.relkind='v'
        and not coalesce(t.reloptions @> array['security_invoker=true'],false)))
      and (has_table_privilege(r.role_name,t.oid,'SELECT')
        or has_any_column_privilege(r.role_name,t.oid,'SELECT'))
  union all
  select 'private_review_relations_accessible',r.role_name || ':' || t.identity
    from relations t cross join client_roles r where t.nspname='content_safety'
      and (has_table_privilege(r.role_name,t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or has_any_column_privilege(r.role_name,t.oid,'SELECT,INSERT,UPDATE,REFERENCES'))
  union all
  select 'client_writable_derived_indexes',r.role_name || ':' || t.identity
    from relations t cross join client_roles r
    where t.identity in ('public.memory_chunks','public.legacy_memory_chunks')
      and (has_table_privilege(r.role_name,t.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or has_any_column_privilege(r.role_name,t.oid,'INSERT,UPDATE,REFERENCES'))
  union all
  select 'public_storage_buckets',id from storage.buckets where public
)
select c.check_name, count(f.object_identity)::integer as finding_count,
  coalesce(jsonb_agg(f.object_identity order by f.object_identity)
    filter (where f.object_identity is not null),'[]'::jsonb) as findings
from checks c left join findings f using(check_name)
group by c.check_name order by c.check_name;

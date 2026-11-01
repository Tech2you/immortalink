-- Profile slots use the same active contribution lifecycle as storage.
-- No receipts, family rows, memberships or media are changed.
do $migration$
declare
  definition text := pg_get_functiondef('heiro_billing.tier_limits(text)'::regprocedure);
begin
  if length(definition) - length(replace(definition, '''legacy_people'', 250,', '')) <> length('''legacy_people'', 250,')
     or length(definition) - length(replace(definition, '''legacy_people'', 8,', '')) <> length('''legacy_people'', 8,') then
    raise exception 'Unexpected tier definition; inspect before changing legacy allowances';
  end if;
  execute replace(replace(definition, '''legacy_people'', 250,', '''legacy_people'', 500,'), '''legacy_people'', 8,', '''legacy_people'', 50,');
end;
$migration$;

create or replace function public.everroot_limits(p_family_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with active as (
  select e.*,heiro_billing.tier_limits(e.plan) limits from public.family_entitlements e
  where family_id=p_family_id and status in ('active','grace_period')
    and (current_period_end is null or current_period_end>now())
    and plan in ('everroot_family','everroot_legacy')
 ), pooled as (
  select coalesce(sum(heiro_billing.storage_grant(plan,storage_model_version)) filter(where provider='apple'),0) bytes,
    coalesce(max((limits->>'storage_bytes')::bigint) filter(where provider is distinct from 'apple'),0) grant_bytes,
    coalesce(sum((limits->>'ai_responses_monthly')::bigint) filter(where provider='apple'),0) ai,
    coalesce(sum((limits->>'transcription_seconds_monthly')::bigint) filter(where provider='apple'),0) transcription,
    coalesce(sum((limits->>'legacy_people')::bigint) filter(where provider='apple'),0) profile_slots,
    coalesce(max((limits->>'legacy_people')::bigint) filter(where provider is distinct from 'apple'),0) grant_profile_slots
  from active
 ), tier as(select heiro_billing.tier_limits(public.everroot_family_plan(p_family_id)) limits)
 select limits || jsonb_build_object('storage_bytes',
   case when greatest(bytes,grant_bytes)>0 then greatest(bytes,grant_bytes) else 524288000 end,
   'ai_responses_monthly',least(2147483647,greatest(ai,(limits->>'ai_responses_monthly')::bigint)),
   'transcription_seconds_monthly',least(2147483647,greatest(transcription,(limits->>'transcription_seconds_monthly')::bigint)),
   'legacy_people',least(2147483647,greatest(profile_slots,grant_profile_slots,50)))
 from pooled cross join tier;
$$;
-- CREATE OR REPLACE retains the existing service-only execution grants.

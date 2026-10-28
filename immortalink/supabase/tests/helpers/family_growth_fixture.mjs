import { readFile } from 'node:fs/promises';
import { singleFamilyFixture, familyA } from './single_family_fixture.mjs';

const read = name => readFile(new URL(`../../migrations/${name}.sql`, import.meta.url),'utf8');
export const growthMigration = (await read('20261026080435_family_growth_admission_guards')) + '\n' +
  (await read('20261026080449_family_growth_invitation_limits'));
const tierSql = await read('20260826194454_everroot_three_tier_billing_model');
const quotaSql = await read('20260809100000_everroot_entitlements_and_quotas');
const readonlySql = await read('20260928212929_expired_family_read_only');
const retirementSql = await read('20261023101256_memory_media_retirement');
function fn(source, name) {
  const start = source.indexOf(`create or replace function public.${name}(`);
  if (start < 0) throw new Error(`Missing function ${name}`);
  return source.slice(start, source.indexOf('\n$$;',start)+4);
}

export async function growthFixture(db, {createRoles=true, migrate=true}={}) {
  await singleFamilyFixture(db,{createRoles});
  await db.exec(`
    alter table family_invites add primary key(id);
    alter table family_invites add created_at timestamptz default now();
    alter table family_invites add recipient_email text;
    alter table family_invites add recipient_phone text;
    create table family_entitlements(family_id uuid primary key, plan text);
    create table legacy_family_members(id uuid primary key default gen_random_uuid(),
      family_id uuid, replaced_by_vault_id uuid, name text);
    create table everroot_invite_usage_periods(family_id uuid,period_start date,used_count integer,
      primary key(family_id,period_start));
    create schema storage;
    create table storage.objects(bucket_id text,name text,metadata jsonb);
    create schema content_safety;
    create function storage.foldername(text) returns text[] language sql immutable as
      $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    create function everroot_family_plan(uuid) returns text language sql stable as
      $$select coalesce((select plan from public.family_entitlements where family_id=$1),'free')$$;
    create function everroot_media_bucket_ids() returns text[] language sql immutable as
      $$select array['memory_photos','memory_voice','vault_photos']$$;
    create function everroot_storage_metadata_size(jsonb) returns bigint language sql immutable as
      $$select coalesce(($1->>'size')::bigint,0)$$;
  `);
  // The same statement lock used by deployed Storage and membership writes.
  await db.exec(retirementSql.slice(
    retirementSql.indexOf('create function content_safety.media_lifecycle_lock()'),
    retirementSql.indexOf('do $$ declare t text; begin')));
  for (const table of ['public.family_members','public.vaults','public.legacy_family_members','storage.objects']) {
    await db.exec(`create trigger safety_media_lifecycle before insert or update or delete on ${table}
      for each statement execute function content_safety.lock_media_statement()`);
  }
  await db.exec(fn(tierSql,'everroot_limits')
    .replace("'transcription_seconds_monthly', 120000","'transcription_seconds_monthly', 24000")
    .replace("'transcription_seconds_monthly', 36000","'transcription_seconds_monthly', 7200"));
  await db.exec(`
    create function everroot_limit_int(uuid,text) returns integer language sql stable as
      $$select (public.everroot_limits($1)->>$2)::integer$$;
    create function everroot_limit_bigint(uuid,text) returns bigint language sql stable as
      $$select (public.everroot_limits($1)->>$2)::bigint$$;
    create function everroot_memory_count(uuid,uuid) returns bigint language sql stable as $$select 0::bigint$$;
    create function everroot_photo_count(uuid,uuid) returns bigint language sql stable as $$select 0::bigint$$;
    create function everroot_voice_note_count(uuid,uuid) returns bigint language sql stable as $$select 0::bigint$$;
  `);
  await db.exec(fn(quotaSql,'everroot_quota_error'));
  await db.exec(fn(quotaSql,'everroot_storage_bytes_used'));
  await db.exec(readonlySql.slice(0,readonlySql.indexOf('-- Attach to existing')));
  await db.exec(fn(quotaSql,'everroot_assert_family_member_capacity'));
  await db.exec(fn(quotaSql,'everroot_assert_legacy_person_capacity'));
  await db.exec(`
    create function everroot_assert_invite_capacity() returns trigger language plpgsql as $$begin return new; end$$;
    create trigger everroot_invite_capacity_before_insert before insert on family_invites
      for each row execute function everroot_assert_invite_capacity();
    create trigger everroot_family_member_capacity_before_insert before insert on family_members
      for each row execute function everroot_assert_family_member_capacity();
    create trigger everroot_legacy_person_capacity_before_insert before insert on legacy_family_members
      for each row execute function everroot_assert_legacy_person_capacity();
    delete from family_invites;
    select set_config('test.uid','',false);
    alter table family_invites enable row level security;
    create policy member_invites on family_invites for all to authenticated
      using(exists(select 1 from family_members where family_id=family_invites.family_id and user_id=auth.uid()))
      with check(created_by=auth.uid() and exists(select 1 from family_members where family_id=family_invites.family_id and user_id=auth.uid()));
    grant select,insert,update on family_invites to authenticated;
  `);
  if(migrate) await db.exec(growthMigration);
}

export async function installStorageQuota(db) {
  await db.exec(`
    create function auth.jwt() returns jsonb language sql as $$select '{}'::jsonb$$;
    create table public.account_deletion_jobs(user_id uuid);
    create function public.deletion_copy_authorized(text,text,bigint) returns boolean language sql as $$select false$$;
    create function content_safety.approved_retirement_move(storage.objects,storage.objects) returns boolean
      language sql as $$select false$$;
    create function public.everroot_try_uuid(text) returns uuid language plpgsql as
      $$begin return $1::uuid; exception when invalid_text_representation then return null; end$$;
  `);
  await db.exec(fn(retirementSql,'everroot_assert_storage_object_capacity'));
  await db.exec(`create trigger everroot_storage_capacity before insert or update on storage.objects
    for each row execute function public.everroot_assert_storage_object_capacity()`);
}

export async function setBytes(db, bytes, family=familyA) {
  await db.query('delete from storage.objects where name=$1',[`fixture/${family}/test.jpg`]);
  await db.query('insert into storage.objects values($1,$2,$3)',
    ['memory_photos',`fixture/${family}/test.jpg`,JSON.stringify({size:bytes})]);
}

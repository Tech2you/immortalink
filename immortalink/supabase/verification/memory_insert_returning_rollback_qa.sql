-- Disposable database-only fixtures. No real accounts, media bytes or reports
-- are accessed; every fixture and restriction is rolled back before returning.
begin;
set local statement_timeout='20s';
do $$
declare
  u uuid:=gen_random_uuid(); viewer uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  f uuid:=gen_random_uuid(); other_f uuid:=gen_random_uuid();
  v uuid:=gen_random_uuid(); other_v uuid:=gen_random_uuid();
begin
  insert into auth.users(id) values(u),(viewer),(outsider);
  insert into public.family_groups(id,name,created_by)
    values(f,'Rollback QA',u),(other_f,'Other rollback QA',outsider);
  insert into public.family_members(family_id,user_id,role)
    values(f,u,'owner'),(f,viewer,'member'),(other_f,outsider,'owner');
  insert into public.vaults(id,owner_id,family_id,name)
    values(v,u,f,'Rollback QA'),(other_v,outsider,other_f,'Other rollback QA');
  perform set_config('qa.memory_owner',u::text,true);
  perform set_config('qa.memory_viewer',viewer::text,true);
  perform set_config('qa.memory_outsider',outsider::text,true);
  perform set_config('qa.memory_vault',v::text,true);
  perform set_config('qa.memory_other_vault',other_v::text,true);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
end $$;

set local role authenticated;
do $$
declare m uuid; sibling uuid; updated uuid;
begin
  with pgrst_source as (
    insert into public.memories(vault_id,life_stage,prompt_key,prompt_text,body,share_to_family_feed)
      values(current_setting('qa.memory_vault')::uuid,'mid','rollback_qa','QA','Harmless rollback-only memory',true)
      returning id
  ) select id into strict m from pgrst_source;
  perform set_config('qa.memory_id',m::text,true);
  update public.memories set body='Edited harmless rollback-only memory' where id=m returning id into strict updated;
  if updated<>m then raise exception 'Owner update failed'; end if;
  insert into public.memories(vault_id,life_stage,prompt_key,prompt_text,body)
    values(current_setting('qa.memory_vault')::uuid,'mid','rollback_sibling','QA','Sibling QA') returning id into strict sibling;
  perform set_config('qa.memory_sibling',sibling::text,true);
  begin
    insert into public.memories(vault_id,life_stage,prompt_key,prompt_text,body)
      values(current_setting('qa.memory_other_vault')::uuid,'mid','rollback_forbidden','QA','Must fail') returning id into m;
    raise exception 'Foreign vault write was permitted';
  exception when insufficient_privilege then null; end;
end $$;

do $$ declare m uuid; begin
  perform set_config('request.jwt.claim.sub',current_setting('qa.memory_viewer'),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.memory_viewer'),'role','authenticated')::text,true);
  if (select count(*) from public.memories where id=current_setting('qa.memory_id')::uuid)<>1 then
    raise exception 'Family read failed'; end if;
  begin
    insert into public.memories(vault_id,life_stage,prompt_key,prompt_text,body)
      values(current_setting('qa.memory_vault')::uuid,'mid','rollback_viewer','QA','Must fail') returning id into m;
    raise exception 'Viewer write was permitted';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
insert into content_safety.restrictions(target_kind,target_id)
  values('memory',current_setting('qa.memory_id')::uuid);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.memories where id=current_setting('qa.memory_id')::uuid) then
    raise exception 'Hidden memory is readable'; end if;
  if (select count(*) from public.memories where id=current_setting('qa.memory_sibling')::uuid)<>1 then
    raise exception 'Hiding affected sibling'; end if;
end $$;

reset role;
delete from content_safety.restrictions
  where target_kind='memory' and target_id=current_setting('qa.memory_id')::uuid;
set local role authenticated;
do $$ begin
  if (select count(*) from public.memories where id=current_setting('qa.memory_id')::uuid)<>1 then
    raise exception 'Restore failed'; end if;
  perform set_config('request.jwt.claim.sub',current_setting('qa.memory_outsider'),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.memory_outsider'),'role','authenticated')::text,true);
  if exists(select 1 from public.memories where id=current_setting('qa.memory_id')::uuid) then
    raise exception 'Outsider could read memory'; end if;
end $$;

reset role;
insert into content_safety.restrictions(target_kind,target_id)
  values('member',current_setting('qa.memory_owner')::uuid);
set local role authenticated;
do $$ declare m uuid; begin
  perform set_config('request.jwt.claim.sub',current_setting('qa.memory_owner'),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('qa.memory_owner'),'role','authenticated')::text,true);
  begin
    insert into public.memories(vault_id,life_stage,prompt_key,prompt_text,body)
      values(current_setting('qa.memory_vault')::uuid,'mid','rollback_suspended','QA','Must fail') returning id into m;
    raise exception 'Suspended write was permitted';
  exception when insufficient_privilege then
    if sqlerrm<>'SAFETY_ACCOUNT_RESTRICTED' then raise; end if;
  end;
end $$;

reset role;
rollback;
select 'Rollback-only owner insert/update, family read, foreign/viewer write denial, exact hide/restore, outsider read denial and suspension checks passed' as result;

-- Run only with approval. All generated fixtures roll back; no Auth, media or billing writes.
begin;
set local statement_timeout = '15s';
set local lock_timeout = '3s';
do $$
declare
  v_family uuid := gen_random_uuid();
  v_other_family uuid := gen_random_uuid();
  v_owner uuid := gen_random_uuid();
  v_member uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_user uuid;
  v_name text;
begin
  insert into public.family_groups(id, name, created_by) values
    (v_family, 'Rename QA', v_owner), (v_other_family, 'Unchanged QA', v_outsider);
  insert into public.family_members(family_id, user_id, role) values
    (v_family, v_owner, 'owner'), (v_family, v_member, 'member'),
    (v_other_family, v_outsider, 'owner');

  foreach v_user in array array[v_owner, v_member] loop
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub',v_user,'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.rename_family(v_family, '  Updated QA  ');
    execute 'reset role';
    if (select name from public.family_groups where id=v_family) <> 'Updated QA' then
      raise exception 'QA rename did not persist the trimmed name';
    end if;
  end loop;
  if (select created_by from public.family_groups where id=v_family) <> v_owner
     or (select role from public.family_members where family_id=v_family and user_id=v_member) <> 'member'
     or (select role from public.family_members where family_id=v_family and user_id=v_owner) <> 'owner' then
    raise exception 'QA ownership or membership changed';
  end if;

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  execute 'set local role authenticated';
  begin
    perform public.rename_family(v_other_family, 'Forbidden');
    raise exception 'QA cross-family rename unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  foreach v_name in array array[null::text, '', '   ', repeat('x',101)] loop
    begin
      perform public.rename_family(v_family, v_name);
      raise exception 'QA invalid name unexpectedly succeeded';
    exception when invalid_parameter_value then null;
    end;
  end loop;
  execute 'reset role';

  foreach v_user in array array[v_outsider, null::uuid] loop
    perform set_config('request.jwt.claim.sub', coalesce(v_user::text,''), true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub',v_user,'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.rename_family(v_family, 'Forbidden');
      raise exception 'QA outsider or missing identity unexpectedly succeeded';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;

  delete from public.family_members where family_id=v_family and user_id=v_member;
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',v_member,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.rename_family(v_family, 'Forbidden');
    raise exception 'QA former member unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  if has_function_privilege('anon','public.rename_family(uuid,text)','execute')
     or not has_function_privilege('authenticated','public.rename_family(uuid,text)','execute') then
    raise exception 'QA unexpected RPC grants';
  end if;
  if (select name from public.family_groups where id=v_family) <> 'Updated QA'
     or (select name from public.family_groups where id=v_other_family) <> 'Unchanged QA' then
    raise exception 'QA denied operation changed a name';
  end if;
end;
$$;
rollback;
select 'passed; generated fixtures rolled back' as family_name_verification;

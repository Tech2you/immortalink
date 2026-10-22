-- No real user content is read. All fixture/report/alert/audit writes roll back.
begin;
do $$ declare v_report uuid:=gen_random_uuid(); begin
  insert into public.content_reports(id,target_kind,target_id,reason,details,status)
    values(v_report,'legacy_memory',gen_random_uuid(),'other','Disposable rollback-only review test','open');
  perform set_config('qa.review_report_id',v_report::text,true);
end $$;
set local role service_role;
do $$ declare v_report uuid:=current_setting('qa.review_report_id')::uuid; snapshot jsonb; decision jsonb; begin
  snapshot:=public.preview_content_report(v_report,'QA rollback test');
  if snapshot->>'available'<>'false' or jsonb_array_length(snapshot->'media')<>0 then raise exception 'preview scope failed'; end if;
  decision:=public.review_content_report_checked(v_report,'dismiss','QA rollback test','Disposable test only',snapshot->>'revision');
  if decision->>'status'<>'dismissed' then raise exception 'decision failed'; end if;
  if (select count(*) from content_safety.preview_access where report_id=v_report)<>1 then raise exception 'audit failed'; end if;
end $$;
set local role authenticated;
do $$ begin
  begin
    perform public.preview_content_report(current_setting('qa.review_report_id')::uuid,'Unauthorized app user');
    raise exception 'client access was not denied';
  exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  begin
    perform public.preview_content_report(current_setting('qa.review_report_id')::uuid,'Anonymous');
    raise exception 'anonymous access was not denied';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'operator preview, audit, decision, client denial and rollback passed' as result,
  (select count(*) from public.content_reports)::int as reports,
  (select count(*) from content_safety.preview_access)::int as preview_audits,
  (select count(*) from public.family_groups)::int as families,
  (select count(*) from public.legacy_memories)::int as legacy_memories,
  (select count(*) from storage.objects)::int as objects,
  (select count(*) from auth.users)::int as users;

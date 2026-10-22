create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- The scheduler credential never goes to app clients or migration output.
do $$ declare token text; begin
  if exists(select 1 from vault.secrets where name='content_report_alert_worker_token') then
    raise exception 'ALERT_WORKER_SECRET_ALREADY_EXISTS';
  end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  perform vault.create_secret(token,'content_report_alert_worker_token','Private content-report alert scheduler');
  update content_safety.alert_config set worker_token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') where singleton;
end $$;

create function content_safety.dispatch_report_alert()
returns bigint language plpgsql security definer set search_path='' as $$
declare token text; request_id bigint;
begin
  if not exists(select 1 from content_safety.alert_config where singleton and enabled
    and (attempts_today<daily_attempt_limit or budget_day<(now() at time zone 'UTC')::date)) then return null; end if;
  if not exists(select 1 from content_safety.report_alerts where
    (state='pending' and next_attempt_at<=now()) or (state='sending' and lease_until<now())) then return null; end if;
  select decrypted_secret into token from vault.decrypted_secrets where name='content_report_alert_worker_token';
  if token is null then raise exception 'ALERT_SCHEDULER_NOT_CONFIGURED'; end if;
  select net.http_post(
    url:='https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/send_content_report_alert',
    headers:=jsonb_build_object('Content-Type','application/json','x-report-alert-token',token),
    body:='{}'::jsonb,timeout_milliseconds:=40000
  ) into request_id;
  return request_id;
end;
$$;
revoke all on function content_safety.dispatch_report_alert() from public,anon,authenticated;
grant execute on function content_safety.dispatch_report_alert() to service_role;
select cron.schedule('content-report-alerts','* * * * *','select content_safety.dispatch_report_alert()');
-- Remains disabled until the sending-only Resend key and deployed worker pass QA.

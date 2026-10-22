-- Read-only operator diagnostics. No report text, media or credentials leave here.
create function public.content_report_alert_health()
returns jsonb language sql stable security definer set search_path='' as $$
  with config as (
    select enabled,daily_attempt_limit,
      case when budget_day=(now() at time zone 'UTC')::date then attempts_today else 0 end as attempts_today
    from content_safety.alert_config where singleton
  ), queue as (
    select count(*) filter(where state='pending') as pending,
      count(*) filter(where state='sending') as sending,
      count(*) filter(where state='failed') as failed,
      count(*) filter(where state='sent') as accepted,
      min(created_at) filter(where state in ('pending','sending','failed')) as oldest_unsent
    from content_safety.report_alerts
  ), scheduler as (
    select exists(select 1 from cron.job where jobname='content-report-alerts' and active) as active,
      (select max(start_time) from cron.job_run_details where status='succeeded'
        and jobid in (select jobid from cron.job where jobname='content-report-alerts')) as last_success
  )
  select jsonb_build_object(
    'enabled',c.enabled,'scheduler_active',s.active,'last_scheduler_success',s.last_success,
    'attempts_today',c.attempts_today,'daily_attempt_limit',c.daily_attempt_limit,
    'pending',q.pending,'sending',q.sending,'failed',q.failed,'provider_accepted',q.accepted,
    'oldest_unsent',q.oldest_unsent,
    'open_reports',(select count(*) from public.content_reports where status in ('open','reviewing')),
    'needs_attention',not c.enabled or not s.active or s.last_success is null
      or s.last_success<now()-interval '5 minutes' or q.failed>0
      or coalesce(q.oldest_unsent<now()-interval '10 minutes',false)
      or (c.attempts_today>=c.daily_attempt_limit and q.pending+q.sending>0),
    'failed_references',coalesce((select jsonb_agg(f) from (
      select report_id,result_code,attempts from content_safety.report_alerts
      where state='failed' order by created_at limit 20) f),'[]'::jsonb)
  ) from config c cross join queue q cross join scheduler s;
$$;
revoke all on function public.content_report_alert_health() from public,anon,authenticated;
grant execute on function public.content_report_alert_health() to service_role;

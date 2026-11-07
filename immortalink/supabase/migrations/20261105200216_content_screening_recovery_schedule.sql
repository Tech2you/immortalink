-- Recovery only. The existing dispatchers check their database switches,
-- eligible work and bounded budgets before making any network request.
-- No credential, user content, recipient or provider key is stored in cron.
-- Activation remains separate; this migration does not enable checking.
select cron.schedule(
  'content-screening-recovery',
  '* * * * *',
  $job$
    select public.dispatch_content_screening();
    select public.dispatch_screening_delivery('email');
    select public.dispatch_screening_delivery('push');
  $job$
);

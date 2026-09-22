-- Preserve existing plan benefits and permissions; change only metered AI usage.
-- Fail on schema drift rather than silently leaving a cost control unchanged.
do $$
declare
  definition text;
  signature regprocedure;
begin
  signature := 'public.everroot_limits(uuid)'::regprocedure;
  definition := pg_get_functiondef(signature);
  if position('''transcription_seconds_monthly'', 120000' in definition) = 0
     or position('''transcription_seconds_monthly'', 36000' in definition) = 0 then
    raise exception 'Unexpected transcription allowances; review before migrating';
  end if;
  definition := replace(definition,
    '''transcription_seconds_monthly'', 120000',
    '''transcription_seconds_monthly'', 24000');
  definition := replace(definition,
    '''transcription_seconds_monthly'', 36000',
    '''transcription_seconds_monthly'', 7200');
  execute definition;

  foreach signature in array array[
    'public.everroot_consume_ai_usage(uuid,uuid,integer)'::regprocedure,
    'public.everroot_consume_transcription_usage(uuid,uuid,integer)'::regprocedure
  ] loop
    definition := pg_get_functiondef(signature);
    if position('v_plan = ''everroot_family''' in definition) = 0 then
      raise exception 'Unexpected paid-family quota implementation: %', signature;
    end if;
    definition := replace(definition, 'v_plan = ''everroot_family''',
      'v_plan in (''everroot_family'', ''everroot_legacy'')');
    if signature = 'public.everroot_consume_transcription_usage(uuid,uuid,integer)'::regprocedure then
      if position('v_seconds := least(v_seconds, 120);' in definition) = 0 then
        raise exception 'Unexpected transcription duration accounting';
      end if;
      -- Count the full recorded duration, including Legacy five-minute notes.
      definition := replace(definition,
        '  -- Current voice-note UX/server policy caps a single note at 120 seconds.' || chr(10) ||
        '  -- Do not trust clients to report a larger/smaller value as the billing' || chr(10) ||
        '  -- boundary until the DB stores verified audio duration.' || chr(10) ||
        '  v_seconds := least(v_seconds, 120);',
        '  -- Use the full duration supplied by the transcription service.');
      if position('v_seconds := least(v_seconds, 120);' in definition) > 0 then
        raise exception 'Transcription duration replacement did not match';
      end if;
    end if;
    execute definition;
  end loop;
end;
$$;

alter table public.memory_voice_notes
  add column if not exists transcript text;

comment on column public.memory_voice_notes.transcript is
  'Transcribed voice-note text used to rebuild the complete searchable memory context.';

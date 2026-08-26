revoke truncate, references, trigger on public.user_push_tokens
  from authenticated;

revoke all on public.user_push_tokens from anon;

grant select, insert, update, delete on public.user_push_tokens
  to authenticated;

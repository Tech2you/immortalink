-- Dependency readback found only the postgres-owned report-alert dispatcher
-- using these newly enabled HTTP functions. Leave other extension objects alone.
-- Queued HTTP headers contain the worker token and must never be client-readable.
revoke all on table net.http_request_queue,net._http_response from public,anon,authenticated;
revoke execute on function net.http_post(text,jsonb,jsonb,jsonb,integer),
  net.http_get(text,jsonb,jsonb,integer),net.http_delete(text,jsonb,jsonb,integer,jsonb)
  from public,anon,authenticated;

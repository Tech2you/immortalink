const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const buckets = new Set(['vault_photos','memory_photos','legacy_memory_photos','memory_voice','legacy_memory_voice']);
const validPath = (path) => typeof path === 'string' && path.length <= 2048
  && !/[\\\x00-\x1f\x7f]/.test(path) && path.split('/').length >= 3
  && path.split('/').every((part) => part && part !== '.' && part !== '..');
const extension = (path) => path.match(/\.[a-z0-9]{1,12}$/i)?.[0] || '';

export function moveRequest(job) {
  if (!job || !uuid.test(job.id) || !buckets.has(job.bucket) || !validPath(job.source)
    || !validPath(job.destination) || job.source === job.destination
    || job.source.slice(0,job.source.lastIndexOf('/')) !== job.destination.slice(0,job.destination.lastIndexOf('/'))
    || extension(job.source)!==extension(job.destination)
    || !uuid.test(job.destination.split('/').at(-1).replace(/\.[a-z0-9]{1,12}$/i,''))) throw new Error('Invalid retirement job.');
  return { bucketId:job.bucket,sourceKey:job.source,destinationKey:job.destination };
}

// Fixed jobs and DB readback make retries safe after an ambiguous API response.
// Bounds keep an operator request short; remaining work stays in the DB queue.
export async function retireReportMedia(request, reportId, { maximum = 4 } = {}) {
  if (!uuid.test(reportId)) throw new Error('Invalid report reference.');
  const params = { p_report_id:reportId };
  const attempted = new Set();
  for (let index=0; index<Math.min(maximum,4); index++) {
    const job = await request('/rest/v1/rpc/next_content_media_retirement',params);
    if (!job || attempted.has(job.id)) break;
    const body = moveRequest(job);
    attempted.add(job.id);
    try { await request('/storage/v1/object/move',body); }
    catch { /* Read the durable state, never infer failure or expose provider data. */ }
  }
  return request('/rest/v1/rpc/content_report_media_status',params);
}

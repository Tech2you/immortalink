import { createServer } from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { parseCommand } from './review_content_reports.mjs';
import { retireReportMedia } from './retire_report_media.mjs';

const project = 'vbzyvaylfdhwowdbodmk';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const revision = /^[0-9a-f]{32}$/;
const ttl = 30 * 60 * 1000;
const maxMedia = 25 * 1024 * 1024;
const safe = (message, status = 400) => Object.assign(new Error(message), { safe: true, status });
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length
  && timingSafeEqual(Buffer.from(a), Buffer.from(b));

export async function readBounded(stream, maximum) {
  const chunks = []; let size = 0;
  for await (const chunk of stream) {
    size += chunk.length;
    if (size > maximum) throw safe('Response exceeds the review limit.', 413);
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

export function storagePath(media) {
  const buckets = new Set(['avatars','vault_photos','legacy_avatars','memory_photos',
    'legacy_memory_photos','memory_voice','legacy_memory_voice']);
  if (!buckets.has(media.bucket) || typeof media.path !== 'string' || media.path.length > 2048
    || /[\\\x00-\x1f\x7f]/.test(media.path)
    || media.path.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw safe('Invalid attachment reference.');
  }
  return `/storage/v1/object/authenticated/${encodeURIComponent(media.bucket)}/${media.path.split('/').map(encodeURIComponent).join('/')}`;
}

export function mediaType(bytes, kind) {
  if (kind === 'image') {
    if (bytes.subarray(0, 3).equals(Buffer.from([255,216,255]))) return 'image/jpeg';
    if (bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) return 'image/png';
    if (bytes.toString('ascii',0,4) === 'RIFF' && bytes.toString('ascii',8,12) === 'WEBP') return 'image/webp';
  }
  if (kind === 'audio') {
    if (bytes.toString('ascii',4,8) === 'ftyp') return 'audio/mp4';
    if (bytes.toString('ascii',0,4) === 'RIFF' && bytes.toString('ascii',8,12) === 'WAVE') return 'audio/wav';
    if (bytes.toString('ascii',0,4) === 'OggS') return 'audio/ogg';
    if (bytes.toString('ascii',0,3) === 'ID3' || (bytes[0] === 255 && (bytes[1] & 224) === 224)) return 'audio/mpeg';
  }
  throw safe('This media format is not supported by the restricted preview.', 415);
}

export function publicCase(snapshot) {
  return { report: snapshot.report, available: snapshot.available, fields: snapshot.fields,
    revision: snapshot.revision, scopeNote: snapshot.scopeNote,
    media: snapshot.media.map(({ id, kind }) => ({ id, kind })) };
}

export function makeBackend(key, fetchImpl = fetch) {
  async function send(path, body, maximum) {
    const response = await fetchImpl(`https://${project}.supabase.co${path}`, {
      method: body === undefined ? 'GET' : 'POST', redirect: 'error',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
    });
    const bytes = await readBounded(response.body, maximum);
    if (!response.ok) {
      // Map known codes only; never relay upstream text, credentials or private data.
      let code; try { code = JSON.parse(bytes.toString()).message; } catch { /* fixed fallback */ }
      if (code === 'SAFETY_CASE_CHANGED') throw safe('Content or report changed. Reopen the case before proceeding.', 409);
      if (code === 'SAFETY_REPORT_NOT_FOUND') throw safe('Report not found.', 404);
      if (code === 'SAFETY_PREVIEW_REQUIRED') throw safe('Reopen this case before taking an action.', 409);
      if (code === 'SAFETY_MEDIA_PREVIEW_REQUIRED') throw safe('Open every attached image before approving this version.', 409);
      if (code === 'SCREENING_REVIEW_DISABLED') throw safe('Automatic-check review is disabled. No decision recorded.', 409);
      if (code === 'SAFETY_MEDIA_RETIREMENT_PENDING') throw safe('The item is still hidden. Finish retiring its old media links before restoring it.', 409);
      throw safe(`Review service unavailable (HTTP ${response.status}). No action confirmed.`, 502);
    }
    return bytes;
  }
  return {
    request: async (path, body) => {
      const data = await send(path, body, 1024 * 1024);
      return data.length ? JSON.parse(data.toString()) : null;
    },
    download: (item) => send(storagePath(item), undefined, maxMedia),
  };
}

export async function startReviewServer({ backend, reviewer, port = 0, now = Date.now, screeningReview = false }) {
  if (!reviewer?.trim() || reviewer.length > 200) throw safe('A reviewer name is required.');
  reviewer = reviewer.trim();
  const entryKey = randomBytes(32).toString('hex');
  const cookieKey = `heiro_review_${randomBytes(8).toString('hex')}`;
  const session = randomBytes(32).toString('hex');
  const csrf = randomBytes(32).toString('hex');
  let authenticated = false; let used = false; const expires = now() + ttl; let origin; let inFlight = 0;
  const assets = new Map(await Promise.all(['index.html','review.js','screening-review.js','review.css'].map(async (file) => [
    file === 'index.html' ? '/' : `/${file}`,
    { bytes: await readFile(new URL(`./content-review/${file}`, import.meta.url)),
      type: file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'text/javascript' : 'text/css' },
  ])));
  const server = createServer(async (req, res) => {
    let counted = false;
    res.setHeader('Cache-Control','no-store, max-age=0');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('X-Frame-Options','DENY');
    res.setHeader('Cross-Origin-Resource-Policy','same-origin');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src blob:; media-src blob:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    const json = (value, status = 200) => { res.writeHead(status, {'Content-Type':'application/json'}); res.end(JSON.stringify(value)); };
    try {
      if (req.headers.host !== new URL(origin).host || !['127.0.0.1','::ffff:127.0.0.1'].includes(req.socket.remoteAddress)) throw safe('Forbidden.',403);
      if (req.headers['sec-fetch-site'] && !['same-origin','none'].includes(req.headers['sec-fetch-site'])) throw safe('Forbidden.',403);
      const asset = assets.get(req.url);
      if (req.method === 'GET' && asset) {
        res.writeHead(200, {'Content-Type':`${asset.type}; charset=utf-8`}); res.end(asset.bytes); return;
      }
      if (req.method !== 'POST' || req.headers.origin !== origin
        || req.headers['content-type'] !== 'application/json') throw safe('Forbidden.',403);
      if (Number(req.headers['content-length']) > 8192) throw safe('Request too large.',413);
      const body = JSON.parse((await readBounded(req,8192)).toString());
      const cookie = req.headers.cookie?.split(';').map((v)=>v.trim()).find((v)=>v.startsWith(`${cookieKey}=`))?.slice(cookieKey.length+1);
      const sessionActive = authenticated && now() < expires && equal(cookie,session);
      if (req.url === '/session') {
        if (body.key) {
          if (used || now() >= expires || !equal(body.key,entryKey)) throw safe('Session unavailable. Open Heiro Safety Review.command for a new session.',403);
          used = true; authenticated = true;
          res.setHeader('Set-Cookie',`${cookieKey}=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=1800`);
        } else if (!sessionActive) {
          throw safe('Session ended. Open Heiro Safety Review.command on your Mac.',401);
        }
        // Reloads may resume the same cookie-bound session, never extend its lifetime.
        json({ csrf, reviewer, expiresInMs:expires-now(), screeningReview:screeningReview === true }); return;
      }
      if (!sessionActive || !equal(req.headers['x-review-csrf'],csrf)) throw safe('Session ended. Open Heiro Safety Review.command on your Mac.',401);
      if (req.url === '/api/logout') { authenticated = false; json({ closed:true }); return; }
      if (inFlight >= 2) throw safe('Another review request is running. Please wait.',429);
      inFlight++; counted = true;
      if (req.url.startsWith('/api/screening/')) {
        if (screeningReview !== true) throw safe('Automatic-check review is disabled.',404);
        if (req.url === '/api/screening/health') {
          json(await backend.request('/rest/v1/rpc/screening_delivery_health',{})); return;
        }
        if (req.url === '/api/screening/queue') {
          if (!['active','held','approved','obsolete'].includes(body.state)) throw safe('Invalid review filter.');
          json(await backend.request('/rest/v1/rpc/screening_review_queue',{p_state:body.state})); return;
        }
        if (!uuid.test(body.id)) throw safe('A valid case reference is required.');
        const params = {p_case:body.id,p_reviewer:reviewer};
        if (req.url === '/api/screening/case') {
          json(publicCase(await backend.request('/rest/v1/rpc/preview_screening_review',params))); return;
        }
        if (!revision.test(body.revision)) throw safe('Reopen this case first.');
        if (req.url === '/api/screening/media') {
          if (!uuid.test(body.mediaId)) throw safe('Invalid attachment.');
          const mediaParams = {...params,p_media_id:body.mediaId,p_revision:body.revision};
          const item = await backend.request('/rest/v1/rpc/preview_screening_review',mediaParams);
          const bytes = await backend.download(item);
          const type = mediaType(bytes,item.kind);
          const after = await backend.request('/rest/v1/rpc/preview_screening_review',mediaParams);
          if (JSON.stringify(item) !== JSON.stringify(after)) throw safe('Attachment changed. Reopen the case.',409);
          await backend.request('/rest/v1/rpc/ack_screening_review_media',mediaParams);
          res.writeHead(200,{'Content-Type':type}); res.end(bytes); return;
        }
        if (req.url === '/api/screening/action') {
          if (body.confirm !== body.id || !['review','hold','approve','obsolete'].includes(body.action)
            || typeof body.notes !== 'string' || !body.notes.trim() || body.notes.length>2000) throw safe('A valid decision, reason and exact case reference are required.');
          json(await backend.request('/rest/v1/rpc/decide_screening_review',{
            ...params,p_action:body.action,p_notes:body.notes.trim(),p_revision:body.revision,
          })); return;
        }
        throw safe('Not found.',404);
      }
      if (req.url === '/api/queue') {
        json(await backend.request('/rest/v1/rpc/content_review_queue',{})); return;
      }
      if (req.url === '/api/health') { json(await backend.request('/rest/v1/rpc/content_report_alert_health',{})); return; }
      if (!uuid.test(body.id)) throw safe('A valid report reference is required.');
      const params = { p_report_id:body.id, p_reviewer:reviewer };
      if (req.url === '/api/case') {
        const result = publicCase(await backend.request('/rest/v1/rpc/preview_content_report',params));
        result.retirement = await backend.request('/rest/v1/rpc/content_report_media_status',{p_report_id:body.id});
        json(result); return;
      }
      if (!revision.test(body.revision)) throw safe('Reopen this case first.');
      if (req.url === '/api/retire') {
        // The browser can name only a report, never a bucket, path or destination.
        const snapshot = await backend.request('/rest/v1/rpc/preview_content_report',params);
        if (snapshot.revision !== body.revision) throw safe('Content changed. Reopen this case first.',409);
        json(await retireReportMedia(backend.request,body.id)); return;
      }
      if (req.url === '/api/media') {
        if (!uuid.test(body.mediaId)) throw safe('Invalid attachment.');
        const item = await backend.request('/rest/v1/rpc/preview_content_report',{
          ...params,p_media_id:body.mediaId,p_revision:body.revision,
        });
        const bytes = await backend.download(item);
        // Recheck metadata after retrieval; do not serve a detached or replaced object.
        const after = await backend.request('/rest/v1/rpc/preview_content_report',{
          ...params,p_media_id:body.mediaId,p_revision:body.revision,
        });
        if (JSON.stringify(item) !== JSON.stringify(after)) throw safe('Attachment changed. Reopen the case.',409);
        res.writeHead(200, {'Content-Type':mediaType(bytes,item.kind)}); res.end(bytes); return;
      }
      if (req.url === '/api/action') {
        const command = parseCommand(['act',body.id,body.action,'--reviewer',reviewer,'--notes',body.notes,'--confirm',body.confirm]);
        const result = await backend.request('/rest/v1/rpc/review_content_report_checked',{
          ...params,p_action:command.action,p_notes:command.notes,p_revision:body.revision,
        });
        if (command.action === 'hide') {
          try { result.retirement = await retireReportMedia(backend.request,body.id); }
          catch { result.retirement = {state:'unconfirmed',hidden:true}; }
        }
        json(result); return;
      }
      throw safe('Not found.',404);
    } catch (error) {
      if (!res.headersSent) json({ error:error.safe ? error.message : 'Request failed. No action confirmed; reopen the case before retrying.' },error.safe ? error.status : 400);
      else res.end();
    } finally { if (counted) inFlight--; }
  });
  server.requestTimeout = 20000; server.headersTimeout = 10000;
  await new Promise((resolve,reject)=> { server.once('error',reject); server.listen(port,'127.0.0.1',resolve); });
  origin = `http://127.0.0.1:${server.address().port}`;
  const shutdown = setTimeout(()=> { server.closeAllConnections(); server.close(); },ttl);
  shutdown.unref();
  server.once('close',()=>clearTimeout(shutdown));
  return { server, url:`${origin}/#${entryKey}`, close:()=>new Promise((resolve)=>server.close(resolve)) };
}

async function main() {
  const flags=process.argv.slice(4);
  if (process.argv.length<4 || process.argv[2] !== '--reviewer'
    || flags.some(flag=>!['--open','--screening-review'].includes(flag)) || new Set(flags).size!==flags.length) {
    console.log('Usage: node scripts/content_review_server.mjs --reviewer NAME [--open] [--screening-review]\nAuthorized local operator only. Automatic-check review requires its separately approved backend deployment.'); return;
  }
  const keys = JSON.parse(execFileSync('supabase',['projects','api-keys','--project-ref',project,'--output','json'],{
    encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:20000,
  }));
  const key = keys.find((item)=>item.name === 'service_role')?.api_key;
  if (!key) throw new Error('Credential unavailable');
  const app = await startReviewServer({ backend:makeBackend(key), reviewer:process.argv[3],screeningReview:flags.includes('--screening-review') });
  console.log(`Private review console (30-minute session): ${app.url}\nDo not share this link. Press Control-C to stop.`);
  if (flags.includes('--open') && process.platform === 'darwin') {
    try { execFileSync('/usr/bin/open',[app.url],{stdio:'ignore',timeout:10000}); }
    catch { console.log('The browser could not open automatically. Open the private link above on this Mac.'); }
  }
  for (const signal of ['SIGINT','SIGTERM']) process.once(signal,()=> { app.server.closeAllConnections(); app.server.close(); });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(()=> { console.error('Review console could not start. Check your internet connection and authorized Supabase CLI login. No report decision was made.'); process.exitCode=1; });
}

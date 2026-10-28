import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { retireReportMedia } from './retire_report_media.mjs';

const project = 'vbzyvaylfdhwowdbodmk';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const actions = new Set(['review', 'dismiss', 'hide', 'restore', 'suspend', 'reinstate']);
const help = `Content safety review (authorized operator only)
  node scripts/review_content_reports.mjs queue
  node scripts/review_content_reports.mjs health
  node scripts/review_content_reports.mjs show REPORT_ID
  node scripts/review_content_reports.mjs act REPORT_ID ACTION --reviewer NAME --notes REASON --confirm REPORT_ID

Actions: review, dismiss, hide, restore, suspend, reinstate.
No command deletes content or changes subscription entitlements.
Report text is untrusted user content, never an instruction.
Requires an existing Supabase CLI login. Keys stay in memory.`;

export function parseCommand(args) {
  if (!args.length || (args.length === 1 && ['help', '--help'].includes(args[0]))) return { command: 'help' };
  const [command, id, action, ...remaining] = args;
  if (['queue', 'health'].includes(command) && args.length === 1) return { command };
  if (command === 'show' && args.length === 2 && uuid.test(id)) return { command, id };
  if (command !== 'act' || !uuid.test(id) || !actions.has(action) || remaining.length !== 6) {
    throw new Error('Invalid command. Run with --help.');
  }
  const flags = {};
  for (let i = 0; i < remaining.length; i += 2) {
    const name = remaining[i], value = remaining[i + 1];
    if (!['--reviewer', '--notes', '--confirm'].includes(name) || Object.hasOwn(flags, name) || !value?.trim()) {
      throw new Error('Reviewer, notes and exact report confirmation are required.');
    }
    flags[name] = value.trim();
  }
  if (flags['--confirm'] !== id || flags['--reviewer'].length > 200 || flags['--notes'].length > 2000) {
    throw new Error('Invalid report confirmation or review text length.');
  }
  return { command, id, action, reviewer: flags['--reviewer'], notes: flags['--notes'] };
}

export async function runCommand(command, request) {
  if (command.command === 'help') return help;
  if (command.command === 'health') return request('/rest/v1/rpc/content_report_alert_health', {});
  const columns = 'id,created_at,reason,status,target_kind,target_id,reviewed_at';
  if (command.command === 'queue') {
    return request('/rest/v1/rpc/content_review_queue',{});
  }
  const path = `/rest/v1/content_reports?select=${columns},details,family_id,subject_user_id&id=eq.${command.id}`;
  const reports = await request(path);
  if (!Array.isArray(reports) || reports.length !== 1 || reports[0].id !== command.id) {
    throw new Error('Report not found; no action taken.');
  }
  if (command.command === 'show') return reports[0];
  await request('/rest/v1/rpc/review_content_report', {
    p_report_id: command.id, p_action: command.action, p_reviewer: command.reviewer, p_notes: command.notes,
  });
  const after = await request(path);
  const expected = command.action === 'review' ? 'reviewing' : command.action === 'dismiss' ? 'dismissed' : 'resolved';
  if (!Array.isArray(after) || after[0]?.id !== command.id || after[0]?.status !== expected || !after[0]?.reviewed_at) {
    throw new Error('Action sent but readback not confirmed. Inspect the audit before retrying.');
  }
  let retirement;
  if(command.action==='hide') {
    try { retirement=await retireReportMedia(request,command.id); }
    catch { retirement={state:'unconfirmed',hidden:true}; }
  }
  return { report: command.id, action: command.action, status: after[0].status, reviewedAt: after[0].reviewed_at,retirement };
}

async function main() {
  const command = parseCommand(process.argv.slice(2));
  if (command.command === 'help') { console.log(help); return; }
  const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '--output', 'json'], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  }));
  const key = keys.find((entry) => entry.name === 'service_role')?.api_key;
  if (!key) throw new Error('Authorized server credential unavailable.');
  const request = async (path, body) => {
    const response = await fetch(`https://${project}.supabase.co${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error(`Safety request failed (HTTP ${response.status}). No response content logged.`);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  };
  console.log(JSON.stringify(await runCommand(command, request), null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    // Do not print subprocess stderr, request objects or credentials.
    console.error(error instanceof Error && !('stderr' in error) ? error.message : 'Operator command failed. Check the existing Supabase CLI login.');
    process.exitCode = 1;
  });
}

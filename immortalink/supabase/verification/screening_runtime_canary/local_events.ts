// Local diagnostics expose only fixed stage labels, never arbitrary user logs.
const events = new globalThis.EventManager();
for await (const data of events) {
  if (data?.event_type === 'Log') {
    const match = String(data.event?.msg).match(/^CANARY_STAGE ([a-z_]+)\s*$/);
    if (match) console.log(`CANARY_STAGE ${match[1]}`);
  }
}

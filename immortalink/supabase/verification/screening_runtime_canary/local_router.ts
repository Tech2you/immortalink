// Local-only harness. Never deploy or route to a request-controlled service.
const maybeEszip = await Deno.readFile('/bundle/diagnostic.eszip');
Deno.serve(async request => {
  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath: '/local-generated-diagnostic',
      maybeEszip,
      maybeEntrypoint: 'file:///source/index.ts',
      memoryLimitMb: 256,
      workerTimeoutMs: 30000,
      cpuTimeSoftLimitMs: 1800,
      cpuTimeHardLimitMs: 2000,
      noModuleCache: false,
      envVars: [],
      forceCreate: true,
    });
    return await worker.fetch(request);
  } catch {
    return Response.json({ code: 'LOCAL_WORKER_FAILED' }, { status: 503 });
  }
});

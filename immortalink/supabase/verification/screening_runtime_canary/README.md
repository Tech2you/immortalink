# Temporary Generated-Image Diagnostic

Not a production worker, automatic deployment or screening activation. Obtain
explicit approval before a live run. It must not process family files or call AI.

The earlier evidence is in `results-2026-10-24.json`: single JPEGs at three sizes
passed; four large photos per invocation exceeded CPU. The later
`results-bundled-2026-10-24.json` verifies packaged static assets locally and on
the host for the three single-image fixtures. Splitting production work
is implemented and tested locally, but the complete hosted flow is unverified.
Do not retry identical failed batches or raise resource caps to make this
benchmark appear successful.

## Preparation

From the application repository, with the locked local image dependencies present:

```sh
node scripts/content-screening/prepare_runtime_canary.mjs --single-photo --bundled-wasm
```

Omit `--single-photo` only when intentionally testing the original batch. The
generator creates an isolated temporary folder, generated random-noise JPEGs,
exact fixture hashes, checked source copies and a 30-minute expiry. It makes no
network requests and does not deploy. Inspect those sources before deployment.

`--bundled-wasm` copies the pinned module unchanged and one local decoder into
the temporary function, retaining its license/notices in `static_files`. It
does not import the whole npm package with duplicate/unused binaries.
The loader verifies its byte count
and SHA-256 before initialization, shares one initialization per isolate, and
never falls back to a network download. Use `Deno.readFile`, not `Deno.stat`:
the runtime's static-asset filesystem does not support the latter for this asset.
The generated-image hosted run confirms static-file access; it does not verify
the full split worker or all supported/adversarial formats.

This mode requires a running Docker-compatible engine for local CLI bundling.
The runner checks the asset and engine before obtaining project keys and does
not use `--use-api` for static files. Installation of local build tools needs
owner approval; this script does not install or start them. The approved
`heiro-build` Colima profile is installed but stopped after testing. There is no automatic
switch to the historical CDN-loader mode if the engine is absent.

Omitting `--bundled-wasm` retains the old, pinned-CDN diagnostic for deliberate
comparison only. Regenerate old temporary folders: the runner requires an
explicit `binaryPackaging` value and will reject a missing one.

## Local Bundle Check

`run_local.mjs --approved-local-only <generated-local-build-directory>` targets
only the named `colima-heiro-build` Docker context. Prepare fixtures inside the
profile's mounted `/private/tmp/heiro-local-bundle.*` directory. The runner uses
the pinned official runtime image, builds with networking disabled, and mounts
only the produced bundle plus local routing/logging helpers at execution time.
The test server binds a temporary localhost-only port. It uses an in-memory
random test token, never a Supabase credential. One-shot workers enforce 256 MiB
memory and 2-second hard CPU limits; each fixture gets a cold worker.

The runner records numeric outcomes/fixed stages, removes the container, and
removes the temporary test-key fingerprint from fixture configuration. A forcibly
terminated runner needs independent container cleanup. Stop the dedicated Colima
profile after use. Local runtime 1.70.0 is not the hosted runtime version, and
local success alone does not establish hosted performance.

## Approved Hosted Run

Use the exact temporary directory returned by the generator:

```sh
node supabase/verification/screening_runtime_canary/run.mjs --approved-generated-only <temporary-directory>
```

The runner targets only `screening_runtime_canary` in the existing linked project,
checks the ten-function baseline, refuses an occupied diagnostic name, and keeps
gateway JWT verification enabled. It retrieves the operator key without printing
it, pins only its SHA-256 fingerprint in the temporary configuration, and sends
credentials to curl via stdin rather than argv or a credential file. It does not
rotate or change any shared credential. Public app keys cannot run the handler.

Rejection controls run before image uploads. An unexpected HTTP result stops
further fixtures. Removal and existing-function comparisons run on success or
handled failure. An unsuccessful deletion/readback is a failure, not a clean
result. If the process is forcibly terminated, independently check/remove the
temporary function before continuing. Do not remove or redeploy other functions.

Read `diagnostic-result.json` in the temporary folder. For lifecycle CPU evidence,
query only its `diagnosticId` and narrow UTC interval in Supabase function logs.
Logs contain fixed stage labels only; responses contain codes and numeric metrics,
not images, credentials or arbitrary exception text. Preserve sanitized results
in this directory, never keys or temporary reviewer/session URLs.

Earlier hosted results used a fixed, integrity-verified public WASM download.
The later bundled run passes single-image packaging; the complete split flow,
cold-start compute and transfer budgets, concurrency, unsupported formats, adversarial limits, classifier quality
and the publication path remain separate gates. Bundling avoids a loader's
per-start CDN fetch; it does not make hosting or deployment transfer free.
Fixture processing time excludes upload time and is not a CPU measurement.

The runner tests use fake CLI, Docker and curl executables only; running them never
deploys, obtains real credentials or contacts a service:

```sh
node --test scripts/content-screening/bundled_normalizer.test.mjs scripts/content-screening/runtime_canary_runner.test.mjs
```

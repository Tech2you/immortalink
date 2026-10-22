import { strict as assert } from "node:assert";
import { DeletionOperations, recentPasswordSession, runDeletion } from "./deletion_workflow.ts";

function fixture() {
  const calls: string[] = [];
  const ops: DeletionOperations = {
    claim: async () => { calls.push("claim"); return "preserving"; },
    files: async function* () {
      yield { bucket_id: "vault_photos", source_path: "old/shared", target_path: "new/shared" };
      yield { bucket_id: "vault_photos", source_path: "old/private", target_path: null };
    },
    copyReady: async () => false,
    copy: async (f) => { calls.push(`copy:${f.source_path}`); },
    finalizeData: async () => { calls.push("finalize"); },
    remove: async (f) => { calls.push(`remove:${f.source_path}`); },
    storageClean: async () => { calls.push("clean"); return true; },
    deleteAuth: async () => { calls.push("auth"); },
    finish: async () => { calls.push("finish"); },
    release: async () => { calls.push("release"); },
  };
  return { ops, calls };
}
Deno.test("shared copy precedes atomic data cleanup and auth is last", async () => {
  const {ops,calls}=fixture();
  assert.equal(await runDeletion(ops,100,()=>0),true);
  assert.deepEqual(calls,["claim","copy:old/shared","finalize","remove:old/shared","remove:old/private","clean","auth","finish","release"]);
});
Deno.test("copy failure cannot remove any metadata, original file or account",async()=>{
  const {ops,calls}=fixture();
  ops.copy=async()=>{throw new Error("storage offline");};
  await assert.rejects(()=>runDeletion(ops,100,()=>0));
  assert.deepEqual(calls,["claim","release"]);
});
Deno.test("resume reuses validated copies, and cleanup retries do not rerun metadata deletion",async()=>{
  const {ops,calls}=fixture();
  ops.copyReady=async()=>true;
  ops.remove=async()=>{throw new Error("remove failed");};
  await assert.rejects(()=>runDeletion(ops,100,()=>0));
  assert.deepEqual(calls,["claim","finalize","release"]);
  calls.length=0;
  ops.claim=async()=>"cleanup";
  ops.remove=async()=>{calls.push("remove");};
  assert.equal(await runDeletion(ops,100,()=>0),true);
  assert.deepEqual(calls,["remove","remove","clean","auth","finish","release"]);
});
Deno.test("timeout and leftover storage never report completion or delete auth",async()=>{
  const {ops,calls}=fixture();
  assert.equal(await runDeletion(ops,0,()=>0),false);
  assert.deepEqual(calls,["claim","release"]);
  calls.length=0;
  ops.storageClean=async()=>false;
  await assert.rejects(()=>runDeletion(ops,100,()=>0),/CLEANUP_INCOMPLETE/);
  assert.equal(calls.includes("auth"),false);
});
Deno.test("failed claim never releases another worker's lease",async()=>{
  const {ops,calls}=fixture();
  ops.claim=async()=>{throw new Error("busy");};
  await assert.rejects(()=>runDeletion(ops,100,()=>0));
  assert.deepEqual(calls,[]);
});
Deno.test("only recent password AMR on a verified session allows deletion",()=>{
  const session_id="00000000-0000-4000-8000-000000000001";
  const jwt=(amr:unknown)=>`e30.${btoa(JSON.stringify({session_id,amr}))}.verified-elsewhere`;
  assert.equal(recentPasswordSession(jwt([{method:"password",timestamp:1000}]),1000000),session_id);
  for(const amr of [undefined,[],[{method:"token_refresh",timestamp:1000}],
    [{method:"password",timestamp:1}],[{method:"password",timestamp:2000}]]){
    assert.equal(recentPasswordSession(jwt(amr),1000000),null);
  }
  assert.equal(recentPasswordSession("malformed"),null);
});

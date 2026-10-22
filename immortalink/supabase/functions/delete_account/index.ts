import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { DeletionFile, recentPasswordSession, runDeletion } from "./deletion_workflow.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, "Content-Type": "application/json" },
});

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Use POST" });
  let step = "authenticate";
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const header = req.headers.get("authorization") || "";
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: header } },
    });
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) return json(401, { error: "Invalid or missing session." });
    const userId = data.user.id;
    const sessionId = recentPasswordSession(header.replace(/^Bearer\s+/i, ""));
    const rpc = async (name: string, args: Record<string, unknown>) => {
      step = name;
      const result = await admin.rpc(name, args);
      if (result.error) throw result.error;
      return result.data;
    };
    if (!sessionId || !await rpc("account_deletion_session_current", { p_user_id: userId, p_session_id: sessionId })) {
      return json(403, { code: "RECENT_PASSWORD_REQUIRED", error: "Confirm your password again before deleting your account." });
    }
    const lease = crypto.randomUUID();
    const args = { p_user_id: userId, p_lease_token: lease };
    const complete = await runDeletion({
      claim: async () => await rpc("claim_account_deletion", args),
      files: async function* () {
        for (let offset = 0; ; offset += 100) {
          const result = await admin.from("account_deletion_files")
            .select("bucket_id,source_path,target_path,keep_source").eq("user_id", userId)
            .order("bucket_id").order("source_path").range(offset, offset + 99);
          if (result.error) throw result.error;
          for (const file of result.data as DeletionFile[]) yield file;
          if (result.data.length < 100) break;
        }
      },
      copyReady: async (file) => await rpc("account_deletion_copy_ready", {
        p_user_id: userId, p_bucket: file.bucket_id, p_source: file.source_path, p_original: file.keep_source ?? false,
      }) === true,
      copy: async (file) => {
        const storage = admin.storage.from(file.bucket_id);
        const ready = await rpc("account_deletion_copy_ready", {
          p_user_id: userId, p_bucket: file.bucket_id, p_source: file.source_path,
        });
        if (!ready) {
          step = "copy_shared_media";
          const result = await storage.copy(file.source_path, file.target_path!);
          if (result.error) throw result.error;
        }
        if (file.keep_source) {
          // Fixed family-avatar URLs must keep their path. The durable copy
          // survives an interruption between removing and re-creating the source.
          step = "rehome_family_avatar";
          const removed = await storage.remove([file.source_path]);
          if (removed.error) throw removed.error;
          const copied = await storage.copy(file.target_path!, file.source_path);
          if (copied.error) throw copied.error;
        }
      },
      finalizeData: async () => { await rpc("finalize_account_deletion_data", args); },
      remove: async (file) => {
        step = "remove_private_media";
        const result = await admin.storage.from(file.bucket_id).remove([file.keep_source ? file.target_path! : file.source_path]);
        if (result.error) throw result.error;
      },
      storageClean: async () => await rpc("account_deletion_storage_clean", args) === true,
      deleteAuth: async () => {
        step = "delete_auth_user";
        const result = await admin.auth.admin.deleteUser(userId);
        if (result.error) throw result.error;
      },
      finish: async () => {
        const result = await admin.from("account_deletion_jobs").delete().eq("user_id", userId).eq("lease_token", lease);
        if (result.error) throw result.error;
      },
      release: async () => {
        const result = await admin.from("account_deletion_jobs").update({ lease_until: new Date().toISOString() })
          .eq("user_id", userId).eq("lease_token", lease);
        if (result.error) throw result.error;
      },
    }, Date.now() + 25000);
    return complete ? json(200, { ok: true }) : json(409, { ok: false, code: "ACCOUNT_DELETION_PENDING",
      error: "Deletion is in progress. Confirm Delete account again to continue safely." });
  } catch (e) {
    const busy = e && typeof e === "object" && "message" in e && e.message === "ACCOUNT_DELETION_BUSY";
    console.error("Account deletion deferred", { step, reason: busy ? "BUSY" : "PRESERVATION_OR_CLEANUP_FAILED" });
    return json(busy ? 409 : 503, { code: busy ? "ACCOUNT_DELETION_BUSY" : "ACCOUNT_DELETION_RETRY",
      error: busy ? "Deletion is already in progress. Please wait a moment."
        : "Account deletion could not finish safely. Please retry or contact support." });
  }
});

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown) {
  return (value ?? "").toString().trim();
}

function missingRelation(error: any) {
  const message = `${error?.message ?? ""}`;
  return error?.code === "42P01" ||
    message.includes("does not exist") ||
    message.includes("schema cache") ||
    message.includes("Could not find the table");
}

function optionalSchemaError(error: any) {
  return missingRelation(error) || error?.code === "42703";
}

async function optionalDelete(query: PromiseLike<{ error: any }>) {
  const { error } = await query;
  if (error && !missingRelation(error)) throw error;
}

async function optionalProfileDelete(query: PromiseLike<{ error: any }>) {
  const { error } = await query;
  if (error && !optionalSchemaError(error)) throw error;
}

async function optionalSelect(
  query: PromiseLike<{ data: any[] | null; error: any }>,
) {
  const { data, error } = await query;
  if (error && !optionalSchemaError(error)) throw error;
  return (data || []) as any[];
}

async function removeStoragePrefix(admin: any, bucket: string, prefix: string) {
  const files: string[] = [];

  async function walk(path: string) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(path, { limit: 1000 });
    if (error || !data) return;

    for (const item of data) {
      const itemPath = `${path}/${item.name}`.replace(/^\/+/, "");
      if (item.id) {
        files.push(itemPath);
      } else {
        await walk(itemPath);
      }
    }
  }

  await walk(prefix.replace(/\/+$/, ""));

  for (let i = 0; i < files.length; i += 100) {
    await admin.storage.from(bucket).remove(files.slice(i, i + 100));
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Use POST" });

  let step = "start";

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
      return json(500, { error: "Delete account function is not configured." });
    }

    const authHeader =
      req.headers.get("authorization") || req.headers.get("Authorization") || "";

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData?.user) {
      return json(401, { error: "Invalid or missing session." });
    }

    const userId = authData.user.id;

    const runStep = async (label: string, action: () => Promise<void>) => {
      step = label;
      await action();
    };

    const { data: vaultRows, error: vaultError } = await admin
      .from("vaults")
      .select("id, family_id")
      .eq("owner_id", userId);
    if (vaultError && !missingRelation(vaultError)) throw vaultError;

    const vaultIds = (vaultRows || [])
      .map((row: any) => clean(row.id))
      .filter(Boolean);
    const familyRows = await optionalSelect(
      admin.from("family_members").select("family_id, role").eq("user_id", userId),
    );
    const ownerFamilyIds = familyRows
      .filter((row: any) => clean(row.role).toLowerCase() === "owner")
      .map((row: any) => clean(row.family_id))
      .filter(Boolean);
    const accountFamilyIds = [...new Set(ownerFamilyIds)];

    let memoryIds: string[] = [];
    if (vaultIds.length) {
      const { data: memoryRows, error: memoryError } = await admin
        .from("memories")
        .select("id")
        .in("vault_id", vaultIds);
      if (memoryError && !missingRelation(memoryError)) throw memoryError;
      memoryIds = (memoryRows || [])
        .map((row: any) => clean(row.id))
        .filter(Boolean);
    }

    if (vaultIds.length) {
      await runStep("delete account invites", async () => {
        await optionalProfileDelete(
          admin.from("family_invites").delete().eq("created_by", userId),
        );
        await optionalProfileDelete(
          admin.from("family_invites").delete().in("inviter_vault_id", vaultIds),
        );
      });
    } else {
      await runStep("delete account invites", async () => {
        await optionalProfileDelete(
          admin.from("family_invites").delete().eq("created_by", userId),
        );
      });
    }

    for (const vaultId of vaultIds) {
      await runStep("delete vault family links", async () => {
        await optionalDelete(
          admin
            .from("family_relationships")
            .delete()
            .eq("parent_type", "vault")
            .eq("parent_id", vaultId),
        );
        await optionalDelete(
          admin
            .from("family_relationships")
            .delete()
            .eq("child_type", "vault")
            .eq("child_id", vaultId),
        );
      });
    }

    if (accountFamilyIds.length) {
      await runStep("delete owned family tree rows", async () => {
        await optionalDelete(
          admin.from("family_relationships").delete().in("family_id", accountFamilyIds),
        );
        await optionalDelete(
          admin.from("legacy_member_photos").delete().in("family_id", accountFamilyIds),
        );
        await optionalDelete(
          admin.from("legacy_memory_photos").delete().in("family_id", accountFamilyIds),
        );
        await optionalDelete(
          admin
            .from("legacy_memory_voice_notes")
            .delete()
            .in("family_id", accountFamilyIds),
        );
        await optionalDelete(
          admin.from("legacy_memories").delete().in("family_id", accountFamilyIds),
        );
        await optionalDelete(
          admin.from("legacy_family_members").delete().in("family_id", accountFamilyIds),
        );
      });
    }

    if (memoryIds.length) {
      await runStep("delete memory media", async () => {
        await optionalDelete(
          admin.from("memory_voice_notes").delete().in("memory_id", memoryIds),
        );
        await optionalDelete(
          admin.from("memory_photos").delete().in("memory_id", memoryIds),
        );
        await optionalDelete(
          admin.from("memory_chunks").delete().in("memory_id", memoryIds),
        );
      });
    }

    if (vaultIds.length) {
      await runStep("delete vault data", async () => {
        await optionalDelete(
          admin.from("vault_highlight_photos").delete().in("vault_id", vaultIds),
        );
        await optionalDelete(
          admin.from("vault_about_photos").delete().in("vault_id", vaultIds),
        );
        await optionalDelete(
          admin.from("vault_core_voice_note").delete().in("vault_id", vaultIds),
        );
        await optionalDelete(
          admin
            .from("family_feed_hidden_vaults")
            .delete()
            .in("hidden_vault_id", vaultIds),
        );
        await optionalDelete(admin.from("memories").delete().in("vault_id", vaultIds));
        await optionalDelete(admin.from("vaults").delete().in("id", vaultIds));
      });
    }

    await runStep("delete account rows", async () => {
      await optionalDelete(
        admin.from("family_feed_hidden_vaults").delete().eq("user_id", userId),
      );
      await optionalDelete(admin.from("family_members").delete().eq("user_id", userId));
      await optionalProfileDelete(
        admin.from("family_groups").delete().eq("owner_id", userId),
      );
      await optionalProfileDelete(
        admin.from("family_groups").delete().eq("created_by", userId),
      );
      await optionalProfileDelete(admin.from("profiles").delete().eq("id", userId));
      await optionalProfileDelete(
        admin.from("profiles").delete().eq("user_id", userId),
      );
    });

    await optionalDelete(
      admin.from("legacy_member_photos").delete().like("path", `${userId}/%`),
    );
    await optionalDelete(
      admin.from("legacy_memory_photos").delete().like("path", `${userId}/%`),
    );
    await optionalDelete(
      admin.from("legacy_memory_voice_notes").delete().like("path", `${userId}/%`),
    );

    await runStep("delete storage objects", async () => {
      await Promise.all([
        removeStoragePrefix(admin, "avatars", userId),
        removeStoragePrefix(admin, "vault_photos", userId),
        removeStoragePrefix(admin, "memory_photos", userId),
        removeStoragePrefix(admin, "memory_voice", userId),
      ]);
    });

    await runStep("delete auth user", async () => {
      const { error: deleteUserError } = await admin.auth.admin.deleteUser(userId);
      if (deleteUserError) throw deleteUserError;
    });

    return json(200, { ok: true });
  } catch (error) {
    return json(500, {
      error: "Could not delete account.",
      step,
      detail: error?.message ?? `${error}`,
    });
  }
});

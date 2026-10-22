export type DeletionFile = { bucket_id: string; source_path: string; target_path: string | null; keep_source?: boolean };
export interface DeletionOperations {
  claim(): Promise<"preserving" | "cleanup">;
  files(): AsyncIterable<DeletionFile>;
  copyReady(file: DeletionFile): Promise<boolean>;
  copy(file: DeletionFile): Promise<void>;
  finalizeData(): Promise<void>;
  remove(file: DeletionFile): Promise<void>;
  storageClean(): Promise<boolean>;
  deleteAuth(): Promise<void>;
  finish(): Promise<void>;
  release(): Promise<void>;
}

export async function runDeletion(ops: DeletionOperations, deadline: number, now = Date.now): Promise<boolean> {
  const phase = await ops.claim();
  try {
    if (phase === "preserving") {
      for await (const file of ops.files()) {
        if (now() >= deadline) return false;
        if (file.target_path && !await ops.copyReady(file)) await ops.copy(file);
      }
      if (now() >= deadline) return false;
      // Copy validation, reference switching, succession and private-data
      // removal are a single database transaction.
      await ops.finalizeData();
    }
    for await (const file of ops.files()) {
      if (now() >= deadline) return false;
      await ops.remove(file);
    }
    if (now() >= deadline) return false;
    if (!await ops.storageClean()) throw new Error("ACCOUNT_STORAGE_CLEANUP_INCOMPLETE");
    await ops.deleteAuth();
    await ops.finish().catch(() => console.error("Account deletion housekeeping pending"));
    return true;
  } finally {
    await ops.release().catch(() => console.error("Account deletion lease release pending"));
  }
}

export function recentPasswordSession(verifiedJwt: string, now = Date.now()): string | null {
  // Call ONLY after auth.getUser has validated this exact token.
  try {
    if (verifiedJwt.length > 16384) return null;
    const part = verifiedJwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(part.padEnd(Math.ceil(part.length / 4) * 4, "=")));
    if (typeof claims.session_id !== "string" || !/^[0-9a-f-]{36}$/i.test(claims.session_id)) return null;
    const seconds = now / 1000;
    return Array.isArray(claims.amr) && claims.amr.some((entry: { method?: string; timestamp?: number }) =>
        entry.method === "password" && typeof entry.timestamp === "number" &&
        entry.timestamp <= seconds + 60 && entry.timestamp >= seconds - 600)
      ? claims.session_id : null;
  } catch { return null; }
}

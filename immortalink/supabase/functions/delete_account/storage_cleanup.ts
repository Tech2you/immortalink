// Enumerate before deleting so pagination cannot skip objects as offsets shift.
export async function removeStoragePrefix(admin: any, bucket: string, prefix: string) {
  const root = prefix.replace(/^\/+|\/+$/g, "");
  if (!root) throw new Error("Refusing to delete an entire bucket");
  const storage = admin.storage.from(bucket);
  const files: string[] = [];
  async function walk(path: string) {
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await storage.list(path, {
        limit: 1000, offset, sortBy: { column: "name", order: "asc" },
      });
      if (error) throw error;
      if (!Array.isArray(data)) throw new Error("Storage listing unavailable");
      for (const item of data) {
        const name = `${path}/${item.name}`;
        if (item.id) files.push(name);
        else await walk(name);
      }
      if (data.length < 1000) break;
    }
  }
  await walk(root);
  for (let i = 0; i < files.length; i += 100) {
    const { error } = await storage.remove(files.slice(i, i + 100));
    if (error) throw error;
  }
}

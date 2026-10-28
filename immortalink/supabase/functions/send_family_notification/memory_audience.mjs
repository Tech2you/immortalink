const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Never fall back to the caller's SELECT result: authors can read pending items.
export async function memoryAudience(admin, memoryId, actorId) {
  const { data, error } = await admin.rpc('memory_notification_route', {
    p_memory: memoryId,
    p_actor: actorId,
  });
  if (error) throw new Error('Notification eligibility unavailable');
  if (data?.allowed !== true) return null;
  if (!['direct', 'outbox'].includes(data.delivery_mode) ||
      !uuid.test(data.family_id ?? '') || !Array.isArray(data.recipient_ids) ||
      data.recipient_ids.some(id => typeof id !== 'string' || !uuid.test(id) || id === actorId)) {
    throw new Error('Invalid notification audience');
  }
  return { familyId: data.family_id, recipientIds: [...new Set(data.recipient_ids)], mode: data.delivery_mode };
}

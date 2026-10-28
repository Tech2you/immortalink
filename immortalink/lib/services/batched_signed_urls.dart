import 'package:supabase_flutter/supabase_flutter.dart';

/// Fresh, access-checked links for one load; never a cross-user URL cache.
Future<Map<String, String>> batchedSignedUrls(
  SupabaseClient client,
  String bucket,
  Iterable<String> paths,
) async {
  final unique = paths
      .map((path) => path.trim())
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();
  final urls = <String, String>{};
  // Bound both payload size and concurrency for large family trees.
  for (var start = 0; start < unique.length; start += 100) {
    final end = start + 100 < unique.length ? start + 100 : unique.length;
    final batch = unique.sublist(start, end);
    try {
      final signed = await client.storage
          .from(bucket)
          .createSignedUrls(batch, 3600)
          .timeout(const Duration(seconds: 8));
      for (final item in signed) {
        final uri = Uri.tryParse(item.signedUrl);
        // storage_client 2.4.1 turns a missing signedURL into a URL ending in
        // "null". Missing/denied objects must remain absent, not broken links.
        if (batch.contains(item.path) &&
            uri != null &&
            uri.hasAuthority &&
            uri.path.contains('/object/sign/') &&
            (uri.queryParameters['token']?.isNotEmpty ?? false)) {
          urls[item.path] = item.signedUrl;
        }
      }
    } catch (_) {
      // Optional media must not prevent the family data from opening.
    }
  }
  return urls;
}

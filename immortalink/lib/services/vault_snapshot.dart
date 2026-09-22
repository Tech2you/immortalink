import 'dart:convert';
import 'recent_cache.dart';

/// Call only after the existing authorized loaders have completed successfully.
Future<void> cacheVisitedVault({
  required String key,
  required String name,
  required int epoch,
  required List<Map<String, dynamic>> memories,
  required List<Map<String, dynamic>> photos,
  String? avatar,
  String? about,
  String? familyId,
}) => RecentCache.instance.put(
  key,
  utf8.encode(
    jsonEncode({
      'name': name,
      'avatar': avatar,
      'about': about ?? '',
      'memories': memories,
      'photos': photos,
    }),
  ),
  epoch: epoch,
  kind: 'vault',
  title: name,
  familyId: familyId,
);

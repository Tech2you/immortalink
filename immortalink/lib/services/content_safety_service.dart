import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'recent_cache.dart';

class SafetyMember {
  const SafetyMember({
    required this.id,
    required this.name,
    required this.blocked,
    this.familyId,
    this.familyName,
  });

  final String id;
  final String name;
  final bool blocked;
  final String? familyId;
  final String? familyName;

  factory SafetyMember.fromJson(Map<String, dynamic> row) => SafetyMember(
    id: row['member_id'] as String,
    name: row['display_name'] as String,
    blocked: row['blocked'] == true,
    familyId: row['family_id'] as String?,
    familyName: row['family_name'] as String?,
  );
}

class ContentSafetyService {
  ContentSafetyService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _backend => _client ?? Supabase.instance.client;
  static const _timeout = Duration(seconds: 15);

  Future<List<SafetyMember>> members() async {
    final rows = await _backend.rpc('list_safety_members').timeout(_timeout);
    return (rows as List)
        .map(
          (row) => SafetyMember.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> setBlocked(String memberId, bool blocked) async {
    await _backend
        .rpc(
          'set_member_block',
          params: {'p_member_id': memberId, 'p_blocked': blocked},
        )
        .timeout(_timeout);
    // Invalidate offline snapshots and in-flight writes, not family records.
    await RecentCache.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> report({
    required String kind,
    required String targetId,
    required String reason,
    required String details,
    String? familyId,
  }) async {
    await _backend
        .rpc(
          'report_family_content',
          params: {
            'p_kind': kind,
            'p_target_id': targetId,
            'p_reason': reason,
            'p_details': details,
            'p_family_id': familyId,
          },
        )
        .timeout(_timeout);
  }
}

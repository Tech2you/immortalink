import 'package:supabase_flutter/supabase_flutter.dart';

class FamilyLeaveImpact {
  final bool isLastRealMember;
  final bool requiresDestructiveConfirmation;
  final String? message;
  final Map<String, dynamic> treeData;

  const FamilyLeaveImpact({
    required this.isLastRealMember,
    required this.requiresDestructiveConfirmation,
    required this.message,
    required this.treeData,
  });

  factory FamilyLeaveImpact.fromJson(Map<String, dynamic> json) {
    return FamilyLeaveImpact(
      isLastRealMember: json['is_last_real_member'] == true,
      requiresDestructiveConfirmation:
          json['requires_destructive_confirmation'] == true,
      message: json['message']?.toString(),
      treeData: Map<String, dynamic>.from(
        (json['tree_data'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class FamilyLeaveService {
  const FamilyLeaveService(this._client);

  final SupabaseClient _client;

  Future<FamilyLeaveImpact> getLeaveImpact(String familyId) async {
    final result = await _client.rpc(
      'get_family_leave_impact',
      params: {'p_family_id': familyId},
    );

    return FamilyLeaveImpact.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> leaveFamily(
    String familyId, {
    required bool confirmedDestructiveLeave,
  }) async {
    await _client.rpc(
      confirmedDestructiveLeave ? 'leave_family_confirmed' : 'leave_family',
      params: {'p_family_id': familyId},
    );
  }
}

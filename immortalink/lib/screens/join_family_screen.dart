import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'relationship_tree_screen.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  bool _loading = false;

  /// Ensures the signed-in user has a vault row.
  /// This prevents RPCs like join_family_by_invite from failing with "No vault found".
  Future<void> _ensureVaultExistsForUser(User user) async {
    // If they already have a vault, do nothing.
    final existing = await _supabase
        .from('vaults')
        .select('id')
        .eq('owner_id', user.id)
        .maybeSingle();

    if (existing != null) return;

    // Create a minimal vault.
    // NOTE: this assumes vaults.about_me_memory_id is nullable (you already dropped NOT NULL).
    final meta = user.userMetadata;
    final fullName = meta == null ? null : meta['full_name'];
    final fallbackName = (fullName ?? user.email ?? 'My Vault')
        .toString()
        .trim();
    final name = fallbackName.isEmpty ? 'My Vault' : fallbackName;

    await _supabase.from('vaults').insert({
      'owner_id': user.id,
      'name': name,
      'display_name': name,
      // family_id stays null until they join.
    });
  }

  Future<void> _finalizeMemberSlot({
    required String familyId,
    required String userId,
  }) async {
    // Uses your existing RPC that returns inviter_vault_id + slot_key for THIS user
    String slotKey = '';
    try {
      final res = await _supabase.rpc(
        'get_join_context',
        params: {'p_family_id': familyId},
      );

      if (res is List && res.isNotEmpty && res.first is Map) {
        final m = (res.first as Map);
        slotKey = (m['slot_key'] ?? '').toString().trim();
      }
    } catch (_) {
      // ignore, we'll still try to at least set role
    }

    // 1) try UPDATE existing row
    try {
      await _supabase
          .from('family_members')
          .update({
            'role': 'member',
            if (slotKey.isNotEmpty) 'slot_key': slotKey,
          })
          .eq('family_id', familyId)
          .eq('user_id', userId);
    } catch (_) {
      // ignore
    }

    // 2) if row didn't exist (or update did nothing), try INSERT (safe)
    // We don't know your constraints, so keep it minimal and wrapped in try.
    try {
      await _supabase.from('family_members').insert({
        'family_id': familyId,
        'user_id': userId,
        'role': 'member',
        if (slotKey.isNotEmpty) 'slot_key': slotKey,
        // joined_at exists in your select earlier, so it's likely a real column
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // If insert fails due to duplicate constraint, that's fine — update already ran.
    }
  }

  Future<void> _join() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      // ✅ Ensure the joining account has a vault BEFORE calling join RPC.
      await _ensureVaultExistsForUser(user);

      dynamic res;
      try {
        res = await _supabase.rpc(
          'join_family_by_relationship_invite',
          params: {'p_invite_code': code},
        );
      } catch (e) {
        // Compatibility fallback while older deployments are still active.
        final msg = e.toString();
        final missingNewRpc =
            msg.contains('PGRST202') ||
            msg.toLowerCase().contains('could not find the function');
        if (missingNewRpc) {
          res = await _supabase.rpc(
            'join_family_by_invite',
            params: {'p_invite_code': code},
          );
        } else if (msg.contains('P0001') ||
            msg.toLowerCase().contains('no vault')) {
          await _ensureVaultExistsForUser(user);
          res = await _supabase.rpc(
            'join_family_by_relationship_invite',
            params: {'p_invite_code': code},
          );
        } else {
          rethrow;
        }
      }

      final familyId = res?.toString().trim();
      if (familyId == null || familyId.isEmpty) {
        throw Exception('Join failed (no family id returned)');
      }

      // ✅ Critical: ensure THIS viewer gets the invite slot_key + correct role
      await _finalizeMemberSlot(familyId: familyId, userId: user.id);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RelationshipTreeScreen(familyId: familyId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Join failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Family')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste the invite code you received.'),
            const SizedBox(height: 6),
            Text(
              'Joining another family will not remove you from your current family. You can switch between trees from Your Vault.',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.62)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _loading ? null : _join(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _join,
                child: Text(_loading ? 'Joining…' : 'Join'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

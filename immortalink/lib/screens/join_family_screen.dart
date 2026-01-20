import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_tree_screen.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _join() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      // 1) Fetch invite by invite_code (your real schema)
      final invite = await _supabase
          .from('family_invites')
          .select('family_id, slot_key, used_at, expires_at')
          .eq('invite_code', code)
          .maybeSingle();

      if (invite == null) throw Exception('Invite not found');
      if (invite['used_at'] != null) throw Exception('Invite already used');

      final expiresAt = invite['expires_at'];
      if (expiresAt != null) {
        final exp = DateTime.tryParse(expiresAt.toString());
        if (exp != null && DateTime.now().isAfter(exp)) {
          throw Exception('Invite expired');
        }
      }

      final familyId = invite['family_id'] as String?;
      final slotKey = invite['slot_key'] as String?;

      if (familyId == null || familyId.isEmpty) throw Exception('Invite missing family_id');
      if (slotKey == null || slotKey.isEmpty) throw Exception('Invite missing slot_key');

      // 2) Find your vault (MVP assumes 1 vault per user)
      final myVault = await _supabase
          .from('vaults')
          .select('id')
          .eq('owner_id', user.id)
          .maybeSingle();

      if (myVault == null) throw Exception('No vault found for your account');

      // 3) Add to family_members with correct slot placement
      await _supabase.from('family_members').upsert({
        'family_id': familyId,
        'user_id': user.id,
        'role': 'member',
        'slot_key': slotKey,
      }, onConflict: 'family_id,user_id');

      // 4) Link your vault to family
      await _supabase
          .from('vaults')
          .update({'family_id': familyId})
          .eq('id', myVault['id']);

      // 5) Mark invite used
      await _supabase.from('family_invites').update({
        'used_at': DateTime.now().toIso8601String(),
      }).eq('invite_code', code);

      if (!mounted) return;

      // 6) Go to tree
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => FamilyTreeScreen(familyId: familyId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join failed: $e')),
      );
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

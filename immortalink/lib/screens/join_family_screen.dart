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
    final token = _controller.text.trim();
    if (token.isEmpty) return;

    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Not signed in');
      }

      // 1) Fetch invite by token
      final invite = await _supabase
          .from('family_invites')
          .select('family_id, slot_key, used_at')
          .eq('token', token)
          .maybeSingle();

      if (invite == null) throw Exception('Invite not found');
      if (invite['used_at'] != null) throw Exception('Invite already used');

      final familyId = invite['family_id'] as String?;
      final slotKey = invite['slot_key'] as String?;

      if (familyId == null || familyId.isEmpty) {
        throw Exception('Invite missing family_id');
      }
      if (slotKey == null || slotKey.isEmpty) {
        throw Exception('Invite missing slot_key');
      }

      // 2) Find your vault (MVP assumes 1 vault per user)
      final myVault = await _supabase
          .from('vaults')
          .select('id')
          .eq('owner_id', user.id)
          .maybeSingle();

      if (myVault == null) throw Exception('No vault found for your account');

      // 3) Save membership with correct slot placement
      // NOTE: If you don't have slot_key column in family_members yet,
      // run the SQL from Step 2 earlier.
      await _supabase.from('family_members').upsert({
        'family_id': familyId,
        'user_id': user.id,
        'role': 'member',
        'slot_key': slotKey,
      }, onConflict: 'family_id,user_id');

      // 4) Link your vault to the family
      await _supabase
          .from('vaults')
          .update({'family_id': familyId})
          .eq('id', myVault['id']);

      // 5) Mark invite as used
      await _supabase.from('family_invites').update({
        'used_at': DateTime.now().toIso8601String(),
      }).eq('token', token);

      if (!mounted) return;

      // 6) Navigate straight to that family's tree
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FamilyTreeScreen(familyId: familyId),
        ),
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
            const Text(
              'Paste the invite code you received.',
              style: TextStyle(fontSize: 15),
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

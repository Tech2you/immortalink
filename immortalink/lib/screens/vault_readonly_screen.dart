import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';

class VaultReadOnlyScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;

  const VaultReadOnlyScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
  });

  @override
  State<VaultReadOnlyScreen> createState() => _VaultReadOnlyScreenState();
}

class _VaultReadOnlyScreenState extends State<VaultReadOnlyScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _memories = [];
  String _vaultName = '';

  String? _avatarUrl; // signed url
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _vaultName = widget.vaultName;
    _loadAll();
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed =
          await _client.storage.from('avatars').createSignedUrl(path, 60 * 60);
      return '$signed&t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Meta
      final meta = await _client
          .from('vaults')
          .select('avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      final path = (meta?['avatar_path'] as String?)?.trim();
      final dn = (meta?['display_name'] as String?) ??
          (meta?['name'] as String?) ??
          _vaultName;

      String? signed;
      if (path != null && path.isNotEmpty) {
        signed = await _signedAvatarUrl(path);
      }

      // Memories (read only)
      final data = await _client
          .from('memories')
          .select('id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _avatarUrl = signed;
        _displayName = (dn ?? _vaultName).toString();
        _memories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _prettyStage(String s) {
    switch (s) {
      case 'early':
        return 'Early life';
      case 'mid':
        return 'Mid life';
      case 'late':
        return 'Late life';
      default:
        return s;
    }
  }

  Widget _headerCard() {
    final name = (_displayName ?? _vaultName).trim().isEmpty
        ? _vaultName
        : (_displayName ?? _vaultName).trim();

    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.35),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.black.withOpacity(0.06),
            backgroundImage: hasAvatar ? NetworkImage(_avatarUrl!) : null,
            child: !hasAvatar
                ? Icon(
                    Icons.person,
                    color: Colors.black.withOpacity(0.45),
                    size: 28,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'View only',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withOpacity(0.60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(_vaultName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: LogoWatermark(
        opacity: 0.03,
        size: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Load failed: $_error'))
                  : ListView.separated(
                      itemCount: _memories.isEmpty ? 2 : _memories.length + 1,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        if (i == 0) return _headerCard();

                        if (_memories.isEmpty && i == 1) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Center(child: Text('No memories yet.')),
                          );
                        }

                        final m = _memories[i - 1];
                        final stage = (m['life_stage'] ?? '').toString();
                        final prompt = (m['prompt_text'] ?? '').toString();
                        final body = (m['body'] ?? '').toString();

                        return ListTile(
                          tileColor: tileBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Chip(label: Text(_prettyStage(stage))),
                          title: Text(prompt.isEmpty ? '(No prompt)' : prompt),
                          subtitle: Text(
                            body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

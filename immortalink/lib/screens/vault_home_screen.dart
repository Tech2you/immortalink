import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';
import 'create_memory_screen.dart';

class VaultHomeScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;

  const VaultHomeScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
  });

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _memories = [];
  String _vaultName = '';

  // --- Avatar / display meta ---
  String? _avatarUrl; // signed URL for display
  String? _avatarPath; // stored in DB (vaults.avatar_path)
  String? _displayName;
  bool _savingAvatar = false;

  @override
  void initState() {
    super.initState();
    _vaultName = widget.vaultName;

    _loadVaultMeta();
    _loadMemories();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _extFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    return 'png';
  }

  String _contentTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    return 'image/png';
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      // 1 hour signed URL
      final signed =
          await _client.storage.from('avatars').createSignedUrl(path, 60 * 60);

      // cache-bust so Flutter web doesn't keep old image
      return '$signed&t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVaultMeta() async {
    try {
      final res = await _client
          .from('vaults')
          .select('avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      if (!mounted) return;

      final path = res?['avatar_path'] as String?;
      final dn = (res?['display_name'] as String?) ??
          (res?['name'] as String?) ??
          _vaultName;

      String? signedUrl;
      if (path != null && path.trim().isNotEmpty) {
        signedUrl = await _signedAvatarUrl(path.trim());
      }

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
        _displayName = (dn ?? _vaultName).trim().isEmpty ? _vaultName : dn;
      });
    } catch (_) {
      // Silent fail for MVP (doesn't block memories page)
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      setState(() => _savingAvatar = true);

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // IMPORTANT for Flutter Web
      );

      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final ext = _extFromName(file.name);
      final path = '$userId/${widget.vaultId}/avatar.$ext';

      // Upload into PRIVATE bucket "avatars"
      await _client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      // Store PATH in DB (not public URL)
      await _client
          .from('vaults')
          .update({'avatar_path': path}).eq('id', widget.vaultId);

      // Create signed URL for display
      final signedUrl = await _signedAvatarUrl(path);

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
      });

      _toast('Vault photo updated.');
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Widget _vaultAvatarHeader() {
    final name = (_displayName ?? _vaultName).trim().isEmpty
        ? 'Your vault'
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
                  'Add your vault photo\nIt helps family recognize you on the tree',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withOpacity(0.60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _savingAvatar ? null : _pickAndUploadAvatar,
            child: Text(
              _savingAvatar ? 'Uploading…' : (hasAvatar ? 'Change' : 'Add'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _client
          .from('memories')
          .select('id, vault_id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      setState(() {
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

  Future<void> _openAddMemory({String? initialLifeStage}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(
          vaultId: widget.vaultId,
          initialLifeStage: initialLifeStage,
        ),
      ),
    );

    if (saved == true) {
      await _loadMemories();
      _toast('Memory saved.');
    }
  }

  Future<void> _renameVault() async {
    final controller = TextEditingController(text: _vaultName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Vault name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await _client
          .from('vaults')
          .update({'name': newName}).eq('id', widget.vaultId);

      setState(() => _vaultName = newName);

      // If display name wasn't set, keep header aligned
      if ((_displayName == null || _displayName!.trim().isEmpty) && mounted) {
        setState(() => _displayName = newName);
      }

      _toast('Vault renamed.');
    } on PostgrestException catch (e) {
      _toast('Rename failed: ${e.message}');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _editMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();

    final promptController =
        TextEditingController(text: (m['prompt_text'] ?? '').toString());
    final bodyController =
        TextEditingController(text: (m['body'] ?? '').toString());

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Prompt (question)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'prompt_text': promptController.text.trim(),
              'body': bodyController.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final newPromptText = (result['prompt_text'] ?? '').trim();
    final newBody = (result['body'] ?? '').trim();

    if (newPromptText.isEmpty) {
      _toast('Prompt cannot be empty.');
      return;
    }
    if (newBody.isEmpty) {
      _toast('Answer cannot be empty.');
      return;
    }

    try {
      await _client.from('memories').update({
        'prompt_text': newPromptText,
        'body': newBody,
      }).eq('id', memoryId);

      await _loadMemories();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete memory?'),
        content: Text('Delete this memory permanently?\n\n$prompt'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _client.from('memories').delete().eq('id', memoryId);
      await _loadMemories();
      _toast('Memory deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
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

  @override
  Widget build(BuildContext context) {
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(_vaultName),
        actions: [
          IconButton(
            tooltip: 'Rename vault',
            icon: const Icon(Icons.edit),
            onPressed: _renameVault,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadVaultMeta();
              await _loadMemories();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddMemory(initialLifeStage: 'early'),
        child: const Icon(Icons.add),
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
                        if (i == 0) return _vaultAvatarHeader();

                        if (_memories.isEmpty && i == 1) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('No memories yet.'),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _openAddMemory(initialLifeStage: 'early'),
                                    child: const Text('Add your first memory'),
                                  ),
                                ],
                              ),
                            ),
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
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _editMemory(m),
                          trailing: IconButton(
                            tooltip: 'Delete memory',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteMemory(m),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

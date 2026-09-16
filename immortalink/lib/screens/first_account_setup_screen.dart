import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/first_account_setup.dart';
import '../utils/image_upload_optimizer.dart';
import '../utils/media_upload_policy.dart';
import '../widgets/profile_photo_cropper.dart';
import 'create_memory_screen.dart';

enum FirstAccountSetupResult { done, familyTree }

class FirstAccountSetupScreen extends StatefulWidget {
  const FirstAccountSetupScreen({super.key});

  @override
  State<FirstAccountSetupScreen> createState() =>
      _FirstAccountSetupScreenState();
}

class _FirstAccountSetupScreenState extends State<FirstAccountSetupScreen> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  late final String _userId;
  Map<String, dynamic>? _vault;
  String? _avatarUrl;
  String? _error;
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  bool _hasMemory = false;

  @override
  void initState() {
    super.initState();
    _userId = _client.auth.currentUser!.id;
    _step = firstAccountSetupStep(_client.auth.currentUser?.userMetadata);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _checkAccount() {
    if (_client.auth.currentUser?.id != _userId) {
      throw StateError('The signed-in account changed.');
    }
  }

  Future<void> _load() async {
    try {
      _checkAccount();
      final vault = await _client
          .from('vaults')
          .select('id, name, display_name, avatar_path')
          .eq('owner_id', _userId)
          .maybeSingle();
      bool hasMemory = false;
      if (vault != null) {
        final rows = await _client
            .from('memories')
            .select('id')
            .eq('vault_id', vault['id'])
            .limit(1);
        hasMemory = rows.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _vault = vault;
        _hasMemory = hasMemory;
        _name.text = (vault?['display_name'] ?? vault?['name'] ?? '')
            .toString();
        if (vault == null) _step = 0;
        _loading = false;
        _error = null;
      });
      final path = (vault?['avatar_path'] ?? '').toString();
      if (path.isNotEmpty) {
        // An unavailable preview must not block account setup.
        try {
          final url = await _client.storage
              .from('avatars')
              .createSignedUrl(path, 3600);
          if (mounted) setState(() => _avatarUrl = url);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Could not load your setup. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _checkAccount();
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this step. Your saved work is kept. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _go(int step) async {
    _checkAccount();
    await _client.auth.updateUser(
      UserAttributes(data: {firstAccountSetupStepKey: step}),
    );
    if (mounted) setState(() => _step = step);
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.contains('@')) {
      setState(
        () => _error = 'Enter your name, rather than your email address.',
      );
      return;
    }
    await _run(() async {
      // Re-query before inserting, including after a timed-out creation attempt.
      final existing = await _client
          .from('vaults')
          .select('id')
          .eq('owner_id', _userId)
          .maybeSingle();
      final values = {'name': name, 'display_name': name};
      final vault = existing == null
          ? await _client
                .from('vaults')
                .insert(values)
                .select('id, name, display_name, avatar_path')
                .single()
          : await _client
                .from('vaults')
                .update(values)
                .eq('id', existing['id'])
                .eq('owner_id', _userId)
                .select('id, name, display_name, avatar_path')
                .single();
      if (!mounted) return;
      setState(() => _vault = vault);
      await _go(1);
    });
  }

  Future<void> _photo() => _run(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null || !mounted) return;
    final cropped = await cropProfilePhoto(context, bytes);
    if (cropped == null) return;
    final image = await ImageUploadOptimizer.optimize(
      cropped,
      kind: MediaUploadKind.avatarPhoto,
      fileName: 'profile.png',
      contentType: 'image/png',
    );
    _checkAccount();
    final path = '$_userId/${_vault!['id']}/avatar.${image.extension}';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          image.bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: image.contentType,
          ),
        );
    await _client
        .from('vaults')
        .update({'avatar_path': path})
        .eq('id', _vault!['id'])
        .eq('owner_id', _userId);
    if (mounted) setState(() => _vault!['avatar_path'] = path);
    final url = await _client.storage
        .from('avatars')
        .createSignedUrl(path, 3600);
    if (mounted) setState(() => _avatarUrl = url);
  });

  Future<void> _memory() => _run(() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(
          vaultId: _vault!['id'].toString(),
          displayName: _name.text.trim(),
          avatarUrl: _avatarUrl,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    setState(() => _hasMemory = true);
    await _go(3);
  });

  Future<void> _finish(FirstAccountSetupResult result) => _run(() async {
    await _client.auth.updateUser(
      UserAttributes(data: {firstAccountSetupKey: 'complete'}),
    );
    if (mounted) Navigator.of(context).pop(result);
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (_vault?['avatar_path'] ?? '').toString().isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (_step > 0) {
          _run(() => _go(_step - 1));
        } else {
          _finish(FirstAccountSetupResult.done);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Get started'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy
                ? null
                : () => _step > 0
                      ? _run(() => _go(_step - 1))
                      : _finish(FirstAccountSetupResult.done),
          ),
          actions: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _finish(FirstAccountSetupResult.done),
              child: const Text('Skip setup'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SetupStepLayout(
                step: _step,
                busy: _busy,
                error: _error,
                title: const [
                  'Your vault',
                  'Your profile photo',
                  'Your first memory',
                  'Your family tree',
                ][_step],
                children: [
                  if (_step == 0)
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Your name'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_busy) _saveName();
                      },
                    ),
                  if (_step == 1) ...[
                    Center(
                      child: CircleAvatar(
                        radius: 64,
                        foregroundImage: _avatarUrl == null
                            ? null
                            : NetworkImage(_avatarUrl!),
                        onForegroundImageError: _avatarUrl == null
                            ? null
                            : (_, _) {},
                        child: const Icon(Icons.person_outline, size: 56),
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _photo,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(hasPhoto ? 'Change photo' : 'Choose photo'),
                    ),
                  ],
                  if (_step == 2)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _memory,
                      icon: const Icon(Icons.edit_note),
                      label: Text(
                        _hasMemory ? 'Add another memory' : 'Add a memory',
                      ),
                    ),
                  if (_step == 3)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _finish(FirstAccountSetupResult.familyTree),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Add family and share invites'),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_step == 0) {
                              _saveName();
                            } else if (_step == 3) {
                              _finish(FirstAccountSetupResult.done);
                            } else {
                              _run(() => _go(_step + 1));
                            }
                          },
                    child: Text(
                      _step == 3
                          ? 'Go to my vault'
                          : _step == 1 && !hasPhoto || _step == 2 && !_hasMemory
                          ? 'Skip for now'
                          : 'Continue',
                    ),
                  ),
                  if (_error != null)
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Reload saved progress'),
                    ),
                ],
              ),
      ),
    );
  }
}

class SetupStepLayout extends StatelessWidget {
  const SetupStepLayout({
    super.key,
    required this.step,
    required this.title,
    required this.children,
    this.busy = false,
    this.error,
  });
  final int step;
  final String title;
  final List<Widget> children;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${step + 1} of 4',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (step + 1) / 4),
            const SizedBox(height: 28),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            ...children,
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}

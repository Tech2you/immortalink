import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_vault_companion_screen.dart';

class LegacyVaultScreen extends StatefulWidget {
  final String legacyMemberId;
  final String familyId;

  const LegacyVaultScreen({
    super.key,
    required this.legacyMemberId,
    required this.familyId,
  });

  @override
  State<LegacyVaultScreen> createState() => _LegacyVaultScreenState();
}

class _LegacyVaultScreenState extends State<LegacyVaultScreen> {
  final _supabase = Supabase.instance.client;

  static const String _photosBucket = 'vault_photos';

  bool _loading = true;
  bool _savingProfile = false;
  bool _deletingProfile = false;
  bool _uploadingPhoto = false;
  bool _uploadingProfilePhoto = false;
  bool _loadingPhotos = true;
  bool _loadingMemories = true;
  bool _loadingMemoryPhotos = true;
  bool _showExtraDetails = false;

  String? _error;
  String? _photoError;
  String? _memoryError;
  String? _memoryPhotoError;

  Map<String, dynamic>? _row;

  String? _profilePhotoId;
  String? _profilePhotoPath;
  String? _profilePhotoUrl;

  List<Map<String, String>> _photos = [];
  List<Map<String, dynamic>> _memories = [];
  final Map<String, List<Map<String, String>>> _memoryPhotosById = {};

  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _deathYearController = TextEditingController();
  final _aboutController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _birthYearController.dispose();
    _deathYearController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openLegacyAi() async {
    final row = _row;
    if (row == null) {
      _toast('Legacy profile is not loaded yet.');
      return;
    }

    final displayName = _titleFromRow(row);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegacyVaultCompanionScreen(
          legacyMemberId: widget.legacyMemberId,
          familyId: widget.familyId,
          displayName: displayName,
        ),
      ),
    );
  }

  int? _parseYear(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  String _titleFromRow(Map<String, dynamic>? row) {
    final display = (row?['display_name'] ?? '').toString().trim();
    final name = (row?['name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    if (name.isNotEmpty) return name;
    return 'Legacy predecessor';
  }

  String _subtitleFromRow(Map<String, dynamic>? row) {
    final birth = row?['birth_year'];
    final b = birth == null ? '' : birth.toString();
    if (b.isNotEmpty) return 'Born $b';
    return 'Family-owned predecessor profile';
  }

  String _detailsLabel(Map<String, dynamic>? row) {
    final birth = row?['birth_year'];
    final death = row?['death_year'];

    final b = birth == null ? '' : birth.toString();
    final d = death == null ? '' : death.toString();

    if (b.isEmpty && d.isEmpty) return 'No extra details yet';
    if (b.isNotEmpty && d.isEmpty) return 'Birth year: $b';
    if (b.isEmpty && d.isNotEmpty) return 'Death year: $d';
    return 'Birth year: $b   •   Death year: $d';
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

  String _extFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String _contentTypeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  bool _isProfilePhotoPath(String path) {
    final p = path.toLowerCase();
    return p.contains('/profile_picture/');
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    try {
      final signed = await _supabase.storage.from(bucket).createSignedUrl(
            path,
            60 * 60,
          );
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _supabase
          .from('legacy_family_members')
          .select(
            'id, family_id, slot_key, name, display_name, birth_year, death_year, about_me_text, created_by, created_at, updated_at, replaced_by_vault_id',
          )
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .maybeSingle();

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _row = null;
          _error = 'Legacy predecessor not found.';
          _loading = false;
        });
        return;
      }

      final row = Map<String, dynamic>.from(res);
      _row = row;

      _nameController.text = (row['name'] ?? '').toString();
      _displayNameController.text = (row['display_name'] ?? '').toString();
      _birthYearController.text =
          row['birth_year'] == null ? '' : row['birth_year'].toString();
      _deathYearController.text =
          row['death_year'] == null ? '' : row['death_year'].toString();
      _aboutController.text = (row['about_me_text'] ?? '').toString();

      setState(() {
        _loading = false;
      });

      await _loadPhotos();
      await _loadMemories();
      await _loadMemoryPhotos();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
    if (!mounted) return;

    setState(() {
      _loadingPhotos = true;
      _photoError = null;
      _photos = [];
      _profilePhotoId = null;
      _profilePhotoPath = null;
      _profilePhotoUrl = null;
    });

    try {
      final rows = await _supabase
          .from('legacy_member_photos')
          .select('id, path, created_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();
      final items = <Map<String, String>>[];

      String? profileId;
      String? profilePath;
      String? profileUrl;

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        if (id.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_photosBucket, path);
        if (url == null || url.trim().isEmpty) continue;

        if (_isProfilePhotoPath(path)) {
          if (profilePath == null) {
            profileId = id;
            profilePath = path;
            profileUrl = url;
          }
          continue;
        }

        items.add({
          'id': id,
          'path': path,
          'url': url,
        });
      }

      if (!mounted) return;
      setState(() {
        _profilePhotoId = profileId;
        _profilePhotoPath = profilePath;
        _profilePhotoUrl = profileUrl;
        _photos = items;
        _loadingPhotos = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _photoError = e.message;
        _loadingPhotos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoError = e.toString();
        _loadingPhotos = false;
      });
    }
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;

    setState(() {
      _loadingMemories = true;
      _memoryError = null;
      _memories = [];
    });

    try {
      final rows = await _supabase
          .from('legacy_memories')
          .select(
              'id, life_stage, prompt_key, prompt_text, body, created_at, updated_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _memories = (rows as List).cast<Map<String, dynamic>>();
        _loadingMemories = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryError = e.message;
        _loadingMemories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryError = e.toString();
        _loadingMemories = false;
      });
    }
  }

  Future<void> _loadMemoryPhotos() async {
    if (!mounted) return;

    setState(() {
      _loadingMemoryPhotos = true;
      _memoryPhotoError = null;
      _memoryPhotosById.clear();
    });

    try {
      final rows = await _supabase
          .from('legacy_memory_photos')
          .select('id, legacy_memory_id, path, created_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['legacy_memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();

        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_photosBucket, path);
        if (url == null || url.trim().isEmpty) continue;

        _memoryPhotosById.putIfAbsent(memoryId, () => []).add({
          'id': id,
          'path': path,
          'url': url,
        });
      }

      if (!mounted) return;
      setState(() {
        _loadingMemoryPhotos = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryPhotoError = e.message;
        _loadingMemoryPhotos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryPhotoError = e.toString();
        _loadingMemoryPhotos = false;
      });
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      setState(() => _uploadingPhoto = true);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      final ext = _extFromName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/gallery/$ts.$ext';

      await _supabase.storage.from(_photosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase.from('legacy_member_photos').insert({
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });

      await _loadPhotos();
      _toast('Photo added.');
    } catch (e) {
      _toast('Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _uploadOrReplaceProfilePhoto() async {
    try {
      setState(() => _uploadingProfilePhoto = true);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      if (_profilePhotoPath != null && _profilePhotoPath!.trim().isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove([_profilePhotoPath!]);
      }
      if (_profilePhotoId != null && _profilePhotoId!.trim().isNotEmpty) {
        await _supabase
            .from('legacy_member_photos')
            .delete()
            .eq('id', _profilePhotoId!)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      final ext = _extFromName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/profile_picture/$ts.$ext';

      await _supabase.storage.from(_photosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase.from('legacy_member_photos').insert({
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });

      await _loadPhotos();
      _toast('Profile picture updated.');
    } catch (e) {
      _toast('Profile picture upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingProfilePhoto = false);
    }
  }

  Future<void> _deletePhoto(Map<String, String> photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This will permanently delete this photo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final id = (photo['id'] ?? '').trim();
      final path = (photo['path'] ?? '').trim();

      if (path.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove([path]);
      }

      if (id.isNotEmpty) {
        await _supabase
            .from('legacy_member_photos')
            .delete()
            .eq('id', id)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      await _loadPhotos();
      _toast('Photo deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final birthYear = _parseYear(_birthYearController.text);
    final deathYear = _parseYear(_deathYearController.text);
    final about = _aboutController.text.trim();

    if (name.isEmpty) {
      _toast('Name is required.');
      return;
    }

    if (_birthYearController.text.trim().isNotEmpty && birthYear == null) {
      _toast('Birth year must be a valid number.');
      return;
    }

    if (_deathYearController.text.trim().isNotEmpty && deathYear == null) {
      _toast('Death year must be a valid number.');
      return;
    }

    setState(() => _savingProfile = true);

    try {
      await _supabase
          .from('legacy_family_members')
          .update({
            'name': name,
            'display_name': displayName.isEmpty ? null : displayName,
            'birth_year': birthYear,
            'death_year': deathYear,
            'about_me_text': about.isEmpty ? null : about,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _load();
      _toast('Legacy profile saved.');
    } on PostgrestException catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _deleteProfile() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete legacy predecessor?'),
        content: const Text(
          'This removes the family-owned predecessor profile from the tree. Use this if the real person later joins and creates their own vault.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deletingProfile = true);

    try {
      final photoPaths = <String>[
        ..._photos
            .map((p) => (p['path'] ?? '').trim())
            .where((p) => p.isNotEmpty),
        if ((_profilePhotoPath ?? '').trim().isNotEmpty) _profilePhotoPath!.trim(),
      ];

      if (photoPaths.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove(photoPaths);
      }

      await _supabase
          .from('legacy_family_members')
          .delete()
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _deletingProfile = false);
    }
  }

  Future<void> _openAddMemory() async {
    final promptController = TextEditingController();
    final bodyController = TextEditingController();
    String stage = 'mid';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Add memory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: stage,
                  decoration: const InputDecoration(
                    labelText: 'Life stage',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'early', child: Text('Early life')),
                    DropdownMenuItem(value: 'mid', child: Text('Mid life')),
                    DropdownMenuItem(value: 'late', child: Text('Late life')),
                  ],
                  onChanged: (v) {
                    if (v != null) setInner(() => stage = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: promptController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Memory title / prompt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Memory details',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'life_stage': stage,
                  'prompt_text': promptController.text.trim(),
                  'body': bodyController.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final promptText = (result['prompt_text'] ?? '').trim();
    final body = (result['body'] ?? '').trim();
    final lifeStage = (result['life_stage'] ?? 'mid').trim();

    if (promptText.isEmpty) {
      _toast('Memory title is required.');
      return;
    }
    if (body.isEmpty) {
      _toast('Memory details are required.');
      return;
    }

    try {
      await _supabase.from('legacy_memories').insert({
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'life_stage': lifeStage,
        'prompt_key': 'legacy_memory',
        'prompt_text': promptText,
        'body': body,
      });

      await _loadMemories();
      await _loadMemoryPhotos();
      _toast('Memory added.');
    } on PostgrestException catch (e) {
      _toast('Add memory failed: ${e.message}');
    } catch (e) {
      _toast('Add memory failed: $e');
    }
  }

  Future<void> _editMemory(Map<String, dynamic> memory) async {
    final memoryId = (memory['id'] ?? '').toString();
    if (memoryId.isEmpty) return;

    final promptController =
        TextEditingController(text: (memory['prompt_text'] ?? '').toString());
    final bodyController =
        TextEditingController(text: (memory['body'] ?? '').toString());
    String stage = (memory['life_stage'] ?? 'mid').toString();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Edit memory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: stage,
                  decoration: const InputDecoration(
                    labelText: 'Life stage',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'early', child: Text('Early life')),
                    DropdownMenuItem(value: 'mid', child: Text('Mid life')),
                    DropdownMenuItem(value: 'late', child: Text('Late life')),
                  ],
                  onChanged: (v) {
                    if (v != null) setInner(() => stage = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: promptController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Memory title / prompt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Memory details',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'life_stage': stage,
                  'prompt_text': promptController.text.trim(),
                  'body': bodyController.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final promptText = (result['prompt_text'] ?? '').trim();
    final body = (result['body'] ?? '').trim();
    final lifeStage = (result['life_stage'] ?? 'mid').trim();

    if (promptText.isEmpty) {
      _toast('Memory title is required.');
      return;
    }
    if (body.isEmpty) {
      _toast('Memory details are required.');
      return;
    }

    try {
      await _supabase
          .from('legacy_memories')
          .update({
            'life_stage': lifeStage,
            'prompt_text': promptText,
            'body': body,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', memoryId)
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _loadMemories();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> memory) async {
    final memoryId = (memory['id'] ?? '').toString();
    if (memoryId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memory?'),
        content: const Text('This will permanently delete this memory.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final photos = _memoryPhotosById[memoryId] ?? [];
      final paths = photos
          .map((p) => (p['path'] ?? '').trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (paths.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove(paths);
      }

      await _supabase
          .from('legacy_memories')
          .delete()
          .eq('id', memoryId)
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _loadMemories();
      await _loadMemoryPhotos();
      _toast('Memory deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _uploadMemoryPhoto(String memoryId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      final ext = _extFromName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/memories/$memoryId/$ts.$ext';

      await _supabase.storage.from(_photosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase.from('legacy_memory_photos').insert({
        'legacy_memory_id': memoryId,
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });

      await _loadMemoryPhotos();
      _toast('Photo added to memory.');
    } on PostgrestException catch (e) {
      _toast('Add photo failed: ${e.message}');
    } catch (e) {
      _toast('Add photo failed: $e');
    }
  }

  Future<void> _deleteMemoryPhoto(
    String memoryId,
    Map<String, String> photo,
  ) async {
    try {
      final id = (photo['id'] ?? '').trim();
      final path = (photo['path'] ?? '').trim();

      if (path.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove([path]);
      }

      if (id.isNotEmpty) {
        await _supabase
            .from('legacy_memory_photos')
            .delete()
            .eq('id', id)
            .eq('legacy_memory_id', memoryId)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      await _loadMemoryPhotos();
      _toast('Photo deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Widget _fieldCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.45),
      ),
      child: child,
    );
  }

  Widget _headerCard() {
    final title = _titleFromRow(_row);
    final subtitle = _subtitleFromRow(_row);

    return _fieldCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: Container(
              width: 72,
              height: 72,
              color: Colors.black.withOpacity(0.08),
              child: _profilePhotoUrl == null || _profilePhotoUrl!.trim().isEmpty
                  ? Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.black.withOpacity(0.65),
                    )
                  : Image.network(
                      _profilePhotoUrl!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.person,
                        size: 30,
                        color: Colors.black.withOpacity(0.65),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.60),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Family-owned predecessor profile',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _uploadingProfilePhoto
                            ? null
                            : _uploadOrReplaceProfilePhoto,
                        icon: const Icon(Icons.person_outline),
                        label: Text(
                          _uploadingProfilePhoto
                              ? 'Uploading…'
                              : ((_profilePhotoUrl ?? '').trim().isEmpty
                                  ? 'Add profile picture'
                                  : 'Change pfp'),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _openLegacyAi,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Ask (AI)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About them',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _aboutController,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Family notes, memories, personality, stories',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Photos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _uploadingPhoto ? null : _uploadPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_uploadingPhoto ? 'Uploading…' : 'Add photo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingPhotos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_photoError != null)
            Text(
              'Photo load issue: $_photoError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else if (_photos.isEmpty)
            Text(
              'No photos yet. Add a few warm family photos.',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _photos.map((photo) {
                final url = (photo['url'] ?? '').trim();
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 120,
                        height: 120,
                        color: Colors.black.withOpacity(0.05),
                        child: url.isEmpty
                            ? const SizedBox.shrink()
                            : Image.network(
                                url,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: InkWell(
                        onTap: () => _deletePhoto(photo),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black.withOpacity(0.55),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _identityCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _extraDetailsCard() {
    return _fieldCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _showExtraDetails,
          onExpansionChanged: (v) => setState(() => _showExtraDetails = v),
          title: const Text(
            'Extra details',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _detailsLabel(_row),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.55),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _birthYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Birth year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _deathYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Death year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _memoryPhotoStrip(String memoryId) {
    final photos = _memoryPhotosById[memoryId] ?? [];
    final preview = photos.take(4).toList();

    if (_loadingMemoryPhotos) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Loading photos…',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
        ),
      );
    }

    if (_memoryPhotoError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Photo load issue: $_memoryPhotoError',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
        ),
      );
    }

    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _uploadMemoryPhoto(memoryId),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add photo'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: preview.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _uploadMemoryPhoto(memoryId),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withOpacity(0.10)),
                    color: Colors.white.withOpacity(0.35),
                  ),
                  child: Icon(Icons.add, color: Colors.black.withOpacity(0.65)),
                ),
              );
            }

            final p = preview[i - 1];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _deleteMemoryPhoto(memoryId, p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Image.network(
                      p['url'] ?? '',
                      width: 92,
                      height: 66,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black.withOpacity(0.55),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _memoryCard(Map<String, dynamic> m) {
    final memoryId = (m['id'] ?? '').toString();
    final stage = (m['life_stage'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();
    final body = (m['body'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.38),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(label: Text(_prettyStage(stage))),
                const SizedBox(height: 8),
                Text(
                  prompt.isEmpty ? '(No title)' : prompt,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                _memoryPhotoStrip(memoryId),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editMemory(m),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteMemory(m),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memoriesCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Memories',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _openAddMemory,
                  icon: const Icon(Icons.add),
                  label: const Text('Add memory'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingMemories)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_memoryError != null)
            Text(
              'Memory load issue: $_memoryError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else if (_memories.isEmpty)
            Text(
              'No memories yet. Add a story, family memory, or important moment.',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else
            Column(
              children: _memories.map(_memoryCard).toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleFromRow(_row);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: (_loading || _deletingProfile) ? null : _deleteProfile,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.05,
                  child: Image.asset(
                    'assets/images/immortalink_logo.png',
                    width: 520,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : ListView(
                        children: [
                          _headerCard(),
                          const SizedBox(height: 12),
                          _aboutCard(),
                          const SizedBox(height: 12),
                          _photosCard(),
                          const SizedBox(height: 12),
                          _memoriesCard(),
                          const SizedBox(height: 12),
                          _identityCard(),
                          const SizedBox(height: 12),
                          _extraDetailsCard(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: (_savingProfile || _deletingProfile)
                                      ? null
                                      : _deleteProfile,
                                  icon: const Icon(Icons.delete_outline),
                                  label: Text(
                                    _deletingProfile ? 'Deleting…' : 'Delete',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (_savingProfile || _deletingProfile)
                                      ? null
                                      : _saveProfile,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(
                                    _savingProfile ? 'Saving…' : 'Save',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
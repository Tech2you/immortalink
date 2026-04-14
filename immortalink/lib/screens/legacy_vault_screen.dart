import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  Map<String, dynamic>? _row;

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

  String _yearsLabel(Map<String, dynamic>? row) {
    final birth = row?['birth_year'];
    final death = row?['death_year'];

    final b = birth == null ? '' : birth.toString();
    final d = death == null ? '' : death.toString();

    if (b.isEmpty && d.isEmpty) return 'Legacy family profile';
    if (b.isNotEmpty && d.isEmpty) return 'Born $b';
    if (b.isEmpty && d.isNotEmpty) return 'Died $d';
    return '$b – $d';
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
              'id, family_id, slot_key, name, display_name, birth_year, death_year, about_me_text, created_by, created_at, updated_at, replaced_by_vault_id')
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

  Future<void> _save() async {
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

    setState(() => _saving = true);

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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete legacy predecessor?'),
        content: const Text(
          'This removes the family-owned predecessor profile from the tree. '
          'Use this if the real person later joins and creates their own vault.',
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

    setState(() => _deleting = true);

    try {
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
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _fieldCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.50),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleFromRow(_row);
    final subtitle = _yearsLabel(_row);

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
            onPressed: (_loading || _deleting) ? null : _delete,
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
                          _fieldCard(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      Colors.black.withOpacity(0.08),
                                  child: Icon(
                                    Icons.history_edu_outlined,
                                    color: Colors.black.withOpacity(0.65),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          color:
                                              Colors.black.withOpacity(0.60),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Family-owned predecessor profile',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              Colors.black.withOpacity(0.55),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _fieldCard(
                            child: Column(
                              children: [
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
                                const SizedBox(height: 12),
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
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _aboutController,
                                  minLines: 6,
                                  maxLines: 12,
                                  decoration: const InputDecoration(
                                    labelText: 'About me / family notes',
                                    border: OutlineInputBorder(),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: (_saving || _deleting)
                                      ? null
                                      : _delete,
                                  icon: const Icon(Icons.delete_outline),
                                  label: Text(
                                    _deleting ? 'Deleting…' : 'Delete',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (_saving || _deleting)
                                      ? null
                                      : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(_saving ? 'Saving…' : 'Save'),
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
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/recent_cache.dart';
import 'relationship_tree_screen.dart';
import 'vault_home_screen.dart';

class RecentlyViewedScreen extends StatefulWidget {
  const RecentlyViewedScreen({super.key, this.cache});
  final RecentCache? cache;
  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  late final _cache = widget.cache ?? RecentCache.instance;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _cache.addListener(_changed);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _entries = [];
      });
    }
    _load();
  }

  Future<void> _load() async {
    final epoch = _cache.generation;
    final entries = await _cache.list();
    for (final entry in entries.where((e) => e['kind'] == 'vault')) {
      final bytes = await _cache.read(entry['key'] as String);
      if (bytes == null) continue;
      try {
        final snapshot = jsonDecode(utf8.decode(bytes)) as Map;
        entry['title'] = snapshot['name'] ?? 'Family vault';
        entry['avatar'] = snapshot['avatar'];
      } catch (_) {
        /* A damaged copy must not block the directory. */
      }
    }
    if (mounted && epoch == _cache.generation) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear offline storage?'),
        content: const Text(
          'Only downloaded copies on this device will be removed. Your saved memories will stay online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _cache.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cache.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _entries.where((e) => e['kind'] == 'photo').toList();
    final trees = _entries.where((e) => e['kind'] == 'tree').toList();
    final vaults = _entries.where((e) => e['kind'] == 'vault').toList();
    final bytes = _entries.fold<int>(0, (n, e) => n + (e['size'] as int));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline'),
        actions: [
          IconButton(
            tooltip: 'Clear offline storage',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'Recently viewed',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB / 250 MB - Up to 6 hours',
                      ),
                      const SizedBox(height: 16),
                      if (photos.isEmpty && trees.isEmpty && vaults.isEmpty)
                        const Text('No recent offline copies.'),
                      if (vaults.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Vaults',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      for (final vault in vaults)
                        ListTile(
                          leading: CircleAvatar(
                            child: vault['avatar'] == null
                                ? const Icon(Icons.person_outline)
                                : ClipOval(
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: OfflinePhoto(
                                        cache: _cache,
                                        cacheKey: _cache.photoKey(
                                          vault['avatar'],
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                          ),
                          title: Text(vault['title'] ?? 'Family vault'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => VaultHomeScreen(
                                vaultId: (vault['key'] as String)
                                    .split(':')
                                    .last,
                                vaultName: vault['title'] ?? 'Family vault',
                                cache: _cache,
                                cachedOnly: true,
                                snapshotKey: vault['key'],
                              ),
                            ),
                          ).then((_) => _load()),
                        ),
                      if (trees.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Family trees',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      for (final tree in trees)
                        ListTile(
                          leading: const Icon(Icons.account_tree_outlined),
                          title: Text(tree['title'] ?? 'Family tree'),
                          subtitle: Text(
                            'Saved ${MaterialLocalizations.of(context).formatShortDate(DateTime.fromMillisecondsSinceEpoch(tree['saved']).toLocal())}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RelationshipTreeScreen(
                                familyId: tree['familyId'],
                                cachedOnly: true,
                                cache: _cache,
                              ),
                            ),
                          ).then((_) => _load()),
                        ),
                      const SizedBox(height: 12),
                      if (photos.isNotEmpty)
                        const Text(
                          'Media',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid.builder(
                    itemCount: photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemBuilder: (context, index) {
                      final key = photos[index]['key'] as String;
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Offline')),
                              body: Center(
                                child: InteractiveViewer(
                                  child: OfflinePhoto(
                                    cacheKey: key,
                                    cache: _cache,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: OfflinePhoto(
                          key: ValueKey('$key:${_cache.generation}'),
                          cacheKey: key,
                          cache: _cache,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class OfflinePhoto extends StatefulWidget {
  const OfflinePhoto({
    super.key,
    required this.cacheKey,
    this.fit = BoxFit.contain,
    this.cache,
  });
  final String cacheKey;
  final BoxFit fit;
  final RecentCache? cache;
  @override
  State<OfflinePhoto> createState() => _OfflinePhotoState();
}

class _OfflinePhotoState extends State<OfflinePhoto> {
  late final _cache = widget.cache ?? RecentCache.instance;
  Uint8List? _bytes;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _cache.addListener(_clear);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  Future<void> _load() async {
    final epoch = _cache.generation;
    final bytes = await _cache.read(widget.cacheKey);
    if (mounted && epoch == _cache.generation) setState(() => _bytes = bytes);
  }

  void _clear() {
    if (mounted) setState(() => _bytes = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cache.removeListener(_clear);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _bytes == null
      ? const Center(child: Icon(Icons.image_not_supported_outlined))
      : Image.memory(
          _bytes!,
          fit: widget.fit,
          cacheWidth: widget.fit == BoxFit.cover ? 400 : null,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.image_not_supported_outlined),
        );
}

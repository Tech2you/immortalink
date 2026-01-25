import 'package:flutter/material.dart';

typedef VoiceNote = Map<String, dynamic>;

class MemoryVoiceNotesSheet {
  static Future<void> open({
    required BuildContext context,
    required String title,
    required List<VoiceNote> notes,
    required void Function(VoiceNote note) onPlay,
    required Future<void> Function(VoiceNote note) onRename,
    required Future<void> Function(VoiceNote note) onDelete,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        title: title,
        notes: notes,
        onPlay: onPlay,
        onRename: onRename,
        onDelete: onDelete,
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final List<VoiceNote> notes;
  final void Function(VoiceNote note) onPlay;
  final Future<void> Function(VoiceNote note) onRename;
  final Future<void> Function(VoiceNote note) onDelete;

  const _Sheet({
    required this.title,
    required this.notes,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  String _safeTitle(VoiceNote n) {
    final t = (n['title'] ?? n['name'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;

    final path = (n['path'] ?? n['storage_path'] ?? '').toString().trim();
    if (path.isNotEmpty) {
      final file = path.split('/').last;
      return file.isNotEmpty ? file : 'Recorded voice note';
    }

    return 'Recorded voice note';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black26)],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),
              const Divider(height: 1),

              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No voice notes yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final n = notes[i];
                      return _VoiceRow(
                        title: _safeTitle(n),
                        onPlay: () => onPlay(n),
                        onRename: () => onRename(n),
                        onDelete: () => onDelete(n),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  final String title;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _VoiceRow({
    required this.title,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Play',
            onPressed: onPlay,
            icon: const Icon(Icons.play_circle_outline),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Rename',
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

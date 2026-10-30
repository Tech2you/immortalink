import 'package:flutter/material.dart';
import 'heiro_surface.dart';

Future<String?> showMemoryCreationMenu(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => HeiroSurface(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'New memory',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              for (final entry in const [
                ('text', Icons.edit_note, 'Write a memory'),
                ('photo', Icons.photo_library_outlined, 'Add photos'),
                ('voice', Icons.mic_none, 'Record voice'),
              ])
                ListTile(
                  leading: Icon(entry.$2, color: heiroBlue),
                  title: Text(entry.$3),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, entry.$1),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../widgets/heiro_surface.dart';

class HeiroSettingsEntry {
  const HeiroSettingsEntry({
    required this.group,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
  final String group;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// Presentation only: the existing account actions remain owned by the caller.
class HeiroSettingsScreen extends StatelessWidget {
  const HeiroSettingsScreen({super.key, required this.entries});
  final List<HeiroSettingsEntry> entries;

  @override
  Widget build(BuildContext context) => HeiroSurface(
    child: Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i == 0 || entries[i].group != entries[i - 1].group)
                  Container(
                    color: heiroIce,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Text(
                      entries[i].group,
                      style: const TextStyle(color: Color(0xFF526D7C)),
                    ),
                  ),
                ListTile(
                  leading: Icon(
                    entries[i].icon,
                    color: entries[i].destructive
                        ? Colors.red.shade700
                        : heiroBlue,
                  ),
                  title: Text(entries[i].label),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  minVerticalPadding: 14,
                  onTap: entries[i].onTap,
                ),
                const Divider(height: 1, indent: 60, endIndent: 20),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

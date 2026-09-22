import 'package:flutter/material.dart';

enum FamilyTreeAction { recenter, refresh, leave, photo, name }

class FamilyTreeSettingsMenu extends StatelessWidget {
  const FamilyTreeSettingsMenu({
    super.key,
    required this.onSelected,
    required this.canRecenter,
    required this.canLeave,
    required this.canEditName,
    this.enabled = true,
  });

  final ValueChanged<FamilyTreeAction> onSelected;
  final bool canRecenter;
  final bool canLeave;
  final bool canEditName;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopupMenuButton<FamilyTreeAction>(
    tooltip: 'Family tree settings',
    icon: const Icon(Icons.settings_outlined),
    enabled: enabled,
    onSelected: onSelected,
    itemBuilder: (_) => [
      _item(
        FamilyTreeAction.recenter,
        Icons.my_location,
        'Recenter',
        canRecenter,
      ),
      _item(FamilyTreeAction.refresh, Icons.refresh, 'Refresh', true),
      _item(
        FamilyTreeAction.photo,
        Icons.photo_library_outlined,
        'Change family photo',
        canLeave,
      ),
      _item(
        FamilyTreeAction.name,
        Icons.edit_outlined,
        'Change family name',
        canEditName,
      ),
      const PopupMenuDivider(),
      _item(
        FamilyTreeAction.leave,
        Icons.group_remove_outlined,
        'Leave family',
        canLeave,
      ),
    ],
  );

  PopupMenuItem<FamilyTreeAction> _item(
    FamilyTreeAction action,
    IconData icon,
    String label,
    bool enabled,
  ) => PopupMenuItem(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

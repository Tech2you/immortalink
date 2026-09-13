import 'package:flutter/material.dart';

class VaultSectionPicker extends StatelessWidget {
  const VaultSectionPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<int>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      ),
      segments: const [
        ButtonSegment(
          value: 0,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Memories', maxLines: 1, softWrap: false),
          ),
        ),
        ButtonSegment(
          value: 1,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('About', maxLines: 1, softWrap: false),
          ),
        ),
        ButtonSegment(
          value: 2,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Media', maxLines: 1, softWrap: false),
          ),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    ),
  );
}

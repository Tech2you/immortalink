import 'package:flutter/material.dart';

class CompanionPromptButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  const CompanionPromptButton({super.key, required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(text, softWrap: true),
    ),
  );
}

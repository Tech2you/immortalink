import 'package:flutter/material.dart';
import '../utils/everroot_upgrade_prompt.dart';

/// Displays used profiles against the server's pooled family allowance.
class LegacyProfileUsage extends StatelessWidget {
  const LegacyProfileUsage({
    super.key,
    required this.limits,
    required this.usage,
    this.onViewPlans,
  });

  final Map<String, dynamic> limits;
  final Map<String, dynamic> usage;
  final VoidCallback? onViewPlans;

  @override
  Widget build(BuildContext context) {
    final cap = limits['legacy_people'];
    final count = usage['legacy_people'];
    final known = cap is int && cap > 0 && count is int && count >= 0;
    final full = known && count >= cap;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Legacy profiles', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(known ? '$count of $cap used' : 'Profile usage is unavailable.'),
        if (known) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (count / cap).clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              color: full ? theme.colorScheme.error : null,
              semanticsLabel: 'Legacy profiles: $count of $cap used',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            full
                ? legacyProfileLimitMessage(cap)
                : 'One allowance for the whole family. Invited members are separate.',
            style: theme.textTheme.bodySmall,
          ),
          if (full && onViewPlans != null)
            TextButton(
              onPressed: onViewPlans,
              child: const Text('View contribution options'),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text('What counts as a legacy profile?'),
            children: const [
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Profiles for relatives without an account count toward this allowance, including unnamed relatives and retained profiles later linked to a member. Real members themselves are not counted.\n\nWithout paid contributions, your family has 50 slots. Each active Family contribution provides 100 and each Legacy contribution provides 500. Paid contributions add together and replace the free allowance. Renewals maintain the allowance; changing a plan replaces that contribution.\n\nIf a contribution ends or moves, existing profiles stay available. New profiles pause while the family is at or above its allowance. Photos and recordings still use shared storage.',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

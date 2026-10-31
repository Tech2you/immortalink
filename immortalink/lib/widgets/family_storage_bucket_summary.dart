import 'package:flutter/material.dart';
import '../services/apple_subscription_service.dart';
import '../utils/everroot_upgrade_prompt.dart';

String formatFamilyCapacity(num bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb && bytes % gb == 0) return '${bytes ~/ gb} GB';
  return formatEverRootStorageBytes(bytes);
}

class FamilyStorageBucketSummary extends StatelessWidget {
  const FamilyStorageBucketSummary({
    super.key,
    required this.service,
    required this.limits,
    required this.usage,
  });
  final AppleSubscriptionService service;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capacity = (limits['storage_bytes'] as num?) ?? 0;
    final used = (usage['storage_bytes'] as num?) ?? 0;
    final ratio = capacity <= 0
        ? 0.0
        : (used / capacity).clamp(0, 1).toDouble();
    final count = service.contributorCount;
    final people = service.contributors;
    final full = capacity > 0 && used >= capacity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your family’s shared space',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                formatFamilyCapacity(capacity),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${formatEverRootStorageBytes(used)} used · ${count == 1 ? '1 contributor' : '$count contributors'}',
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: ratio, minHeight: 8),
              ),
              const SizedBox(height: 16),
              Text(
                full
                    ? 'Your storage is full. Existing memories stay available. Add a contribution or free up space to upload or invite more people.'
                    : 'Every active contribution adds space for everyone in this family.',
              ),
            ],
          ),
        ),
        if (service.includedAccessBytes case final num included
            when included > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Your existing beta access keeps at least ${formatFamilyCapacity(included)} available${service.includedAccessUntil == null ? '.' : ' until ${MaterialLocalizations.of(context).formatMediumDate(service.includedAccessUntil!.toLocal())}.'}',
          ),
        ],
        const SizedBox(height: 20),
        if (people.isNotEmpty) ...[
          Text(
            'Contributions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...people
              .take(3)
              .map(
                (person) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          person['is_you'] == true
                              ? 'You'
                              : person['name']?.toString() ?? 'Family member',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${formatFamilyCapacity((person['storage_bytes'] as num?) ?? 0)}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
          if (count > 3)
            Text(
              'Plus ${count - 3} more ${count - 3 == 1 ? 'contributor' : 'contributors'}',
            ),
          const SizedBox(height: 16),
        ],
        if (limits['ai_responses_monthly'] is num &&
            limits['transcription_seconds_monthly'] is num) ...[
          Text(
            'This month’s shared allowance',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${usage['ai_responses_monthly'] ?? 0} of ${limits['ai_responses_monthly']} AI answers used',
          ),
          Text(
            '${((usage['transcription_seconds_monthly'] as num?) ?? 0) ~/ 60} of ${(limits['transcription_seconds_monthly'] as num) ~/ 60} transcription minutes used',
          ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('What do these allowances mean?'),
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'AI answers are replies when you ask Heiro questions about your family memories. Transcription turns recorded speech into text: 120 minutes covers two hours of audio. These are separate monthly allowances shared by your family.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Storage stays available while each contribution is active. Renewals keep that space available; they do not add extra storage each month.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

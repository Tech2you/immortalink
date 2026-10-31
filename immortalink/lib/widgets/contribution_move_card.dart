import 'package:flutter/material.dart';
import '../services/apple_subscription_service.dart';

class ContributionMoveCard extends StatelessWidget {
  final AppleSubscriptionService service;
  const ContributionMoveCard({super.key, required this.service});

  Future<void> _review(BuildContext context) async {
    final preview = await service.previewContributionMove();
    if (preview == null || !context.mounted) return;
    final local = MaterialLocalizations.of(context);
    final until = preview.paidUntil.toLocal();
    final date =
        '${local.formatMediumDate(until)}, ${local.formatTimeOfDay(TimeOfDay.fromDateTime(until))}';
    final gb = preview.storageBytes / (1024 * 1024 * 1024);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move your contribution here?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This family receives ${gb.toStringAsFixed(0)} GB of shared storage, paid through $date.',
              ),
              const SizedBox(height: 16),
              Text(
                'This month, your contribution brings up to ${preview.aiRemaining} remaining AI answers and ${(preview.transcriptionSecondsRemaining / 60).toStringAsFixed(1)} transcription minutes.',
              ),
              const SizedBox(height: 12),
              const Text(
                'A share of this month’s usage moves with the contribution. Moving does not restart your allowance.',
              ),
              if (preview.previousFamilyExists) ...[
                const SizedBox(height: 16),
                const Text(
                  'Your previous family loses this contribution. Its memories remain, but new uploads may pause if its storage is full.',
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'No new payment. Your Apple price, renewal settings and paid end date stay the same. Photos, profiles and family permissions do not move.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move contribution'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await service.confirmContributionMove(preview);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      if (!service.canMoveContribution && service.moveError == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Already supporting another family?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your existing contribution and move its remaining benefits here without buying again.',
              ),
              if (service.moveError case final String error)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      service.canMoveContribution && !service.purchasePending
                      ? () => _review(context)
                      : null,
                  child: Text(
                    service.purchasePending
                        ? 'Checking contribution…'
                        : 'Move my contribution',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';
import '../utils/public_error.dart';

class VaultLoadFailure extends StatelessWidget {
  const VaultLoadFailure({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onRecentlyViewed,
  });
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onRecentlyViewed;

  @override
  Widget build(BuildContext context) {
    final connection = isConnectionFailure(error);
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                connection ? Icons.cloud_off_outlined : Icons.error_outline,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                connection ? 'Unable to connect' : 'Unable to load your vault',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(publicErrorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRecentlyViewed,
                icon: const Icon(Icons.offline_pin_outlined),
                label: const Text('Recently viewed'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

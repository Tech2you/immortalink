import 'package:flutter/material.dart';

class AccountDeletionDataNotice extends StatelessWidget {
  const AccountDeletionDataNotice({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'This permanently deletes your account, personal vault, personal memories, media, and your family-tree links. This cannot be undone.',
      ),
      SizedBox(height: 12),
      Text(
        'Contributions you added to shared legacy profiles, such as a grandparent\'s photos, stories, and recordings, stay with the remaining family members. Creating a legacy profile does not make it part of your personal vault.',
      ),
    ],
  );
}

class AccountDeletionBillingNotice extends StatefulWidget {
  const AccountDeletionBillingNotice({
    super.key,
    required this.onManage,
    this.leavingFamily = false,
    this.checkActiveSubscription,
  });
  final Future<void> Function() onManage;
  final bool leavingFamily;
  final Future<bool> Function()? checkActiveSubscription;

  @override
  State<AccountDeletionBillingNotice> createState() => _BillingNoticeState();
}

class _BillingNoticeState extends State<AccountDeletionBillingNotice> {
  bool _opening = false;
  bool _hasActiveSubscription = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSubscription();
  }

  Future<void> _checkSubscription() async {
    final check = widget.checkActiveSubscription;
    if (check == null) return;
    try {
      final active = await check().timeout(const Duration(seconds: 12));
      if (mounted) setState(() => _hasActiveSubscription = active);
    } catch (_) {
      // A failed or empty check must never imply Apple billing has stopped.
    }
  }

  Future<void> _manage() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.onManage();
      await _checkSubscription();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open Apple subscriptions. Cancel in iPhone Settings > your name > Subscriptions using the Apple Account that paid.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _hasActiveSubscription
            ? 'You have an active Apple subscription'
            : 'Apple billing does not stop automatically',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${widget.leavingFamily ? 'Leaving this family' : 'Deleting your account'} does not cancel an Apple subscription. If renewal is still on, Apple will continue charging you.',
      ),
      const SizedBox(height: 8),
      Text(
        'Cancel with Apple now. If you ${widget.leavingFamily ? 'leave' : 'delete'} first, you must cancel later in iPhone Settings > your name > Subscriptions, using the Apple Account that paid.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _opening ? null : _manage,
        icon: const Icon(Icons.open_in_new),
        label: Text(
          _opening ? 'Opening Apple...' : 'Cancel subscription with Apple',
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Confirm cancellation on Apple\'s screen. Opening it alone does not cancel. If you already cancelled, paid coverage can remain active until its end date.',
      ),
      if (_error != null) Text(_error!),
    ],
  );
}

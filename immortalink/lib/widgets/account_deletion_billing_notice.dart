import 'package:flutter/material.dart';

class AccountDeletionBillingNotice extends StatefulWidget {
  const AccountDeletionBillingNotice({super.key, required this.onManage});
  final Future<void> Function() onManage;

  @override
  State<AccountDeletionBillingNotice> createState() => _BillingNoticeState();
}

class _BillingNoticeState extends State<AccountDeletionBillingNotice> {
  bool _opening = false;
  String? _error;

  Future<void> _manage() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.onManage();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Open iPhone Settings > your name > Subscriptions to cancel.',
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
      const Text(
        'Apple subscriptions',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Deleting your account does not cancel an Apple subscription. If you subscribed, cancel it with Apple first to stop future renewals. Opening subscription settings alone does not cancel it.',
      ),
      TextButton.icon(
        onPressed: _opening ? null : _manage,
        icon: const Icon(Icons.open_in_new),
        label: Text(
          _opening ? 'Opening Apple...' : 'Manage Apple subscription',
        ),
      ),
      if (_error != null) Text(_error!),
    ],
  );
}

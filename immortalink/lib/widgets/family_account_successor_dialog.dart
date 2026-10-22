import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/public_error.dart';

Future<void> showFamilyAccountSuccessor(BuildContext context, String familyId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SuccessorDialog(familyId: familyId),
  );
}

class _SuccessorDialog extends StatefulWidget {
  const _SuccessorDialog({required this.familyId});
  final String familyId;

  @override
  State<_SuccessorDialog> createState() => _SuccessorDialogState();
}

class _SuccessorDialogState extends State<_SuccessorDialog> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _members = [];
  String? _selected;
  String? _error;
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = Map<String, dynamic>.from(
        await _client.rpc(
              'get_family_account_successors',
              params: {'p_family_id': widget.familyId},
            )
            as Map,
      );
      if (!mounted) return;
      final members = (data['members'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final selected = data['selected_user_id']?.toString();
      setState(() {
        _members = members;
        _selected = members.any((m) => m['user_id'] == selected)
            ? selected
            : null;
        _loading = false;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = publicErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'set_family_account_successor',
        params: {
          'p_family_id': widget.familyId,
          'p_successor_user_id': _selected,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = publicErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Account successor'),
    content: SizedBox(
      width: double.maxFinite,
      child: _loading
          ? const Center(heightFactor: 2, child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Family administration after you delete your account. Your Apple subscription stays yours.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selected ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Successor'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Automatic'),
                      ),
                      for (final member in _members)
                        DropdownMenuItem(
                          value: member['user_id'] as String,
                          child: Text(
                            member['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(
                            () => _selected = value == '' ? null : value,
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!),
                  ],
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_loaded || _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save'),
      ),
    ],
  );
}

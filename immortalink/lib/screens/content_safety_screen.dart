import 'package:flutter/material.dart';

import '../services/content_safety_service.dart';
import '../widgets/content_safety_actions.dart';
import '../widgets/legal_links.dart';

class ContentSafetyScreen extends StatefulWidget {
  const ContentSafetyScreen({super.key, this.service});
  final ContentSafetyService? service;

  @override
  State<ContentSafetyScreen> createState() => _ContentSafetyScreenState();
}

class _ContentSafetyScreenState extends State<ContentSafetyScreen> {
  late final _service = widget.service ?? ContentSafetyService();
  List<SafetyMember> _members = [];
  bool _loading = true;
  bool _changing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _service.members();
      if (mounted) setState(() => _members = members);
    } catch (error) {
      if (mounted) setState(() => _error = safetyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(SafetyMember member, String action) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      if (action == 'report') {
        await showContentReport(
          context,
          kind: 'member',
          targetId: member.id,
          familyId: member.familyId,
          service: _service,
        );
      } else {
        final changed = await confirmMemberBlock(
          context,
          memberId: member.id,
          memberName: member.name,
          blocked: !member.blocked,
          service: _service,
        );
        if (changed && mounted) await _load();
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Safety'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading || _changing ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_changing) const LinearProgressIndicator(),
              if (_error == null && _members.isEmpty)
                const ListTile(title: Text('No other family members')),
              for (final member in _members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    member.blocked ? Icons.block : Icons.person_outline,
                  ),
                  title: Text(member.name),
                  subtitle: Text(
                    [
                      member.familyName ?? 'No shared family',
                      if (member.blocked) 'Blocked',
                    ].join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Member safety options',
                    enabled: !_changing,
                    onSelected: (action) => _action(member, action),
                    itemBuilder: (_) => [
                      if (member.familyId != null)
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('Report member'),
                        ),
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          member.blocked ? 'Unblock member' : 'Block member',
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline),
                title: const Text('Contact support'),
                subtitle: const Text('linebreakers@outlook.com'),
                onTap: () => openLegalLink(context, LegalDestination.support),
              ),
            ],
          ),
  );
}

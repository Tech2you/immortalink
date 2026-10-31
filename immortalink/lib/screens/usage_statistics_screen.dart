import 'package:flutter/material.dart';
import '../services/activity_tracking_service.dart';
import '../widgets/heiro_surface.dart';

class UsageStatisticsScreen extends StatefulWidget {
  const UsageStatisticsScreen({super.key});
  @override
  State<UsageStatisticsScreen> createState() => _UsageStatisticsScreenState();
}

class _UsageStatisticsScreenState extends State<UsageStatisticsScreen> {
  final _tracker = ActivityTrackingService.current;
  bool? _allowed;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final allowed = await _tracker?.isAllowed();
      if (mounted) setState(() => _allowed = allowed);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load this preference. Please reopen this page.',
        );
      }
    }
  }

  Future<void> _change(bool value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _tracker?.setAllowed(value);
      if (mounted) setState(() => _allowed = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save this preference. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => HeiroSurface(
    child: Scaffold(
      appBar: AppBar(title: const Text('Usage statistics')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share usage statistics'),
            subtitle: const Text('For this Heiro account on this device.'),
            value: _allowed ?? false,
            onChanged: _allowed == null || _saving ? null : _change,
          ),
          const SizedBox(height: 20),
          const Text(
            'Help us understand whether Heiro is useful and easy to get started with.',
          ),
          const SizedBox(height: 16),
          const Text(
            'We record the days you use Heiro and the first time we observe a successful memory save or accepted invitation. These records use your account ID.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Your stories, photos, recordings and invite codes are not included in these statistics. We do not use them for advertising or record your screen.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Turning this off stops future collection on this device. Daily records are kept for up to 90 days; first-use dates remain until account deletion. All features continue to work.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(_error!),
            ),
        ],
      ),
    ),
  );
}

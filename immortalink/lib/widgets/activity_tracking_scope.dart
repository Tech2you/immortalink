import 'dart:async';
import 'package:flutter/widgets.dart';
import '../services/activity_tracking_service.dart';

/// Mounted only after session preferences and password recovery are resolved.
class ActivityTrackingScope extends StatefulWidget {
  const ActivityTrackingScope({
    super.key,
    required this.userId,
    required this.child,
  });
  final String userId;
  final Widget child;
  @override
  State<ActivityTrackingScope> createState() => _ActivityTrackingScopeState();
}

class _ActivityTrackingScopeState extends State<ActivityTrackingScope>
    with WidgetsBindingObserver {
  late ActivityTrackingService _tracker;
  Timer? _midnight;
  @override
  void initState() {
    super.initState();
    _tracker = ActivityTrackingService.forUser(widget.userId);
    ActivityTrackingService.current = _tracker;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tracker.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      _scheduleMidnight();
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now().toUtc();
    _midnight = Timer(
      DateTime.utc(now.year, now.month, now.day + 1).difference(now),
      () {
        if (!mounted) return;
        _tracker.record(AppActivity.active);
        _scheduleMidnight();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _tracker.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _scheduleMidnight();
    } else {
      _midnight?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

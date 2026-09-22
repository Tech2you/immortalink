import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/public_error.dart';

/// Reachability is a UI hint, never an authorization or entitlement decision.
class ConnectionStatus extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionStatus({Future<void> Function()? probe}) : _probe = probe;
  static final instance = ConnectionStatus();
  final Future<void> Function()? _probe;
  bool offline = false;
  int _users = 0;
  Timer? _timer;
  Future<bool>? _pending;

  void attach() {
    if (_users++ != 0) return;
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void detach() {
    if (--_users > 0) return;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _start() {
    unawaited(check());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  void report(Object error) {
    if (isConnectionFailure(error)) _setOffline(true);
  }

  void _setOffline(bool value) {
    if (offline == value) return;
    offline = value;
    notifyListeners();
  }

  Future<bool> check() =>
      _pending ??= _check().whenComplete(() => _pending = null);

  Future<bool> _check() async {
    try {
      await (_probe?.call() ?? _backendProbe()).timeout(
        const Duration(seconds: 4),
      );
      _setOffline(false);
      return true;
    } catch (e) {
      report(e);
      return false;
    }
  }

  Future<void> _backendProbe() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      throw const AuthException('Sign in required');
    }
    await client.from('vaults').select('id').limit(1);
  }
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/services/connection_status.dart';

void main() {
  test(
    'network failure blocks writes, recovery clears the offline hint',
    () async {
      var connected = false;
      final status = ConnectionStatus(
        probe: () async {
          if (!connected) throw ClientException('private URL');
        },
      );
      expect(await status.check(), isFalse);
      expect(status.offline, isTrue);
      connected = true;
      expect(await status.check(), isTrue);
      expect(status.offline, isFalse);
      status.dispose();
    },
  );
  test('permission failures are not mistaken for offline access', () async {
    final status = ConnectionStatus(
      probe: () async {
        throw const PostgrestException(message: 'denied', code: '42501');
      },
    );
    status.report(ClientException('Previous outage'));
    expect(status.offline, isTrue);
    expect(await status.check(), isFalse);
    expect(status.offline, isFalse);
    status.dispose();
  });
  test('concurrent checks share one request', () async {
    var calls = 0;
    final done = Completer<void>();
    final status = ConnectionStatus(
      probe: () {
        calls++;
        return done.future;
      },
    );
    final first = status.check();
    final second = status.check();
    done.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(calls, 1);
    status.dispose();
  });
  test(
    'failed token refresh transport is offline, invalid session is not',
    () async {
      var unavailable = true;
      final status = ConnectionStatus(
        probe: () async {
          if (unavailable) {
            throw AuthRetryableFetchException(message: 'network unavailable');
          }
          throw const AuthException('Session revoked', statusCode: '401');
        },
      );
      expect(await status.check(), isFalse);
      expect(status.offline, isTrue);
      unavailable = false;
      expect(await status.check(), isFalse);
      expect(status.offline, isFalse);
      status.dispose();
    },
  );
  testWidgets('unresponsive connection falls back after four seconds', (
    tester,
  ) async {
    final pending = Completer<void>();
    final status = ConnectionStatus(probe: () => pending.future);
    final result = status.check();
    await tester.pump(const Duration(seconds: 4));
    expect(await result, isFalse);
    expect(status.offline, isTrue);
    pending.complete();
    await tester.pump();
    // The late request must not silently switch an offline screen to online.
    expect(status.offline, isTrue);
    status.dispose();
  });
}

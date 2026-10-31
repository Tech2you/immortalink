import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/subscription_family.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_subscription_service_test.dart' show FakeSupabase;

class MembershipClient extends FakeSupabase {
  MembershipClient(this.reader);
  final SupabaseClient reader;
  @override
  SupabaseQueryBuilder from(String table) => reader.from(table);
}

void main() {
  late MembershipClient client;
  var calls = 0;
  Object rows = <Map<String, dynamic>>[];
  Completer<void>? pending;
  var status = 200;
  setUp(() {
    calls = 0;
    pending = null;
    status = 200;
    rows = <Map<String, dynamic>>[];
    client = MembershipClient(
      SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.path, '/rest/v1/family_members');
          expect(
            request.url.queryParameters['user_id'],
            'eq.00000000-0000-4000-8000-000000000001',
          );
          expect(
            request.url.queryParameters['select'],
            'family_id,is_primary,joined_at',
          );
          await pending?.future;
          return http.Response(
            jsonEncode(rows),
            status,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  });
  tearDown(() async => client.reader.dispose());
  test(
    'missing or stale home selection resolves current primary membership',
    () async {
      rows = [
        {'family_id': 'other', 'is_primary': false},
        {'family_id': 'home', 'is_primary': true},
      ];
      expect(await resolveSubscriptionFamily(client), 'home');
      expect(
        await resolveSubscriptionFamily(
          client,
          preferredFamilyId: 'left-family',
        ),
        'home',
      );
      expect(calls, 2);
    },
  );
  test(
    'a selected family is used only while it is still a membership',
    () async {
      rows = [
        {'family_id': 'selected', 'is_primary': false},
        {'family_id': 'home', 'is_primary': true},
      ];
      expect(
        await resolveSubscriptionFamily(
          client,
          preferredFamilyId: ' selected ',
        ),
        'selected',
      );
    },
  );
  test('only successful empty membership returns no family', () async {
    expect(
      await resolveSubscriptionFamily(client, preferredFamilyId: 'stale'),
      isNull,
    );
    status = 403;
    rows = {'message': 'access unavailable', 'code': '42501'};
    await expectLater(
      resolveSubscriptionFamily(client),
      throwsA(isA<PostgrestException>()),
    );
  });
  test(
    'account change during loading discards the previous user result',
    () async {
      pending = Completer<void>();
      rows = [
        {'family_id': 'previous-user-family'},
      ];
      final result = resolveSubscriptionFamily(client);
      final assertion = expectLater(result, throwsStateError);
      client.auth.currentUser = null;
      pending!.complete();
      await assertion;
    },
  );
  test(
    'signed-out and malformed results never become no-family claims',
    () async {
      rows = [
        {'family_id': null},
      ];
      await expectLater(
        resolveSubscriptionFamily(client),
        throwsFormatException,
      );
      client.auth.currentUser = null;
      await expectLater(resolveSubscriptionFamily(client), throwsStateError);
      expect(calls, 1);
    },
  );
}

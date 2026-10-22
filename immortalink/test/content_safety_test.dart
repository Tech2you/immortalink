import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/content_safety_screen.dart';
import 'package:immortalink/services/content_safety_service.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/content_safety_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SafetyService extends ContentSafetyService {
  bool blocked = false;
  bool fail = false;
  @override
  Future<List<SafetyMember>> members() async => [
    SafetyMember(
      id: 'member',
      name: 'Frank',
      familyId: 'family',
      familyName: 'Our family',
      blocked: blocked,
    ),
  ];
  @override
  Future<void> setBlocked(String memberId, bool value) async {
    if (fail) {
      throw const PostgrestException(message: 'private backend details');
    }
    blocked = value;
  }
}

class _ReportService extends ContentSafetyService {
  final reports = <Map<String, dynamic>>[];
  @override
  Future<void> report({
    required String kind,
    required String targetId,
    required String reason,
    required String details,
    String? familyId,
  }) async {
    reports.add({
      'p_kind': kind,
      'p_target_id': targetId,
      'p_reason': reason,
      'p_details': details,
      'p_family_id': familyId,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'memory menu reports only its item without edit or delete actions',
    (tester) async {
      final service = _ReportService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                MemoryReportMenu(memoryId: 'selected-memory', service: service),
                MemoryReportMenu(memoryId: 'other-memory', service: service),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Memory options').first);
      await tester.pumpAndSettle();
      expect(find.text('Report memory or media'), findsOneWidget);
      expect(find.text('Edit memory'), findsNothing);
      expect(find.text('Delete memory'), findsNothing);
      await tester.tap(find.text('Report memory or media'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Something else').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Harmless QA photo');
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.text('Report received'), findsOneWidget);
      expect(service.reports, hasLength(1));
      expect(service.reports.single, {
        'p_kind': 'memory',
        'p_target_id': 'selected-memory',
        'p_reason': 'other',
        'p_details': 'Harmless QA photo',
        'p_family_id': null,
      });
    },
  );

  testWidgets('memory report can be cancelled without sending a report', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryReportMenu(
            memoryId: 'selected-memory',
            service: _ReportService(),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Memory options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report memory or media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ContentReportDialog), findsNothing);
    expect(find.byTooltip('Memory options'), findsOneWidget);
  });

  test(
    'reports and blocks use scoped RPCs; a successful block invalidates cached data',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path.endsWith('list_safety_members') ? '[]' : 'null',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final service = ContentSafetyService(client: client);
      await service.report(
        kind: 'legacy_memory',
        targetId: 'memory',
        reason: 'privacy',
        details: 'Consent',
      );
      expect(requests.single.url.path, '/rest/v1/rpc/report_family_content');
      expect(jsonDecode(requests.single.body), {
        'p_kind': 'legacy_memory',
        'p_target_id': 'memory',
        'p_reason': 'privacy',
        'p_details': 'Consent',
        'p_family_id': null,
      });
      final before = RecentCache.instance.generation;
      await service.setBlocked('member', true);
      expect(RecentCache.instance.generation, greaterThan(before));
      expect(jsonDecode(requests.last.body), {
        'p_member_id': 'member',
        'p_blocked': true,
      });
      expect(await service.members(), isEmpty);
      await client.dispose();
    },
  );

  testWidgets(
    'report needs a reason and confirms only after the server succeeds',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentReportDialog(
              submit: (reason, details) {
                expect(reason, 'privacy');
                expect(details, 'Please check this');
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy or consent').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Please check this');
      await tester.tap(find.text('Send report'));
      await tester.pump();
      expect(find.text('Report received'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Report received'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    },
  );

  testWidgets(
    'failed report remains retryable without exposing backend details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentReportDialog(
              submit: (_, _) async {
                throw const PostgrestException(
                  message: 'private SQL receipt and account details',
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam or scam').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.text('Report received'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private SQL'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('member block is confirmed and can be reversed', (tester) async {
    final service = _SafetyService();
    await tester.pumpWidget(
      MaterialApp(home: ContentSafetyScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Member safety options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block member'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.blocked, false);
    await tester.tap(find.text('Block').last);
    await tester.pumpAndSettle();
    expect(service.blocked, true);
    expect(find.text('Our family · Blocked'), findsOneWidget);
    await tester.tap(find.byTooltip('Member safety options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock member'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Unblock').last);
    await tester.pumpAndSettle();
    expect(service.blocked, false);
  });

  testWidgets('failed block does not pretend to succeed', (tester) async {
    final service = _SafetyService()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: ContentSafetyScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Member safety options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block member'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Block').last);
    await tester.pumpAndSettle();
    expect(service.blocked, false);
    expect(find.textContaining('Blocked'), findsNothing);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('report dialog fits a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: ContentReportDialog(submit: (_, _) async {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Report content'), findsOneWidget);
  });
}

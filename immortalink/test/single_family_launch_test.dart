import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/main.dart';
import 'package:immortalink/screens/family_branch_screen.dart';
import 'package:immortalink/screens/family_tree_screen.dart';
import 'package:immortalink/screens/join_family_screen.dart';
import 'package:immortalink/screens/relationship_tree_screen.dart';
import 'package:immortalink/screens/sign_in_screen.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/widgets/startup_screen.dart';
import 'package:immortalink/widgets/content_placeholder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const userId = '00000000-0000-4000-8000-000000000001';
  const firstFamily = '00000000-0000-4000-8000-000000000002';
  const secondFamily = '00000000-0000-4000-8000-000000000003';
  const familyNames = {
    firstFamily: 'Strauss family',
    secondFamily: 'Botha family',
  };
  var memberships = <Map<String, dynamic>>[];
  var hasVault = true;
  var rejectJoin = false;
  var vaultInserts = 0;
  final joinCalls = <String>[];
  final renameCalls = <Map<String, dynamic>>[];
  var renamedFamily = 'Strauss family';
  var rejectRename = false;
  Completer<void>? avatarGate;
  Completer<void>? membershipGate;
  Completer<void>? feedGate;
  var includeFeed = false;
  var denyFeed = false;
  var avatarRequested = false;
  final leaveCalls = <String>[];
  var deletionCalls = 0;

  Map<String, dynamic> member(String familyId, {bool primary = false}) => {
    'family_id': familyId,
    'user_id': userId,
    'role': 'member',
    'slot_key': null,
    'joined_at': '2026-09-16T00:00:00Z',
    'is_primary': primary,
  };

  Map<String, dynamic> vault() => {
    'id': '00000000-0000-4000-8000-000000000004',
    'owner_id': userId,
    'name': 'Frank Strauss',
    'display_name': 'Frank Strauss',
    'created_at': '2026-09-15T00:00:00Z',
    'family_id': memberships.isEmpty ? null : memberships.first['family_id'],
    'avatar_path': avatarGate == null ? null : 'test/avatar.jpg',
  };

  http.Response response(
    http.Request request,
    Object? body, {
    int status = 200,
  }) => http.Response(
    jsonEncode(body),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  setUpAll(() async {
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isNotEmpty) {
      await (FontLoader('Roboto')..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '${File(fontPath).parent.path}/MaterialIcons-Regular.otf',
                ).readAsBytes(),
              ),
            ),
          ))
          .load();
    }
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'com.llfbandit.app_links/messages',
      'com.llfbandit.app_links/events',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          if (call.method == 'create') {
            final playerId = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$playerId'),
              (_) async => null,
            );
          }
          return 1;
        },
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      // Invite codes are supplied to the real join screen below; this fixture
      // does not need the native authentication-link event channel.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/delete_account') || request.method == 'DELETE') {
          deletionCalls++;
          return response(request, {
            'message': 'Unexpected deletion',
          }, status: 500);
        }
        if (path.endsWith('/rpc/get_family_leave_impact')) {
          return response(request, {
            'is_last_real_member': false,
            'requires_destructive_confirmation': false,
          });
        }
        if (path.endsWith('/rpc/leave_family')) {
          leaveCalls.add(path.split('/').last);
          memberships = [];
          return response(request, null);
        }
        if (path.endsWith('/token')) {
          return response(request, {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': userId,
              'aud': 'authenticated',
              'email': 'test@example.com',
              'created_at': '2026-09-15T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        if (path.endsWith('/vaults')) {
          if (request.method == 'POST') {
            vaultInserts++;
            hasVault = true;
            return response(request, null, status: 201);
          }
          if (includeFeed &&
              request.url.queryParameters['owner_id']?.startsWith('in.') ==
                  true) {
            return response(request, [
              vault(),
              {
                ...vault(),
                'id': 'feed-vault',
                'owner_id': 'other-user',
                'name': 'Demo relative',
                'display_name': 'Demo relative',
              },
            ]);
          }
          return response(request, hasVault ? [vault()] : <Object>[]);
        }
        if (includeFeed && path.endsWith('/memories')) {
          await feedGate?.future;
          if (denyFeed) {
            return response(request, {
              'code': '42501',
              'message': 'denied',
            }, status: 403);
          }
          return response(request, [
            {
              'id': 'feed-memory',
              'vault_id': 'feed-vault',
              'body': 'A sample family story',
              'prompt_text': 'A good day',
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'share_to_family_feed': true,
            },
          ]);
        }
        if (path.endsWith('/family_members')) {
          await membershipGate?.future;
          final familyFilter = request.url.queryParameters['family_id'];
          return response(
            request,
            familyFilter == null
                ? memberships
                : memberships
                      .where((row) => 'eq.${row['family_id']}' == familyFilter)
                      .toList(),
          );
        }
        if (path.endsWith('/family_groups')) {
          final families = [
            for (final row in memberships)
              {
                'id': row['family_id'],
                'name': row['family_id'] == firstFamily
                    ? renamedFamily
                    : familyNames[row['family_id']],
              },
          ];
          return response(
            request,
            request.headers['accept']?.contains('vnd.pgrst.object') == true
                ? families.first
                : families,
          );
        }
        if (path.endsWith('/rpc/rename_family')) {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          renameCalls.add(params);
          if (rejectRename) {
            return response(request, {
              'code': '42501',
              'message': 'Only a current family member can rename this family',
            }, status: 403);
          }
          renamedFamily = params['p_name'] as String;
          return response(request, null);
        }
        if (path.contains('/rpc/join_family_by_')) {
          joinCalls.add(path.split('/').last);
          if (rejectJoin) {
            return response(request, {
              'code': 'P0001',
              'message': 'FAMILY_MEMBERSHIP_LIMIT',
              'details': null,
              'hint': null,
            }, status: 400);
          }
          memberships = [member(firstFamily, primary: true)];
          return response(request, firstFamily);
        }
        if (path.startsWith('/storage/')) {
          if (path.contains('/object/sign/avatars/')) {
            avatarRequested = true;
            await avatarGate?.future;
          }
          return response(request, {'message': 'No family photo'}, status: 404);
        }
        return response(request, <Object>[]);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-only',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    memberships = [];
    hasVault = true;
    rejectJoin = false;
    vaultInserts = 0;
    joinCalls.clear();
    renameCalls.clear();
    renamedFamily = 'Strauss family';
    rejectRename = false;
    avatarGate = null;
    membershipGate = null;
    feedGate = null;
    includeFeed = false;
    denyFeed = false;
    avatarRequested = false;
    leaveCalls.clear();
    deletionCalls = 0;
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<void> settle(WidgetTester tester) async {
    // Supabase's JSON worker and platform replies run outside the fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> pumpLegacyTree(WidgetTester tester) async {
    // The older tree schedules geometry updates every frame, so it cannot settle.
    for (var frame = 0; frame < 4; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(debugShowCheckedModeBanner: false, home: screen),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Let pending mocked network work finish before cancelling reconnects.
    await settle(tester);
    await Supabase.instance.client.realtime.disconnect();
    // The mocked socket closes before connecting; this SDK version leaves its
    // reconnect timer alive when disconnecting an already-closed transport.
    Supabase.instance.client.realtime.reconnectTimer.reset();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> captureLoading(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('LOADING_VISUAL_QA')) return;
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/loading-ux-qa/$name.png'),
    );
  }

  // Keep the real app's singleton cache in one fake-async lifetime while
  // exercising the no-family, one-family, and grandfathered-family states.
  testWidgets('first-family entry and existing trees survive the launch limit', (
    tester,
  ) async {
    await show(tester, const VaultsScreen());
    expect(find.text('Create your family tree'), findsOneWidget);
    expect(find.text('Join with invite code'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Join family'), findsOneWidget);
    await tester.tap(find.text('Join family'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinFamilyScreen), findsOneWidget);
    expect(
      find.text(
        'Use an invite to join your family. Joining additional families is not available yet.',
      ),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create your family tree'));
    await tester.pumpAndSettle();
    expect(find.text('Invite your family'), findsOneWidget);
    expect(joinCalls, isEmpty);
    await close(tester);
    memberships = [member(firstFamily, primary: true)];
    await show(tester, const VaultsScreen());
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('My vault'), findsOneWidget);
    expect(find.text('Strauss family'), findsOneWidget);
    expect(find.text('Create your family tree'), findsNothing);
    expect(find.text('Join with invite code'), findsNothing);
    expect(find.text('Join another family'), findsNothing);
    expect(find.text('Create another family'), findsNothing);
    expect(find.byTooltip('Family tree actions'), findsNothing);
    expect(find.text('Heiro'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Invite family'), findsOneWidget);
    await captureLoading(tester, 'ui34-empty-feed');
    await tester.tap(find.text('Invite family'));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipTreeScreen), findsOneWidget);
    expect(find.text('Invite parent'), findsOneWidget);
    expect(find.text('Invite sibling'), findsOneWidget);
    expect(joinCalls, isEmpty);
    await tester.tapAt(const Offset(10, 120));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Join family'), findsNothing);
    expect(find.text('Subscription and storage'), findsOneWidget);
    await close(tester);

    // A regular member can rename from both entry points, without gaining
    // owner-only successor controls or bypassing a server permission failure.
    await show(tester, const VaultsScreen());
    await tester.tap(
      find.text('Strauss family').evaluate().isNotEmpty
          ? find.text('Strauss family')
          : find.text('Tree rename'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit family details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit family name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a family name.'), findsOneWidget);
    expect(renameCalls, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  Renamed family  ');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(renameCalls.single, {
      'p_family_id': firstFamily,
      'p_name': 'Renamed family',
    });
    expect(find.text('Renamed family'), findsOneWidget);

    await tester.tap(find.text('Tree'));
    await settle(tester);
    await tester.tap(find.byTooltip('Family tree settings'));
    await tester.pumpAndSettle();
    expect(find.text('Account successor'), findsNothing);
    await tester.tap(find.text('Change family name'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), 'Tree rename');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(renameCalls.last['p_name'], 'Tree rename');
    expect(find.text('Family name updated.'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Tree rename'), findsOneWidget);

    await close(tester);
    await show(tester, const VaultsScreen());
    rejectRename = true;
    await tester.tap(
      find.text('Strauss family').evaluate().isNotEmpty
          ? find.text('Strauss family')
          : find.text('Tree rename'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit family details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit family name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Rejected name');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(renameCalls.length, 3);
    expect(renameCalls.last['p_name'], 'Rejected name');
    expect(renamedFamily, 'Tree rename');
    expect(
      find.text('You do not have permission to complete this action.'),
      findsOneWidget,
    );
    expect(find.text('Tree rename'), findsOneWidget);
    expect(find.text('Rejected name'), findsNothing);
    await close(tester);
    renamedFamily = 'Strauss family';
    rejectRename = false;
    memberships = [member(firstFamily, primary: true), member(secondFamily)];
    await show(tester, const VaultsScreen());
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Join another family'), findsNothing);
    expect(find.text('Create another family'), findsNothing);
    expect(find.byTooltip('Family tree actions'), findsNothing);

    for (final family in familyNames.entries) {
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.text(family.value), findsOneWidget);
      await tester.tap(find.text(family.value));
      await settle(tester);
      expect(
        tester
            .widget<RelationshipTreeScreen>(find.byType(RelationshipTreeScreen))
            .familyId,
        family.key,
      );
      await tester.pageBack();
      await settle(tester);
    }
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Join family'), findsNothing);
    await close(tester);

    // No empty account/family screen may appear while membership is pending.
    memberships = [member(firstFamily, primary: true)];
    membershipGate = Completer<void>();
    await show(tester, const VaultsScreen());
    expect(find.byType(StartupScreen), findsOneWidget);
    expect(find.text('Your Vault'), findsNothing);
    expect(find.text('Create your vault'), findsNothing);
    expect(find.text('No vault yet'), findsNothing);
    expect(find.text('Offline'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await captureLoading(tester, 'startup-phone');
    tester.view.physicalSize = const Size(834, 1194);
    await captureLoading(tester, 'startup-tablet');
    tester.view.physicalSize = const Size(390, 844);
    membershipGate!.complete();
    await settle(tester);
    expect(find.text('Strauss family'), findsOneWidget);
    expect(find.byType(StartupScreen), findsNothing);
    await close(tester);
    membershipGate = null;

    // Family navigation must be usable even while its optional avatar is slow.
    memberships = [member(firstFamily, primary: true)];
    avatarGate = Completer<void>();
    await show(tester, const VaultsScreen());
    expect(avatarRequested, isTrue);
    expect(avatarGate!.isCompleted, isFalse);
    expect(find.text('Strauss family'), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    avatarGate!.complete();
    await settle(tester);
    await close(tester);
    avatarGate = null;

    includeFeed = true;
    feedGate = Completer<void>();
    await show(tester, const VaultsScreen());
    expect(find.byType(FeedPlaceholder), findsOneWidget);
    expect(find.text('No family memories yet.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await captureLoading(tester, 'feed-loading-phone');
    tester.view.physicalSize = const Size(834, 1194);
    await captureLoading(tester, 'feed-loading-tablet');
    if (const bool.fromEnvironment('LOADING_VISUAL_QA')) {
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await captureLoading(tester, 'feed-loading-small-large-text');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
    tester.view.physicalSize = const Size(390, 844);
    feedGate!.complete();
    await settle(tester);
    expect(find.text('A sample family story'), findsOneWidget);
    expect(find.text('Invite family'), findsNothing);

    // Refresh leaves the verified feed in place until its replacement arrives.
    feedGate = Completer<void>();
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await settle(tester);
    expect(find.text('A sample family story'), findsOneWidget);
    expect(find.byType(FeedPlaceholder), findsNothing);
    expect(find.byType(StartupScreen), findsNothing);
    denyFeed = true;
    feedGate!.complete();
    await settle(tester);
    await refresh;
    expect(find.text('A sample family story'), findsNothing);
    expect(find.textContaining('permission'), findsWidgets);
    await close(tester);
    includeFeed = false;
    feedGate = null;
    denyFeed = false;

    memberships = [];
    hasVault = false;
    await show(
      tester,
      const JoinFamilyScreen(initialInviteCode: 'first-family'),
    );
    await tester.tap(find.text('Join'));
    await settle(tester);
    expect(vaultInserts, 1);
    expect(joinCalls, ['join_family_by_relationship_invite']);
    expect(
      tester
          .widget<RelationshipTreeScreen>(find.byType(RelationshipTreeScreen))
          .familyId,
      firstFamily,
    );
    expect(find.text('Could not join family'), findsNothing);
    await close(tester);
    // Continue in the same fake-async lifetime as the singleton cache above.
    for (final legacyTree in [false, true]) {
      tester.view.physicalSize = legacyTree
          ? const Size(1440, 1100)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'auth_has_seen_create_account_prompt': true,
      });
      memberships = [member(firstFamily, primary: true)];
      leaveCalls.clear();
      vaultInserts = 0;
      await tester.pumpWidget(const MyApp());
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.text('My vault'), findsOneWidget);

      if (legacyTree) {
        Navigator.of(tester.element(find.byType(VaultsScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const FamilyTreeScreen(familyId: firstFamily),
          ),
        );
        await pumpLegacyTree(tester);
        await tester.tap(find.byTooltip('Leave family'));
      } else {
        await tester.tap(find.text('Tree'));
        await settle(tester);
        await tester.tap(find.byTooltip('Family tree settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave family'));
      }
      if (legacyTree) {
        await pumpLegacyTree(tester);
      } else {
        await settle(tester);
      }
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          legacyTree ? 'Leave' : 'Leave family',
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(leaveCalls, ['leave_family']);
      expect(memberships, isEmpty);
      expect(hasVault, isTrue);
      expect(find.text('My vault'), findsOneWidget);
      expect(find.text('No vault yet'), findsNothing);
      expect(find.byType(AuthGate), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sign out'), 350);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(Supabase.instance.client.auth.currentUser?.id, userId);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sign out'), 350);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(VaultsScreen), findsNothing);
      expect(find.text('No vault yet'), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(SignInScreen))).canPop(),
        isFalse,
      );
      expect(deletionCalls, 0);

      await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'test-only');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.text('My vault'), findsOneWidget);
      expect(find.text('Join with invite code'), findsOneWidget);
      expect(vaultInserts, 0);
      expect(deletionCalls, 0);
      if (legacyTree) {
        memberships = [member(firstFamily, primary: true)];
        Navigator.of(tester.element(find.byType(VaultsScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const FamilyBranchScreen(
              familyId: firstFamily,
              rootLabel: 'Test relative',
              rootSlotKey: 'mother',
              direction: 'ancestor',
            ),
          ),
        );
        await pumpLegacyTree(tester);
        await tester.tap(find.byTooltip('Back to family tree'));
        await pumpLegacyTree(tester);
        expect(find.byType(AuthGate, skipOffstage: false), findsOneWidget);
        expect(
          Navigator.of(
            tester.element(find.byType(RelationshipTreeScreen)),
          ).canPop(),
          isTrue,
        );
        Navigator.of(tester.element(find.byType(RelationshipTreeScreen))).pop();
        await settle(tester);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Sign out'), 350);
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 350));
        await settle(tester);
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(AuthGate), findsOneWidget);
        await tester.runAsync(
          () => Supabase.instance.client.auth.signInWithPassword(
            email: 'test@example.com',
            password: 'test-only',
          ),
        );
        await settle(tester);
        expect(find.text('My vault'), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
        expect(deletionCalls, 0);
      }
      await close(tester);
    }
  });

  testWidgets('deep-linked invite shows the family limit without legacy retry', (
    tester,
  ) async {
    memberships = [member(firstFamily, primary: true)];
    rejectJoin = true;
    await show(
      tester,
      const JoinFamilyScreen(initialInviteCode: 'another-family'),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('Could not join family'), findsOneWidget);
    expect(
      find.text(
        'You already belong to a family. Joining another family is not available yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('You are already part of this family.'), findsNothing);
    expect(joinCalls, ['join_family_by_relationship_invite']);
    expect(vaultInserts, 0);
    expect(memberships.single['family_id'], firstFamily);
    await close(tester);
  });
}

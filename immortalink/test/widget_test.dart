import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:immortalink/main.dart';
import 'package:immortalink/services/onboarding_invite_state.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'http://localhost:54321',
        anonKey: 'test-anon-key',
      );
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch makes create account impossible to miss', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.text('Start free. Add your vault, then invite or join family.'),
      findsOneWidget,
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Family invite code (optional)'), findsNothing);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('pending family invite keeps the invite handoff subtle', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      pendingFamilyInviteCodePreferenceKey: 'abc 123',
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);
    expect(
      find.text(
        'Family invite ready. After this, Ever Roots will open the join step.',
      ),
      findsOneWidget,
    );
    expect(find.text('Family invite code (optional)'), findsNothing);
    expect(find.text('ABC123'), findsNothing);
  });

  testWidgets('returning unauthenticated users can still sign in', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_has_seen_create_account_prompt': true,
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Use the account your family knows.'), findsOneWidget);
    expect(find.text('Stay signed in'), findsOneWidget);
  });
}

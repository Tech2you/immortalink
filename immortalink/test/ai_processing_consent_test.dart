import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/ai_processing_consent.dart';
import 'apple_subscription_service_test.dart' show FakeSupabase, FakeRpc;

class ConsentBackend extends FakeSupabase {
  bool allowed = false;
  bool fail = false;
  final choices = <bool>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #rpc) {
      if (fail) return FakeRpc(Exception('offline'));
      if (invocation.positionalArguments.first == 'has_ai_processing_consent') {
        return FakeRpc(allowed);
      }
      final params = invocation.namedArguments[#params] as Map;
      allowed = params['p_allowed'] as bool;
      choices.add(allowed);
      return FakeRpc(null);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  for (final choice in [true, false]) {
    testWidgets('explicit consent choice $choice is recorded without a provider call', (tester) async {
      final backend = ConsentBackend();
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        TextButton(onPressed: () async { result = await requestAiProcessingConsent(context,client: backend); }, child: const Text('Start'))))));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.textContaining('personal information'),findsOneWidget);
      expect(backend.choices,isEmpty);
      await tester.tap(find.text(choice ? 'Allow OpenAI processing' : 'Not now'));
      await tester.pumpAndSettle();
      expect(result,choice);
      expect(backend.choices,[choice]);
    });
  }
  testWidgets('permission can be withdrawn from settings', (tester) async {
    final backend = ConsentBackend()..allowed=true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => requestAiProcessingConsent(context,client: backend,settings: true), child: const Text('Settings'))))));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off AI'));
    await tester.pumpAndSettle();
    expect(backend.allowed,false);
  });
  testWidgets('offline consent lookup does not enable AI', (tester) async {
    final backend = ConsentBackend()..fail=true;
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { result=await requestAiProcessingConsent(context,client: backend); }, child: const Text('Start'))))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(result,false);
    expect(backend.choices,isEmpty);
  });
}

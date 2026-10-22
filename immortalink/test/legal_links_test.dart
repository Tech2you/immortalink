import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/legal_links.dart';

void main() {
  test(
    'legal destinations are public HTTPS pages and an explicit support address',
    () {
      expect(legalUrl(LegalDestination.privacy).scheme, 'https');
      expect(legalUrl(LegalDestination.privacy).host, 'heiro.app');
      expect(legalUrl(LegalDestination.privacy).path, '/privacy.html');
      expect(legalUrl(LegalDestination.terms).host, 'www.apple.com');
      expect(
        legalUrl(LegalDestination.support).path,
        'linebreakers@outlook.com',
      );
      expect(
        legalUrl(LegalDestination.support).queryParameters['subject'],
        'Heiro support',
      );
    },
  );
  testWidgets('links wrap on narrow screens with large text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SizedBox(width: 240, child: LegalLinks()),
          ),
        ),
      ),
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

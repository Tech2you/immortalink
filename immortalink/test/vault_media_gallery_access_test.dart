import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/vault_media.dart';
import 'package:immortalink/widgets/vault_media_gallery.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _UnavailableCacheDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationCachePath() async => null;
}

void main() {
  // The singleton queue is isolated here so it cannot carry pending futures
  // from a previous widget test's fake-async clock.
  testWidgets(
    'account/cache change prevents paging to previous account photos',
    (tester) async {
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _UnavailableCacheDirectory();
      addTearDown(() => PathProviderPlatform.instance = original);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openVaultMediaGallery(
                  context,
                  [
                    'https://example.com/one.jpg',
                    'https://example.com/two.jpg',
                  ],
                  initialIndex: 0,
                  cachedOnly: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final clear = RecentCache.instance.clear();
      await tester.pump();
      await clear;
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(VaultMedia), findsNothing);
      expect(find.text('Reopen this media from your vault.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

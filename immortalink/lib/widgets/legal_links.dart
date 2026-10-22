import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalDestination { privacy, terms, support }

Uri legalUrl(LegalDestination destination) => Uri.parse(switch (destination) {
  LegalDestination.privacy => 'https://heiro.app/privacy.html',
  LegalDestination.terms =>
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
  LegalDestination.support =>
    'mailto:linebreakers@outlook.com?subject=Heiro%20support',
});

Future<void> openLegalLink(
  BuildContext context,
  LegalDestination destination,
) async {
  try {
    if (await launchUrl(
      legalUrl(destination),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } catch (_) {
    /* Show a usable fallback when a browser/mail app is unavailable. */
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Contact and legal information'),
      content: SelectableText(legalUrl(destination).toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    children: [
      TextButton(
        onPressed: () => openLegalLink(context, LegalDestination.privacy),
        child: const Text('Privacy Policy'),
      ),
      TextButton(
        onPressed: () => openLegalLink(context, LegalDestination.terms),
        child: const Text('Terms of Use'),
      ),
    ],
  );
}

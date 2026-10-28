import 'package:flutter/material.dart';

/// Shared by session restoration and the first account load, with no empty UI.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F0F7),
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Loading Heiro',
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Image.asset(
                'assets/images/immortalink_logo.png',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

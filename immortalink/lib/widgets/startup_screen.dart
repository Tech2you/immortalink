import 'package:flutter/material.dart';
import 'brand_loading.dart';

/// Shared by session restoration and the first account load, with no empty UI.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FCFE),
      body: const SafeArea(child: BrandLoading()),
    );
  }
}

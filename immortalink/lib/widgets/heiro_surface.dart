import 'package:flutter/material.dart';

const heiroBlue = Color(0xFF007D93);
const heiroIce = Color(0xFFEEF8FC);
const heiroInk = Color(0xFF172A35);

/// Scoped to the preview screens; the tree and other routes keep their theme.
class HeiroSurface extends StatelessWidget {
  const HeiroSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: heiroBlue,
          primary: heiroBlue,
          surface: Colors.white,
          onSurface: heiroInk,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: heiroInk,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        dividerColor: const Color(0xFFE3EEF3),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFAFCFD),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD6E5ED)),
          ),
        ),
      ),
      child: child,
    );
  }
}

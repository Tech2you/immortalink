import 'package:flutter/material.dart';

class LogoWatermark extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double size;

  const LogoWatermark({
    super.key,
    required this.child,
    this.opacity = 0.05,
    this.size = 520,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Opacity(
              opacity: opacity,
              child: Center(
                child: Image.asset(
                  'assets/images/immortalink_logo.png',
                  width: size,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

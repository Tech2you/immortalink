import 'package:flutter/material.dart';

/// Brief breathing artwork, without delaying navigation or changing its size.
class BrandLoading extends StatefulWidget {
  const BrandLoading({super.key, this.size = 180});
  final double size;

  @override
  State<BrandLoading> createState() => _BrandLoadingState();
}

class _BrandLoadingState extends State<BrandLoading>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.88), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading Heiro',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FadeTransition(
          opacity: _opacity,
          child: Image.asset(
            'assets/images/immortalink_logo.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}

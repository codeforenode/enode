import 'package:flutter/material.dart';

/// 连续点击 [taps] 次（每次间隔不超过 1.5s）才触发 [onUnlock]。
class SecretTap extends StatefulWidget {
  const SecretTap({super.key, required this.child, required this.onUnlock, this.taps = 5});
  final Widget child;
  final VoidCallback onUnlock;
  final int taps;

  @override
  State<SecretTap> createState() => _SecretTapState();
}

class _SecretTapState extends State<SecretTap> {
  int _count = 0;
  DateTime? _last;

  void _tap() {
    final now = DateTime.now();
    final last = _last;
    if (last == null || now.difference(last) > const Duration(milliseconds: 1500)) {
      _count = 0;
    }
    _last = now;
    _count++;
    if (_count >= widget.taps) {
      _count = 0;
      _last = null;
      widget.onUnlock();
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: widget.child,
        ),
      );
}

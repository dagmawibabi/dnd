import 'dart:async';

import 'package:flutter/material.dart';

/// Reveals text progressively; tap to complete instantly.
class TypewriterText extends StatefulWidget {
  const TypewriterText({super.key, required this.text, required this.style, this.animate = true, this.speed = 1.0, this.onDone, this.onTap, this.textAlign = TextAlign.start});
  final VoidCallback? onTap;
  final String text;
  final TextStyle style;
  final bool animate;
  final double speed;
  final VoidCallback? onDone;
  final TextAlign textAlign;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.animate && !(WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations)) {
      _start();
    } else {
      _count = widget.text.length;
    }
  }

  void _start() {
    final perTick = (2 * widget.speed).clamp(1, 12).round();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) return;
      setState(() => _count = (_count + perTick).clamp(0, widget.text.length));
      if (_count >= widget.text.length) {
        t.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      if (widget.text.startsWith(old.text) && widget.animate) {
        // streaming growth: keep going
        if (_timer == null || !_timer!.isActive) _start();
      } else {
        _timer?.cancel();
        _count = widget.animate ? 0 : widget.text.length;
        if (widget.animate) _start();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _count.clamp(0, widget.text.length));
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _count < widget.text.length
          ? () {
              _timer?.cancel();
              setState(() => _count = widget.text.length);
              widget.onDone?.call();
            }
          : widget.onTap,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: shown),
          TextSpan(text: widget.text.substring(shown.length), style: const TextStyle(color: Colors.transparent)),
        ]),
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

/// Lifts dark procedural cover art so night scenes read clearly in lists.
class BrightArt extends StatelessWidget {
  const BrightArt({super.key, required this.child, this.gain = 1.45, this.lift = 14});
  final Widget child;
  final double gain;
  final double lift;

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: ColorFilter.matrix([
          gain, 0, 0, 0, lift, //
          0, gain, 0, 0, lift,
          0, 0, gain, 0, lift,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );
}

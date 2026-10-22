import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/settings.dart';
import '../../theme/ui.dart';

/// Applies fullscreen (no status or navigation bar) while a story is open and
/// restores the system bars when it closes.
class Immersive extends StatefulWidget {
  const Immersive({super.key, required this.child});
  final Widget child;

  @override
  State<Immersive> createState() => _ImmersiveState();
}

class _ImmersiveState extends State<Immersive> {
  bool? _applied;

  void _apply(bool on) {
    if (_applied == on) return;
    _applied = on;
    SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    if (_applied == true) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _apply(context.select<SettingsController, bool>((s) => s.fullscreen));
    return widget.child;
  }
}

/// In fullscreen the app bar is gone: a small floating back button and the
/// story's actions sit over the top corners instead.
class FullscreenControls extends StatelessWidget {
  const FullscreenControls({super.key, required this.title, required this.onTitle, this.actions = const []});
  final String title;
  final VoidCallback onTitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Widget pill(Widget child) => Material(
          color: AppColors.surface.withValues(alpha: 0.82),
          shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
          child: child,
        );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          pill(IconButton(tooltip: 'Back', visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_back, size: 20), onPressed: () => Navigator.maybePop(context))),
          const SizedBox(width: 6),
          Flexible(
            child: pill(InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTitle,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small(color: AppColors.text))),
            )),
          ),
          const Spacer(),
          if (actions.isNotEmpty) pill(Row(mainAxisSize: MainAxisSize.min, children: actions)),
          const SizedBox(width: 6),
          pill(IconButton(
            tooltip: 'Leave fullscreen',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.fullscreen_exit, size: 20),
            onPressed: () => context.read<SettingsController>().update((s) => s.fullscreen = false),
          )),
        ]),
      ),
    );
  }
}

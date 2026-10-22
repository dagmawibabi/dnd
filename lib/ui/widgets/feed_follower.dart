import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/adventure.dart';

/// Keeps a reversed story feed showing the *start* of the newest passage, so
/// the end of a long reply isn't read first. It follows the passage while it
/// streams or types out, and stops following once the player scrolls.
class FeedFollower {
  FeedFollower(this.scroll);
  final ScrollController scroll;
  final GlobalKey _anchor = GlobalKey();

  /// Off after the player scrolls by hand; on again with their next action.
  bool follow = true;
  bool _pending = false;

  /// Space left above the passage so its first line isn't flush with the edge.
  static const margin = 28.0;

  /// Index in [log] of the first entry of the latest turn: what came after the
  /// player's last action, or the newest narration when there is none.
  static int anchorIndex(List<LogEntry> log) {
    if (log.isEmpty) return -1;
    final player = log.lastIndexWhere((e) => e.kind == LogKind.player);
    if (player >= 0 && player < log.length - 1) return player + 1;
    if (player == log.length - 1) return player;
    final story = log.lastIndexWhere((e) => e.kind == LogKind.narration || e.kind == LogKind.dialogue);
    return story < 0 ? log.length - 1 : story;
  }

  /// Wraps the item the view should keep in sight.
  Widget anchor(Widget child) => NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          if (follow) reveal(animate: false);
          return true;
        },
        child: SizeChangedLayoutNotifier(child: KeyedSubtree(key: _anchor, child: child)),
      );

  /// Call when the player acts: the next reply is followed again.
  void resume() => follow = true;

  /// Tracks hand scrolling; pass to a `NotificationListener<ScrollNotification>`.
  bool onScroll(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) follow = false;
    return false;
  }

  /// Scrolls so the top of the anchored item sits near the top of the view
  /// (or the newest content when it fits on screen).
  void reveal({bool animate = true}) {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!scroll.hasClients) return;
      final ctx = _anchor.currentContext;
      final ro = ctx?.findRenderObject();
      final pos = scroll.position;
      double target = 0;
      if (ro != null && ro.attached) {
        final viewport = RenderAbstractViewport.maybeOf(ro);
        if (viewport != null) target = viewport.getOffsetToReveal(ro, 1.0).offset + margin;
      }
      target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - target).abs() < 1) return;
      if (animate) {
        scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      } else {
        scroll.jumpTo(target);
      }
    });
  }
}

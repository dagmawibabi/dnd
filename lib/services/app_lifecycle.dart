import 'package:flutter/widgets.dart';

/// Knows when the app went to the background, so work the system cut off
/// (a story reply, an image) is retried quietly instead of shown as an error.
class AppLifecycle with WidgetsBindingObserver {
  AppLifecycle._();
  static final instance = AppLifecycle._();

  bool _started = false;
  bool foreground = true;

  /// Counts trips to the background; compare before and after a request.
  int epoch = 0;
  final _onResume = <VoidCallback>{};

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (foreground) {
        foreground = false;
        epoch++;
      }
    } else if (state == AppLifecycleState.resumed && !foreground) {
      foreground = true;
      for (final cb in List.of(_onResume)) {
        cb();
      }
    }
  }

  /// Whether the app left the foreground since [since] (an earlier [epoch]).
  bool interrupted(int since) => epoch != since || !foreground;

  void addResumeListener(VoidCallback cb) => _onResume.add(cb);
  void removeResumeListener(VoidCallback cb) => _onResume.remove(cb);

  /// Runs [cb] now if the app is in front, otherwise once it comes back.
  void whenForeground(VoidCallback cb) {
    if (foreground) {
      cb();
      return;
    }
    late VoidCallback once;
    once = () {
      _onResume.remove(once);
      cb();
    };
    _onResume.add(once);
  }

  /// Errors a dropped connection produces, as opposed to a real refusal.
  static bool isNetworkError(Object e) {
    final t = e.toString().toLowerCase();
    return t.contains('socket') ||
        t.contains('connection') ||
        t.contains('closed') ||
        t.contains('abort') ||
        t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('handshake') ||
        t.contains('failed host lookup') ||
        t.contains('network') ||
        t.contains('broken pipe') ||
        t.contains('incomplete');
  }

  /// A failure caused by the app being backgrounded mid-request.
  bool cutOff(Object e, int since) => interrupted(since) && isNetworkError(e);
}

import 'package:flutter/foundation.dart';

import 'gateway_client.dart';

/// One step the storyteller went through ("Gathering memory", "Writing"…).
class AiStep {
  AiStep(this.title, {this.detail = '', this.done = false}) : at = DateTime.now();
  final String title;
  String detail;
  bool done;
  bool failed = false;
  final DateTime at;
}

/// A live record of one AI turn: what it was given, what it thought, what it
/// wrote and which actions ("tools") it took, so the player can look inside.
class AiTrace extends ChangeNotifier {
  AiTrace({required this.label, required this.model}) : started = DateTime.now();

  final String label;
  final String model;
  final DateTime started;
  DateTime? ended;

  /// The messages sent: (role, text).
  final List<(String, String)> context = [];
  final List<AiStep> steps = [];
  final StringBuffer reasoning = StringBuffer();
  final StringBuffer output = StringBuffer();

  /// Actions the reply asked the app to take (events): (type, summary).
  final List<(String, String)> tools = [];
  int tokens = 0;
  double cost = 0;
  String? error;
  bool stopped = false;

  /// The request in flight, so Stop can cancel it.
  GatewayClient? client;

  bool get running => ended == null;
  Duration get elapsed => (ended ?? DateTime.now()).difference(started);

  /// Characters of context sent, as a rough size.
  int get contextChars => context.fold(0, (n, m) => n + m.$2.length);

  AiStep step(String title, {String detail = ''}) {
    if (steps.isNotEmpty && !steps.last.done) steps.last.done = true;
    final s = AiStep(title, detail: detail);
    steps.add(s);
    _notify();
    return s;
  }

  void think(String delta) {
    if (reasoning.isEmpty) step('Thinking');
    reasoning.write(delta);
    _notify();
  }

  void write(String delta) {
    if (output.isEmpty) step('Writing the reply');
    output.write(delta);
    _notify();
  }

  void finish({String? error, int tokens = 0, double cost = 0}) {
    this.error = error;
    this.tokens = tokens;
    this.cost = cost;
    if (steps.isNotEmpty) {
      steps.last.done = true;
      if (error != null) steps.last.failed = true;
    }
    if (error == null) step('Done').done = true;
    ended = DateTime.now();
    _notify();
  }

  /// Stops the request; the controller decides what happens next.
  void stop() {
    stopped = true;
    client?.cancel();
    _notify();
  }

  bool _scheduled = false;

  /// Streams fire many times a second: redraw at most once per frame or so.
  void _notify() {
    if (_scheduled) return;
    _scheduled = true;
    Future.delayed(const Duration(milliseconds: 60), () {
      _scheduled = false;
      if (hasListeners) notifyListeners();
    });
  }

  /// Reads the action list from a finished JSON reply.
  void readTools(Map<String, dynamic>? j) {
    if (j == null) return;
    for (final e in (j['events'] as List? ?? const [])) {
      if (e is Map) tools.add(((e['type'] ?? 'event').toString(), e.entries.where((x) => x.key != 'type').map((x) => '${x.key}: ${x.value}').join(', ')));
    }
    for (final key in const ['people', 'relationships', 'characters', 'memory', 'goals', 'consequences', 'inventory_add', 'inventory_remove', 'party_banter', 'dialogue', 'approval', 'money']) {
      final v = j[key];
      if (v is List && v.isNotEmpty) tools.add((key, '${v.length} × ${v.map((x) => x is Map ? (x['name'] ?? x['title'] ?? x['type'] ?? '') : x).join(', ')}'));
      if (v is Map && v.isNotEmpty) tools.add((key, v.entries.map((x) => '${x.key}: ${x.value}').join(', ')));
    }
    for (final key in const ['vitals', 'achievement', 'scene']) {
      final v = j[key];
      if (v is Map && v.isNotEmpty) tools.add((key, v.entries.map((x) => '${x.key}: ${x.value}').join(', ')));
    }
    if (j['health_change'] is num && j['health_change'] != 0) tools.add(('health', '${j['health_change']}'));
    _notify();
  }
}

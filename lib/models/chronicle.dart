import 'character.dart' show newId;

/// Current world state and its permanent, attributed change history.
class WorldFact {
  WorldFact({required this.kind, required this.name, required this.state, this.reputation = 0, this.pinned = false});
  final String kind;
  final String name;
  String state;
  int reputation;
  bool pinned;
  String get key => '${kind.toLowerCase()}:${name.trim().toLowerCase()}';
  Map<String, dynamic> toJson() => {'kind': kind, 'name': name, 'state': state, 'reputation': reputation, 'pinned': pinned};
  factory WorldFact.fromJson(Map<String, dynamic> j) =>
      WorldFact(kind: j['kind'] ?? 'fact', name: j['name'] ?? '', state: j['state'] ?? '', reputation: j['reputation'] ?? 0, pinned: j['pinned'] ?? false);
}

class WorldChange {
  WorldChange({
    String? id,
    required this.kind,
    required this.name,
    required this.before,
    required this.after,
    required this.reason,
    required this.chapter,
    required this.chapterTitle,
    required this.turn,
    this.day = 1,
  }) : id = id ?? newId();
  final String id, kind, name, before, after, reason, chapter, chapterTitle;
  final int turn, day;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'before': before,
    'after': after,
    'reason': reason,
    'chapter': chapter,
    'chapterTitle': chapterTitle,
    'turn': turn,
    'day': day,
  };
  factory WorldChange.fromJson(Map<String, dynamic> j) => WorldChange(
    id: j['id'],
    kind: j['kind'] ?? 'fact',
    name: j['name'] ?? '',
    before: j['before'] ?? '',
    after: j['after'] ?? '',
    reason: j['reason'] ?? '',
    chapter: j['chapter'] ?? '',
    chapterTitle: j['chapterTitle'] ?? '',
    turn: j['turn'] ?? 0,
    day: j['day'] ?? 1,
  );
}

class CompanionArc {
  CompanionArc({
    required this.companionId,
    required this.name,
    required this.title,
    required this.description,
    this.stage = 'revealed',
    this.progress = 0,
    this.outcome = '',
    this.rewarded = false,
  });
  final String companionId, name, title, description;

  /// revealed -> pursuing -> choice -> resolved; failed/departed are terminal.
  String stage;
  int progress;
  String outcome;
  bool rewarded;
  bool get ended => const {'resolved', 'failed', 'departed'}.contains(stage);
  Map<String, dynamic> toJson() => {
    'companion': companionId,
    'name': name,
    'title': title,
    'description': description,
    'stage': stage,
    'progress': progress,
    'outcome': outcome,
    'rewarded': rewarded,
  };
  factory CompanionArc.fromJson(Map<String, dynamic> j) => CompanionArc(
    companionId: j['companion'],
    name: j['name'],
    title: j['title'],
    description: j['description'] ?? '',
    stage: j['stage'] ?? 'revealed',
    progress: j['progress'] ?? 0,
    outcome: j['outcome'] ?? '',
    rewarded: j['rewarded'] ?? false,
  );
}

class Chronicle {
  List<WorldFact> facts = [];
  List<WorldChange> history = [];
  Map<String, CompanionArc> arcs = {};
  int day = 1;
  String lastActivityChapter = '';
  int lastActivityTurn = -1;

  WorldFact? fact(String kind, String name) => facts.where((f) => f.key == '${kind.toLowerCase()}:${name.trim().toLowerCase()}').firstOrNull;

  /// Replaces current state; never appends contradictory states to one fact.
  bool record({
    required String kind,
    required String name,
    required String state,
    required String reason,
    required String chapter,
    required String chapterTitle,
    required int turn,
    int reputation = 0,
  }) {
    if (name.trim().isEmpty || state.trim().isEmpty) return false;
    final existing = fact(kind, name);
    final previous = existing == null ? '' : describe(existing);
    final f = existing ?? WorldFact(kind: kind, name: name.trim(), state: '');
    f.state = state.trim();
    if (kind == 'faction') f.reputation = (f.reputation + reputation.clamp(-20, 20)).clamp(-100, 100);
    if (existing == null) facts.add(f);
    final next = describe(f);
    if (previous == next) return false;
    history.add(
      WorldChange(kind: kind, name: f.name, before: previous, after: next, reason: reason, chapter: chapter, chapterTitle: chapterTitle, turn: turn, day: day),
    );
    return true;
  }

  String describe(WorldFact f) => '${f.state}${f.kind == 'faction' ? ' (reputation ${f.reputation})' : ''}';

  /// Every current state is included: durable facts must not disappear merely
  /// because the recent transcript or summary has been trimmed.
  String prompt({String focus = ''}) {
    if (facts.isEmpty && arcs.isEmpty) return '';
    final sorted = [...facts]..sort((a, b) => (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0));
    final relevant = history.reversed.where((h) => focus.toLowerCase().contains(h.name.toLowerCase())).take(6).toList();
    final changes = {...relevant, ...history.reversed.take(4)}.take(8);
    return [
      'WORLD MEMORY — current authoritative state, day $day. Respect these consequences; old prose may describe superseded states.',
      for (final f in sorted) '- [${f.kind}${f.pinned ? ', pinned' : ''}] ${f.name}: ${describe(f)}',
      if (arcs.isNotEmpty) 'COMPANION ARCS (do not repeat completed rewards or undo choices):',
      for (final a in arcs.values) '- ${a.name}: ${a.title}; ${a.stage}; leads ${a.progress}/2. ${a.description} ${a.outcome}',
      if (changes.isNotEmpty) 'WHY THINGS CHANGED:',
      for (final h in changes) '- ${h.name}: ${h.before.isEmpty ? 'first recorded' : h.before} -> ${h.after}. ${h.reason} [${h.chapterTitle}, turn ${h.turn}]',
    ].join('\n');
  }

  Map<String, dynamic> toJson() => {
    'facts': facts.map((f) => f.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'arcs': arcs.map((k, v) => MapEntry(k, v.toJson())),
    'day': day,
    'lastChapter': lastActivityChapter,
    'lastTurn': lastActivityTurn,
  };
  factory Chronicle.fromJson(Map<String, dynamic> j) => Chronicle()
    ..facts = [for (final f in (j['facts'] as List? ?? [])) WorldFact.fromJson(Map<String, dynamic>.from(f))]
    ..history = [for (final h in (j['history'] as List? ?? [])) WorldChange.fromJson(Map<String, dynamic>.from(h))]
    ..arcs = {for (final e in (j['arcs'] as Map? ?? {}).entries) e.key as String: CompanionArc.fromJson(Map<String, dynamic>.from(e.value))}
    ..day = j['day'] ?? 1
    ..lastActivityChapter = j['lastChapter'] ?? ''
    ..lastActivityTurn = j['lastTurn'] ?? -1;
  Chronicle();
}

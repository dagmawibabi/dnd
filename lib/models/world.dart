import 'adventure.dart';
import 'character.dart' show Character, newId;

/// What the story feed needs from a D&D adventure or a text adventure.
abstract interface class StoryRecord {
  String get id;
  Npc? personNamed(String? name);
  Character? companionNamed(String? name);
  String? get sceneImagePath;
  Map<String, String> get sceneImages;
  Map<String, double> get mediaCosts;
}

/// A notable moment in a relationship ("+10 romance: you kissed her").
class BondMoment {
  BondMoment({required this.text, this.friendship = 0, this.romance = 0, this.turn = 0, DateTime? at}) : at = at ?? DateTime.now();
  final String text;
  final int friendship;
  final int romance;
  final int turn;
  final DateTime at;

  Map<String, dynamic> toJson() => {'t': text, 'f': friendship, 'r': romance, 'n': turn, 'at': at.millisecondsSinceEpoch};
  factory BondMoment.fromJson(Map<String, dynamic> j) => BondMoment(
        text: j['t'] ?? '',
        friendship: j['f'] ?? 0,
        romance: j['r'] ?? 0,
        turn: j['n'] ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// How a character feels about the protagonist: friendship and romance are
/// tracked separately, so a rival can still be attracted to you.
class Bond {
  Bond({this.friendship = 0, this.romance = 0, this.status = '', this.romanceClosed = false, List<BondMoment>? moments}) : moments = moments ?? [];

  /// -100 (enemy) .. 100 (best friend)
  int friendship;

  /// 0 (none) .. 100 (deeply in love)
  int romance;

  /// A label set by the story ("Partners", "Betrothed", "Rivals", "Ex"). Empty uses the derived labels.
  String status;

  /// They turned romance down; the storyteller shouldn't push it.
  bool romanceClosed;
  List<BondMoment> moments;

  String get friendshipLabel => friendship >= 80
      ? 'Best friend'
      : friendship >= 50
          ? 'Close friend'
          : friendship >= 20
              ? 'Friend'
              : friendship > -20
                  ? 'Acquaintance'
                  : friendship > -50
                      ? 'Wary'
                      : friendship > -80
                          ? 'Rival'
                          : 'Enemy';

  String get romanceLabel => romanceClosed
      ? 'Not interested'
      : romance >= 90
          ? 'In love'
          : romance >= 70
              ? 'Smitten'
              : romance >= 45
                  ? 'Courting'
                  : romance >= 20
                      ? 'Flirting'
                      : romance > 0
                          ? 'Curious'
                          : 'None';

  /// The single label shown on cards.
  String get label {
    if (status.isNotEmpty) return status;
    if (romance >= 20 && !romanceClosed) return romanceLabel;
    return friendshipLabel;
  }

  bool get isRomantic => romance >= 20 && !romanceClosed;

  /// One line for AI prompts.
  String describe(String name) => '$name — friendship $friendship/100 ($friendshipLabel)'
      '${romance > 0 || romanceClosed ? ', romance $romance/100 ($romanceLabel)' : ''}'
      '${status.isNotEmpty ? ', status: $status' : ''}'
      '${moments.isEmpty ? '' : '. Recently: ${moments.reversed.take(2).map((m) => m.text).join('; ')}'}';

  Map<String, dynamic> toJson() => {
        'f': friendship,
        'r': romance,
        's': status,
        'rc': romanceClosed,
        'm': (moments.length > 40 ? moments.sublist(moments.length - 40) : moments).map((m) => m.toJson()).toList(),
      };
  factory Bond.fromJson(Map<String, dynamic> j) => Bond(
        friendship: j['f'] ?? 0,
        romance: j['r'] ?? 0,
        status: j['s'] ?? '',
        romanceClosed: j['rc'] ?? false,
        moments: [for (final m in (j['m'] as List? ?? const [])) BondMoment.fromJson(Map<String, dynamic>.from(m))],
      );
}

/// One line of a private conversation with a character.
class ChatLine {
  ChatLine({required this.fromPlayer, required this.text, DateTime? at, this.tokens = 0, this.cost = 0}) : at = at ?? DateTime.now();
  final bool fromPlayer;
  final String text;
  final DateTime at;
  final int tokens;
  final double cost;

  Map<String, dynamic> toJson() => {'p': fromPlayer, 't': text, 'at': at.millisecondsSinceEpoch, if (tokens > 0) 'tok': tokens, if (cost > 0) 'usd': cost};
  factory ChatLine.fromJson(Map<String, dynamic> j) => ChatLine(
        fromPlayer: j['p'] ?? false,
        text: j['t'] ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
        tokens: j['tok'] ?? 0,
        cost: ((j['usd'] ?? 0) as num).toDouble(),
      );
}

/// A generated image or video kept in the story's gallery.
class MediaItem {
  MediaItem({String? id, required this.path, this.video = false, this.kind = 'scene', this.caption = '', this.turn = 0, this.cost = 0, DateTime? at})
      : id = id ?? newId(),
        at = at ?? DateTime.now();
  final String id;
  final String path;
  final bool video;

  /// scene | portrait | effect | map | cover
  final String kind;
  final String caption;
  final int turn;
  final double cost;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 'p': path, if (video) 'v': true, 'k': kind, 'c': caption, 'n': turn, if (cost > 0) 'usd': cost, 'at': at.millisecondsSinceEpoch};
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'],
        path: j['p'] ?? '',
        video: j['v'] ?? false,
        kind: j['k'] ?? 'scene',
        caption: j['c'] ?? '',
        turn: j['n'] ?? 0,
        cost: ((j['usd'] ?? 0) as num).toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// A note the player writes for themselves.
class StoryNote {
  StoryNote({String? id, this.title = '', this.body = '', this.pinned = false, DateTime? created, DateTime? updated})
      : id = id ?? newId(),
        created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now();
  final String id;
  String title;
  String body;
  bool pinned;
  final DateTime created;
  DateTime updated;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
  String get heading {
    if (title.trim().isNotEmpty) return title.trim();
    final first = body.trim().split('\n').first.trim();
    return first.isEmpty ? 'Untitled note' : first;
  }

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'b': body, if (pinned) 'p': true, 'c': created.millisecondsSinceEpoch, 'u': updated.millisecondsSinceEpoch};
  factory StoryNote.fromJson(Map<String, dynamic> j) => StoryNote(
        id: j['id'],
        title: j['t'] ?? '',
        body: j['b'] ?? '',
        pinned: j['p'] ?? false,
        created: DateTime.fromMillisecondsSinceEpoch(j['c'] ?? 0),
        updated: DateTime.fromMillisecondsSinceEpoch(j['u'] ?? 0),
      );
}

/// State every story keeps, whether it is a D&D adventure or a text adventure:
/// relationships, private chats, generated media and character voices.
mixin WorldData {
  Map<String, Bond> bonds = {};
  Map<String, List<ChatLine>> chats = {};
  List<MediaItem> gallery = [];

  /// Person id -> voice name for AI voices.
  Map<String, String> voices = {};

  /// Media path -> cost of generating it (for per-image labels).
  Map<String, double> mediaCosts = {};

  /// The player's own notes.
  List<StoryNote> notes = [];

  /// Seconds spent with this story open.
  int playSeconds = 0;

  Bond bondFor(Npc person) => bonds.putIfAbsent(person.id, () => Bond(friendship: person.disposition.clamp(-100, 100)));

  List<ChatLine> chatWith(String personId) => chats.putIfAbsent(personId, () => []);

  void addMedia(MediaItem m) {
    gallery.removeWhere((g) => g.path == m.path);
    gallery.add(m);
    if (m.cost > 0) mediaCosts[m.path] = m.cost;
    if (gallery.length > 300) gallery.removeAt(0);
  }

  Map<String, dynamic> worldToJson() => {
        'bonds': bonds.map((k, v) => MapEntry(k, v.toJson())),
        'chats': chats.map((k, v) => MapEntry(k, (v.length > 120 ? v.sublist(v.length - 120) : v).map((l) => l.toJson()).toList())),
        'gallery': gallery.map((m) => m.toJson()).toList(),
        'voices': voices,
        'mediaCosts': mediaCosts,
        'playerNotes': notes.where((n) => !n.isEmpty).map((n) => n.toJson()).toList(),
        'play': playSeconds,
      };

  void worldFromJson(Map<String, dynamic> j) {
    bonds = {for (final e in (j['bonds'] as Map? ?? const {}).entries) e.key as String: Bond.fromJson(Map<String, dynamic>.from(e.value))};
    chats = {
      for (final e in (j['chats'] as Map? ?? const {}).entries)
        e.key as String: [for (final l in (e.value as List)) ChatLine.fromJson(Map<String, dynamic>.from(l))],
    };
    gallery = [for (final m in (j['gallery'] as List? ?? const [])) MediaItem.fromJson(Map<String, dynamic>.from(m))];
    voices = Map<String, String>.from(j['voices'] ?? const {});
    mediaCosts = {for (final e in (j['mediaCosts'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toDouble()};
    notes = [for (final n in (j['playerNotes'] as List? ?? const [])) StoryNote.fromJson(Map<String, dynamic>.from(n))];
    playSeconds = (j['play'] as num?)?.toInt() ?? 0;
  }

  /// Relationships for the AI, strongest first.
  String bondsPrompt(Iterable<Npc> people) {
    final lines = [
      for (final p in people)
        if (bonds[p.id] case final b? when b.friendship != 0 || b.romance != 0 || b.status.isNotEmpty || b.romanceClosed) b.describe(p.name),
    ];
    return lines.isEmpty ? '' : 'RELATIONSHIPS (how they feel about the protagonist; keep this consistent):\n- ${lines.join('\n- ')}';
  }
}

/// Applies a relationship change from the story or a conversation and records it.
/// Returns a one-line summary for the log, or null if nothing changed.
String? applyBondChange(WorldData w, Npc person, {int friendship = 0, int romance = 0, String reason = '', String? status, bool? romanceClosed, int turn = 0}) {
  final b = w.bondFor(person);
  final f = friendship.clamp(-20, 20), r = romance.clamp(-25, 25);
  if (f == 0 && r == 0 && (status == null || status == b.status) && (romanceClosed == null || romanceClosed == b.romanceClosed)) return null;
  b.friendship = (b.friendship + f).clamp(-100, 100);
  if (romanceClosed != null) b.romanceClosed = romanceClosed;
  if (!b.romanceClosed) b.romance = (b.romance + r).clamp(0, 100);
  if (status != null) b.status = status.trim();
  person.disposition = b.friendship;
  final parts = [
    if (f != 0) '${f > 0 ? '+' : ''}$f friendship',
    if (r != 0 && !b.romanceClosed) '${r > 0 ? '+' : ''}$r romance',
    if (status != null && status.trim().isNotEmpty) status.trim(),
  ];
  b.moments.add(BondMoment(text: reason.isEmpty ? parts.join(', ') : reason, friendship: f, romance: r, turn: turn));
  return '${person.name}: ${parts.join(', ')}${reason.isEmpty ? '' : ' — $reason'}';
}


/// The memory worth sending this turn: pinned facts, facts about whatever was
/// just mentioned, then the most recent — instead of everything ever recorded.
List<CanonEntry> relevantCanon(List<CanonEntry> canon, String focus, {int max = 20}) {
  final text = focus.toLowerCase();
  bool mentioned(CanonEntry c) {
    final name = c.name.toLowerCase().trim();
    if (name.isEmpty) return false;
    if (text.contains(name)) return true;
    final first = name.split(RegExp(r'\s+')).first;
    return first.length >= 4 && text.contains(first);
  }

  final out = <CanonEntry>[];
  void add(Iterable<CanonEntry> xs) {
    for (final c in xs) {
      if (out.length >= max) return;
      if (!out.contains(c)) out.add(c);
    }
  }

  final recent = canon.toList()..sort((a, b) => b.turn.compareTo(a.turn));
  add(canon.where((c) => c.pinned));
  add(recent.where(mentioned));
  add(recent);
  return out;
}

/// The last few lines of a story, for deciding what memory is relevant.
String recentFocus(List<LogEntry> log, {int entries = 8}) =>
    log.reversed.take(entries).map((e) => '${e.speaker ?? ''} ${e.text}').join(' ');

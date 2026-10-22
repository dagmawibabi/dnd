import 'adventure.dart';
import 'character.dart';
import 'world.dart';

/// One story a companion has been part of: where they came from, or an
/// adventure they joined.
class CompanionTrip {
  CompanionTrip({required this.storyId, required this.title, this.kind = 'tale', this.personId = '', this.name = '', this.origin = false, this.summary = '', DateTime? joined, DateTime? lastSeen})
      : joined = joined ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now();

  final String storyId;
  String title;

  /// 'dnd' or 'tale'.
  final String kind;

  /// Their id among that story's people (bonds, chats and profiles use it).
  String personId;

  /// The name they go by in that story (usually theirs).
  String name;

  /// The story they were first met in.
  final bool origin;

  /// What happened to them there, kept up to date while it's played.
  String summary;
  final DateTime joined;
  DateTime lastSeen;

  Map<String, dynamic> toJson() => {
        'id': storyId,
        't': title,
        'k': kind,
        if (personId.isNotEmpty) 'p': personId,
        if (name.isNotEmpty) 'n': name,
        if (origin) 'o': true,
        if (summary.isNotEmpty) 's': summary,
        'j': joined.millisecondsSinceEpoch,
        'l': lastSeen.millisecondsSinceEpoch,
      };
  factory CompanionTrip.fromJson(Map<String, dynamic> j) => CompanionTrip(
        storyId: j['id'] ?? '',
        title: j['t'] ?? 'A story',
        kind: j['k'] ?? 'tale',
        personId: j['p'] ?? '',
        name: j['n'] ?? '',
        origin: j['o'] ?? false,
        summary: j['s'] ?? '',
        joined: DateTime.fromMillisecondsSinceEpoch(j['j'] ?? 0),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(j['l'] ?? 0),
      );
}

/// A friend who lives outside any one story: they chat with the player,
/// text first, send pictures, recommend adventures and come along on them,
/// keeping their memories from one adventure to the next.
class Companion {
  Companion({
    required this.id,
    required this.name,
    required this.portrait,
    this.kind = 'Human',
    this.gender = '',
    this.pronouns = '',
    this.personality = '',
    this.backstory = '',
    this.appearance = '',
    this.interests = '',
    this.voice = '',
    this.raceId = 'human',
    this.proactive = true,
    this.sendsPictures = true,
    this.speaks = true,
    Bond? bond,
    PersonProfile? profile,
    List<ChatLine>? chat,
    List<CompanionTrip>? trips,
    List<String>? avatars,
    this.sheet,
    this.unread = false,
    DateTime? created,
    this.lastTextAt,
  })  : bond = bond ?? Bond(friendship: 30),
        profile = profile ?? PersonProfile(),
        chat = chat ?? [],
        trips = trips ?? [],
        avatars = avatars ?? [],
        created = created ?? DateTime.now();

  final String id;
  String name;

  /// What they are, in the player's words: "Human", "Robot", "Talking cat".
  String kind;

  /// female, male, nonbinary, or empty.
  String gender;
  String pronouns;
  String personality;
  String backstory;

  /// Physical description, so AI pictures of them stay consistent.
  String appearance;

  /// Things they love talking about.
  String interests;

  /// Their AI voice (empty: picked to match them when they first speak).
  String voice;
  String raceId;
  PortraitSpec portrait;

  /// Every avatar they've had, newest last, to pick from again.
  List<String> avatars;

  /// They may message the player on their own.
  bool proactive;

  /// They may send AI-made pictures in chat.
  bool sendsPictures;

  /// Their replies are read aloud in their voice.
  bool speaks;

  /// How they feel about the player; carried into every adventure.
  Bond bond;

  /// Goals, needs, memories and how they've grown (shared with stories they join).
  PersonProfile profile;
  List<ChatLine> chat;
  List<CompanionTrip> trips;

  /// A D&D character sheet, made the first time they join a D&D adventure.
  Character? sheet;
  bool unread;
  final DateTime created;
  DateTime? lastTextAt;

  CompanionTrip? get origin => trips.where((t) => t.origin).firstOrNull;
  CompanionTrip? tripFor(String storyId) => trips.where((t) => t.storyId == storyId).firstOrNull;

  /// "Talking cat · she/her".
  String get subtitle => [if (kind.isNotEmpty) kind, if (pronouns.isNotEmpty) pronouns].join(' · ');

  /// A stand-in for story tools that expect a story character.
  Npc asNpc({String? name}) => Npc(
        id: 'companion_$id',
        name: name ?? this.name,
        role: kind.toLowerCase() == 'human' ? 'companion' : '$kind companion',
        description: [personality, appearance].where((s) => s.trim().isNotEmpty).join('. '),
        portrait: portrait,
        raceId: raceId,
        gender: gender,
        disposition: bond.friendship,
      );

  /// Who they are, for AI prompts.
  String describe() {
    final b = StringBuffer('${name}${kind.isEmpty || kind.toLowerCase() == 'human' ? '' : ' ($kind)'}');
    if (pronouns.isNotEmpty) b.write(', $pronouns');
    b.write('.');
    if (personality.isNotEmpty) b.write(' Personality: $personality.');
    if (appearance.isNotEmpty) b.write(' Looks: $appearance.');
    if (interests.isNotEmpty) b.write(' Loves: $interests.');
    if (backstory.isNotEmpty) b.write(' Backstory: $backstory');
    return b.toString();
  }

  /// The adventures they've had, for AI prompts.
  String history({int max = 6}) {
    final list = [...trips]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return [
      for (final t in list.take(max))
        '- ${t.title}${t.origin ? ' (where they come from)' : ''}${t.summary.isEmpty ? '' : ': ${t.summary}'}',
    ].join('\n');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        if (gender.isNotEmpty) 'g': gender,
        if (pronouns.isNotEmpty) 'pn': pronouns,
        'pers': personality,
        'story': backstory,
        'look': appearance,
        'int': interests,
        'voice': voice,
        'race': raceId,
        'portrait': portrait.toJson(),
        'avatars': avatars,
        'pro': proactive,
        'pics': sendsPictures,
        'speaks': speaks,
        'bond': bond.toJson(),
        'profile': profile.toJson(),
        'chat': chat.map((c) => c.toJson()).toList(),
        'trips': trips.map((t) => t.toJson()).toList(),
        if (sheet != null) 'sheet': sheet!.toJson(),
        'unread': unread,
        'created': created.millisecondsSinceEpoch,
        if (lastTextAt != null) 'texted': lastTextAt!.millisecondsSinceEpoch,
      };

  factory Companion.fromJson(Map<String, dynamic> j) => Companion(
        id: j['id'] ?? newId(),
        name: j['name'] ?? 'Friend',
        kind: j['kind'] ?? 'Human',
        gender: j['g'] ?? '',
        pronouns: j['pn'] ?? '',
        personality: j['pers'] ?? '',
        backstory: j['story'] ?? '',
        appearance: j['look'] ?? '',
        interests: j['int'] ?? '',
        voice: j['voice'] ?? '',
        raceId: j['race'] ?? 'human',
        portrait: j['portrait'] is Map ? PortraitSpec.fromJson(Map<String, dynamic>.from(j['portrait'])) : PortraitSpec.random('human'),
        avatars: List<String>.from(j['avatars'] ?? const []),
        proactive: j['pro'] ?? true,
        sendsPictures: j['pics'] ?? true,
        speaks: j['speaks'] ?? true,
        bond: j['bond'] is Map ? Bond.fromJson(Map<String, dynamic>.from(j['bond'])) : null,
        profile: j['profile'] is Map ? PersonProfile.fromJson(Map<String, dynamic>.from(j['profile'])) : null,
        chat: [for (final c in (j['chat'] as List? ?? const [])) ChatLine.fromJson(Map<String, dynamic>.from(c))],
        trips: [for (final t in (j['trips'] as List? ?? const [])) CompanionTrip.fromJson(Map<String, dynamic>.from(t))],
        sheet: j['sheet'] is Map ? Character.fromJson(Map<String, dynamic>.from(j['sheet'])) : null,
        unread: j['unread'] ?? false,
        created: DateTime.fromMillisecondsSinceEpoch(j['created'] ?? DateTime.now().millisecondsSinceEpoch),
        lastTextAt: j['texted'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['texted']),
      );
}

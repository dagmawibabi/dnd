import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/presets.dart';
import '../game/story_host.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import '../models/companion.dart';
import '../models/tale.dart';
import '../models/world.dart';
import 'db/database.dart';
import 'story_archive.dart';

/// The player's companions: friends who live outside any one story.
///
/// A companion who joins a story is linked to that story's person (by id).
/// Who they are is copied into the story's profile and bond when they join,
/// and what they learn there flows back on every save, so the next adventure
/// remembers it.
class CompanionStore extends ChangeNotifier {
  CompanionStore._(this._db);

  /// The app's store (an in-memory one until [open] runs, e.g. in tests).
  static CompanionStore instance = CompanionStore._(null);

  static const _key = 'companions.v1';
  final AppDatabase? _db;
  final List<Companion> companions = [];
  Timer? _saveTimer;

  static CompanionStore memory() => CompanionStore._(null);

  static Future<CompanionStore> open(AppDatabase? db) async {
    final s = CompanionStore._(db);
    try {
      final raw = await db?.get(_key);
      if (raw != null) {
        for (final c in jsonDecode(raw) as List) {
          try {
            s.companions.add(Companion.fromJson(Map<String, dynamic>.from(c)));
          } catch (e) {
            debugPrint('Skipping unreadable companion: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Companions could not be loaded: $e');
    }
    return instance = s;
  }

  Companion? byId(String? id) => id == null ? null : companions.where((c) => c.id == id).firstOrNull;

  int get unread => companions.where((c) => c.unread).length;

  void add(Companion c) {
    companions.add(c);
    changed();
  }

  void remove(Companion c) {
    companions.remove(c);
    changed();
  }

  /// Saves soon and tells listeners.
  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final db = _db;
    if (db == null) return;
    try {
      await db.put(_key, jsonEncode([for (final c in companions) c.toJson()]));
    } catch (e) {
      debugPrint('Companions could not be saved: $e');
    }
  }

  // -------------------------------------------------------------- backup

  /// Every companion for a backup file, with their pictures packed in
  /// (paths only work on this device). [read] gives a file's bytes.
  Future<Map<String, dynamic>> backup(Future<Uint8List?> Function(String path) read) async {
    final list = [for (final c in companions) c.toJson()];
    final paths = <String>{
      for (final c in companions) ...[
        if (c.portrait.aiImagePath case final p? when p.isNotEmpty) p,
        ...c.avatars,
        for (final l in c.chat) ...l.images,
      ],
    };
    final assets = <String, dynamic>{};
    final keys = <String, String>{};
    for (final p in paths) {
      final bytes = await read(p);
      if (bytes == null) continue;
      final key = 'asset:${assets.length}';
      final ext = RegExp(r'\.(png|jpg|jpeg|webp|gif)$', caseSensitive: false).firstMatch(p)?.group(1)?.toLowerCase() ?? 'png';
      assets[key] = {'ext': ext, 'bytes': base64Encode(bytes)};
      keys[p] = key;
    }
    return {'list': remapArchive(list, keys), 'assets': assets};
  }

  /// Puts companions from a backup back. [save] stores a picture and returns
  /// its new path. A companion already here is kept if it was used more
  /// recently than the backup's copy. Returns how many were restored.
  Future<int> restore(Map<String, dynamic> j, Future<String> Function(Uint8List bytes, String ext) save) async {
    final paths = <String, String>{};
    for (final e in (j['assets'] as Map? ?? const {}).entries) {
      final a = e.value;
      if (a is! Map || a['bytes'] is! String) continue;
      paths['${e.key}'] = await save(base64Decode(a['bytes'] as String), '${a['ext'] ?? 'png'}');
    }
    var n = 0;
    for (final raw in (j['list'] as List? ?? const [])) {
      if (raw is! Map) continue;
      try {
        final c = Companion.fromJson(Map<String, dynamic>.from(remapArchive(Map<String, dynamic>.from(raw), paths) as Map));
        final here = byId(c.id);
        if (here != null) {
          if (_lastSeen(here).isAfter(_lastSeen(c))) continue;
          companions.remove(here);
        }
        companions.add(c);
        n++;
      } catch (e) {
        debugPrint('Skipping a companion in the backup: $e');
      }
    }
    if (n > 0) changed();
    return n;
  }

  static DateTime _lastSeen(Companion c) => c.chat.isEmpty ? (c.lastTextAt ?? c.created) : c.chat.last.at;

  // ------------------------------------------------------------- stories

  /// Companions taking part in a story, with how they appear in it.
  List<(Companion, CompanionTrip)> inStory(String storyId) => [
        for (final c in companions)
          if (c.tripFor(storyId) case final t?) (c, t),
      ];

  /// The companion a story's person is, if any.
  Companion? companionFor(String storyId, String personId) {
    for (final (c, t) in inStory(storyId)) {
      if (t.personId == personId) return c;
    }
    return null;
  }

  /// Adds [c] to a story as the person [personId] and gives that story
  /// everything they remember from their life so far.
  void join(Companion c, {required String storyId, required String title, required String kind, required String personId, required WorldData world, String? name}) {
    final trip = c.tripFor(storyId);
    if (trip == null) {
      c.trips.add(CompanionTrip(storyId: storyId, title: title, kind: kind, personId: personId, name: name ?? c.name));
    } else {
      trip
        ..personId = personId
        ..name = name ?? c.name
        ..lastSeen = DateTime.now();
    }
    world.profiles[personId] = _profileForStory(c);
    world.bonds[personId] = Bond.fromJson(c.bond.toJson());
    if (c.voice.isNotEmpty) world.voices[name ?? c.name] = c.voice;
    changed();
  }

  /// Their profile as a story should see it: who they are plus where they've been.
  PersonProfile _profileForStory(Companion c) {
    final p = PersonProfile.fromJson(c.profile.toJson());
    final history = c.history();
    p.backstory = [
      if (c.backstory.isNotEmpty) c.backstory,
      if (history.isNotEmpty) 'Adventures together with the player before this one:\n$history',
      'They are the player\'s companion and friend, travelling with them from story to story.',
    ].join('\n');
    if (p.personality.isEmpty) p.personality = c.personality;
    return p;
  }

  /// Copies what companions learned in [host] back to them. Called on save.
  void syncFrom(StoryHost host) {
    final here = inStory(host.storyId);
    if (here.isEmpty) return;
    final world = host.world;
    for (final (c, trip) in here) {
      final id = trip.personId;
      final p = world.profiles[id];
      if (p != null) {
        for (final m in p.memories) {
          final known = c.profile.memories.any((x) => x.id == m.id || x.text.toLowerCase() == m.text.toLowerCase());
          if (!known) {
            c.profile.memories.add(CharacterMemory(id: m.id, text: m.text, turn: m.turn, source: m.source.startsWith('story:') ? m.source : 'story:${host.storyTitle}', pinned: m.pinned, at: m.at));
          }
        }
        while (c.profile.memories.length > 80) {
          final i = c.profile.memories.indexWhere((m) => !m.pinned);
          if (i < 0) break;
          c.profile.memories.removeAt(i);
        }
        // Who they are now: the story's view evolves them.
        if (p.personality.isNotEmpty) c.personality = p.personality;
        if (p.traits.isNotEmpty) c.profile.traits = [...p.traits];
        if (p.goals.isNotEmpty) c.profile.goals = [...p.goals];
        if (p.needs.isNotEmpty) c.profile.needs = [...p.needs];
        for (final g in p.growth) {
          final line = '${host.storyTitle}: $g';
          if (!c.profile.growth.contains(line) && !c.profile.growth.contains(g)) c.profile.growth.add(line);
        }
        if (p.secret.isNotEmpty) c.profile.secret = p.secret;
      }
      final b = world.bonds[id];
      if (b != null) c.bond = Bond.fromJson(b.toJson());
      // Levels, gear and scars carry over to their next D&D adventure.
      if (host.record case final Adventure a) {
        final sheet = a.companions.where((x) => x.id == id).firstOrNull;
        if (sheet != null) c.sheet = Character.fromJson(sheet.toJson());
      }
      final person = host.people.where((n) => n.id == id).firstOrNull;
      if (person != null) {
        final img = person.portrait.aiImagePath;
        if (img != null && img.isNotEmpty && !c.avatars.contains(img)) c.avatars.add(img);
      }
      trip
        ..title = host.storyTitle
        ..lastSeen = DateTime.now()
        ..summary = _summary(host, c, trip);
    }
    changed();
  }

  String _summary(StoryHost host, Companion c, CompanionTrip trip) {
    final story = host.summary.trim();
    final mine = host.world.profiles[trip.personId]?.memories ?? const <CharacterMemory>[];
    final recent = mine.reversed.take(3).map((m) => m.text).join(' ');
    final bond = host.world.bonds[trip.personId];
    final parts = [
      if (story.isNotEmpty) story.length > 420 ? '${story.substring(0, 420)}…' : story,
      if (recent.isNotEmpty) 'What ${c.name} remembers: $recent',
      if (bond != null) 'Ended up: ${bond.label}.',
    ];
    return parts.join(' ');
  }

  /// Takes someone out of a story and makes them a companion, with all they
  /// know from it. They stay linked, so playing on in that story keeps
  /// adding to their memories.
  Companion promote(StoryHost host, Npc npc) {
    final existing = companionFor(host.storyId, npc.id);
    if (existing != null) return existing;
    final world = host.world;
    final from = world.profiles[npc.id] ?? PersonProfile();
    final profile = PersonProfile.fromJson(from.toJson())
      ..memories = [
        for (final m in from.memories)
          CharacterMemory(id: m.id, text: m.text, turn: m.turn, source: 'story:${host.storyTitle}', pinned: m.pinned, at: m.at),
      ];
    profile.remember('I was asked to leave "${host.storyTitle}" behind and become ${host.playerName}\'s companion, a friend who travels with them into other stories.', source: 'companion');
    final chat = world.chats[npc.id] ?? const <ChatLine>[];
    final img = npc.portrait.aiImagePath;
    final c = Companion(
      id: newId(),
      name: npc.name,
      kind: npc.role.toLowerCase().contains('robot') || npc.role.toLowerCase().contains('android') ? 'Robot' : 'Human',
      gender: npc.gender,
      pronouns: switch (npc.gender) { 'female' => 'she/her', 'male' => 'he/him', 'nonbinary' => 'they/them', _ => '' },
      personality: profile.personality.isNotEmpty ? profile.personality : npc.description,
      backstory: [
        if (profile.backstory.isNotEmpty) profile.backstory,
        if (npc.role.isNotEmpty) 'In "${host.storyTitle}" they were ${npc.role}.',
      ].join(' '),
      appearance: npc.description,
      voice: world.voices[npc.name] ?? '',
      raceId: npc.raceId,
      portrait: PortraitSpec.fromJson(npc.portrait.toJson()),
      avatars: [if (img != null && img.isNotEmpty) img],
      bond: Bond.fromJson(world.bondFor(npc).toJson()),
      profile: profile,
      chat: [
        for (final l in chat.length > 30 ? chat.sublist(chat.length - 30) : chat) l,
      ],
      trips: [
        CompanionTrip(storyId: host.storyId, title: host.storyTitle, kind: host.record is Adventure ? 'dnd' : 'tale', personId: npc.id, name: npc.name, origin: true),
      ],
    );
    c.trips.first.summary = _summary(host, c, c.trips.first);
    add(c);
    return c;
  }
}

/// Adds [c] to a saved story (D&D party or text adventure cast) with their
/// memories, and tells the storyteller. Returns why it couldn't, or null.
/// The caller saves the story.
String? bringCompanionTo(StoryRecord r, Companion c) {
  final store = CompanionStore.instance;
  void tell(List<String> notes, String text) {
    notes.add(text);
    if (notes.length > 20) notes.removeAt(0);
  }

  if (r is Adventure) {
    if (r.companions.any((x) => x.id == 'companion_${c.id}')) return '${c.name} is already in your party';
    if (r.companions.length >= 3) return 'Your party is full (3 companions)';
    final sheet = companionSheet(c, level: r.hero.level);
    if (sheet.xp < r.hero.xp) sheet.xp = r.hero.xp;
    r.companions.add(sheet);
    store.join(c, storyId: r.id, title: r.title, kind: 'dnd', personId: sheet.id, world: r);
    tell(r.pendingNotes, "${c.name}, ${r.hero.name}'s companion and friend, has joined the party and travels with them from now on. Give them a natural entrance.");
    return null;
  }
  final t = r as Tale;
  final npc = c.asNpc();
  if (c.tripFor(t.id) != null && t.npcs.any((n) => n.id == npc.id)) return '${c.name} is already here';
  t.npcs
    ..removeWhere((n) => n.id == npc.id)
    ..add(npc);
  store.join(c, storyId: t.id, title: t.title, kind: 'tale', personId: npc.id, world: t);
  t.remember('npc', npc.name, "The player's companion and friend, travelling with them. ${c.describe()}");
  final who = t.protagonist == 'You' ? 'the player' : t.protagonist;
  tell(t.pendingNotes, "${c.name}, $who's companion, has joined the story and travels with them from now on. Give them a natural entrance and let them take part.");
  return null;
}

/// [c] as a D&D party member: their saved sheet, or a new one built around
/// who they are. Levelled up to [level] when they'd lag behind the hero.
Character companionSheet(Companion c, {int level = 1}) {
  final saved = c.sheet;
  final Character sheet;
  if (saved != null) {
    sheet = saved.clone();
  } else {
    final k = c.kind.toLowerCase();
    final race = k.contains('elf') ? 'elf' : k.contains('dwarf') ? 'dwarf' : k.contains('halfling') ? 'halfling' : k.contains('dragon') ? 'dragonborn' : k.contains('tiefling') || k.contains('demon') ? 'tiefling' : 'human';
    final matching = presets.where((p) => p.raceId == race).toList();
    final pool = matching.isEmpty ? presets : matching;
    sheet = pool[c.id.hashCode.abs() % pool.length].create();
  }
  sheet
    ..id = 'companion_${c.id}'
    ..name = c.name
    ..isCompanion = true
    ..personality = c.personality
    ..backstory = [
      c.backstory,
      if (c.history().isNotEmpty) 'Adventures with the player before this one:\n${c.history()}',
      if (c.kind.isNotEmpty && c.kind.toLowerCase() != 'human') 'They are a ${c.kind}.',
    ].where((s) => s.isNotEmpty).join('\n')
    ..appearance = c.appearance
    ..voice = c.voice
    ..loyalty = (50 + c.bond.friendship ~/ 2).clamp(0, 100);
  if (c.pronouns.isNotEmpty) sheet.pronouns = c.pronouns;
  sheet.portrait = PortraitSpec.fromJson(c.portrait.toJson());
  while (sheet.level < level) {
    final cls = sheet.classLevels.keys.first;
    sheet.levelUp(cls);
    sheet.autoProgress(cls);
  }
  return sheet;
}

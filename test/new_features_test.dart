import 'dart:convert';
import 'dart:math' as math;

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/adventure_controller.dart';
import 'package:dnd/game/approaches.dart';
import 'package:dnd/game/campaign_world.dart';
import 'package:dnd/game/chapter_recap.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/character.dart';
import 'package:dnd/models/chronicle.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/audio/synth.dart';
import 'package:dnd/services/export.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/studio.dart';
import 'package:dnd/services/voice_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Always rolls under any chance, so approaches that qualify always happen.
class _Sure implements math.Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

Adventure _withCompanion() {
  final a = Adventure(id: 'ch1', title: 'Chapter One', premise: '', hero: presets.first.create(), engine: StoryEngine.offline, turns: 10);
  final c = presets.last.create()
    ..name = 'Mira Vale'
    ..isCompanion = true;
  a.companions.add(c);
  return a;
}

Future<AdventureController> _controller(Adventure a) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs)
    ..musicEnabled = false
    ..ambienceEnabled = false
    ..sfxEnabled = false
    ..haptics = false;
  final audio = AudioService(settings);
  final store = GameStore.memory();
  final ctl = AdventureController(adventure: a, settings: settings, store: store, audio: audio, images: ImageService(settings, ModelCatalog(prefs)));
  addTearDown(() async {
    await ctl.flush();
    ctl.dispose();
    audio.dispose();
    store.dispose();
  });
  return ctl;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('companions start conversations', () {
    test('a personal-quest decision brings the companion to the player once', () async {
      final a = _withCompanion();
      final c = a.companions.single;
      final ctl = await _controller(a);
      a.chronicle.arcs[c.id] = CompanionArc(companionId: c.id, name: c.name, title: 'The Broken Banner', description: 'Recover the standard.', stage: 'choice', progress: 2);
      final pick = pickApproach(ctl, close: {c.id}, rng: _Sure());
      expect(pick, isNotNull);
      expect(pick!.person.id, c.id);
      expect(pick.label, contains('decision'));

      final line = await deliverApproach(ctl, pick);
      expect(line!.opener, isNotEmpty);
      expect(a.unreadChats, contains(c.id));
      expect(a.chats[c.id]!.last.fromPlayer, isFalse);
      expect(latestApproach(ctl)!.$1.id, c.id);

      // Unread, then on cooldown, then the topic is spent.
      expect(pickApproach(ctl, close: {c.id}, rng: _Sure()), isNull);
      readChat(ctl, ctl.people.firstWhere((p) => p.id == c.id));
      expect(a.unreadChats, isEmpty);
      expect(pickApproach(ctl, close: {c.id}, rng: _Sure()), isNull, reason: 'cooldown');
      a.turns += approachCooldown;
      expect(pickApproach(ctl, close: {c.id}, rng: _Sure())?.topic, isNot(pick.topic));
    });

    test('strangers do not approach; warm friends and big world changes do', () async {
      final a = _withCompanion();
      final stranger = Npc(id: 'n1', name: 'Old Bram', portrait: PortraitSpec.random('human', seed: 1));
      a.npcs.add(stranger);
      final ctl = await _controller(a);
      expect(pickApproach(ctl, rng: _Sure()), isNull);
      a.bonds[stranger.id] = Bond(friendship: 60, moments: [BondMoment(text: 'You saved his mill.', friendship: 15, turn: a.turns)]);
      final pick = pickApproach(ctl, rng: _Sure());
      expect(pick?.person.id, stranger.id);

      a.chronicle.arcs.clear();
      rememberWorld(a, 'place', 'Redhollow', 'Burned', 'Mira Vale set the granary alight.');
      final c = a.companions.single;
      a.approachTopics[pick!.topic] = a.turns;
      final world = pickApproach(ctl, close: {c.id}, rng: _Sure());
      expect(world?.topic, startsWith('world:'));
    });

    test('approach state and openers survive save and load', () {
      final a = _withCompanion();
      a.unreadChats.add('x');
      a.approachTopics['bond:x:Friend'] = 3;
      a.lastApproachTurn = 3;
      a.seenRecaps.add(a.id);
      a.chatWith('x').add(ChatLine(fromPlayer: false, text: 'Walk with me?', opener: 'How they feel about you'));
      final back = Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.unreadChats, {'x'});
      expect(back.approachTopics['bond:x:Friend'], 3);
      expect(back.lastApproachTurn, 3);
      expect(back.seenRecaps, {a.id});
      expect(back.chats['x']!.single.opener, 'How they feel about you');
    });

    test('a new chapter resets the approach cooldown', () {
      final a = _withCompanion()..lastApproachTurn = 9;
      final next = Adventure(id: 'ch2', title: 'Two', premise: '', hero: a.hero, engine: StoryEngine.offline);
      carryChapterWorld(a, next);
      expect(next.lastApproachTurn, -1);
    });
  });

  test('chapter recap lists only this chapter\'s changes and relationship shifts', () {
    final a = _withCompanion();
    a.chronicle.history.add(WorldChange(kind: 'place', name: 'Old Keep', before: '', after: 'Abandoned', reason: 'Long ago', chapter: 'ch0', chapterTitle: 'Zero', turn: 1));
    rememberWorld(a, 'faction', 'Villagers', 'Grateful', 'You protected their homes.', reputation: 15);
    rememberWorld(a, 'place', 'Redhollow', 'Safe again', 'You drove out the raiders.');
    final p = Npc(id: 'n1', name: 'Old Bram', portrait: PortraitSpec.random('human', seed: 1));
    a.npcs.add(p);
    applyBondChange(a, p, friendship: 12, reason: 'Shared a meal', turn: 4);
    a.quests.add(Quest(id: 'q', title: 'Clear the road', status: QuestStatus.completed));
    final c = summarizeChapter(a, a.people);
    expect(c.changes.map((x) => x.name), ['Villagers', 'Redhollow']);
    expect(c.reputation, {'Villagers': 15});
    expect(c.bonds.single.friendship, 12);
    expect(c.completed.single.title, 'Clear the road');
    expect(c.toText(), contains('Redhollow'));
    expect(c.byKind.keys, ['faction', 'place']);
  });

  test('map pins and place notes are saved with the map', () {
    final m = MapState(kind: MapKind.overworld, seed: 3, name: 'Coast', locations: [MapLocation(name: 'Ford', note: 'Toll keeper lies')], pins: [MapPin(x: 0.25, y: 0.75, label: 'Cache', note: 'Under the oak', icon: 2, color: 3)]);
    final back = MapState.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
    expect(back.locations.single.note, 'Toll keeper lies');
    expect(back.pins.single.label, 'Cache');
    expect(back.pins.single.x, 0.25);
    expect(back.pins.single.color, 3);
  });

  group('studio audio', () {
    test('every game theme renders from its spec, and specs round-trip', () {
      for (final t in ['tavern', 'dungeon']) {
        final spec = MusicSpec.forTheme(t);
        expect(MusicSpec.fromJson(jsonDecode(jsonEncode(spec.toJson())) as Map<String, dynamic>).key, spec.key);
        expect(renderMusic(t).length, renderMusicSpec(spec).length);
      }
      final custom = MusicSpec.forTheme('calm').copy({'style': 'driving', 'lead': 'pluck', 'drums': true, 'beats': 16});
      expect(decodeWav(renderMusicSpec(custom)).length, greaterThan(kSampleRate));
    });

    test('designed sounds render, repitch and survive save and load', () {
      for (final k in SfxSpec.kinds) {
        final wav = renderSfxSpec(SfxSpec.random(k, math.Random(1)));
        expect(decodeWav(wav), isNotEmpty, reason: k);
      }
      final wav = renderSfx('coin');
      final up = repitchWav(wav, 2);
      expect(decodeWav(up).length, closeTo(decodeWav(wav).length / 2, 2));

      final studio = StudioStore.memory();
      studio.update((s) {
        s.sounds.add(StudioSound(id: 's1', name: 'Zap', spec: SfxSpec.random('laser', math.Random(2))));
        s.sounds.add(StudioSound(id: 's2', name: 'Recorded clang', file: '/music/clang.mp3'));
        s.sfxSlots['hit'] = ['s1', 's2'];
        s.sfxSlots['miss'] = ['gone'];
        s.tweaks['dice'] = const SfxTweak(volume: 0.5, pitch: 1.5);
        s.tracks.add(StudioTrack(id: 't1', name: 'Theme', spec: MusicSpec.forTheme('town')));
        s.tracks.add(StudioTrack(id: 't2', name: 'My song', file: '/music/song.mp3'));
        s.musicSlots['combat'] = ['t1', 't2'];
        s.ambienceSlots['rain'] = ['t2'];
        s.images.add(StudioImage(id: 'i1', name: 'Woods', path: '/pics/woods.jpg'));
        s.images.add(StudioImage(id: 'i2', name: 'Pines', path: '/pics/pines.jpg'));
        s.sceneImages['forest'] = ['i1', 'i2'];
        s.mapImages['dungeon'] = ['i2'];
      });
      expect(studio.sfxSlots.containsKey('miss'), isFalse, reason: 'slots to deleted sounds are dropped');
      final back = StudioStore.memory()..restore(jsonDecode(jsonEncode(studio.toJson())) as Map<String, dynamic>);
      expect(back.tracksFor('combat').map((t) => t.name), ['Theme', 'My song'], reason: 'a theme can have a playlist');
      expect(back.ambienceFor('rain')?.isFile, isTrue);
      expect({for (var i = 0; i < 40; i++) back.soundFor('hit', math.Random(i))?.id}, {'s1', 's2'}, reason: 'variations are picked at random');
      expect(back.tweakFor('dice').pitch, 1.5);
      expect(back.sceneImageFor('forest', 0), isNot(back.sceneImageFor('forest', 1)), reason: 'scenes spread across your pictures');
      expect(back.sceneImageFor('forest', 7), back.sceneImageFor('forest', 7), reason: 'the same scene keeps its picture');
      expect(back.mapImageFor('dungeon', 3), '/pics/pines.jpg');
      expect(back.sceneImageFor('tavern', 1), isNull);
      studio.update((s) => s.images.removeWhere((i) => i.id == 'i2'));
      expect(studio.mapImages.containsKey('dungeon'), isFalse);
      studio.update((s) => s.tracks.clear());
      expect(studio.trackFor('combat'), isNull);

      // Saves from before playlists stored one id per slot.
      final old = StudioStore.memory()..fromJson({'tracks': [StudioTrack(id: 't9', name: 'Old', spec: MusicSpec.forTheme('calm')).toJson()], 'musicSlots': {'calm': 't9'}});
      expect(old.trackFor('calm')?.name, 'Old');
    });
  });

  test('exports include map notes, pins and conversations companions started', () async {
    final a = _withCompanion();
    a.map = MapState(kind: MapKind.overworld, seed: 1, name: 'The Vale', locations: [MapLocation(name: 'Ford', note: 'Toll keeper lies')], pins: [MapPin(x: 0.1, y: 0.2, label: 'Cache', note: 'Under the oak')]);
    a.chatWith(a.companions.single.id).add(ChatLine(fromPlayer: false, text: 'Walk with me?', opener: 'A quiet word at camp'));
    final d = exportDocFromAdventure(a);
    for (final out in [storyMarkdown(d), storyText(d), await storyHtml(d)]) {
      expect(out, contains('Map notes: The Vale'));
      expect(out, contains('Toll keeper lies'));
      expect(out, contains('Under the oak'));
      expect(out, contains('came to you: A quiet word at camp'));
    }
  });

  test('dictation is added after what was typed', () {
    expect(joinDictation('', ' open the door '), 'open the door');
    expect(joinDictation('I draw my sword', 'and charge'), 'I draw my sword and charge');
    expect(joinDictation('hello ', ''), 'hello');
  });
}

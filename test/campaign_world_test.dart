import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/adventure_controller.dart';
import 'package:dnd/game/campaign_world.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/campaign.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/dungeon_master.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/ui/screens/story/world_memory_screen.dart';
import 'package:dnd/ui/screens/adventure/camp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Adventure adventure(String id) => Adventure(id: id, title: 'Chapter $id', premise: '', hero: presets.first.create(), engine: StoryEngine.offline);
Adventure reload(Adventure a) => Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);

Future<AdventureController> controller(Adventure a) async {
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

  test('chapters retain relationships and all private chat history without shared objects', () {
    final a = adventure('one');
    final c = presets.last.create()..loyalty = 65;
    a.companions.add(c);
    a.bonds[c.id] = Bond(friendship: 70, romance: 50, romanceClosed: true, moments: [BondMoment(text: 'A promise')]);
    a.chats[c.id] = List.generate(150, (i) => ChatLine(fromPlayer: i.isEven, text: 'Message $i'));
    a.voices[c.id] = 'voice-one';
    a.notes.add(StoryNote(title: 'Remember', body: 'The secret'));
    rememberWorld(a, 'place', 'Bridge', 'Destroyed', 'We burned it.');
    seedCompanionArcs(a);
    final next = adventure('two')..companions.add(c.clone());
    carryChapterWorld(a, next);
    final restored = reload(next);
    expect(restored.chats[c.id], hasLength(150));
    expect(restored.bonds[c.id]!.romanceClosed, isTrue);
    expect(restored.voices[c.id], 'voice-one');
    expect(restored.notes.single.body, 'The secret');
    expect(restored.chronicle.arcs[c.id]!.title, c.personalQuest);
    next.bonds[c.id]!.friendship = -10;
    next.chats[c.id]!.clear();
    next.chronicle.facts.first.state = 'Rebuilt';
    next.quests.first.description = 'Changed';
    expect(a.bonds[c.id]!.friendship, 70);
    expect(a.chats[c.id], hasLength(150));
    expect(a.chronicle.fact('place', 'Bridge')!.state, 'Destroyed');
    expect(a.quests.first.description, isNot('Changed'));
  });

  test('current world replaces stale facts while preserving attributed history and AI context', () {
    final a = adventure('one');
    rememberWorld(a, 'place', 'Bridge', 'Guarded by raiders', 'We arrived.');
    a.turns = 4;
    rememberWorld(a, 'place', 'Bridge', 'Safe for travelers', 'We defeated the raiders.');
    rememberWorld(a, 'faction', 'Villagers', 'Grateful', 'We protected them.', reputation: 200);
    final back = reload(a);
    expect(back.chronicle.fact('place', 'Bridge')!.state, 'Safe for travelers');
    expect(back.chronicle.history[1].before, 'Guarded by raiders');
    expect(back.chronicle.history[1].turn, 4);
    expect(back.chronicle.fact('faction', 'Villagers')!.reputation, 20);
    expect(dmStateBlock(back), contains('We defeated the raiders.'));
    expect(dmStateBlock(back), contains('Safe for travelers'));
    expect(rememberWorld(back, 'place', 'Bridge', 'Safe for travelers', 'Duplicate'), isFalse);
  });

  test('older chapters cannot overwrite the current campaign and backups retain world state', () async {
    final store = GameStore.memory();
    final camp = Campaign(id: 'campaign', name: 'Saga', heroId: 'hero', chapters: ['one', 'two']);
    await store.saveCampaign(camp);
    final old = adventure('one')..campaignId = camp.id;
    final latest = adventure('two')..campaignId = camp.id;
    rememberWorld(old, 'place', 'Bridge', 'Occupied', 'Arrival');
    rememberWorld(latest, 'place', 'Bridge', 'Liberated', 'Victory');
    await store.saveAdventure(latest);
    await store.saveAdventure(old);
    expect(camp.chronicle.facts.single.state, 'Liberated');
    final backup = jsonDecode(jsonEncode(await store.backup())) as Map<String, dynamic>;
    final restored = GameStore.memory();
    await restored.restore(backup);
    expect(restored.campaign(camp.id)!.chronicle.facts.single.state, 'Liberated');
    store.dispose();
    restored.dispose();
  });

  test('downtime limits survive reopening and unaffordable activities do not consume a day', () async {
    final a = adventure('one')..scene.location = 'town';
    a.hero.gold = 0;
    final ctl = await controller(a);
    expect(ctl.downtime('craft'), contains('25 gp'));
    expect(ctl.canDowntime, isTrue);
    expect(a.chronicle.day, 1);
    ctl.downtime('train');
    expect(a.hero.inspiration, isTrue);
    expect(ctl.canDowntime, isFalse);
    final reopened = await controller(reload(a));
    expect(reopened.canDowntime, isFalse);
    reopened.adventure.turns++;
    expect(reopened.canDowntime, isTrue);
    expect(a.chronicle.history.last.reason, contains('train'));
  });

  test('camp bonds unlock an arc; quest completion enables a single lasting decision', () async {
    final a = adventure('one');
    final c = presets.last.create()..loyalty = 55;
    a.companions.add(c);
    final ctl = await controller(a);
    ctl.spendTimeWith(c);
    final arc = a.chronicle.arcs[c.id]!;
    expect(arc.stage, 'revealed');
    final q = a.quests.single..status = QuestStatus.completed;
    syncCompanionQuest(a, q);
    expect(arc.stage, 'choice');
    ctl.resolveCompanionArc(c, fulfill: false);
    expect(arc.stage, 'resolved');
    expect(a.hero.inspiration, isTrue);
    final loyalty = c.loyalty;
    final historyCount = a.chronicle.history.length;
    ctl.resolveCompanionArc(c, fulfill: true);
    expect(c.loyalty, loyalty);
    expect(a.chronicle.history.length, historyCount);
    final back = reload(a);
    expect(back.chronicle.arcs[c.id]!.outcome, contains('new path'));
    expect(dmStateBlock(back), contains('new path'));
  });

  test('departed companions retain identity, conversations and arc outcome', () {
    final a = adventure('one');
    final c = presets.last.create()..loyalty = 65;
    a.companions.add(c);
    seedCompanionArcs(a);
    a.chats[c.id] = [ChatLine(fromPlayer: true, text: 'Goodbye')];
    rememberDeparture(a, c, 'A broken promise');
    a.companions.remove(c);
    final back = reload(a);
    expect(back.personNamed(c.name)!.id, c.id);
    expect(back.chats[c.id]!.single.text, 'Goodbye');
    expect(back.chronicle.arcs[c.id]!.stage, 'departed');
  });

  testWidgets('world browser searches facts and displays the cause and chapter', (tester) async {
    final a = adventure('one');
    rememberWorld(a, 'place', 'Bridge', 'Safe for travelers', 'We defeated the raiders.');
    rememberWorld(a, 'place', 'Tower', 'Ruined', 'A storm.');
    await tester.pumpWidget(MaterialApp(home: WorldMemoryScreen(world: () => a.chronicle)));
    await tester.enterText(find.byType(TextField), 'Bridge');
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Bridge'), findsOneWidget);
    expect(find.text('Tower'), findsNothing);
    await tester.tap(find.text('See what changed'));
    await tester.pump();
    expect(find.text('Because: We defeated the raiders.'), findsOneWidget);
    expect(find.textContaining('Chapter one · turn 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camp shows available activities and companion arcs on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final a = adventure('one')..scene.location = 'town';
    a.companions.add(presets.last.create()..loyalty = 65);
    final ctl = await controller(a);
    await tester.pumpWidget(MaterialApp(home: CampScreen(controller: ctl)));
    expect(find.text('Camp & companions'), findsOneWidget);
    expect(find.text('Brew a healing potion'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Spend time · +5 loyalty'), 250);
    expect(find.text('Follow a lead · DC 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/campaign_world.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/campaign.dart';
import 'package:dnd/models/chronicle.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/export.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/story_archive.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dnd/ui/screens/character/character_sheet.dart';
import 'package:dnd/ui/widgets/character_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Adventure fixture() {
  final a = Adventure(
    id: 'chapter-one',
    title: 'The Saved Village',
    premise: 'Choices leave a mark.',
    hero: presets.first.create(),
    engine: StoryEngine.offline,
    turns: 8,
  );
  final c = presets.last.create()
    ..name = 'Mira'
    ..isCompanion = true
    ..loyalty = 85
    ..inspiration = true
    ..personalQuest = 'The Broken Banner';
  a.companions.add(c);
  a.log.add(LogEntry(kind: LogKind.narration, text: 'The gates reopened after the raiders fled.'));
  rememberWorld(a, 'place', 'Redhollow', 'Occupied', 'The raiders arrived.');
  rememberWorld(a, 'place', 'Redhollow', 'Safe again', 'You drove out the raiders.');
  rememberWorld(a, 'faction', 'Villagers', 'Grateful', 'You protected their homes.', reputation: 15);
  a.chronicle.facts.first.pinned = true;
  a.chronicle.arcs[c.id] = CompanionArc(
    companionId: c.id,
    name: c.name,
    title: c.personalQuest,
    description: 'Recover the lost standard.',
    stage: 'resolved',
    progress: 2,
    outcome: 'Mira chose a new path.',
    rewarded: true,
  );
  a.chronicle.day = 4;
  a.chronicle.lastActivityChapter = a.id;
  a.chronicle.lastActivityTurn = a.turns;
  a.bonds[c.id] = Bond(friendship: 80, romance: 20, romanceClosed: true, moments: [BondMoment(text: 'You kept your promise.', turn: 3)]);
  a.chats[c.id] = [ChatLine(fromPlayer: true, text: 'I remember the banner.'), ChatLine(fromPlayer: false, text: 'And I remember your help.')];
  a.voices[c.id] = 'Mira voice';
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Markdown, plain text and HTML include the full new world sections', () async {
    final a = fixture();
    final d = exportDocFromAdventure(a);
    final html = await storyHtml(d);
    for (final result in [storyMarkdown(d), storyText(d), html]) {
      for (final expected in [
        'World memory',
        'World consequences',
        'Companion stories',
        'Safe again',
        'You drove out the raiders.',
        'reputation 15',
        'Mira chose a new path.',
        'World day: 4',
        'Activity used this turn: yes',
        'Rewards granted: yes',
        'You kept your promise.',
        'And I remember your help.',
        'Romance declined: yes',
      ]) {
        expect(result, contains(expected));
      }
    }
    a.chronicle.facts.first.state = '<script>alert("world")</script>';
    final escaped = await storyHtml(exportDocFromAdventure(a));
    expect(escaped, contains('&lt;script&gt;'));
    expect(escaped, isNot(contains('<script>alert')));
  });

  test('tale reading exports and imports retain memory and spent downtime', () {
    final t = Tale.create(title: 'A tale', genre: 'noir', engine: TaleEngine.ai);
    t.worldFromJson(fixture().worldToJson());
    t.chronicle.lastActivityChapter = t.id;
    final saved = restoreStoryArchive(decodeStoryArchive(jsonEncode(storyArchive(t)))) as Tale;
    expect(saved.chronicle.lastActivityChapter, saved.id);
    expect(saved.chronicle.history.last.reason, 'You protected their homes.');
    expect(storyText(exportDocFromTale(saved)), contains('Mira chose a new path.'));
  });

  test('playable and portable saves preserve all state while remapping the activity owner', () async {
    final a = fixture();
    for (final archive in [storyArchive(a), await portableStoryArchive(a, (_) async => null)]) {
      final back = restoreStoryArchive(decodeStoryArchive(jsonEncode(archive))) as Adventure;
      expect(back.id, isNot(a.id));
      expect(back.chronicle.lastActivityChapter, back.id);
      expect(back.chronicle.lastActivityTurn, back.turns);
      expect(back.chronicle.history.first.chapter, a.id, reason: 'Historical provenance stays intact.');
      expect(back.chronicle.arcs.values.single.rewarded, isTrue);
      expect(back.bonds.values.single.romanceClosed, isTrue);
      expect(back.chats.values.single.last.text, 'And I remember your help.');
      expect(back.voices.values.single, 'Mira voice');
    }
  });

  test('library backups preserve campaign facts, arcs, conversations and camp state', () async {
    final store = GameStore.memory();
    final a = fixture()..campaignId = 'campaign';
    await store.saveCampaign(Campaign(id: 'campaign', name: 'Saga', heroId: a.hero.id, chapters: [a.id]));
    await store.saveAdventure(a);
    final restored = GameStore.memory();
    await restored.restore(jsonDecode(jsonEncode(await store.backup())) as Map<String, dynamic>);
    expect(restored.campaign('campaign')!.worldToJson(), store.campaign('campaign')!.worldToJson());
    expect((await restored.loadAdventure(a.id))!.chronicle.lastActivityTurn, 8);
    store.dispose();
    restored.dispose();
  });

  testWidgets('PDF exports long world history and chat across pages', (tester) async {
    final a = fixture();
    a.chats.values.single.add(ChatLine(fromPlayer: false, text: List.filled(100, 'We remember what happened at Redhollow.').join(' ')));
    for (var i = 0; i < 25; i++) {
      rememberWorld(a, 'place', 'Outpost $i', 'Restored and open to travelers.', 'The party repaired the gate and secured the road.');
    }
    final bytes = await tester.runAsync(() => storyPdf(exportDocFromAdventure(a)));
    expect(utf8.decode(bytes!.take(5).toList()), '%PDF-');
    if (Platform.environment['VERIFY_EXPORT_PDF'] == '1') {
      await tester.runAsync(() async {
        await Directory('build/export-verification').create(recursive: true);
        await File('build/export-verification/world.pdf').writeAsBytes(bytes);
      });
    }
  });

  testWidgets('all character card styles show companion camp rewards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final images = ImageService(SettingsController(prefs), ModelCatalog(prefs));
    final c = fixture().companions.single;
    for (final text in [characterCardText(c), characterSheetText(c)]) {
      expect(text, contains('Inspiration: available'));
      expect(text, contains('Loyalty: 85'));
      expect(text, contains('Personal quest: The Broken Banner'));
    }
    for (final style in CardStyle.values) {
      await tester.pumpWidget(
        ChangeNotifierProvider<ImageService>.value(
          value: images,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: CharacterCard(character: c, style: style),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Inspired'), findsWidgets);
      expect(find.textContaining('The Broken Banner'), findsWidgets);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });
}

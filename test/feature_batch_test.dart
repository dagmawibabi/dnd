import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/character.dart' show PortraitSpec;
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/game/character_life.dart';
import 'package:dnd/game/money.dart';
import 'package:dnd/services/ai/tale_narrator.dart';
import 'package:dnd/services/narrator.dart';
import 'package:dnd/services/story_archive.dart';
import 'package:flutter_test/flutter_test.dart';

Npc npc(String name, {String description = ''}) => Npc(
  id: name.toLowerCase(),
  name: name,
  description: description,
  portrait: PortraitSpec.random('human', seed: 1),
);

void main() {
  test('genders come from the story or are guessed from descriptions', () {
    expect(normalizeGender('Female'), 'female');
    expect(normalizeGender('she/her'), 'female');
    expect(normalizeGender('he/him'), 'male');
    expect(normalizeGender('they/them'), 'nonbinary');
    expect(
      npc(
        'Mira',
        description: 'A sharp-eyed smuggler. She never smiles.',
      ).gender,
      'female',
    );
    expect(
      npc('Bram', description: 'An old innkeeper; his beard is white.').gender,
      'male',
    );
    expect(npc('Ash', description: 'A shadow in the alley.').gender, '');
    final n = npc('Kit')..gender = 'woman';
    expect(Npc.fromJson(n.toJson()).gender, 'female');
  });

  test('enemies are labeled as enemies, not acquaintances', () {
    final t = Tale.create(title: 't', genre: 'fantasy', engine: TaleEngine.ai);
    final villain = npc('Vor');
    t.npcs.add(villain);
    expect(
      introduceCharacter(t, villain, {
        'stance': 'enemy',
        'backstory': 'Exiled lord.',
        'goal': 'Take the throne',
      }),
      isTrue,
    );
    final b = t.bondFor(villain);
    expect(b.label, 'Enemy');
    expect(b.isHostile, isTrue);
    expect(t.profileOf(villain).backstory, 'Exiled lord.');
    expect(t.profileOf(villain).goals, ['Take the throne']);
    expect(Bond(friendship: 0).label, 'Stranger');
    expect(Bond(friendship: -50).friendshipLabel, 'Hostile');
    expect(Bond(friendship: -70).friendshipLabel, 'Enemy');
    // Big moments can move a relationship further than small talk.
    final friend = npc('Ana');
    t.npcs.add(friend);
    applyBondChange(t, friend, friendship: 30, reason: 'Saved her life');
    expect(t.bondFor(friend).friendship, 30);
  });

  test('characters grow and remember, and profiles survive saving', () {
    final t = Tale.create(title: 't', genre: 'fantasy', engine: TaleEngine.ai);
    final p = npc('Jun');
    t.npcs.add(p);
    t.profileOf(p).personality = 'guarded';
    final changes = growCharacter(t, p, {
      'personality': 'trusting',
      'memory': 'You shared your bread.',
      'growth': 'Learned to trust you',
    }, 7);
    expect(changes, isNotEmpty);
    final back = Tale.fromJson(t.toJson());
    final pr = back.profileOf(back.npcs.single);
    expect(pr.personality, 'trusting');
    expect(pr.memories.single.text, 'You shared your bread.');
    expect(pr.growth.length, 2);
    expect(pr.prompt(), contains('trusting'));
  });

  test(
    'condition changes accept both directions of words and wear down over time',
    () {
      final v = Vitals();
      final notes = v.apply({
        'tiredness': 30,
        'hunger': 20,
        'sickness': 10,
        'morale': 5,
        'type': 'vitals',
      });
      expect(v.energy, 60);
      expect(v.fullness, 65);
      expect(v.wellness, 90);
      expect(notes, hasLength(4));
      v.tick();
      expect(v.energy, 58);
      v.rest();
      expect(v.energy, 100);
      expect(Vitals.fromJson(v.toJson()).fullness, v.fullness);
      expect(Vitals(energy: 10).prompt(), contains('exhausted'));
    },
  );

  test('the narrator splits long passages at sentences, starting short', () {
    final text = List.generate(
      12,
      (i) => 'Sentence number $i goes on for a while to fill space.',
    ).join(' ');
    final parts = Narrator.chunk(text);
    expect(parts.length, greaterThan(2));
    expect(parts.first.length, lessThanOrEqualTo(200));
    expect(parts.join(' '), text);
    expect(Narrator.chunk('Short.'), ['Short.']);
    expect(Narrator.clean('**Hello,** [go](x)  there.'), 'Hello, go there.');
    expect(Narrator.voiceTraits['alloy'], contains('neutral'));
  });

  test('science-fiction money uses a dollar symbol', () {
    final t = Tale.create(title: 't', genre: 'scifi', engine: TaleEngine.ai);
    expect(money(t, 25), r'$25');
  });

  test('scene art is reused for the same kind of place', () {
    final log = [
      LogEntry(
        kind: LogKind.system,
        text: 'Old Forest',
        meta: {
          'scene': SceneInfo(
            title: 'Old Forest',
            location: 'forest',
            time: 'day',
          ).toJson(),
        },
      ),
    ];
    final art = {'Old Forest': 'forest.png'};
    expect(
      reusableSceneArt(
        log,
        art,
        SceneInfo(title: 'Deeper Woods', location: 'forest', time: 'dusk'),
      ),
      'forest.png',
    );
    expect(
      reusableSceneArt(
        log,
        art,
        SceneInfo(title: 'Night Woods', location: 'forest', time: 'night'),
      ),
      isNull,
    );
    expect(
      reusableSceneArt(
        log,
        art,
        SceneInfo(title: 'A Cave', location: 'cave', time: 'day'),
      ),
      isNull,
    );
  });

  test('quests keep their history', () {
    final q =
        Quest(id: 'q', title: 'Find the ledger', startTurn: 2, giver: 'Mira')
          ..log('Mira asked for help.', 2)
          ..log('Mira asked for help.', 3)
          ..log('The ledger is at the docks.', 5);
    final back = Quest.fromJson(q.toJson());
    expect(back.updates, hasLength(2));
    expect(back.giver, 'Mira');
    expect(back.startTurn, 2);
  });

  test('readable items, writing kinds and AI tool notes', () {
    expect(isReadableItem('Torn letter'), isTrue);
    expect(isReadableItem('Captain\'s log'), isTrue);
    expect(isReadableItem('Silver key'), isFalse);
    expect(writingKind('Old diary'), 'journal');
    final t = Tale.create(title: 't', genre: 'noir', engine: TaleEngine.ai)
      ..writings['torn letter'] = ItemWriting(
        title: 'Torn letter',
        text: 'Meet me at midnight.',
      )
      ..narratorTone = 'Terse'
      ..wrapUpTurn = 3
      ..addAiNote(
        AiNote(
          kind: 'lore',
          title: 'Lore',
          question: 'Who is Vor?',
          text: 'An exile.',
        ),
      );
    final back = Tale.fromJson(t.toJson());
    expect(back.writings['torn letter']!.text, 'Meet me at midnight.');
    expect(back.aiNotes.single.question, 'Who is Vor?');
    expect(
      back.directionPrompt(4),
      allOf(contains('Terse'), contains('FINISH SOON')),
    );
  });

  test('the text narrator reads characters, consequences, condition and readable items', () {
    final turn = TaleTurn.parse(
      '{"narration": "You wake.", "people": [{"name": "Vor", "gender": "male", "stance": "enemy", "backstory": "Exiled."}], "characters": [{"name": "Vor", "goal": "Revenge"}], "consequences": [{"kind": "place", "name": "Mill", "state": "Burned", "reason": "You lit it"}], "vitals": {"hunger": 10}, "inventory_add": ["Rope", {"name": "Note", "text": "Run."}], "achievement": {"title": "Firestarter", "description": "Burned the mill"}}',
    );
    expect(turn.people.single['stance'], 'enemy');
    expect(turn.characters.single['goal'], 'Revenge');
    expect(turn.consequences.single['state'], 'Burned');
    expect(turn.vitals['hunger'], 10);
    expect(turn.add, ['Rope', 'Note']);
    expect(turn.writings['Note'], 'Run.');
    expect(turn.achievement!['title'], 'Firestarter');
  });

  test(
    'a shared adventure carries its world, tone and cast but no progress',
    () async {
      final t =
          Tale.create(
              title: 'Ash Road',
              genre: 'postapoc',
              engine: TaleEngine.ai,
              premise: 'Walk west.',
            )
            ..narratorTone = 'Grim'
            ..turns = 12;
      t.npcs.add(npc('Vor', description: 'A raider king.'));
      t.log.add(LogEntry(kind: LogKind.narration, text: 'Dust.'));
      final shared = await storyTemplate(t, (_) async => null);
      final s = shared['state'] as Map<String, dynamic>;
      expect(shared['format'], 'template');
      expect(s['premise'], 'Walk west.');
      expect(s['tone'], 'Grim');
      expect(s.containsKey('log'), isFalse);
      expect(templateWorldNotes(s), contains('Vor'));
    },
  );
}

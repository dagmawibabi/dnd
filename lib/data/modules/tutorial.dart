import '../../game/module_engine.dart';
import '../../models/adventure.dart';

/// A guided four-minute first scene that teaches the app.
const tutorialModule = AdventureModule(
  id: 'tutorial',
  title: 'First Steps: The Lantern Cellar',
  tagline: 'A four-minute guided adventure that teaches you how to play.',
  description:
      'Your first night at the Lantern Inn goes wrong when something starts scratching beneath the floorboards. A short, guided adventure that shows you choices, dice, combat, a companion with a story of their own, a world that remembers what you do, camp, the map and the journal, with a friendly innkeeper explaining as you go.',
  levels: '1',
  minutes: 4,
  tone: 'Lighthearted',
  setting: 'High fantasy',
  coverLoc: 'tavern',
  coverTime: 'night',
  mapKind: MapKind.dungeon,
  mapName: 'The Lantern Inn',
  locations: ['Common Room', 'Cellar Stairs', 'The Cellar', 'Old Tunnel'],
  tags: ['Tutorial', 'Short'],
  start: 'inn',
  nodes: {
    'inn': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'night',
      mood: 'festive',
      mapLoc: 'Common Room',
      speaker: 'Hester',
      text:
          'Rain hammers the windows of the Lantern Inn. The innkeeper, Hester, sets a bowl of stew in front of you, then freezes. Something is scratching under the floorboards.\n\n"Rats," she says. "Big ones. Again." She looks you up and down. "First time? Pick one of the options below. Some are safe, some need a dice roll. Or type, or tap the microphone and say what you do."',
      events: [
        {'type': 'quest', 'title': 'Rats in the Cellar', 'description': 'Help Hester deal with whatever is scratching in her cellar.', 'status': 'new'},
        {'type': 'npc', 'name': 'Hester', 'role': 'innkeeper', 'race': 'dwarf', 'disposition': 40, 'description': 'Kind, loud and tired of rats.'},
      ],
      choices: [
        ModChoice('"Of course I\'ll help."', type: ChoiceType.dialogue, go: 'inn_help'),
        ModChoice('"What\'s in it for me?"', type: ChoiceType.dialogue, go: 'inn_pay'),
      ],
    ),
    'inn_help': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'night',
      mood: 'calm',
      speaker: 'Hester',
      text:
          '"Good soul." Hester pours you a drink. People remember how you treat them: her friendship just went up.\n\n"See that option with a skill and a number? That\'s an ability check. Roll a d20, add your bonus, beat the number. Try listening at the cellar door."',
      events: [
        {'type': 'relationship', 'name': 'Hester', 'friendship': 5, 'reason': 'You offered to help for nothing'},
      ],
      choices: [
        ModChoice('Listen at the cellar door', type: ChoiceType.explore, check: 'Perception', dc: 8, ok: 'listen_ok', fail: 'listen_fail'),
      ],
    ),
    'inn_pay': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'night',
      mood: 'calm',
      speaker: 'Hester',
      text:
          'Hester laughs, a little less warmly. "Free stew for a week, and whatever you find down there." People remember how you treat them.\n\n"See an option with a skill and a number? That\'s a check. Roll a d20, add your bonus, beat the number. Try listening at the cellar door."',
      events: [
        {'type': 'disposition', 'name': 'Hester', 'change': -5, 'reason': 'You haggled before helping'},
      ],
      choices: [
        ModChoice('Listen at the cellar door', type: ChoiceType.explore, check: 'Perception', dc: 8, ok: 'listen_ok', fail: 'listen_fail'),
      ],
    ),
    'listen_ok': ModNode(
      title: 'Cellar Stairs',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Cellar Stairs',
      sets: ['listened'],
      text:
          'Success! Squeaking, two voices of it, and something heavier dragging behind.\n\nHester\'s nephew Pip, a halfling with quick fingers, grabs a lantern. "I\'m coming. Don\'t argue." Companions fight beside you, have stories of their own, and sometimes come to you to talk.\n\nTip: tap any roll to see how it was worked out.',
      events: [
        {'type': 'xp', 'amount': 25},
        {
          'type': 'companion_join',
          'name': 'Pip',
          'race': 'halfling',
          'class': 'rogue',
          'personality': 'Quick, nosy and braver than he looks.',
          'personal_quest': 'Pip\'s Lost Brother',
          'quest_description': 'Pip\'s older brother Tam went into the old smugglers\' tunnels a year ago and never came back.',
        },
      ],
      choices: [
        ModChoice('Head down the stairs', type: ChoiceType.explore, go: 'cellar'),
      ],
    ),
    'listen_fail': ModNode(
      title: 'Cellar Stairs',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Cellar Stairs',
      text:
          'Only rain and your own heartbeat. A failed check isn\'t the end: the story just turns.\n\nHester\'s nephew Pip, a halfling with quick fingers, grabs a lantern. "I\'m coming. Don\'t argue." Companions fight beside you, have stories of their own, and sometimes come to you to talk.\n\nTip: tap any roll to see how it was worked out.',
      events: [
        {
          'type': 'companion_join',
          'name': 'Pip',
          'race': 'halfling',
          'class': 'rogue',
          'personality': 'Quick, nosy and braver than he looks.',
          'personal_quest': 'Pip\'s Lost Brother',
          'quest_description': 'Pip\'s older brother Tam went into the old smugglers\' tunnels a year ago and never came back.',
        },
      ],
      choices: [
        ModChoice('Head down the stairs', type: ChoiceType.explore, go: 'cellar'),
      ],
    ),
    'cellar': ModNode(
      title: 'The Cellar',
      loc: 'cave',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Cellar',
      text:
          'Barrels, cobwebs and two rats the size of dogs gnawing on a cheese wheel. They turn, hiss and charge.\n\nThis is combat. On your turn, pick a target and choose Attack, Spell, Potion or Ability. Pip and the rats act on their own. Bring the rats to zero HP to win.',
      combat: ModCombat([
        {'name': 'Giant Rat', 'monster': 'giant_rat', 'count': 2, 'hp': 5},
      ], win: 'after_fight', lose: 'after_fight'),
    ),
    'after_fight': ModNode(
      title: 'The Cellar',
      loc: 'cave',
      time: 'night',
      mood: 'calm',
      speaker: 'Hester',
      text:
          'The rats lie still. Hester peers down the stairs. "Ha! Knew you had it in you." Behind the cheese wheel, a loose brick hides a little bundle.\n\nThe world remembers what you do: the inn and its regulars just changed because of you (lightbulb → World memory).\n\nPip wants a private word. Tap Reply on the banner above your input.',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'potion_healing', 'name': 'Potion of Healing'},
        {'type': 'gold', 'amount': 10},
        {'type': 'world', 'kind': 'place', 'name': 'The Lantern Inn', 'state': 'Free of giant rats', 'reason': 'You cleared the cellar on your first night.'},
        {'type': 'world', 'kind': 'faction', 'name': 'Lantern Inn regulars', 'state': 'They toast your name', 'reputation': 10, 'reason': 'Word spread that you saved the cellar.'},
        {'type': 'relationship', 'name': 'Hester', 'friendship': 10, 'reason': 'You saved her cellar'},
        {
          'type': 'approach',
          'name': 'Pip',
          'label': 'About his lost brother',
          'text': '*Pip tugs your sleeve, out of Hester\'s earshot.* You were good back there. Can I tell you something? My brother Tam went into the old tunnels under this town and never came back. If we ever find a way in... will you help me look?',
        },
      ],
      choices: [
        ModChoice('Investigate the loose brick', type: ChoiceType.explore, check: 'Investigation', dc: 10, ok: 'tunnel', fail: 'tunnel'),
        ModChoice('Rest at camp first', type: ChoiceType.rest, go: 'rest'),
      ],
    ),
    'rest': ModNode(
      title: 'The Cellar',
      loc: 'cave',
      time: 'night',
      mood: 'calm',
      text:
          'You sit on a barrel and catch your breath. Short rests heal with hit dice; long rests restore everything but need rations.\n\nBetween scenes, lightbulb → Camp & companions lets you train, craft, research or spend time with Pip. Each costs a day, and quiet moments are when companions open up.',
      events: [
        {'type': 'rest', 'kind': 'short'},
      ],
      choices: [
        ModChoice('Investigate the loose brick', type: ChoiceType.explore, go: 'tunnel'),
      ],
    ),
    'tunnel': ModNode(
      title: 'Old Tunnel',
      loc: 'dungeon',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'Old Tunnel',
      text:
          'The wall swings open onto an old smugglers\' tunnel. Chalk arrows point into the dark, and a faded note reads: "The Lantern\'s treasure lies where the light first shone." Pip goes very still. "These are Tam\'s arrows."\n\nTip: the map pins places you\'ve been (long-press it to drop your own). The journal keeps quests, people and memory.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Smuggler\'s Note', 'description': '"The Lantern\'s treasure lies where the light first shone."'},
        {'type': 'world', 'kind': 'clue', 'name': 'Smugglers\' Tunnel', 'state': 'Found behind the cellar wall, marked with Tam\'s chalk arrows', 'reason': 'You searched behind the loose brick.'},
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Follow Tam\'s arrows a little way with Pip', type: ChoiceType.explore, go: 'end_follow'),
        ModChoice('Seal it for now and tell Hester', type: ChoiceType.dialogue, go: 'end_tell'),
      ],
    ),
    'end_follow': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Hester',
      text:
          'The arrows end at a fresh scratch: TAM WAS HERE, and a date from last month. Pip laughs and cries at once. Back upstairs, Hester claps you on the back. "Rats gone, a tunnel, and good news for my nephew. Not bad for a first night."\n\nNext: What changed shows how this night left its mark on the inn, Hester and Pip. Then start a real adventure from the home screen.',
      events: [
        {'type': 'world', 'kind': 'place', 'name': 'Smugglers\' Tunnel', 'state': 'Explored a little way: Tam passed through only last month', 'reason': 'You followed the chalk arrows with Pip.'},
        {'type': 'relationship', 'name': 'Pip', 'friendship': 15, 'reason': 'You followed his brother\'s trail with him'},
        {'type': 'quest', 'title': 'Rats in the Cellar', 'status': 'completed'},
        {'type': 'xp', 'amount': 100},
      ],
    ),
    'end_tell': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Hester',
      text:
          'You wedge the wall shut and climb back up. Hester listens, then hugs Pip hard. "We\'ll find him properly, with supplies and daylight." Pip sulks, but nods. "Rats gone, a tunnel and a plan. Not bad for a first night."\n\nNext: What changed shows how this night left its mark on the inn, Hester and Pip. Then start a real adventure from the home screen.',
      events: [
        {'type': 'world', 'kind': 'place', 'name': 'Smugglers\' Tunnel', 'state': 'Sealed until a proper search', 'reason': 'You told Hester instead of going in.'},
        {'type': 'relationship', 'name': 'Hester', 'friendship': 10, 'reason': 'You kept her nephew safe'},
        {'type': 'relationship', 'name': 'Pip', 'friendship': -5, 'reason': 'You held him back from his brother\'s trail'},
        {'type': 'quest', 'title': 'Rats in the Cellar', 'status': 'completed'},
        {'type': 'xp', 'amount': 100},
      ],
    ),
  },
);

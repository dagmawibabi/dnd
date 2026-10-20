import '../../game/module_engine.dart';
import '../../models/adventure.dart';

/// A guided three-minute first scene that teaches the app.
const tutorialModule = AdventureModule(
  id: 'tutorial',
  title: 'First Steps: The Lantern Cellar',
  tagline: 'A three-minute guided adventure that teaches you how to play.',
  description:
      'Your first night at the Lantern Inn goes wrong when something starts scratching beneath the floorboards. A short, guided adventure that shows you choices, dice, combat, loot, the map and the journal, with a friendly innkeeper explaining as you go.',
  levels: '1',
  minutes: 3,
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
          'Rain hammers the windows of the Lantern Inn. The innkeeper, Hester, sets a bowl of stew in front of you, then freezes. Something is scratching under the floorboards.\n\n"Rats," she says. "Big ones. Again." She looks you up and down. "You look like you can swing a sword. First time? Here\'s how it works: pick one of the options below. Some are safe, some need a dice roll."',
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
          '"Good soul." Hester pours you a drink. "Now, see that option with a skill and a number on it? That\'s an ability check. You roll a d20, add your bonus, and try to beat the number. Tap it, then tap the die to roll. Try listening at the cellar door."',
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
          'Hester laughs. "Free stew for a week, and whatever you find down there." She leans in. "Now: see an option with a skill and a number? That\'s a check. Roll a d20, add your bonus, beat the number. Tap it and roll the die. Try listening at the cellar door."',
      events: [
        {'type': 'disposition', 'name': 'Hester', 'change': -5},
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
          'Success! You hear squeaking, two voices of it, and something heavier dragging behind. Rats, then, and maybe more.\n\nTip: tap any roll in the story to see exactly how it was calculated. The map icon at the top shows where you are.',
      events: [
        {'type': 'xp', 'amount': 25},
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
          'You hear only rain and your own heartbeat. Failing a check isn\'t the end: the story just takes a different turn.\n\nTip: tap any roll in the story to see exactly how it was calculated. The map icon at the top shows where you are.',
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
          'Barrels, cobwebs and two rats the size of dogs gnawing on a cheese wheel. They turn, hiss and charge.\n\nThis is combat. On your turn, pick a target and choose Attack, Spell, Potion or Ability. Enemies take their turns automatically. Bring their HP to zero to win.',
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
          'The rats lie still. Hester peers down the stairs. "Ha! Knew you had it in you." Behind the cheese wheel, a loose brick hides a little bundle.\n\nYou earned experience, which levels you up over time. Loot goes to your inventory on the character sheet.',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'potion_healing', 'name': 'Potion of Healing'},
        {'type': 'gold', 'amount': 10},
      ],
      choices: [
        ModChoice('Investigate the loose brick further', type: ChoiceType.explore, check: 'Investigation', dc: 10, ok: 'tunnel', fail: 'tunnel'),
        ModChoice('Take a short rest first', type: ChoiceType.rest, go: 'rest'),
      ],
    ),
    'rest': ModNode(
      title: 'The Cellar',
      loc: 'cave',
      time: 'night',
      mood: 'calm',
      text:
          'You sit on a barrel and catch your breath. Short rests spend hit dice to heal; long rests restore everything but need rations and time. You can rest from the Party sheet too.',
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
          'The brick wall swings open onto an old smugglers\' tunnel. Chalk arrows point into the dark, and a faded note reads: "The Lantern\'s treasure lies where the light first shone."\n\nTip: the journal (book icon) keeps your quests, the people you\'ve met, and everything the story remembers. When you\'re unsure what happens next, the ? button asks the oracle a yes/no question.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Smuggler\'s Note', 'description': '"The Lantern\'s treasure lies where the light first shone."'},
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Follow the chalk arrows', type: ChoiceType.explore, go: 'end'),
        ModChoice('Go back and tell Hester', type: ChoiceType.dialogue, go: 'end'),
      ],
    ),
    'end': ModNode(
      title: 'The Lantern Inn',
      loc: 'tavern',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Hester',
      text:
          'Hester claps you on the back so hard your teeth rattle. "Rats gone, a secret tunnel and a treasure riddle. Not bad for your first night." She tucks the note behind the bar. "Whenever you\'re ready for a real adventure, there\'s a whole world out there."\n\nYou\'re ready. Start a new adventure from the home screen: handcrafted stories, endless generated quests, or an AI Dungeon Master.',
      events: [
        {'type': 'quest', 'title': 'Rats in the Cellar', 'status': 'completed'},
        {'type': 'xp', 'amount': 100},
      ],
    ),
  },
);

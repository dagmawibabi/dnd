import 'dart:math' as math;

import '../data/names.dart';
import '../data/presets.dart';
import '../data/srd.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import 'dice.dart';
import 'story.dart';

/// Procedural, fully offline story engine. Generates a quest outline of
/// linked scenes and resolves choices, checks and outcomes from text banks.
class OfflineEngine {
  OfflineEngine(this.a);
  final Adventure a;

  Map<String, dynamic> get st => a.offline;
  Rng get _r => Rng(stableHash('${st['seed']}-${st['i']}-${a.turns}'));
  List<Map<String, dynamic>> get nodes => (st['nodes'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get node => nodes[(st['i'] as int).clamp(0, nodes.length - 1)];
  String get hero => a.hero.name;
  int get lvl => a.hero.level;

  // ------------------------------------------------------------------ setup

  static const _villains = [
    {'name': 'Morvath the Hollow', 'title': 'a lich-touched necromancer', 'monster': 'lich_apprentice', 'minion': 'skeleton', 'env': 'crypt'},
    {'name': 'Skarnak Gorefang', 'title': 'a brutal orc warlord', 'monster': 'orc', 'minion': 'orc', 'env': 'ruins'},
    {'name': 'The Weaver Below', 'title': 'a monstrous spider-matriarch', 'monster': 'giant_spider', 'minion': 'giant_spider', 'env': 'cave'},
    {'name': 'Mother Gloam', 'title': 'a hag who trades in stolen names', 'monster': 'dark_acolyte', 'minion': 'zombie', 'env': 'swamp'},
    {'name': 'Captain Vey Rask', 'title': 'a ruthless bandit lord', 'monster': 'bandit', 'minion': 'bandit', 'env': 'road'},
    {'name': 'Ashkarr the Ember-Wyrm', 'title': 'a young red dragon', 'monster': 'young_dragon', 'minion': 'kobold', 'env': 'mountain'},
    {'name': 'Brother Malric', 'title': 'the high priest of a forbidden cult', 'monster': 'dark_acolyte', 'minion': 'cultist', 'env': 'temple'},
    {'name': 'The Iron Warden', 'title': 'an ancient animated guardian gone mad', 'monster': 'animated_armor', 'minion': 'animated_armor', 'env': 'tower'},
    {'name': 'Grukk the Unkillable', 'title': 'a regenerating troll', 'monster': 'troll', 'minion': 'goblin', 'env': 'swamp'},
    {'name': 'Lady Seren Nightbloom', 'title': 'a wraith of a betrayed queen', 'monster': 'wraith', 'minion': 'shadow', 'env': 'castle'},
  ];

  static const _macguffins = [
    'the Sunstone of Eldermere', 'a stolen child of the miller', 'the Bell of Drowned Saints', 'the last seed of the World Oak', 'the Crown of Ash',
    'a map to the Lost Vault', 'the town\'s missing well-water', 'the Heartshard Gem', 'a captured caravan', 'the Book of Unspoken Names',
  ];

  static const _hooks = [
    'A desperate {patron} begs you to recover {mac}, taken by {villain}, {vtitle}.',
    'Rumors in {town} speak of {villain}, {vtitle}, who has seized {mac}. {patron} offers a reward to anyone brave enough.',
    'You arrive in {town} to find it in mourning. {villain}, {vtitle}, has taken {mac}, and {patron} needs a hero.',
    'A dying messenger presses a letter into your hand: "{villain} has {mac}. Find {patron} in {town}."',
  ];

  static Map<String, dynamic> createState(int seed, Character hero, {int chapter = 1}) {
    final r = Rng(seed);
    final villain = Map<String, dynamic>.from(r.pick(_villains));
    final lvl = hero.level;
    if (lvl < 5 && villain['monster'] == 'young_dragon') {
      villain['monster'] = 'ogre';
      villain['title'] = 'a dragon-blooded ogre chieftain';
    }
    if (lvl < 3 && ['troll', 'wraith'].contains(villain['monster'])) villain['monster'] = 'bugbear';
    final town = randomPlace(rng: r);
    final region = randomPlace(rng: r);
    final patron = '${randomNpcName(rng: r)} the ${randomNpcRole(rng: r)}';
    final mac = r.pick(_macguffins);
    final lairEnv = villain['env'] as String;
    final wildEnvs = ['forest', 'road', 'plains', 'mountain', 'swamp', 'coast', 'ruins'];
    final middleTypes = r.shuffled(['encounter', 'hazard', 'social', 'treasure', 'riddle', 'lore', 'encounter', 'social', 'hazard']);
    final nodes = <Map<String, dynamic>>[];
    nodes.add({'t': 'town', 'env': 'town', 'name': town});
    final wildCount = 3 + r.nextInt(2);
    for (var i = 0; i < wildCount; i++) {
      final env = r.pick(wildEnvs);
      nodes.add({'t': middleTypes[i], 'env': env, 'name': _placeName(env, r)});
      if (i == 1) nodes.add({'t': 'rest', 'env': env, 'name': 'Campsite near ${_placeName(env, r)}'});
    }
    final lairName = _lairName(lairEnv, r);
    nodes.add({'t': 'lore', 'env': lairEnv, 'name': '$lairName — Threshold', 'lair': true});
    for (var i = 0; i < 2; i++) {
      nodes.add({'t': middleTypes[wildCount + i], 'env': lairEnv, 'name': '$lairName — ${r.pick(_roomNames)}', 'lair': true});
    }
    nodes.add({'t': 'boss', 'env': lairEnv, 'name': '$lairName — Inner Sanctum', 'lair': true});
    nodes.add({'t': 'epilogue', 'env': 'town', 'name': town});
    // assign monsters
    for (final n in nodes) {
      if (n['t'] == 'encounter') {
        final pool = monsters.where((m) => m.environments.contains(n['env']) && m.cr <= math.max(0.5, lvl * 0.75)).toList();
        final m = pool.isEmpty ? monsterById(villain['minion'])! : r.pick(pool);
        n['m'] = m.id;
        n['c'] = _countFor(m.cr, lvl, r);
      }
    }
    return {
      'seed': seed,
      'nodes': nodes,
      'i': 0,
      'phase': 'enter',
      'villain': villain,
      'mac': mac,
      'patron': patron,
      'town': town,
      'region': region,
      'lair': lairName,
      'weakness': false,
      'chapter': chapter,
      'flags': <String, dynamic>{},
    };
  }

  static int _countFor(double cr, int lvl, Rng r) {
    final budget = lvl * 1.0;
    final per = math.max(0.125, cr);
    final n = (budget / per).floor().clamp(1, 4);
    return math.max(1, n - (r.chance(0.3) ? 1 : 0));
  }

  static const _roomNames = ['Hall of Bones', 'Flooded Gallery', 'Collapsed Shrine', 'Guard Barracks', 'Echoing Vault', 'Fungal Grotto', 'Chained Library', 'Forge of Cinders', 'Mirror Chamber', 'Ossuary Stair'];

  static String _placeName(String env, Rng r) {
    final p = randomPlace(rng: r);
    return switch (env) {
      'forest' => '$p Wood',
      'road' => 'The $p Road',
      'plains' => '$p Downs',
      'mountain' => '$p Pass',
      'swamp' => '$p Fen',
      'coast' => '$p Strand',
      'ruins' => 'Ruins of $p',
      _ => p,
    };
  }

  static String _lairName(String env, Rng r) {
    final p = randomPlace(rng: r);
    return switch (env) {
      'crypt' => 'Crypt of $p',
      'cave' => '$p Caverns',
      'swamp' => 'Sunken Hall of $p',
      'road' => 'Fort $p',
      'mountain' => '$p Peak Lair',
      'temple' => 'Temple of the $p Eye',
      'tower' => 'Tower of $p',
      'castle' => 'Castle $p',
      'ruins' => '$p Citadel',
      _ => '$p Deeps',
    };
  }

  // ------------------------------------------------------------ text banks

  static const _envOpen = {
    'town': ['Smoke curls from crooked chimneys over {name}.', 'The cobbled streets of {name} bustle with wary townsfolk.', 'Lanterns sway above the muddy square of {name}.'],
    'forest': ['Ancient trees crowd the path through {name}, their branches knitting out the sky.', 'Moss-draped oaks creak overhead in {name}. Somewhere, a bird stops singing.', 'Shafts of pale light fall through the canopy of {name}.'],
    'road': ['{name} winds between rolling hills, rutted by old wagon wheels.', 'A lonely milestone marks {name}; crows watch from a gibbet nearby.'],
    'plains': ['Tall grass ripples like a golden sea across {name}.', 'Wind howls over {name}, carrying the scent of rain.'],
    'mountain': ['The path up {name} narrows to a ledge above a dizzying drop.', 'Snow flurries whip across {name}; the air is thin and bitter.'],
    'swamp': ['Fog clings to the black water of {name}; things move beneath it.', 'Your boots sink into the reeking mud of {name}. Fireflies — or something else — glimmer.'],
    'coast': ['Waves crash against the rocks of {name}; gulls scream overhead.', 'Wrecked hulls litter {name}, half-buried in grey sand.'],
    'ruins': ['Broken pillars rise from the earth at {name}, carved with forgotten faces.', 'Ivy strangles the toppled walls of {name}.'],
    'crypt': ['Cold air seeps from {name}. Names of the dead line the walls.', 'Candles that no one lit flicker in {name}.'],
    'cave': ['Water drips in the dark of {name}; your light barely reaches the walls.', 'The tunnel of {name} breathes a warm, rank wind.'],
    'temple': ['Defaced idols stare down in {name}; the altar is stained dark.', 'Chanting echoes faintly through {name}, though no one is in sight.'],
    'tower': ['A spiral stair climbs through {name}, humming with residual magic.', 'Arcane sigils pulse faintly along the walls of {name}.'],
    'castle': ['Tattered banners hang in the great hall of {name}.', 'Moonlight falls through shattered windows in {name}.'],
  };

  static const _sensory = [
    'The smell of wet stone hangs in the air.', 'Somewhere far off, something howls.', 'Your torchlight trembles though there is no wind.',
    'A chill runs down your spine.', 'You hear the distant drip of water.', 'Old bones crunch underfoot.', 'The silence feels like held breath.',
    'Tiny footprints cross the dust ahead of you.', 'A faint scent of smoke drifts by.', 'Something glints in the corner of your eye.',
  ];

  static const _riddles = [
    {'q': 'I have cities but no houses, forests but no trees, and water but no fish. What am I?', 'a': 'A map', 'w': ['A dream', 'A painting', 'A mirror']},
    {'q': 'The more of me you take, the more you leave behind. What am I?', 'a': 'Footsteps', 'w': ['Time', 'Breath', 'Coins']},
    {'q': 'I speak without a mouth and hear without ears. I have no body, but come alive with wind.', 'a': 'An echo', 'w': ['A ghost', 'A flute', 'A rumor']},
    {'q': 'What has roots as nobody sees, is taller than trees, up, up it goes, and yet never grows?', 'a': 'A mountain', 'w': ['A tower', 'A shadow', 'The sky']},
    {'q': 'Alive without breath, as cold as death; never thirsty, ever drinking, all in mail never clinking.', 'a': 'A fish', 'w': ['A knight\'s ghost', 'A river', 'A snake']},
    {'q': 'I am always hungry, I must always be fed. The finger I touch will soon turn red.', 'a': 'Fire', 'w': ['A wolf', 'Greed', 'A blade']},
    {'q': 'What can run but never walks, has a mouth but never talks, has a bed but never sleeps?', 'a': 'A river', 'w': ['A road', 'A clock', 'A wind']},
    {'q': 'The one who makes it sells it. The one who buys it never uses it. The one who uses it never knows.', 'a': 'A coffin', 'w': ['A crown', 'A potion', 'A shroud']},
    {'q': 'What has keys but opens no locks, space but no room, and you can enter but not go in?', 'a': 'A keyboard of an organ', 'w': ['A prison', 'A chest', 'A map']},
    {'q': 'Voiceless it cries, wingless flutters, toothless bites, mouthless mutters.', 'a': 'The wind', 'w': ['A bat', 'A spirit', 'Fear']},
  ];

  static const _hazards = [
    {'name': 'a collapsing floor', 'desc': 'The flagstones ahead groan and crack — a pit yawns beneath.', 'checks': [['DEX', 'Acrobatics', 13, 'Leap across the cracking stones'], ['INT', 'Investigation', 12, 'Search for the safe path'], ['STR', 'Athletics', 14, 'Brace and climb along the wall']], 'dmg': '2d6', 'type': 'bludgeoning'},
    {'name': 'a poison dart corridor', 'desc': 'Tiny holes pock the walls of a narrow corridor. A skeleton lies riddled with darts.', 'checks': [['DEX', 'Acrobatics', 14, 'Dash through, ducking and weaving'], ['INT', 'Investigation', 13, 'Find and jam the pressure plates'], ['DEX', 'Sleight of Hand', 13, 'Carefully disarm the mechanism']], 'dmg': '2d4', 'type': 'poison', 'cond': 'Poisoned'},
    {'name': 'a rickety rope bridge', 'desc': 'A fraying rope bridge sways over a roaring chasm.', 'checks': [['DEX', 'Acrobatics', 12, 'Cross quickly and lightly'], ['STR', 'Athletics', 13, 'Climb down and around the gorge'], ['WIS', 'Survival', 12, 'Find a safer crossing upstream']], 'dmg': '3d6', 'type': 'bludgeoning'},
    {'name': 'a glowing glyph', 'desc': 'A rune of crackling light is etched across the threshold, humming with power.', 'checks': [['INT', 'Arcana', 13, 'Unravel the glyph\'s magic'], ['DEX', 'Acrobatics', 15, 'Vault over it without touching'], ['WIS', 'Religion', 14, 'Recite a warding prayer']], 'dmg': '3d6', 'type': 'lightning'},
    {'name': 'a rushing river', 'desc': 'Swollen with rain, a river blocks the path, its current savage.', 'checks': [['STR', 'Athletics', 13, 'Swim across with brute force'], ['WIS', 'Survival', 12, 'Search for a ford'], ['INT', 'Nature', 12, 'Fell a tree to bridge it']], 'dmg': '2d6', 'type': 'bludgeoning'},
    {'name': 'a rockslide', 'desc': 'Pebbles skitter down the slope above. Then the mountain moves.', 'checks': [['DEX', 'Acrobatics', 14, 'Sprint for cover'], ['WIS', 'Perception', 12, 'Spot the safe ledge'], ['STR', 'Athletics', 15, 'Shoulder through the falling stone']], 'dmg': '3d6', 'type': 'bludgeoning'},
    {'name': 'choking spore clouds', 'desc': 'Pale fungus carpets the passage, exhaling clouds of glittering spores.', 'checks': [['CON', 'save', 13, 'Hold your breath and push through'], ['INT', 'Nature', 12, 'Identify which fungi are safe'], ['WIS', 'Medicine', 12, 'Fashion a filtering mask']], 'dmg': '2d6', 'type': 'poison', 'cond': 'Poisoned'},
  ];

  static const _socials = [
    {'who': 'a wounded traveler', 'role': 'traveler', 'desc': 'A traveler slumps against a tree, clutching a bloody side. "Please... they took everything."', 'help': ['WIS', 'Medicine', 11, 'Tend their wounds'], 'talk': ['CHA', 'Persuasion', 12, 'Ask what they saw'], 'read': ['WIS', 'Insight', 13, 'Watch for deception'], 'trap': 0.25},
    {'who': 'a suspicious merchant', 'role': 'merchant', 'desc': 'A merchant with a too-wide smile has set up shop in the middle of nowhere. "Potions, charms, secrets! Cheap!"', 'help': ['CHA', 'Persuasion', 13, 'Haggle for a better price'], 'talk': ['CHA', 'Deception', 13, 'Pose as a rival merchant'], 'read': ['WIS', 'Insight', 12, 'Size them up'], 'trap': 0.15},
    {'who': 'a hermit sage', 'role': 'hermit', 'desc': 'An old hermit stirs a pot over a smoky fire. "Ah. The one the bones spoke of. Sit."', 'help': ['INT', 'History', 12, 'Discuss ancient lore'], 'talk': ['CHA', 'Persuasion', 12, 'Ask for guidance'], 'read': ['INT', 'Arcana', 13, 'Examine their strange charms'], 'trap': 0.05},
    {'who': 'a rival adventurer', 'role': 'adventurer', 'desc': 'A battle-scarred adventurer blocks the path, hand resting on a blade. "This bounty is mine."', 'help': ['CHA', 'Persuasion', 13, 'Propose an alliance'], 'talk': ['CHA', 'Intimidation', 14, 'Warn them off'], 'read': ['WIS', 'Insight', 12, 'Gauge their resolve'], 'trap': 0.1, 'recruit': true},
    {'who': 'a frightened child', 'role': 'child', 'desc': 'A child hides in the hollow of a tree, eyes wide. "The shadows took my da\'."', 'help': ['CHA', 'Persuasion', 10, 'Comfort them gently'], 'talk': ['WIS', 'Survival', 12, 'Track where the shadows went'], 'read': ['WIS', 'Insight', 11, 'Ask what they really saw'], 'trap': 0.0},
    {'who': 'a restless ghost', 'role': 'spirit', 'desc': 'A translucent figure in old armor drifts toward you. "Avenge me... or join me."', 'help': ['WIS', 'Religion', 13, 'Offer a prayer for its rest'], 'talk': ['CHA', 'Persuasion', 13, 'Promise to avenge it'], 'read': ['INT', 'History', 12, 'Recognize its heraldry'], 'trap': 0.2},
    {'who': 'a troll toll-keeper', 'role': 'toll-keeper', 'desc': 'A hulking figure squats on a bridge. "Toll! Ten gold, or a riddle, or your leg!"', 'help': ['CHA', 'Performance', 12, 'Entertain it with a song'], 'talk': ['CHA', 'Deception', 13, 'Claim you already paid'], 'read': ['STR', 'Intimidation', 15, 'Stare it down'], 'trap': 0.3},
  ];

  static const _treasures = [
    {'name': 'an iron-bound chest', 'desc': 'An iron-bound chest sits beneath a cobwebbed alcove, its lock rusted but intact.'},
    {'name': 'a forgotten shrine', 'desc': 'A small shrine glows faintly, offerings of coins and trinkets piled at its base.'},
    {'name': 'a fallen adventurer\'s pack', 'desc': 'A skeleton in rotted leathers clutches a pack, as if guarding it in death.'},
    {'name': 'a dragon-carved coffer', 'desc': 'A coffer carved with coiling dragons rests atop a pedestal. It seems almost too inviting.'},
  ];

  /// A magic item suited to the hero's level, or null.
  Map<String, dynamic>? _magicLoot(double chance) {
    final r = Rng(stableHash('${st['seed']}-${st['i']}-${a.turns}-loot'));
    if (!r.chance(chance)) return null;
    final lvl = a.hero.level;
    final rarity = lvl >= 11 ? r.pick(['rare', 'very rare']) : (lvl >= 5 ? r.pick(['uncommon', 'uncommon', 'rare']) : 'uncommon');
    final pool = itemsOfRarity(rarity);
    if (pool.isEmpty) return null;
    final def = r.pick(pool);
    return {'type': 'item', 'action': 'add', 'id': def.id, 'name': def.name};
  }

  static const _loot = [
    ['potion_healing', 1], ['potion_greater', 1], ['scroll_fireball', 1], ['scroll_shield', 1], ['rope', 1], ['torch', 2], ['studded_leather', 1], ['warhammer', 1], ['greatsword', 1],
  ];

  static const _trinkets = [
    'Silver Locket', 'Obsidian Die', 'Moonstone Ring', 'Ancient Coin', 'Crow-Feather Charm', 'Jade Figurine', 'Rune-Etched Key', 'Vial of Starlight', 'Bone Flute', 'Whispering Shell',
  ];

  static const _lore = [
    'Faded murals depict {villain} rising to power — and a hero striking at {weak}.',
    'A scholar\'s journal, water-stained, describes {villain}\'s one fear: {weak}.',
    'Runes on a broken pillar whisper of how {villain} was nearly defeated once before, by {weak}.',
  ];

  static const _weaknesses = ['the light of dawn', 'a name spoken thrice', 'silvered steel', 'the old songs of this land', 'the cracked gem in its crown', 'running water', 'its own reflection'];

  static const _banter = {
    'encounter': ['Stay close — I count {n} of them.', 'Finally, something to hit!', 'I don\'t like the look of these.', 'On your mark, {hero}.'],
    'hazard': ['Careful. This place wants us dead.', 'After you... no, really, I insist.', 'I\'ve seen traps like this before. Step lightly.'],
    'social': ['Let me do the talking. Or... you do it. You\'re better at it.', 'I don\'t trust them.', 'Poor soul.'],
    'treasure': ['Shiny! Check it for traps first.', 'Is it gold? Tell me it\'s gold.'],
    'rest': ['I\'ll take first watch.', 'Anyone else hear that, or just me?', 'Tell me about your home, {hero}.'],
    'boss': ['This is it. Whatever happens — it was an honor.', 'Let\'s end this.'],
    'riddle': ['Riddles. Why is it always riddles?', 'I think I know this one... no, I don\'t.'],
    'lore': ['Look at this — it might help us.', 'History repeats. Let\'s make sure it doesn\'t this time.'],
    'travel': ['Long road ahead.', 'My feet hate you, {hero}.'],
  };

  String _fill(String s, [Map<String, String> extra = const {}]) {
    final v = st['villain'] as Map;
    var out = s
        .replaceAll('{hero}', hero)
        .replaceAll('{villain}', v['name'])
        .replaceAll('{vtitle}', v['title'])
        .replaceAll('{mac}', st['mac'])
        .replaceAll('{patron}', st['patron'])
        .replaceAll('{town}', st['town'])
        .replaceAll('{lair}', st['lair'])
        .replaceAll('{name}', node['name'])
        .replaceAll('{weak}', (st['flags'] as Map)['weakText'] ?? _weaknesses[(st['seed'] as int) % _weaknesses.length]);
    extra.forEach((k, val) => out = out.replaceAll('{$k}', val));
    return out;
  }

  List<(String, String)> _companionBanter(String kind, {Map<String, String> extra = const {}}) {
    if (a.companions.isEmpty) return [];
    final r = _r;
    if (!r.chance(0.55)) return [];
    final c = r.pick(a.companions);
    final line = r.pick(_banter[kind] ?? _banter['travel']!);
    return [(c.name, _fill(line, extra))];
  }

  SceneInfo _scene({String? mood}) {
    final n = node;
    final r = _r;
    return SceneInfo(
      title: n['name'],
      location: n['env'] == 'road' ? 'road' : n['env'],
      time: r.pick(['dawn', 'day', 'day', 'dusk', 'night']),
      mood: mood ?? 'calm',
      imagePrompt: '${n['name']}, a ${n['env']} in a dark fantasy world',
      seed: stableHash(n['name']),
    );
  }

  CheckSpec _check(List c, {int dcAdj = 0}) {
    final dc = (c[2] as int) + dcAdj + (lvl ~/ 4);
    if (c[1] == 'save') return CheckSpec(ability: AbilityX.fromShort(c[0] as String), dc: dc, save: true);
    final sk = SkillX.parse(c[1] as String);
    return CheckSpec(ability: AbilityX.fromShort(c[0] as String), skill: sk, dc: dc);
  }

  // ----------------------------------------------------------------- turns

  DmTurn begin() {
    final r = Rng(st['seed'] as int);
    final hook = _fill(r.pick(_hooks));
    final town = st['town'] as String;
    final events = <Map<String, dynamic>>[
      {'type': 'quest', 'title': 'Recover ${_cap(st['mac'])}', 'description': hook, 'status': 'new'},
      {
        'type': 'map',
        'kind': 'overworld',
        'name': st['region'],
        'locations': nodes.where((n) => n['lair'] != true && n['t'] != 'epilogue' && n['t'] != 'rest').map((n) => n['name']).toList()..add(st['lair']),
      },
      {'type': 'npc', 'name': (st['patron'] as String).split(' the ').first, 'role': (st['patron'] as String).split(' the ').last, 'disposition': 30, 'description': 'Your quest-giver in $town.'},
    ];
    final narration = '${_fill(r.pick(_envOpen['town']!))} ${r.pick(_sensory)}\n\n$hook\n\n${_fill('"{villain} keeps to {lair}," {patron} says, voice low. "Few who go there come back."')}';
    return DmTurn(
      narration: narration,
      scene: _scene(mood: 'mystery'),
      events: events,
      choices: [
        Choice(text: 'Accept the quest and ask for supplies', type: ChoiceType.dialogue, check: CheckSpec(ability: Ability.cha, skill: Skill.persuasion, dc: 12), data: {'a': 'town_supplies'}),
        Choice(text: 'Ask around the tavern for rumors', type: ChoiceType.explore, check: CheckSpec(ability: Ability.cha, skill: Skill.persuasion, dc: 11), data: {'a': 'town_rumors'}),
        Choice(text: 'Visit the market', type: ChoiceType.action, data: {'a': 'town_shop'}),
        Choice(text: 'Set out immediately', type: ChoiceType.explore, data: {'a': 'next'}),
      ],
      banter: _companionBanter('travel'),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<Choice> _moveOnChoices({bool allowSearch = true}) {
    final i = st['i'] as int;
    final next = i + 1 < nodes.length ? nodes[i + 1] : null;
    final flags = st['flags'] as Map;
    final out = <Choice>[];
    if (next != null) {
      final label = next['t'] == 'epilogue' ? 'Return triumphant to ${next['name']}' : 'Press on toward ${next['name']}';
      out.add(Choice(text: label, type: ChoiceType.explore, data: {'a': 'next'}));
    }
    if (allowSearch && flags['searched$i'] != true) {
      out.add(Choice(text: 'Search the area', type: ChoiceType.explore, check: CheckSpec(ability: Ability.wis, skill: Skill.perception, dc: 12 + lvl ~/ 4), data: {'a': 'search'}));
    }
    if (a.hero.hp < a.hero.maxHp && a.hero.hitDiceRemaining > 0 && flags['short$i'] != true) {
      out.add(Choice(text: 'Take a short rest', type: ChoiceType.rest, data: {'a': 'short_rest'}));
    }
    return out;
  }

  DmTurn choose(Choice c, D20Result? roll) {
    final action = c.data['a'] as String? ?? 'next';
    final ok = roll?.success ?? true;
    final r = _r;
    final flags = st['flags'] as Map;
    final i = st['i'] as int;
    switch (action) {
      case 'next':
        return _enterNext();
      case 'search':
        flags['searched$i'] = true;
        if (ok) {
          final gold = r.range(3, 12) * lvl;
          final events = <Map<String, dynamic>>[
            {'type': 'gold', 'amount': gold},
          ];
          var extra = '';
          if (r.chance(0.45)) {
            final t = r.pick(_trinkets);
            events.add({'type': 'item', 'action': 'add', 'name': t, 'description': 'Found while searching ${node['name']}.'});
            extra = ' Tucked beneath it lies a $t.';
          }
          return DmTurn(narration: 'Your careful search pays off: you uncover a hidden cache with $gold gold.$extra', events: events, choices: _moveOnChoices(allowSearch: false));
        }
        return DmTurn(narration: 'You comb through the area but find nothing of value — only dust and old bones. ${r.pick(_sensory)}', choices: _moveOnChoices(allowSearch: false));
      case 'short_rest':
        flags['short$i'] = true;
        return DmTurn(
          narration: 'You find a sheltered nook and catch your breath, binding wounds and sharing a little food.',
          events: [
            {'type': 'rest', 'kind': 'short'},
          ],
          choices: _moveOnChoices(),
          banter: _companionBanter('rest'),
        );
      case 'town_supplies':
        st['phase'] = 'resolved';
        if (ok) {
          return DmTurn(
            narration: _fill('{patron} studies you, then nods and presses a heavy purse and a corked vial into your hands. "Bring it back. Please."'),
            events: [
              {'type': 'gold', 'amount': 20 + lvl * 10},
              {'type': 'item', 'action': 'add', 'name': 'Potion of Healing', 'id': 'potion_healing'},
            ],
            choices: _townChoices(exclude: 'town_supplies'),
          );
        }
        return DmTurn(narration: _fill('{patron} shakes their head. "I have nothing left to give but my thanks. Please hurry."'), choices: _townChoices(exclude: 'town_supplies'));
      case 'town_rumors':
        if (ok) {
          final weak = _weaknesses[(st['seed'] as int) % _weaknesses.length];
          flags['weakText'] = weak;
          st['weakness'] = true;
          return DmTurn(
            narration: _fill('Over a mug of sour ale, an old sailor leans close. "They say {villain} can be undone by $weak. My gran swore it." You file the knowledge away — it could turn the tide.'),
            events: [
              {'type': 'xp', 'amount': 25 * lvl},
            ],
            choices: _townChoices(exclude: 'town_rumors'),
          );
        }
        return DmTurn(narration: 'The tavern crowd is tight-lipped and suspicious of strangers. You learn little but the price of ale.', choices: _townChoices(exclude: 'town_rumors'));
      case 'town_shop':
        final town = st['town'] as String;
        final kind = r.pick(['general', 'smith', 'alchemist', if (lvl >= 3) 'magic']);
        final name = switch (kind) {
          'smith' => 'The $town Forge',
          'alchemist' => 'Lavender & Lye Apothecary',
          'magic' => 'The Curio of Many Doors',
          _ => '$town Market',
        };
        return DmTurn(
          narration: 'The market square of $town is loud with haggling. A shingle catches your eye: $name.',
          events: [
            {'type': 'shop', 'kind': kind, 'name': name},
          ],
          choices: _townChoices(exclude: 'town_shop'),
        );
      case 'fight':
        return _startFight(surprise: c.data['surprise'] as String? ?? 'none');
      case 'sneak':
        if (ok) {
          flags['done$i'] = true;
          return DmTurn(
            narration: 'You slip past unseen, holding your breath as the foes pass within arm\'s reach.',
            events: [
              {'type': 'xp', 'amount': _encounterXp() ~/ 2},
            ],
            choices: [
              Choice(text: 'Ambush them from behind', type: ChoiceType.combat, data: {'a': 'fight', 'surprise': 'enemies'}),
              ..._moveOnChoices(),
            ],
          );
        }
        return DmTurn(narration: 'A loose stone clatters under your foot. Heads snap toward you — you\'ve been spotted!', events: [_combatEvent(surprise: 'party')], scene: _scene(mood: 'combat'));
      case 'parley':
        if (ok) {
          flags['done$i'] = true;
          final gold = r.range(5, 15) * lvl;
          return DmTurn(
            narration: 'Your words land. After a tense moment, the foes lower their weapons and back away, tossing you a pouch of $gold coins as a peace offering — and a warning about what lies ahead.',
            events: [
              {'type': 'gold', 'amount': gold},
              {'type': 'xp', 'amount': _encounterXp()},
            ],
            choices: _moveOnChoices(),
          );
        }
        return DmTurn(narration: 'They laugh at your words and draw steel. So much for diplomacy.', events: [_combatEvent()], scene: _scene(mood: 'combat'));
      case 'hazard':
        return _resolveHazard(ok, roll);
      case 'social_help':
      case 'social_talk':
      case 'social_read':
        return _resolveSocial(action, ok);
      case 'social_recruit':
        return _recruit();
      case 'social_leave':
        return DmTurn(narration: 'You nod politely and move on. Some encounters are best left alone.', choices: _moveOnChoices());
      case 'treasure_open':
      case 'treasure_force':
      case 'treasure_inspect':
        return _resolveTreasure(action, ok);
      case 'riddle_answer':
        return _resolveRiddle(c.data['correct'] == true);
      case 'riddle_arcana':
        return _resolveRiddle(ok, viaCheck: true);
      case 'lore_study':
        if (ok) {
          final weak = _weaknesses[(st['seed'] as int) % _weaknesses.length];
          flags['weakText'] = weak;
          st['weakness'] = true;
          return DmTurn(
            narration: _fill(r.pick(_lore)),
            events: [
              {'type': 'xp', 'amount': 30 * lvl},
              {'type': 'quest', 'title': 'Recover ${_cap(st['mac'])}', 'description': _fill('You learned that {villain} is vulnerable to {weak}.'), 'status': 'update'},
            ],
            choices: _moveOnChoices(),
            banter: _companionBanter('lore'),
          );
        }
        return DmTurn(narration: 'The carvings are too worn to make sense of. Whatever secret they held is lost.', choices: _moveOnChoices());
      case 'rest_long':
        if (r.chance(0.3)) {
          return DmTurn(
            narration: 'Your sleep is shattered by snapping twigs and low growls — you\'re not alone!',
            events: [_combatEvent(monsterOverride: _pickWildMonster(), surprise: 'party')],
            scene: _scene(mood: 'combat'),
          );
        }
        return DmTurn(
          narration: 'The night passes peacefully beneath a sky full of strange stars. You wake refreshed, wounds mended and magic restored.',
          events: [
            {'type': 'rest', 'kind': 'long'},
          ],
          choices: _moveOnChoices(allowSearch: false),
          banter: _companionBanter('rest'),
        );
      case 'rest_watch':
        return DmTurn(
          narration: 'You keep a careful watch and rest lightly. Nothing stirs but the fire. You recover some strength.',
          events: [
            {'type': 'rest', 'kind': 'short'},
          ],
          choices: _moveOnChoices(allowSearch: false),
        );
      case 'boss_parley':
        if (ok) {
          return DmTurn(
            narration: _fill('Your words cut deeper than any blade. {villain} falters, doubt flickering across their face — and the fight that follows begins with your foe shaken and weakened.'),
            events: [_bossEvent(weakened: true)],
            scene: _scene(mood: 'combat'),
          );
        }
        return DmTurn(narration: _fill('{villain} laughs, a sound like grinding bones. "Bold. Foolish. Die."'), events: [_bossEvent()], scene: _scene(mood: 'combat'));
      case 'boss_weakness':
        return DmTurn(
          narration: _fill('You invoke {weak}. {villain} recoils with a shriek of fury as its power gutters like a dying candle!'),
          events: [_bossEvent(weakened: true)],
          scene: _scene(mood: 'combat'),
        );
      case 'boss_fight':
        return DmTurn(narration: _fill('You raise your weapon. {villain} smiles. "At last."'), events: [_bossEvent()], scene: _scene(mood: 'combat'));
      case 'new_chapter':
        final seed = (st['seed'] as int) * 31 + 7;
        a.offline = createState(seed, a.hero, chapter: (st['chapter'] as int? ?? 1) + 1);
        a.finished = false;
        return OfflineEngine(a).begin();
      default:
        return _enterNext();
    }
  }

  List<Choice> _townChoices({String? exclude}) {
    final flags = st['flags'] as Map;
    if (exclude != null) flags[exclude] = true;
    final all = [
      Choice(text: 'Ask for supplies', type: ChoiceType.dialogue, check: CheckSpec(ability: Ability.cha, skill: Skill.persuasion, dc: 12), data: {'a': 'town_supplies'}),
      Choice(text: 'Gather rumors in the tavern', type: ChoiceType.explore, check: CheckSpec(ability: Ability.cha, skill: Skill.persuasion, dc: 11), data: {'a': 'town_rumors'}),
      Choice(text: 'Buy a potion (50 gp)', type: ChoiceType.action, data: {'a': 'town_shop'}),
    ];
    return [
      ...all.where((c) => flags[c.data['a']] != true || c.data['a'] == 'town_shop'),
      Choice(text: 'Set out on the road', type: ChoiceType.explore, data: {'a': 'next'}),
    ];
  }

  DmTurn _enterNext() {
    final i = (st['i'] as int) + 1;
    if (i >= nodes.length) return _epilogue();
    st['i'] = i;
    st['phase'] = 'enter';
    final n = node;
    final r = _r;
    final events = <Map<String, dynamic>>[];
    final prev = nodes[i - 1];
    if (n['lair'] == true && prev['lair'] != true) {
      events.add({
        'type': 'map',
        'kind': 'dungeon',
        'name': st['lair'],
        'locations': nodes.where((x) => x['lair'] == true).map((x) => (x['name'] as String).split(' — ').last).toList(),
      });
    } else if (n['t'] == 'epilogue') {
      events.add({'type': 'map', 'kind': 'town', 'name': st['town'], 'locations': ['Town Gate', 'Market Square', 'Tavern', 'Temple']});
    } else {
      final loc = n['lair'] == true ? (n['name'] as String).split(' — ').last : n['name'];
      events.add({'type': 'move', 'location': loc});
    }
    final open = _fill(r.pick(_envOpen[n['env']] ?? _envOpen['ruins']!));
    final travel = n['lair'] == true ? '' : '${r.pick(['After hours on the road, ', 'The journey is long. At last, ', 'By the next morning, ', 'As the light shifts, '])}you reach ${n['name']}. ';
    final base = '$travel$open ${r.pick(_sensory)}';
    switch (n['t']) {
      case 'encounter':
        final m = monsterById(n['m'])!;
        final count = n['c'] as int;
        final plural = count > 1 ? '$count ${m.name}${m.name.endsWith('s') ? '' : 's'}' : 'a ${m.name}';
        final intro = r.pick(['Suddenly, $plural burst from cover!', 'Ahead, $plural stand guard, not yet aware of you.', 'You hear them before you see them: $plural, hunting.']);
        final choices = [
          Choice(text: 'Attack!', type: ChoiceType.combat, data: {'a': 'fight'}),
          Choice(text: 'Sneak past them', type: ChoiceType.stealth, check: CheckSpec(ability: Ability.dex, skill: Skill.stealth, dc: 11 + count + lvl ~/ 3), data: {'a': 'sneak'}),
          if (m.type == 'humanoid' || m.type == 'giant')
            Choice(text: 'Try to talk them down', type: ChoiceType.dialogue, check: CheckSpec(ability: Ability.cha, skill: a.hero.skillMod(Skill.intimidation) > a.hero.skillMod(Skill.persuasion) ? Skill.intimidation : Skill.persuasion, dc: 13 + lvl ~/ 3), data: {'a': 'parley'}),
          if (m.type == 'beast')
            Choice(text: 'Calm the beasts', type: ChoiceType.dialogue, check: CheckSpec(ability: Ability.wis, skill: Skill.animalHandling, dc: 13), data: {'a': 'parley'}),
          if (m.type == 'undead' && (a.hero.classLevels.containsKey('cleric') || a.hero.classLevels.containsKey('paladin')))
            Choice(text: 'Turn the undead with holy power', type: ChoiceType.magic, check: CheckSpec(ability: Ability.wis, skill: Skill.religion, dc: 12), data: {'a': 'parley'}),
        ];
        return DmTurn(narration: '$base\n\n$intro', scene: _scene(mood: 'tense'), choices: choices, banter: _companionBanter('encounter', extra: {'n': '$count'}), events: [...events, {'type': 'sfx', 'sound': 'roar'}]);
      case 'hazard':
        final h = r.pick(_hazards);
        n['h'] = _hazards.indexOf(h);
        final checks = (h['checks'] as List).cast<List>();
        return DmTurn(
          narration: '$base\n\n${h['desc']}',
          scene: _scene(mood: 'tense'),
          events: events,
          choices: [for (final c in checks) Choice(text: c[3] as String, type: ChoiceType.action, check: _check(c), data: {'a': 'hazard'})],
          banter: _companionBanter('hazard'),
        );
      case 'social':
        final s = r.pick(_socials);
        n['s'] = _socials.indexOf(s);
        final npcName = randomNpcName(rng: r);
        n['npc'] = npcName;
        events.add({'type': 'npc', 'name': npcName, 'role': s['role'], 'disposition': 0, 'description': 'You met them at ${n['name']}: ${s['who']}.', 'race': r.pick(races).id});
        return DmTurn(
          narration: '$base\n\nYou come upon ${s['who']}. ${s['desc']}',
          speaker: npcName,
          scene: _scene(mood: 'mystery'),
          events: events,
          choices: [
            Choice(text: (s['help'] as List)[3] as String, type: ChoiceType.action, check: _check(s['help'] as List), data: {'a': 'social_help'}),
            Choice(text: (s['talk'] as List)[3] as String, type: ChoiceType.dialogue, check: _check(s['talk'] as List), data: {'a': 'social_talk'}),
            Choice(text: (s['read'] as List)[3] as String, type: ChoiceType.explore, check: _check(s['read'] as List), data: {'a': 'social_read'}),
            Choice(text: 'Leave them be', type: ChoiceType.leave, data: {'a': 'social_leave'}),
          ],
          banter: _companionBanter('social'),
        );
      case 'treasure':
        final t = r.pick(_treasures);
        n['tr'] = _treasures.indexOf(t);
        n['mimic'] = r.chance(0.18) && lvl >= 2;
        return DmTurn(
          narration: '$base\n\n${t['desc']}',
          scene: _scene(mood: 'mystery'),
          events: events,
          choices: [
            Choice(text: 'Pick the lock carefully', type: ChoiceType.action, check: CheckSpec(ability: Ability.dex, skill: Skill.sleightOfHand, dc: 13 + lvl ~/ 4), data: {'a': 'treasure_open'}),
            Choice(text: 'Force it open', type: ChoiceType.action, check: CheckSpec(ability: Ability.str, skill: Skill.athletics, dc: 14 + lvl ~/ 4), data: {'a': 'treasure_force'}),
            Choice(text: 'Inspect it for traps first', type: ChoiceType.explore, check: CheckSpec(ability: Ability.int_, skill: Skill.investigation, dc: 12), data: {'a': 'treasure_inspect'}),
            ..._moveOnChoices(allowSearch: false).where((c) => c.data['a'] == 'next'),
          ],
          banter: _companionBanter('treasure'),
        );
      case 'riddle':
        final rd = r.pick(_riddles);
        n['rd'] = _riddles.indexOf(rd);
        final opts = r.shuffled([rd['a'] as String, ...(rd['w'] as List).cast<String>()]);
        return DmTurn(
          narration: '$base\n\nA stone door bars the way, carved with a grinning face. Its lips move, grinding: "Answer true and pass. Answer false and suffer.\n\n${rd['q']}"',
          speaker: 'The Riddle Door',
          scene: _scene(mood: 'mystery'),
          events: events,
          choices: [
            for (final o in opts) Choice(text: '"$o"', type: ChoiceType.dialogue, data: {'a': 'riddle_answer', 'correct': o == rd['a']}),
            Choice(text: 'Bypass the door\'s magic', type: ChoiceType.magic, check: CheckSpec(ability: Ability.int_, skill: Skill.arcana, dc: 15), data: {'a': 'riddle_arcana'}),
          ],
          banter: _companionBanter('riddle'),
        );
      case 'lore':
        return DmTurn(
          narration: '$base\n\n${n['lair'] == true ? _fill('You stand at the threshold of {lair}. ') : ''}Ancient carvings and faded murals cover the walls here, telling a story half-lost to time.',
          scene: _scene(mood: 'eerie'),
          events: events,
          choices: [
            Choice(text: 'Study the carvings', type: ChoiceType.explore, check: CheckSpec(ability: Ability.int_, skill: Skill.history, dc: 12 + lvl ~/ 4), data: {'a': 'lore_study'}),
            Choice(text: 'Sense the magic woven here', type: ChoiceType.magic, check: CheckSpec(ability: Ability.int_, skill: Skill.arcana, dc: 13 + lvl ~/ 4), data: {'a': 'lore_study'}),
            ..._moveOnChoices(),
          ],
          banter: _companionBanter('lore'),
        );
      case 'rest':
        return DmTurn(
          narration: '$base\n\nAs dusk falls you find a sheltered hollow, perfect for a camp. The fire crackles; for a moment, the world feels almost kind.',
          scene: SceneInfo(title: n['name'], location: 'camp', time: 'night', mood: 'calm', seed: stableHash(n['name'])),
          events: events,
          choices: [
            Choice(text: 'Make camp for a long rest', type: ChoiceType.rest, data: {'a': 'rest_long'}),
            Choice(text: 'Rest lightly and keep watch', type: ChoiceType.rest, data: {'a': 'rest_watch'}),
            Choice(text: 'Push on through the night', type: ChoiceType.explore, data: {'a': 'next'}),
          ],
          banter: _companionBanter('rest'),
        );
      case 'boss':
        final v = st['villain'] as Map;
        return DmTurn(
          narration: _fill('$base\n\nAt the heart of {lair}, {villain} awaits — {vtitle}. {mac} lies behind them, glimmering. "So. The little hero arrives," they say. "Kneel, and I may let you serve."'),
          speaker: v['name'],
          scene: _scene(mood: 'combat'),
          events: [...events, {'type': 'sfx', 'sound': 'thunder'}],
          choices: [
            Choice(text: 'Charge into battle', type: ChoiceType.combat, data: {'a': 'boss_fight'}),
            Choice(text: 'Defy them with words', type: ChoiceType.dialogue, check: CheckSpec(ability: Ability.cha, skill: Skill.intimidation, dc: 16 + lvl ~/ 4), data: {'a': 'boss_parley'}),
            if (st['weakness'] == true) Choice(text: _fill('Use what you learned: {weak}'), type: ChoiceType.magic, data: {'a': 'boss_weakness'}),
          ],
          banter: _companionBanter('boss'),
        );
      case 'epilogue':
        return _epilogue();
      default:
        return DmTurn(narration: base, choices: _moveOnChoices(), events: events);
    }
  }

  int _encounterXp() {
    final m = monsterById(node['m'] ?? 'goblin');
    return (m?.xp ?? 50) * ((node['c'] ?? 1) as int);
  }

  String _pickWildMonster() {
    final env = node['env'] as String;
    final pool = monsters.where((m) => m.environments.contains(env) && m.cr <= math.max(0.5, lvl * 0.5)).toList();
    return pool.isEmpty ? 'wolf' : _r.pick(pool).id;
  }

  Map<String, dynamic> _combatEvent({String surprise = 'none', String? monsterOverride}) {
    final mid = monsterOverride ?? node['m'] ?? 'goblin';
    final m = monsterById(mid) ?? monsters.first;
    final count = monsterOverride != null ? math.max(1, lvl ~/ 2 + 1) : (node['c'] ?? 1) as int;
    return {
      'type': 'combat',
      'surprise': surprise,
      'enemies': [
        {'name': m.name, 'monster': m.id, 'count': count},
      ],
    };
  }

  DmTurn _startFight({String surprise = 'none'}) {
    return DmTurn(
      narration: surprise == 'enemies' ? 'You strike from the shadows before they can react!' : 'Steel rings as battle is joined!',
      events: [_combatEvent(surprise: surprise)],
      scene: _scene(mood: 'combat'),
    );
  }

  Map<String, dynamic> _bossEvent({bool weakened = false}) {
    final v = st['villain'] as Map;
    final m = monsterById(v['monster'])!;
    final minion = monsterById(v['minion'])!;
    final scale = (0.6 + lvl * 0.25).clamp(0.6, 2.5);
    var hp = (m.hp * scale).round();
    if (weakened) hp = (hp * 0.7).round();
    final minions = math.max(0, math.min(3, lvl - 1 + (a.companions.length)));
    return {
      'type': 'combat',
      'boss': true,
      'enemies': [
        {'name': v['name'], 'monster': m.id, 'count': 1, 'hp': hp, 'ac': m.ac + (lvl >= 5 ? 1 : 0), 'attack_bonus': m.attackBonus + lvl ~/ 3, 'damage': m.damage},
        if (minions > 0) {'name': minion.name, 'monster': minion.id, 'count': minions},
      ],
    };
  }

  DmTurn _resolveHazard(bool ok, D20Result? roll) {
    final h = _hazards[(node['h'] ?? 0) as int];
    final flags = st['flags'] as Map;
    flags['done${st['i']}'] = true;
    if (ok) {
      return DmTurn(
        narration: '${roll?.isCrit == true ? 'With masterful grace, you' : 'You'} overcome ${h['name']} unscathed. ${_r.pick(['Your heart pounds, but you\'re through.', 'Behind you, the danger rumbles harmlessly.', 'Not a scratch.'])}',
        events: [
          {'type': 'xp', 'amount': 40 * lvl},
        ],
        choices: _moveOnChoices(),
      );
    }
    // Failing to avoid it means resisting it: a saving throw for half damage.
    final saveAb = h['type'] == 'poison' ? 'CON' : (h['type'] == 'lightning' ? 'DEX' : 'DEX');
    final events = <Map<String, dynamic>>[
      {
        'type': 'save',
        'target': 'hero',
        'ability': saveAb,
        'dc': 12 + lvl ~/ 4,
        'reason': h['name'],
        'damage': '${h['dmg']}+${lvl ~/ 3}',
        'damage_type': h['type'],
        'half': true,
        if (h['cond'] != null) 'condition': h['cond'],
        if (h['cond'] != null) 'turns': 3,
      },
      {'type': 'xp', 'amount': 15 * lvl},
    ];
    return DmTurn(
      narration: 'You fail to avoid ${h['name']}. Now it is a matter of toughing it out.',
      events: events,
      choices: _moveOnChoices(),
    );
  }

  DmTurn _resolveSocial(String action, bool ok) {
    final s = _socials[(node['s'] ?? 0) as int];
    final name = node['npc'] as String? ?? 'the stranger';
    final r = _r;
    final isTrap = r.chance((s['trap'] as num).toDouble()) && action != 'social_read';
    if (isTrap && !ok) {
      return DmTurn(
        narration: '$name\'s expression twists. "Fool." It was an ambush all along — bandits burst from hiding!',
        events: [
          {'type': 'disposition', 'name': name, 'change': -50},
          {
            'type': 'combat',
            'enemies': [
              {'name': 'Bandit', 'monster': 'bandit', 'count': math.max(1, lvl ~/ 2 + 1)},
            ],
          },
        ],
        scene: _scene(mood: 'combat'),
      );
    }
    if (ok) {
      final reward = r.nextInt(4);
      final events = <Map<String, dynamic>>[
        {'type': 'disposition', 'name': name, 'change': 30},
        {'type': 'xp', 'amount': 30 * lvl},
      ];
      String text;
      switch (reward) {
        case 0:
          final weak = _weaknesses[(st['seed'] as int) % _weaknesses.length];
          (st['flags'] as Map)['weakText'] = weak;
          st['weakness'] = true;
          text = _fill('"{villain}?" $name lowers their voice. "I know one thing: they fear {weak}. Remember that."');
        case 1:
          final l = r.pick(_loot);
          events.add({'type': 'item', 'action': 'add', 'id': l[0], 'name': itemById(l[0] as String)!.name, 'qty': l[1]});
          text = '$name presses something into your hand. "Take it. You\'ll need it more than me." (${itemById(l[0] as String)!.name})';
        case 2:
          final g = r.range(10, 30) * lvl;
          events.add({'type': 'gold', 'amount': g});
          text = '$name smiles for the first time. "Bless you." They insist you take $g gold for your kindness.';
        default:
          text = '$name points down a hidden trail. "Go that way — it avoids the worst of it." You feel more confident about the road ahead.';
          events.add({'type': 'heal', 'target': 'hero', 'amount': 5 + lvl});
      }
      final choices = <Choice>[
        if (s['recruit'] == true && a.companions.length < 2 && (st['flags'] as Map)['recruited'] != true)
          Choice(text: 'Invite $name to join your party', type: ChoiceType.dialogue, data: {'a': 'social_recruit'}),
        ..._moveOnChoices(),
      ];
      return DmTurn(narration: text, speaker: name, events: events, choices: choices, banter: _companionBanter('social'));
    }
    return DmTurn(
      narration: r.pick(['$name eyes you warily and refuses to say more.', 'Your approach goes poorly; $name turns away, offended.', '$name mutters something unkind and vanishes into the brush.']),
      speaker: name,
      events: [
        {'type': 'disposition', 'name': name, 'change': -20},
      ],
      choices: _moveOnChoices(),
    );
  }

  DmTurn _recruit() {
    final name = node['npc'] as String? ?? 'the stranger';
    (st['flags'] as Map)['recruited'] = true;
    final p = _r.pick(presets.where((p) => p.classId != a.hero.primaryClass.id).toList());
    return DmTurn(
      narration: '$name considers, then grins and claps your shoulder. "Fine. Better odds together." A new companion joins your party!',
      speaker: name,
      events: [
        {'type': 'companion_join', 'name': name, 'race': p.raceId, 'class': p.classId, 'personality': p.personality},
        {'type': 'npc_remove', 'name': name},
      ],
      choices: _moveOnChoices(),
    );
  }

  DmTurn _resolveTreasure(String action, bool ok) {
    final flags = st['flags'] as Map;
    final i = st['i'];
    final r = _r;
    if (action == 'treasure_inspect') {
      if (ok && node['mimic'] == true) {
        flags['done$i'] = true;
        return DmTurn(
          narration: 'You notice the "wood grain" is breathing. It\'s a MIMIC! You have the advantage of surprise.',
          events: [
            {
              'type': 'combat',
              'surprise': 'enemies',
              'enemies': [
                {'name': 'Mimic', 'monster': 'mimic', 'count': 1},
              ],
            },
          ],
          scene: _scene(mood: 'combat'),
        );
      }
      return DmTurn(
        narration: ok ? 'You find no traps. It looks safe to open.' : 'You can\'t tell whether it\'s trapped.',
        choices: [
          Choice(text: 'Pick the lock carefully', type: ChoiceType.action, check: CheckSpec(ability: Ability.dex, skill: Skill.sleightOfHand, dc: ok ? 11 : 13 + lvl ~/ 4), data: {'a': 'treasure_open', 'safe': ok}),
          Choice(text: 'Force it open', type: ChoiceType.action, check: CheckSpec(ability: Ability.str, skill: Skill.athletics, dc: 14), data: {'a': 'treasure_force', 'safe': ok}),
          ..._moveOnChoices(allowSearch: false).where((c) => c.data['a'] == 'next'),
        ],
      );
    }
    if (node['mimic'] == true) {
      flags['done$i'] = true;
      return DmTurn(
        narration: 'As you touch it, the lid splits into a jagged maw of teeth! It\'s a MIMIC!',
        events: [
          {
            'type': 'combat',
            'surprise': 'party',
            'enemies': [
              {'name': 'Mimic', 'monster': 'mimic', 'count': 1},
            ],
          },
        ],
        scene: _scene(mood: 'combat'),
      );
    }
    flags['done$i'] = true;
    if (ok) {
      final gold = r.range(15, 40) * lvl;
      final l = r.pick(_loot);
      final trinket = r.pick(_trinkets);
      return DmTurn(
        narration: 'The lid creaks open, revealing $gold gold coins, a ${itemById(l[0] as String)!.name}, and a $trinket.',
        events: [
          {'type': 'gold', 'amount': gold, 'sp': 5 + gold % 37, 'cp': 10 + gold % 53},
          {'type': 'item', 'action': 'add', 'id': l[0], 'name': itemById(l[0] as String)!.name, 'qty': l[1]},
          {'type': 'item', 'action': 'add', 'name': trinket, 'description': 'A curious trinket of unknown origin.'},
          ?_magicLoot(0.35),
          {'type': 'xp', 'amount': 20 * lvl},
          {'type': 'sfx', 'sound': 'coin'},
        ],
        choices: _moveOnChoices(allowSearch: false),
      );
    }
    final dmg = DiceExpression.parse('1d6').roll().total + lvl;
    return DmTurn(
      narration: action == 'treasure_force'
          ? 'You heave and strain, and the lock snaps — along with a hidden needle that pricks your hand for $dmg damage. Inside: a handful of coins.'
          : 'Your pick slips and a needle jabs your finger ($dmg damage). The mechanism jams for good, but you pry loose a few coins.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': dmg, 'reason': 'needle trap'},
        {'type': 'gold', 'amount': r.range(3, 10) * lvl},
      ],
      choices: _moveOnChoices(allowSearch: false),
    );
  }

  DmTurn _resolveRiddle(bool ok, {bool viaCheck = false}) {
    (st['flags'] as Map)['done${st['i']}'] = true;
    if (ok) {
      final gold = 25 * lvl;
      return DmTurn(
        narration: viaCheck
            ? 'You trace the threads of enchantment and snap them one by one. The face goes slack and the door swings open.'
            : 'The stone face grinds into a smile. "Correct." The door rumbles aside, revealing a small offering bowl with $gold gold.',
        events: [
          {'type': 'xp', 'amount': 50 * lvl},
          if (!viaCheck) {'type': 'gold', 'amount': gold},
          {'type': 'sfx', 'sound': 'chime'},
        ],
        choices: _moveOnChoices(),
      );
    }
    final dmg = DiceExpression.parse('2d6').roll().total + lvl;
    return DmTurn(
      narration: '"WRONG." Lightning arcs from the face\'s eyes, searing you for $dmg damage. Then, with a grudging groan, the door opens anyway. "Pass, fool."',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': dmg, 'reason': 'riddle door'},
        {'type': 'sfx', 'sound': 'thunder'},
      ],
      choices: _moveOnChoices(),
    );
  }

  DmTurn _epilogue() {
    a.finished = true;
    st['i'] = nodes.length - 1;
    final gold = 100 * lvl;
    return DmTurn(
      narration: _fill('You return to {town} bearing {mac}. Bells ring; people pour into the streets. {patron} weeps openly and embraces you. That night, songs are sung of {hero}, who walked into {lair} and walked back out.\n\nYour legend has only begun.'),
      scene: SceneInfo(title: st['town'], location: 'town', time: 'dusk', mood: 'triumph', seed: stableHash(st['town'])),
      events: [
        {'type': 'gold', 'amount': gold},
        {'type': 'xp', 'amount': 150 * lvl},
        {'type': 'quest', 'title': 'Recover ${_cap(st['mac'])}', 'status': 'completed'},
        {'type': 'end', 'outcome': 'victory', 'epilogue': 'The realm is safe — for now.'},
      ],
      choices: [
        Choice(text: 'Begin a new chapter', type: ChoiceType.explore, data: {'a': 'new_chapter'}),
      ],
      banter: a.companions.isEmpty ? [] : [(a.companions.first.name, 'We did it, ${a.hero.name}. Same time next week?')],
    );
  }

  /// Called after combat resolves.
  DmTurn afterCombat({required bool victory, required bool fled, required int xp, required bool wasBoss}) {
    final r = _r;
    (st['flags'] as Map)['done${st['i']}'] = true;
    if (fled) {
      return DmTurn(narration: 'You flee, lungs burning, until the sounds of pursuit fade behind you.', choices: _moveOnChoices(allowSearch: false));
    }
    if (!victory) {
      return DmTurn(
        narration: 'Darkness takes you... You wake hours later, stripped of some coin and bruised, but alive — left for dead by foes who didn\'t bother to finish the job.',
        events: [
          {'type': 'gold', 'amount': -(a.hero.gold ~/ 4)},
        ],
        choices: _moveOnChoices(allowSearch: false),
      );
    }
    if (wasBoss) {
      return DmTurn(
        narration: _fill('{villain} falls with a final, terrible cry, and the darkness in {lair} lifts like a curtain. {mac} is yours.'),
        events: [
          {'type': 'xp', 'amount': 100 * lvl},
          {'type': 'item', 'action': 'add', 'name': _cap(st['mac']), 'description': 'The object of your quest.'},
          ?_magicLoot(1.0),
          {'type': 'quest', 'title': 'Recover ${_cap(st['mac'])}', 'description': _fill('Return to {town}.'), 'status': 'update'},
          {'type': 'sfx', 'sound': 'chime'},
        ],
        choices: _moveOnChoices(),
        banter: _companionBanter('boss'),
      );
    }
    final gold = r.range(2, 8) * lvl;
    return DmTurn(
      narration: '${r.pick(['The last foe falls.', 'Silence returns.', 'Victory!'])} You catch your breath and loot the fallen, finding $gold gold.',
      events: [
        {'type': 'gold', 'amount': gold},
        if (r.chance(0.3)) {'type': 'item', 'action': 'add', 'id': 'potion_healing', 'name': 'Potion of Healing'},
        ?_magicLoot(0.08),
      ],
      choices: _moveOnChoices(),
    );
  }

  /// Best-effort mapping of typed input to a choice.
  Choice? matchFreeText(String text, List<Choice> choices) {
    final t = text.toLowerCase().trim();
    final n = int.tryParse(t);
    if (n != null && n >= 1 && n <= choices.length) return choices[n - 1];
    final words = t.split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
    Choice? best;
    var bestScore = 0;
    for (final c in choices) {
      final cw = c.text.toLowerCase().split(RegExp(r'\W+')).toSet();
      var score = words.intersection(cw).length;
      if ((t.contains('attack') || t.contains('fight') || t.contains('kill')) && c.type == ChoiceType.combat) score += 3;
      if ((t.contains('sneak') || t.contains('hide')) && c.type == ChoiceType.stealth) score += 3;
      if ((t.contains('talk') || t.contains('say') || t.contains('ask')) && c.type == ChoiceType.dialogue) score += 2;
      if ((t.contains('go') || t.contains('continue') || t.contains('onward') || t.contains('leave')) && c.data['a'] == 'next') score += 2;
      if (t.contains('rest') && c.type == ChoiceType.rest) score += 3;
      if (t.contains('search') && c.data['a'] == 'search') score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return bestScore > 0 ? best : null;
  }
}

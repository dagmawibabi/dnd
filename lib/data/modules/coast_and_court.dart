import '../../game/module_engine.dart';
import '../../models/adventure.dart';

const lighthouse = AdventureModule(
  id: 'gulls_end',
  title: 'The Lighthouse at Gull\'s End',
  tagline: 'The light has gone dark, the keeper is missing, and something is singing under the waves.',
  description:
      'For three nights the lighthouse at Gull\'s End has stood dark. Ships break on the rocks, the keeper Maren Holt has vanished, and fishers whisper about a drowned bell ringing beneath the sea. Climb the storm-lashed cliffs, relight the lamp, and stop a cult before the bell tolls.',
  levels: '2–4',
  minutes: 30,
  tone: 'Dark',
  setting: 'High seas',
  coverLoc: 'coast',
  coverTime: 'night',
  mapKind: MapKind.overworld,
  mapName: 'Gull\'s End',
  locations: ['Gull\'s End Harbor', 'The Cliff Path', 'Keeper\'s Cottage', 'Lighthouse Stair', 'The Lamp Room', 'The Drowned Cave'],
  tags: ['Horror', 'Exploration', 'Companion'],
  start: 'harbor',
  nodes: {
    'harbor': ModNode(
      title: 'Gull\'s End Harbor',
      loc: 'coast',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Gull\'s End Harbor',
      speaker: 'Old Fen',
      text:
          'Rain hisses on black water. Up on the headland, the lighthouse is a dead finger against the storm clouds. An old ferryman hauls his boat higher up the shingle, hands shaking.\n\n"Three nights dark," says Old Fen. "Maren never misses a night. And at low tide… you can hear it. A bell. Ringing under the sea, slow as a heartbeat."',
      events: [
        {'type': 'quest', 'title': 'The Dark Light', 'description': 'Find the keeper, Maren Holt, and relight the lighthouse at Gull\'s End.', 'status': 'new'},
        {'type': 'npc', 'name': 'Old Fen', 'role': 'ferryman', 'race': 'human', 'disposition': 20, 'description': 'Weathered, superstitious, and terrified.'},
      ],
      choices: [
        ModChoice('Buy a flask of lamp oil from Fen (5 gp)', type: ChoiceType.action, requires: 'gold:5', unless: 'oil', set: 'oil', go: 'harbor_oil', effects: [
          {'type': 'gold', 'amount': -5},
          {'type': 'item', 'action': 'add', 'name': 'Lamp Oil', 'description': 'Whale oil for the lighthouse lamp.'},
        ]),
        ModChoice('Ask Fen about the bell', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'harbor_lore', fail: 'harbor_silent', unless: 'lore'),
        ModChoice('Take the cliff path to the lighthouse', type: ChoiceType.explore, go: 'cliff'),
      ],
    ),
    'harbor_oil': ModNode(
      title: 'Gull\'s End Harbor',
      loc: 'coast',
      time: 'night',
      mood: 'eerie',
      speaker: 'Old Fen',
      text: '"Keep it dry," Fen says, pressing the flask into your hands. "That lamp won\'t burn on hope."',
      choices: [
        ModChoice('Ask Fen about the bell', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'harbor_lore', fail: 'harbor_silent', unless: 'lore'),
        ModChoice('Take the cliff path', type: ChoiceType.explore, go: 'cliff'),
      ],
    ),
    'harbor_lore': ModNode(
      title: 'Gull\'s End Harbor',
      loc: 'coast',
      time: 'night',
      mood: 'eerie',
      speaker: 'Old Fen',
      sets: ['lore'],
      text:
          '"My gran told it. A temple sank in the bay, long ago, with its bell. The ones who prayed there didn\'t drown — they changed. They hate light. The lighthouse was built to keep them down." He looks up at the dark tower. "Now it\'s out."',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Buy lamp oil (5 gp)', type: ChoiceType.action, requires: 'gold:5', unless: 'oil', set: 'oil', go: 'harbor_oil', effects: [
          {'type': 'gold', 'amount': -5},
          {'type': 'item', 'action': 'add', 'name': 'Lamp Oil', 'description': 'Whale oil for the lighthouse lamp.'},
        ]),
        ModChoice('Take the cliff path', type: ChoiceType.explore, go: 'cliff'),
      ],
    ),
    'harbor_silent': ModNode(
      title: 'Gull\'s End Harbor',
      loc: 'coast',
      time: 'night',
      mood: 'eerie',
      text: 'Fen spits into the sea and makes a warding sign. "Don\'t ask me. Ask the tide." He won\'t say another word.',
      choices: [
        ModChoice('Take the cliff path', type: ChoiceType.explore, go: 'cliff'),
      ],
    ),
    'cliff': ModNode(
      title: 'The Cliff Path',
      loc: 'mountain',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Cliff Path',
      text:
          'The path is a ledge of wet slate above a boiling sea. Halfway up, a section has collapsed into the dark. Wind screams through the gap, and lightning shows you the rocks far below.',
      choices: [
        ModChoice('Leap the gap', type: ChoiceType.action, check: 'Athletics', dc: 12, ok: 'cottage', fail: 'cliff_fall'),
        ModChoice('Edge along the cliff face', type: ChoiceType.action, check: 'Acrobatics', dc: 13, ok: 'cottage', fail: 'cliff_fall'),
        ModChoice('Rope yourself to the old iron post', type: ChoiceType.action, requires: 'item:Hempen Rope (50 ft)', go: 'cottage'),
      ],
    ),
    'cliff_fall': ModNode(
      title: 'The Cliff Path',
      loc: 'mountain',
      time: 'night',
      mood: 'tense',
      text: 'The slate crumbles. You slide, scrape, and catch a root at the last moment, bleeding but alive. You haul yourself up the far side.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 6, 'reason': 'fall on the cliff'},
      ],
      choices: [
        ModChoice('Continue to the keeper\'s cottage', type: ChoiceType.explore, go: 'cottage'),
      ],
    ),
    'cottage': ModNode(
      title: 'Keeper\'s Cottage',
      loc: 'tavern',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Keeper\'s Cottage',
      text:
          'The cottage door hangs open. Inside: an overturned chair, a cold stove, and wet footprints — bare, webbed — leading out toward the lighthouse. On the table lies a journal, its last page torn and smeared.',
      choices: [
        ModChoice('Read the keeper\'s journal', type: ChoiceType.explore, check: 'Investigation', dc: 12, ok: 'cottage_journal', fail: 'cottage_smudged'),
        ModChoice('Search the cottage', type: ChoiceType.explore, check: 'Perception', dc: 11, ok: 'cottage_key', fail: 'stair', unless: 'key'),
        ModChoice('Follow the webbed footprints', type: ChoiceType.explore, go: 'stair'),
      ],
    ),
    'cottage_journal': ModNode(
      title: 'Keeper\'s Cottage',
      loc: 'tavern',
      time: 'night',
      mood: 'mystery',
      sets: ['journal'],
      text:
          '"…they come closer each low tide. Sister Undine leads them — she was the miller\'s girl, once. They mean to ring the bell three times at the dark of the moon. The light hurts them. As long as it burns, they cannot finish the rite…"\n\nThe last line is in different, shakier ink: "They are on the stairs."',
      events: [
        {'type': 'xp', 'amount': 50},
        {'type': 'quest', 'title': 'The Dark Light', 'description': 'Relight the lamp to weaken the Drowned, then stop Sister Undine from ringing the bell.', 'status': 'update'},
      ],
      choices: [
        ModChoice('Search the cottage', type: ChoiceType.explore, check: 'Perception', dc: 11, ok: 'cottage_key', fail: 'stair', unless: 'key'),
        ModChoice('Head for the lighthouse', type: ChoiceType.explore, go: 'stair'),
      ],
    ),
    'cottage_smudged': ModNode(
      title: 'Keeper\'s Cottage',
      loc: 'tavern',
      time: 'night',
      mood: 'mystery',
      text: 'Seawater has ruined most of the journal. You make out only a name — "Undine" — and the word "light", underlined three times.',
      choices: [
        ModChoice('Search the cottage', type: ChoiceType.explore, check: 'Perception', dc: 11, ok: 'cottage_key', fail: 'stair', unless: 'key'),
        ModChoice('Head for the lighthouse', type: ChoiceType.explore, go: 'stair'),
      ],
    ),
    'cottage_key': ModNode(
      title: 'Keeper\'s Cottage',
      loc: 'tavern',
      time: 'night',
      mood: 'mystery',
      sets: ['key'],
      text: 'Under a loose floorboard: a heavy brass key stamped with a lantern, and a small bottle of oil wrapped in oilcloth.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Keeper\'s Key', 'description': 'Opens the lamp room.'},
        {'type': 'item', 'action': 'add', 'name': 'Lamp Oil', 'description': 'A reserve flask.'},
      ],
      choices: [
        ModChoice('Head for the lighthouse', type: ChoiceType.explore, go: 'stair'),
      ],
    ),
    'stair': ModNode(
      title: 'Lighthouse Stair',
      loc: 'tower',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Lighthouse Stair',
      text:
          'The spiral stair is slick with seawater. Halfway up, two figures in rotted fishing gear stand motionless, faces turned to the dark lamp room above. Their skin is grey and gilled. They have not noticed you yet.',
      choices: [
        ModChoice('Creep past them', type: ChoiceType.stealth, check: 'Stealth', dc: 13, ok: 'lamp', fail: 'stair_fight'),
        ModChoice('Strike first', type: ChoiceType.combat, go: 'stair_ambush'),
        ModChoice('Turn the undead with holy light', type: ChoiceType.magic, requires: 'class:cleric|paladin', go: 'lamp', effects: [
          {'type': 'xp', 'amount': 50},
        ]),
      ],
    ),
    'stair_ambush': ModNode(
      title: 'Lighthouse Stair',
      loc: 'tower',
      time: 'night',
      mood: 'combat',
      text: 'You charge up the stairs before they can turn.',
      combat: ModCombat([
        {'name': 'Drowned Sailor', 'monster': 'zombie', 'count': 2},
      ], win: 'lamp', surprise: 'enemies'),
    ),
    'stair_fight': ModNode(
      title: 'Lighthouse Stair',
      loc: 'tower',
      time: 'night',
      mood: 'combat',
      text: 'A step creaks. Both heads swivel toward you, too far, with a wet crack.',
      combat: ModCombat([
        {'name': 'Drowned Sailor', 'monster': 'zombie', 'count': 2},
      ], win: 'lamp'),
    ),
    'lamp': ModNode(
      title: 'The Lamp Room',
      loc: 'tower',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Lamp Room',
      text:
          'The great lens sits dark and cold, its brass fittings green with salt. Through the rain-streaked glass you see torches far below in the bay — a procession wading into a sea cave. The bell tolls once, and the whole tower shivers.',
      choices: [
        ModChoice('Fill and light the lamp', type: ChoiceType.action, requires: 'item:Lamp Oil', go: 'lamp_lit'),
        ModChoice('Coax a flame from magic', type: ChoiceType.magic, check: 'Arcana', dc: 14, ok: 'lamp_lit', fail: 'lamp_dark'),
        ModChoice('Strike sparks into the old wick', type: ChoiceType.action, check: 'Survival', dc: 15, ok: 'lamp_lit', fail: 'lamp_dark'),
        ModChoice('Leave it and hurry down to the cave', type: ChoiceType.explore, go: 'cave'),
      ],
    ),
    'lamp_lit': ModNode(
      title: 'The Lamp Room',
      loc: 'tower',
      time: 'night',
      mood: 'triumph',
      sets: ['light'],
      text:
          'The wick catches. The lens drinks the flame and throws it out across the bay in a great golden blade. Far below, the procession screams and scatters, shielding their eyes. The bell falters mid-toll.',
      events: [
        {'type': 'xp', 'amount': 100},
        {'type': 'quest', 'title': 'The Dark Light', 'description': 'The lighthouse burns again. Now stop Sister Undine in the sea cave.', 'status': 'update'},
      ],
      choices: [
        ModChoice('Descend to the sea cave', type: ChoiceType.explore, go: 'cave'),
      ],
    ),
    'lamp_dark': ModNode(
      title: 'The Lamp Room',
      loc: 'tower',
      time: 'night',
      mood: 'sad',
      text: 'Nothing. The wick is soaked through. The bell tolls a second time. There is no more time.',
      choices: [
        ModChoice('Run for the sea cave', type: ChoiceType.explore, go: 'cave'),
      ],
    ),
    'cave': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'The Drowned Cave',
      speaker: 'Sister Undine',
      text:
          'Tide water swirls around an ancient bronze bell, green with age, hung from a stone arch. Bound to the arch is a grey-haired woman — Maren Holt, alive, glaring. Before the bell stands Sister Undine, robed in kelp, a coral knife in her hand.\n\n"One toll more," she sings. "Then the Mother wakes, and the sea comes home."',
      events: [
        {'type': 'npc', 'name': 'Sister Undine', 'role': 'drowned priestess', 'race': 'half-elf', 'disposition': -60, 'description': 'Once the miller\'s daughter. Now something else.'},
        {'type': 'npc', 'name': 'Maren Holt', 'role': 'lighthouse keeper', 'race': 'human', 'disposition': 40, 'description': 'Tough as an old rope.'},
      ],
      choices: [
        ModChoice('Remind Undine who she was', type: ChoiceType.dialogue, check: 'Persuasion', dc: 16, easierIf: 'journal', ok: 'end_redeemed', fail: 'boss'),
        ModChoice('Cut the bell rope before the third toll', type: ChoiceType.action, check: 'Athletics', dc: 14, ok: 'boss_weak', fail: 'boss'),
        ModChoice('Ring the bell backwards with a holy rite', type: ChoiceType.magic, check: 'Religion', dc: 15, easierIf: 'lore', ok: 'end_banished', fail: 'boss'),
        ModChoice('Attack!', type: ChoiceType.combat, go: 'boss'),
      ],
    ),
    'boss_weak': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'night',
      mood: 'combat',
      text: 'The rope parts. The bell swings silent. Undine howls and lunges for you, her rite broken.',
      combat: ModCombat([
        {'name': 'Sister Undine', 'monster': 'dark_acolyte', 'count': 1, 'hp': 26, 'ac': 13, 'attack_bonus': 5, 'damage': '2d6+1', 'attack_name': 'Coral Knife'},
        {'name': 'Drowned Cultist', 'monster': 'cultist', 'count': 1},
      ], win: 'end_rescue', lose: 'end_lost', boss: true),
    ),
    'boss': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'night',
      mood: 'combat',
      text: 'Undine raises her knife and the water erupts: drowned cultists rise around her, eyes shining like deep-sea fish.',
      combat: ModCombat([
        {'name': 'Sister Undine', 'monster': 'dark_acolyte', 'count': 1, 'hp': 34, 'ac': 14, 'attack_bonus': 5, 'damage': '2d6+2', 'attack_name': 'Coral Knife'},
        {'name': 'Drowned Cultist', 'monster': 'cultist', 'count': 2},
      ], win: 'end_rescue', lose: 'end_lost', boss: true),
    ),
    'end_redeemed': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Maren Holt',
      text:
          'You speak of the mill, the bread ovens, her father\'s laugh. Undine\'s knife wavers. The light from the tower falls across her face, and for a moment she is just a frightened girl. She drops the knife into the tide and weeps.\n\nMaren, freed, puts an arm around her. "We\'ll get you home, lass." At dawn, three figures walk up the cliff path together, and the lighthouse burns bright.',
      events: [
        {'type': 'quest', 'title': 'The Dark Light', 'status': 'completed'},
        {'type': 'xp', 'amount': 400},
        {'type': 'gold', 'amount': 80},
        {'type': 'companion_join', 'name': 'Maren Holt', 'race': 'human', 'class': 'fighter', 'personality': 'Gruff, practical, protective'},
      ],
    ),
    'end_banished': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      text:
          'You chant the rite in reverse. The bell rings — once, wrong, backwards — and the sea answers with a long, unhappy sigh. The drowned ones sink like stones into the tide, Undine among them, and the bell cracks from lip to crown.\n\nMaren is safe. The lighthouse burns. Gull\'s End will tell your story for a hundred years.',
      events: [
        {'type': 'quest', 'title': 'The Dark Light', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 60},
      ],
    ),
    'end_rescue': ModNode(
      title: 'The Drowned Cave',
      loc: 'cave',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Maren Holt',
      text:
          'Undine dissolves into foam and kelp. You cut Maren loose; she rubs her wrists and spits into the sea. "Took your time." Then, gruffly: "Thank you."\n\nShe insists on coming with you — "someone has to keep you out of the water."',
      events: [
        {'type': 'quest', 'title': 'The Dark Light', 'status': 'completed'},
        {'type': 'xp', 'amount': 300},
        {'type': 'gold', 'amount': 50},
        {'type': 'companion_join', 'name': 'Maren Holt', 'race': 'human', 'class': 'fighter', 'personality': 'Gruff, practical, protective'},
      ],
    ),
    'end_lost': ModNode(
      title: 'Gull\'s End Harbor',
      loc: 'coast',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'You wake on the harbor shingle, coughing up seawater, Old Fen pounding your back. The bell rang its third toll in the night — you heard it in your dreams. But the lighthouse burns. Someone lit it. On the gallery rail, a grey-haired figure waves once, and is gone.',
      events: [
        {'type': 'quest', 'title': 'The Dark Light', 'status': 'failed'},
      ],
    ),
  },
);

const copperVault = AdventureModule(
  id: 'copper_vault',
  title: 'The Copper Dragon\'s Vault',
  tagline: 'A dragon who loves jokes, three ridiculous trials, and a rival crew of thieves.',
  description:
      'Copperwhisk, an ancient copper dragon with a terrible sense of humor, opens her vault once a decade to anyone who can make her laugh and pass her trials. This time, Vesh the Quick and her crew want to skip the trials and rob her blind. Help the dragon, join the thieves, or trick everyone.',
  levels: '3–5',
  minutes: 25,
  tone: 'Whimsical',
  setting: 'High fantasy',
  coverLoc: 'mountain',
  coverTime: 'day',
  mapKind: MapKind.dungeon,
  mapName: 'Copperwhisk\'s Vault',
  locations: ['Mountain Door', 'Hall of Jests', 'Trial of Weights', 'Trial of Echoes', 'The Hoard'],
  tags: ['Puzzles', 'Dragon', 'Choices matter'],
  start: 'path',
  nodes: {
    'path': ModNode(
      title: 'Mountain Door',
      loc: 'mountain',
      time: 'day',
      mood: 'calm',
      mapLoc: 'Mountain Door',
      speaker: 'Vesh the Quick',
      text:
          'Carved into the mountainside is a copper door shaped like a grinning dragon. A sign reads: KNOCK KNOCK. Leaning against it is a lanky elf with a dozen daggers and a crooked smile.\n\n"Vesh the Quick," she says. "Me and the boys are going in the back way while the old lizard\'s busy with whoever\'s at the front. Want a cut? Keep her talking. Ten percent."',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'description': 'Pass the dragon\'s trials — or don\'t.', 'status': 'new'},
        {'type': 'npc', 'name': 'Vesh the Quick', 'role': 'thief', 'race': 'elf', 'disposition': 10, 'description': 'Charming, greedy, and quick with a blade.'},
      ],
      choices: [
        ModChoice('Accept Vesh\'s deal', type: ChoiceType.dialogue, go: 'door', set: 'thief'),
        ModChoice('Haggle for half', type: ChoiceType.dialogue, check: 'Persuasion', dc: 14, ok: 'door', fail: 'door', set: 'thief', effects: [
          {'type': 'disposition', 'name': 'Vesh the Quick', 'change': 15},
        ]),
        ModChoice('Refuse — and remember her face', type: ChoiceType.dialogue, go: 'door', set: 'warned'),
      ],
    ),
    'door': ModNode(
      title: 'Mountain Door',
      loc: 'mountain',
      time: 'day',
      mood: 'calm',
      speaker: 'Copperwhisk',
      text: 'You knock. A voice like a gong full of giggles booms from inside the mountain: "WHO\'S THERE?"',
      events: [
        {'type': 'npc', 'name': 'Copperwhisk', 'role': 'copper dragon', 'race': 'dragonborn', 'disposition': 20, 'description': 'Ancient, enormous, and devoted to puns.'},
      ],
      choices: [
        ModChoice('"Lettuce." ("Lettuce who?") "Lettuce in, it\'s cold out here!"', type: ChoiceType.dialogue, go: 'jests_good'),
        ModChoice('"A dragon-slayer." (Very bold.)', type: ChoiceType.dialogue, go: 'jests_bad'),
        ModChoice('Make up your own joke on the spot', type: ChoiceType.dialogue, check: 'Performance', dc: 13, ok: 'jests_good', fail: 'jests_bad'),
      ],
    ),
    'jests_good': ModNode(
      title: 'Hall of Jests',
      loc: 'dungeon',
      time: 'day',
      mood: 'festive',
      mapLoc: 'Hall of Jests',
      sets: ['laughed'],
      text: 'The mountain shakes with laughter. Pebbles rain from the ceiling. The copper door swings open onto a hall painted floor to ceiling with cartoons of startled knights. "OH, THAT\'S GOOD. Come in, come in! Two trials remain!"',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Proceed to the first trial', type: ChoiceType.explore, go: 'weights'),
      ],
    ),
    'jests_bad': ModNode(
      title: 'Hall of Jests',
      loc: 'dungeon',
      time: 'day',
      mood: 'tense',
      mapLoc: 'Hall of Jests',
      text: 'A long, disappointed silence. Then the door opens anyway, with the sound of a dragon sighing. "Fine. FINE. But the floor is lava." It is not lava. It is very hot copper. You hop across, singed.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 4, 'reason': 'very hot copper floor'},
      ],
      choices: [
        ModChoice('Proceed to the first trial', type: ChoiceType.explore, go: 'weights'),
      ],
    ),
    'weights': ModNode(
      title: 'Trial of Weights',
      loc: 'tower',
      time: 'day',
      mood: 'mystery',
      mapLoc: 'Trial of Weights',
      speaker: 'Copperwhisk',
      text:
          'A great brass scale. On one pan sits a gold crown. On the floor, a pile of copper coins, silver spoons and one live chicken. Carved on the scale: "BALANCE THE CROWN, AND BE A FRIEND TO THE CROWNLESS." The chicken looks at you hopefully.',
      choices: [
        ModChoice('Place the chicken on the scale', type: ChoiceType.action, go: 'weights_win'),
        ModChoice('Work out the exact count of coins', type: ChoiceType.explore, check: 'Investigation', dc: 14, ok: 'weights_win', fail: 'weights_fail'),
        ModChoice('Pocket the crown and run', type: ChoiceType.stealth, requires: 'thief', check: 'Sleight of Hand', dc: 15, ok: 'weights_stole', fail: 'weights_fail'),
      ],
    ),
    'weights_win': ModNode(
      title: 'Trial of Weights',
      loc: 'tower',
      time: 'day',
      mood: 'triumph',
      sets: ['trial1'],
      text: 'The scale settles perfectly level. A brass bell dings. "A FRIEND TO THE CROWNLESS CHICKEN! Correct!" The chicken clucks proudly and follows you for the rest of the dungeon.',
      events: [
        {'type': 'xp', 'amount': 100},
        {'type': 'item', 'action': 'add', 'name': 'A Loyal Chicken', 'description': 'Answers to "Sir Clucksworth".'},
      ],
      choices: [
        ModChoice('Continue to the Trial of Echoes', type: ChoiceType.explore, go: 'echoes'),
      ],
    ),
    'weights_stole': ModNode(
      title: 'Trial of Weights',
      loc: 'tower',
      time: 'day',
      mood: 'tense',
      sets: ['crown'],
      text: 'You swap the crown for a fistful of coins in one smooth motion. The scale wobbles, then holds. Nobody saw. Probably.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Copperwhisk\'s Crown', 'description': 'Gold, heavy, and very much not yours.'},
      ],
      choices: [
        ModChoice('Continue to the Trial of Echoes', type: ChoiceType.explore, go: 'echoes'),
      ],
    ),
    'weights_fail': ModNode(
      title: 'Trial of Weights',
      loc: 'tower',
      time: 'day',
      mood: 'tense',
      text: 'The scale slams down. A bucket of cold custard tips onto your head from above. A dragon snickers somewhere in the walls.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Custard (in your hair)', 'description': 'Vanilla, probably.'},
      ],
      choices: [
        ModChoice('Continue to the Trial of Echoes', type: ChoiceType.explore, go: 'echoes'),
      ],
    ),
    'echoes': ModNode(
      title: 'Trial of Echoes',
      loc: 'cave',
      time: 'day',
      mood: 'mystery',
      mapLoc: 'Trial of Echoes',
      speaker: 'Copperwhisk',
      text:
          'A round cavern with three copper pipes: one LOW, one MIDDLE, one HIGH. The dragon\'s voice hums a tune — low, high, middle, high — then falls silent. "SING IT BACK. I\'LL WAIT. I\'M VERY OLD. I\'M GOOD AT WAITING."',
      choices: [
        ModChoice('Low, high, middle, high', type: ChoiceType.dialogue, go: 'echoes_win'),
        ModChoice('Low, middle, high, high', type: ChoiceType.dialogue, go: 'echoes_fail'),
        ModChoice('High, middle, low, high', type: ChoiceType.dialogue, go: 'echoes_fail'),
        ModChoice('Improvise something better', type: ChoiceType.dialogue, check: 'Performance', dc: 15, ok: 'echoes_win', fail: 'echoes_fail'),
      ],
    ),
    'echoes_win': ModNode(
      title: 'Trial of Echoes',
      loc: 'cave',
      time: 'day',
      mood: 'triumph',
      sets: ['trial2'],
      text: 'The pipes ring in perfect harmony. Somewhere ahead, a great vault door rumbles open, and a smell of old gold and toasted almonds rolls out.',
      events: [
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Enter the hoard', type: ChoiceType.explore, go: 'hoard'),
      ],
    ),
    'echoes_fail': ModNode(
      title: 'Trial of Echoes',
      loc: 'cave',
      time: 'day',
      mood: 'tense',
      text: 'The pipes honk like geese. The echo is so loud it knocks you off your feet. "CLOSE ENOUGH," the dragon grumbles. The vault door opens anyway.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 5, 'reason': 'thunderous echo'},
      ],
      choices: [
        ModChoice('Enter the hoard', type: ChoiceType.explore, go: 'hoard'),
      ],
    ),
    'hoard': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'tense',
      mapLoc: 'The Hoard',
      speaker: 'Copperwhisk',
      text:
          'Mountains of coins. Statues wearing hats. A copper dragon the size of a barn, lying on her back like a cat, beaming at you. "WELL DONE! Now — your reward—"\n\nA side passage bursts open. Vesh the Quick and three thieves sprint in, sacks open. "Keep her busy!" Vesh yells at you.',
      choices: [
        ModChoice('Warn Copperwhisk and fight the thieves', type: ChoiceType.combat, go: 'thieves_fight', set: 'loyal'),
        ModChoice('Stall the dragon with your best joke', type: ChoiceType.dialogue, requires: 'thief', check: 'Deception', dc: 16, ok: 'end_rich', fail: 'end_caught'),
        ModChoice('Offer the stolen crown back to the dragon', type: ChoiceType.dialogue, requires: 'item:Copperwhisk\'s Crown', go: 'end_honest', effects: [
          {'type': 'item', 'action': 'remove', 'name': 'Copperwhisk\'s Crown'},
        ]),
        ModChoice('Convince Vesh the dragon is in on the joke', type: ChoiceType.dialogue, check: 'Persuasion', dc: 14, ok: 'end_friends', fail: 'thieves_fight'),
      ],
    ),
    'thieves_fight': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'combat',
      text: '"Traitor!" Vesh flips two daggers into her hands. Copperwhisk rolls over with interest. "Ooh, a fight! I\'ll watch."',
      combat: ModCombat([
        {'name': 'Vesh the Quick', 'monster': 'bandit', 'count': 1, 'hp': 28, 'ac': 15, 'attack_bonus': 5, 'damage': '1d6+3', 'attack_name': 'Twin Daggers'},
        {'name': 'Vault Thief', 'monster': 'bandit', 'count': 2},
      ], win: 'end_friend', lose: 'end_robbed', boss: true),
    ),
    'end_friend': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Copperwhisk',
      text:
          'The thieves flee down the mountain, minus their sacks and their dignity. Copperwhisk sweeps you into a hug that is mostly claws. "A TRUE FRIEND! Take this — I insist." She presses a warm copper scale into your hands. It tingles with magic and smells faintly of almonds.',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'completed'},
        {'type': 'xp', 'amount': 400},
        {'type': 'gold', 'amount': 250},
        {'type': 'item', 'action': 'add', 'name': 'Copperwhisk\'s Scale', 'description': 'A dragon\'s gift. Warm to the touch; it laughs at your jokes.'},
        {'type': 'item', 'action': 'add', 'id': 'potion_greater', 'name': 'Potion of Greater Healing'},
      ],
    ),
    'end_honest': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Copperwhisk',
      text: 'You hold out the crown. The dragon blinks. Then she laughs so hard the thieves are blown back out of the side passage. "AN HONEST THIEF! The rarest treasure of all!" She lets you keep the crown.',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 150},
        {'type': 'item', 'action': 'add', 'name': 'Copperwhisk\'s Crown', 'description': 'Freely given this time.'},
      ],
    ),
    'end_friends': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'festive',
      end: 'victory',
      text:
          'Somehow, it works. Vesh lowers her daggers, Copperwhisk produces cake, and by midnight the thieves and the dragon are telling jokes around a bonfire of old furniture. Vesh gives you her card: "If you ever need a job done quick."',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 120},
      ],
    ),
    'end_rich': ModNode(
      title: 'The Mountain Road',
      loc: 'mountain',
      time: 'dusk',
      mood: 'tense',
      end: 'bittersweet',
      text:
          'You tell the longest joke of your life. By the punchline, Vesh and her crew are gone with four sacks of gold — and your ten percent is waiting under a rock on the mountain road, as promised. You are rich.\n\nYou are also fairly sure a copper dragon now knows your face. And she has a very long memory.',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'completed'},
        {'type': 'xp', 'amount': 250},
        {'type': 'gold', 'amount': 400},
        {'type': 'condition', 'target': 'hero', 'name': 'Dragon\'s Grudge', 'action': 'add'},
      ],
    ),
    'end_caught': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'sad',
      end: 'bittersweet',
      speaker: 'Copperwhisk',
      text: 'The dragon\'s eyes narrow mid-joke. One sweep of her tail and all of you — thieves included — are sitting outside the mountain in a pile, with the door locked and a sign reading: NO SENSE OF HUMOR. GO AWAY.',
      events: [
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'failed'},
      ],
    ),
    'end_robbed': ModNode(
      title: 'The Hoard',
      loc: 'cave',
      time: 'day',
      mood: 'sad',
      end: 'bittersweet',
      text: 'You wake with a bump on your head. The thieves are long gone, and so is half the hoard. Copperwhisk pats you gently with one claw. "You tried. That\'s the funniest part." She gives you a single gold coin as a souvenir.',
      events: [
        {'type': 'gold', 'amount': 1},
        {'type': 'quest', 'title': 'Copperwhisk\'s Challenge', 'status': 'failed'},
      ],
    ),
  },
);

const masquerade = AdventureModule(
  id: 'masquerade',
  title: 'Masquerade at House Valtieri',
  tagline: 'A masked ball, a poisoned cup, and one hour until midnight.',
  description:
      'Lady Isadora Valtieri is throwing the masquerade of the season, and she plans to poison the Duke when the clock strikes twelve. Your contact, the bard Lucan, needs proof and a plan. Talk, sneak, lockpick and duel your way through an evening of intrigue.',
  levels: '2–5',
  minutes: 30,
  tone: 'Mysterious',
  setting: 'Arcane city',
  coverLoc: 'castle',
  coverTime: 'night',
  mapKind: MapKind.town,
  mapName: 'Villa Valtieri',
  locations: ['Valtieri Gates', 'Grand Ballroom', 'The Gallery', 'Wine Cellar', 'Lady\'s Study', 'Moonlit Balcony'],
  tags: ['Intrigue', 'Social', 'Heist'],
  start: 'gates',
  nodes: {
    'gates': ModNode(
      title: 'Valtieri Gates',
      loc: 'castle',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'Valtieri Gates',
      speaker: 'Lucan',
      text:
          'Carriages roll up a drive lit by floating lanterns. A half-elf bard in a fox mask falls into step beside you. "Lucan. We spoke by letter." He lowers his voice. "Isadora means to poison the Duke at midnight, during the toast. I need proof — her ledger — or the guards will never believe us. One hour."\n\nThe steward at the gate is checking invitations. You don\'t have one.',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'description': 'Find proof of Lady Isadora\'s plot and stop the Duke from being poisoned at midnight.', 'status': 'new'},
        {'type': 'npc', 'name': 'Lucan', 'role': 'bard and spy', 'race': 'half-elf', 'disposition': 40, 'description': 'Charming, nervous, and in over his head.'},
      ],
      choices: [
        ModChoice('Bluff past the steward', type: ChoiceType.dialogue, check: 'Deception', dc: 13, ok: 'ballroom', fail: 'gates_guard'),
        ModChoice('Climb the garden wall', type: ChoiceType.action, check: 'Athletics', dc: 12, ok: 'ballroom', fail: 'gates_guard', set: 'wall'),
        ModChoice('Bribe the steward (20 gp)', type: ChoiceType.action, requires: 'gold:20', go: 'ballroom', effects: [
          {'type': 'gold', 'amount': -20},
        ]),
        ModChoice('Introduce yourself as nobility', type: ChoiceType.dialogue, requires: 'race:elf|half-elf|tiefling', check: 'Persuasion', dc: 10, ok: 'ballroom', fail: 'gates_guard'),
      ],
    ),
    'gates_guard': ModNode(
      title: 'Valtieri Gates',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      text: '"Gatecrasher!" Two guards in silver masks close in, rapiers drawn. Lucan groans. "Quietly. Please. QUIETLY."',
      combat: ModCombat([
        {'name': 'Valtieri Guard', 'monster': 'hobgoblin', 'count': 2, 'hp': 9},
      ], win: 'ballroom'),
    ),
    'ballroom': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'festive',
      mapLoc: 'Grand Ballroom',
      text:
          'Chandeliers of floating candles. A string quartet. Two hundred masked guests. The Duke, portly and cheerful, holds court by the fireplace. On the balcony, a woman in a silver swan mask watches the room like a hawk: Lady Isadora.\n\nThe clock above the doors reads a quarter past eleven.',
      choices: [
        ModChoice('Dance with the Duke\'s guard captain', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'ball_captain', fail: 'ball_snub', unless: 'captain'),
        ModChoice('Eavesdrop on Isadora\'s servants', type: ChoiceType.stealth, check: 'Perception', dc: 13, ok: 'ball_cellar_tip', fail: 'ball_snub', unless: 'cellar_tip'),
        ModChoice('Slip into the gallery', type: ChoiceType.explore, go: 'gallery', unless: 'study_open'),
        ModChoice('Go down to the wine cellar', type: ChoiceType.explore, go: 'cellar', unless: 'swapped'),
        ModChoice('Head to the study', type: ChoiceType.explore, requires: 'study_open', go: 'study', unless: 'ledger'),
        ModChoice('It is almost midnight — go to the balcony', type: ChoiceType.explore, go: 'balcony'),
      ],
    ),
    'ball_captain': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'festive',
      speaker: 'Captain Renna',
      sets: ['captain'],
      text:
          'Captain Renna dances like she fights: precisely. "I know something\'s wrong tonight," she murmurs. "Bring me proof — real proof — and I\'ll arrest anyone in this house. Even her." She spins you away.',
      events: [
        {'type': 'npc', 'name': 'Captain Renna', 'role': 'Duke\'s guard captain', 'race': 'human', 'disposition': 30, 'description': 'Stern, honest, and suspicious of everyone.'},
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Return to the party', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'ball_cellar_tip': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'mystery',
      sets: ['cellar_tip'],
      text: 'Two footmen whisper behind a pillar: "…the Moonvale \'09, the bottle with the blue wax. Only for the Duke\'s cup. Madam was very clear." One of them looks nervously toward the cellar stairs.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Return to the party', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'ball_snub': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'calm',
      text: 'Your attempt goes nowhere. Someone steps on your foot. A duchess asks if you are "one of the entertainers." The clock ticks on.',
      choices: [
        ModChoice('Return to the party', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'gallery': ModNode(
      title: 'The Gallery',
      loc: 'castle',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'The Gallery',
      text:
          'Portraits of Valtieris past glare down a long, quiet hall. At the end, a portrait of Isadora as a girl holds a book — and the book\'s gilt frame is worn shiny, as if touched often.',
      choices: [
        ModChoice('Search for a hidden mechanism', type: ChoiceType.explore, check: 'Investigation', dc: 12, ok: 'gallery_open', fail: 'gallery_noise'),
        ModChoice('Press the worn book in the painting', type: ChoiceType.action, go: 'gallery_open'),
        ModChoice('Return to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'gallery_open': ModNode(
      title: 'The Gallery',
      loc: 'castle',
      time: 'night',
      mood: 'mystery',
      sets: ['study_open'],
      text: 'Click. The portrait swings inward on silent hinges, revealing a narrow stair that smells of ink and sealing wax: the Lady\'s private study.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Climb to the study', type: ChoiceType.explore, go: 'study'),
      ],
    ),
    'gallery_noise': ModNode(
      title: 'The Gallery',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      text: 'You knock a candlestick over. Footsteps approach — you hide behind a curtain until they pass. The clock strikes half past eleven.',
      choices: [
        ModChoice('Try the painting again', type: ChoiceType.action, go: 'gallery_open'),
        ModChoice('Return to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'cellar': ModNode(
      title: 'Wine Cellar',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Wine Cellar',
      text:
          'Racks of bottles vanish into the dark. On a silver tray by the stairs waits a single bottle sealed with blue wax and a crystal goblet with a ducal crest — ready to be carried up at midnight.',
      choices: [
        ModChoice('Identify what\'s in the wine', type: ChoiceType.explore, check: 'Medicine', dc: 12, easierIf: 'cellar_tip', ok: 'cellar_swap', fail: 'cellar_sick'),
        ModChoice('Swap it for a bottle from the racks', type: ChoiceType.stealth, requires: 'cellar_tip', go: 'cellar_swap'),
        ModChoice('Return to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'cellar_swap': ModNode(
      title: 'Wine Cellar',
      loc: 'dungeon',
      time: 'night',
      mood: 'triumph',
      sets: ['swapped'],
      text: 'Bitter almond under the sweetness: deathcap and nightshade. You switch the bottle for an identical vintage and pocket the poison. Evidence — and the Duke\'s cup is safe.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Poisoned Moonvale', 'description': 'A bottle of wine laced with deathcap. Evidence.'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Return to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'cellar_sick': ModNode(
      title: 'Wine Cellar',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      text: 'You sniff too deeply. Your head spins and your stomach lurches. Poison — definitely poison. You stagger back to the stairs, the bottle still on its tray.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 4, 'reason': 'poison fumes'},
        {'type': 'condition', 'target': 'hero', 'name': 'Poisoned', 'action': 'add'},
      ],
      choices: [
        ModChoice('Try again, carefully', type: ChoiceType.explore, check: 'Medicine', dc: 10, ok: 'cellar_swap', fail: 'ballroom'),
        ModChoice('Return to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
      ],
    ),
    'study': ModNode(
      title: 'Lady\'s Study',
      loc: 'tower',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Lady\'s Study',
      text: 'A writing desk, a locked drawer, a cold fireplace. On the blotter, a half-written letter: "…by morning the Duchy will need a regent, and I will be ready…"',
      choices: [
        ModChoice('Pick the drawer lock', type: ChoiceType.action, check: 'Sleight of Hand', dc: 13, ok: 'study_ledger', fail: 'study_ambush'),
        ModChoice('Force the drawer', type: ChoiceType.action, check: 'Athletics', dc: 14, ok: 'study_ambush', fail: 'study_ambush'),
        ModChoice('Open it with a whispered cantrip', type: ChoiceType.magic, requires: 'class:wizard|sorcerer|bard|warlock', go: 'study_ledger'),
      ],
    ),
    'study_ledger': ModNode(
      title: 'Lady\'s Study',
      loc: 'tower',
      time: 'night',
      mood: 'triumph',
      sets: ['ledger'],
      text: 'Inside the drawer: a slim black ledger. Payments to an apothecary, to two guards, to a forger of ducal seals — all in Isadora\'s own hand. Proof.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Valtieri Ledger', 'description': 'Proof of Lady Isadora\'s plot, in her own handwriting.'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Hurry back to the ballroom', type: ChoiceType.explore, go: 'ballroom'),
        ModChoice('Go straight to the balcony', type: ChoiceType.explore, go: 'balcony'),
      ],
    ),
    'study_ambush': ModNode(
      title: 'Lady\'s Study',
      loc: 'tower',
      time: 'night',
      mood: 'combat',
      text: 'The drawer splinters loudly. Behind you, the fireplace slides aside and a masked duelist steps out, rapier first. "Madam said someone might come snooping."',
      combat: ModCombat([
        {'name': 'Masked Duelist', 'monster': 'bandit', 'count': 1, 'hp': 24, 'ac': 15, 'attack_bonus': 5, 'damage': '1d8+3', 'attack_name': 'Rapier'},
      ], win: 'study_ledger'),
    ),
    'balcony': ModNode(
      title: 'Moonlit Balcony',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Moonlit Balcony',
      speaker: 'Lady Isadora',
      text:
          'The clock begins to strike twelve. Below, a footman carries a crystal goblet toward the Duke. On the balcony, Lady Isadora turns her swan mask toward you. "You\'re not on my guest list," she says pleasantly. "How exciting."',
      events: [
        {'type': 'npc', 'name': 'Lady Isadora', 'role': 'host and schemer', 'race': 'elf', 'disposition': -30, 'description': 'Elegant, patient, and utterly ruthless.'},
      ],
      choices: [
        ModChoice('Hand the ledger to Captain Renna', type: ChoiceType.dialogue, requires: 'ledger', unless: '!captain', go: 'end_arrest'),
        ModChoice('Read the ledger aloud to the whole ballroom', type: ChoiceType.dialogue, requires: 'ledger', unless: 'captain', go: 'end_exposed'),
        ModChoice('Shout a warning and show the poisoned wine', type: ChoiceType.dialogue, requires: 'item:Poisoned Moonvale', go: 'end_exposed'),
        ModChoice('Let the toast happen — the wine is safe', type: ChoiceType.dialogue, requires: 'swapped', go: 'end_switch'),
        ModChoice('Knock the goblet from the footman\'s hand', type: ChoiceType.action, check: 'Acrobatics', dc: 14, ok: 'boss', fail: 'end_poisoned'),
        ModChoice('Draw steel on Isadora', type: ChoiceType.combat, go: 'boss'),
      ],
    ),
    'boss': ModNode(
      title: 'Moonlit Balcony',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      speaker: 'Lady Isadora',
      text: 'Isadora sighs and draws a slender blade from her fan. Her bodyguard vaults the balustrade. "Very well. Let\'s make it look like a robbery."',
      combat: ModCombat([
        {'name': 'Lady Isadora', 'monster': 'bandit', 'count': 1, 'hp': 30, 'ac': 15, 'attack_bonus': 6, 'damage': '1d8+3', 'attack_name': 'Fan Blade'},
        {'name': 'Valtieri Bodyguard', 'monster': 'hobgoblin', 'count': 1},
      ], win: 'end_duel', lose: 'end_poisoned', boss: true),
    ),
    'end_arrest': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Captain Renna',
      text:
          'Renna reads three pages and goes pale, then very calm. "Lady Isadora Valtieri, you are under arrest." The music stops. The Duke\'s goblet is taken away and poured into a potted fern, which promptly dies.\n\nThe next morning, a ducal seal arrives at your inn: an invitation to court, and a purse heavy enough to need two hands.',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'status': 'completed'},
        {'type': 'xp', 'amount': 450},
        {'type': 'gold', 'amount': 200},
        {'type': 'item', 'action': 'add', 'name': 'Ducal Signet', 'description': 'A token of the Duke\'s favor.'},
      ],
    ),
    'end_exposed': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text: 'You hold the blue-wax bottle high and pour a drop on the marble. It hisses and smokes. Two hundred masked faces turn toward Isadora. She smiles, bows — and vanishes in a puff of perfumed smoke. The Duke lives. Isadora is gone. For now.',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 120},
      ],
    ),
    'end_switch': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'festive',
      end: 'victory',
      text:
          'The clock strikes twelve. The Duke drinks. He smacks his lips. "Marvellous vintage!" Isadora\'s smile freezes; she drops her own glass. In the confusion, Lucan whispers to the guard captain, who begins asking Isadora some very pointed questions.',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 100},
      ],
    ),
    'end_duel': ModNode(
      title: 'Moonlit Balcony',
      loc: 'castle',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text: 'Isadora\'s blade clatters across the balcony. Guards flood up the stairs, drawn by the noise, and find the Lady of the house disarmed at your feet and a goblet of poison on a footman\'s tray. The truth comes out quickly after that.',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'status': 'completed'},
        {'type': 'xp', 'amount': 400},
        {'type': 'gold', 'amount': 150},
      ],
    ),
    'end_poisoned': ModNode(
      title: 'Grand Ballroom',
      loc: 'castle',
      time: 'night',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'The clock finishes striking. The Duke raises his cup, drinks, and coughs — once, twice — and the music dies. In the chaos, Isadora is suddenly the calmest person in the room, already giving orders. Lucan pulls you out through the kitchens. "We\'re not done," he says. "This was only the first move."',
      events: [
        {'type': 'quest', 'title': 'Midnight Toast', 'status': 'failed'},
      ],
    ),
  },
);

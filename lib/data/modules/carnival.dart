import '../../game/module_engine.dart';
import '../../models/adventure.dart';

const midnightCarnival = AdventureModule(
  id: 'midnight_carnival',
  title: 'The Midnight Carnival',
  tagline: 'A fey carnival has come to town, and the children have stopped laughing.',
  description:
      'Overnight, a striped carnival appears outside the village of Thistlewick. Every child who visited came home unable to laugh. Explore a hall of mirrors, free a menagerie, read your fortune, and face Mister Grinsworth, the ringmaster who bottles laughter in glass jars.',
  levels: '1–3',
  minutes: 25,
  tone: 'Whimsical',
  setting: 'Fey wilds',
  coverLoc: 'town',
  coverTime: 'dusk',
  mapKind: MapKind.town,
  mapName: 'The Midnight Carnival',
  locations: ['Thistlewick Green', 'Carnival Gate', 'The Midway', 'Hall of Mirrors', 'The Menagerie', 'Fortune Tent', 'The Big Top'],
  tags: ['Fey', 'Puzzles', 'Peaceful endings'],
  start: 'start',
  nodes: {
    'start': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      mapLoc: 'Thistlewick Green',
      speaker: 'Widow Pell',
      text:
          'Lanterns bob on strings above the village green. Beyond the last cottage, a carnival glows where there was only a turnip field yesterday, its calliope wheezing a tune that is almost, but not quite, cheerful.\n\nWidow Pell grips your sleeve. "My grandson Tobin went to that carnival. He came back smiling — but he can\'t laugh. Not at anything. None of the children can." Tobin stares at you with a polite, empty grin.',
      events: [
        {'type': 'quest', 'title': 'The Stolen Laughter', 'description': 'Find out what the carnival did to the children of Thistlewick and bring their laughter back.', 'status': 'new'},
        {'type': 'npc', 'name': 'Widow Pell', 'role': 'worried grandmother', 'race': 'halfling', 'disposition': 30, 'description': 'Fierce, small, and out of patience.'},
      ],
      choices: [
        ModChoice('Examine Tobin for signs of magic', type: ChoiceType.explore, check: 'Medicine', dc: 12, ok: 'start_magic', fail: 'start_puzzled', set: 'examined'),
        ModChoice('Ask the villagers what they saw', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'start_rumor', fail: 'start_shrug', set: 'asked'),
        ModChoice('Detect the fey magic on the boy', type: ChoiceType.magic, requires: 'class:wizard|sorcerer|warlock|druid', go: 'start_magic', set: 'examined', unless: 'examined'),
        ModChoice('Head straight for the carnival', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'start_magic': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      sets: ['fey'],
      text:
          'A fine silver glitter clings to Tobin\'s lips — fey dust. His laughter wasn\'t destroyed; it was taken, the way you might pluck a bird from a tree. Somewhere, it is still alive and wanting to come home.',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Ask the villagers what they saw', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'start_rumor', fail: 'start_shrug', set: 'asked', unless: 'asked'),
        ModChoice('Go to the carnival', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'start_puzzled': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      text: 'Tobin is healthy in every way you can measure. That is the frightening part. Whatever is missing, it isn\'t something a healer can find.',
      choices: [
        ModChoice('Ask the villagers what they saw', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'start_rumor', fail: 'start_shrug', set: 'asked', unless: 'asked'),
        ModChoice('Go to the carnival', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'start_rumor': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      sets: ['secrets'],
      text:
          'The miller\'s wife leans close. "They don\'t take coin at the gate. They take secrets. And the ringmaster — Grinsworth — he wears a hat so tall it scrapes the tent. My boy said it was clinking. Like jars."',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Examine Tobin for signs of magic', type: ChoiceType.explore, check: 'Medicine', dc: 12, ok: 'start_magic', fail: 'start_puzzled', set: 'examined', unless: 'examined'),
        ModChoice('Go to the carnival', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'start_shrug': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      text: 'The villagers mutter and look away. Nobody wants to be the one who angers whatever lives in that tent.',
      choices: [
        ModChoice('Examine Tobin for signs of magic', type: ChoiceType.explore, check: 'Medicine', dc: 12, ok: 'start_magic', fail: 'start_puzzled', set: 'examined', unless: 'examined'),
        ModChoice('Go to the carnival', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'gate': ModNode(
      title: 'Carnival Gate',
      loc: 'town',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Carnival Gate',
      speaker: 'Snick',
      text:
          'A goblin in a top hat three sizes too large sits in the ticket booth, swinging his legs. "Welcome, welcome! Admission is one secret, freshly told. Or one laugh, if you\'re feeling generous." He taps a glass jar on the counter. It hums.',
      events: [
        {'type': 'npc', 'name': 'Snick', 'role': 'ticket-taker', 'race': 'gnome', 'disposition': 0, 'description': 'A goblin with a top hat and terrible manners.'},
      ],
      choices: [
        ModChoice('Tell him a true secret', type: ChoiceType.dialogue, go: 'midway', effects: [
          {'type': 'disposition', 'name': 'Snick', 'change': 20},
        ]),
        ModChoice('Feed him a convincing lie', type: ChoiceType.dialogue, check: 'Deception', dc: 13, ok: 'midway', fail: 'gate_fight'),
        ModChoice('Slip under the canvas', type: ChoiceType.stealth, check: 'Stealth', dc: 12, ok: 'midway', fail: 'gate_fight', set: 'sneaked'),
        ModChoice('Lift a ticket from his pocket', type: ChoiceType.stealth, requires: 'class:rogue', go: 'midway', set: 'sneaked'),
      ],
    ),
    'gate_fight': ModNode(
      title: 'Carnival Gate',
      loc: 'town',
      time: 'night',
      mood: 'combat',
      speaker: 'Snick',
      text: '"CHEATER!" Snick blows a tin whistle. Two carnival hands in striped shirts vault the fence, grinning with too many teeth.',
      combat: ModCombat([
        {'name': 'Carnival Hand', 'monster': 'goblin', 'count': 2},
      ], win: 'midway'),
    ),
    'midway': ModNode(
      title: 'The Midway',
      loc: 'town',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'The Midway',
      text:
          'Paper lanterns drift overhead with no strings. Stalls sell candied moths and wishes by the ounce. Paths branch toward a glittering Hall of Mirrors, a creaking Menagerie, a purple Fortune Tent — and the great striped Big Top, where the music is loudest.',
      choices: [
        ModChoice('Enter the Hall of Mirrors', type: ChoiceType.explore, go: 'mirrors', unless: 'mirrors_done'),
        ModChoice('Visit the Menagerie', type: ChoiceType.explore, go: 'menagerie', unless: 'menagerie_done'),
        ModChoice('Have your fortune told', type: ChoiceType.explore, go: 'fortune', unless: 'fortune_done'),
        ModChoice('Walk into the Big Top', type: ChoiceType.explore, go: 'bigtop'),
      ],
    ),
    'mirrors': ModNode(
      title: 'Hall of Mirrors',
      loc: 'tower',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Hall of Mirrors',
      sets: ['mirrors_done'],
      text:
          'A hundred {first}s stare back at you. Then, one by one, they stop copying you. They tilt their heads. They smile. A child\'s giggle echoes from somewhere deep inside the glass.',
      choices: [
        ModChoice('Find the one reflection that doesn\'t blink', type: ChoiceType.explore, check: 'Perception', dc: 13, ok: 'mirrors_win', fail: 'mirrors_fight'),
        ModChoice('Shatter the mirrors', type: ChoiceType.action, check: 'Athletics', dc: 12, ok: 'mirrors_win', fail: 'mirrors_fight', effects: [
          {'type': 'damage', 'target': 'hero', 'amount': 2, 'reason': 'flying glass'},
        ]),
        ModChoice('Ask your reflection what it wants', type: ChoiceType.dialogue, check: 'Persuasion', dc: 14, ok: 'mirrors_secret', fail: 'mirrors_fight'),
      ],
    ),
    'mirrors_win': ModNode(
      title: 'Hall of Mirrors',
      loc: 'tower',
      time: 'night',
      mood: 'triumph',
      text:
          'You find it: the one reflection that is just glass. Behind it, on a velvet cushion, sits a stoppered jar full of tiny golden giggles. When you pick it up, it laughs.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Jar of Giggles', 'description': 'A glass jar of stolen laughter. It hums happily.'},
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'mirrors_secret': ModNode(
      title: 'Hall of Mirrors',
      loc: 'tower',
      time: 'night',
      mood: 'mystery',
      sets: ['weakness'],
      speaker: 'Your reflection',
      text:
          'Your reflection leans close, mouth not quite matching yours. "Grinsworth eats laughter, but he can\'t stand the real thing. Make a whole crowd laugh — honestly laugh — and his jars will burst." It winks, and becomes ordinary glass.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'mirrors_fight': ModNode(
      title: 'Hall of Mirrors',
      loc: 'tower',
      time: 'night',
      mood: 'combat',
      text: 'Two of your reflections step out of the glass, cracking their knuckles in perfect unison with you.',
      combat: ModCombat([
        {'name': 'Mirror Double', 'monster': 'shadow', 'count': 2, 'hp': 10},
      ], win: 'mirrors_win'),
    ),
    'menagerie': ModNode(
      title: 'The Menagerie',
      loc: 'camp',
      time: 'night',
      mood: 'sad',
      mapLoc: 'The Menagerie',
      sets: ['menagerie_done'],
      text:
          'Cages line a sawdust ring. A raven with silver-tipped feathers watches you. In the largest cage, an owlbear cub — all fluff and beak — sits with its head on its paws. A sign reads: BISCUIT. DO NOT FEED.',
      events: [
        {'type': 'npc', 'name': 'Quoth', 'role': 'talking raven', 'disposition': 10, 'description': 'A raven with silver feathers and opinions.'},
      ],
      choices: [
        ModChoice('Pick the lock on Biscuit\'s cage', type: ChoiceType.action, check: 'Sleight of Hand', dc: 13, ok: 'menagerie_free', fail: 'menagerie_alarm'),
        ModChoice('Calm the owlbear cub', type: ChoiceType.dialogue, check: 'Animal Handling', dc: 12, ok: 'menagerie_free', fail: 'menagerie_alarm'),
        ModChoice('Talk to the raven', type: ChoiceType.dialogue, go: 'menagerie_raven'),
        ModChoice('Speak with the cub in its own language', type: ChoiceType.magic, requires: 'class:druid|ranger', go: 'menagerie_free'),
      ],
    ),
    'menagerie_raven': ModNode(
      title: 'The Menagerie',
      loc: 'camp',
      time: 'night',
      mood: 'mystery',
      speaker: 'Quoth',
      sets: ['hat'],
      text:
          '"Jars," croaks Quoth. "Jars and jars. He keeps them under his hat. Tall hat, tall secrets. Knock it off his head and the whole lot comes tumbling." The raven fluffs up. "That\'ll be one shiny button, please."',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Free Biscuit while you\'re here', type: ChoiceType.action, check: 'Sleight of Hand', dc: 13, ok: 'menagerie_free', fail: 'menagerie_alarm'),
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'menagerie_free': ModNode(
      title: 'The Menagerie',
      loc: 'camp',
      time: 'night',
      mood: 'triumph',
      sets: ['biscuit'],
      text:
          'The cage swings open. Biscuit tumbles out, sniffs your boots, and headbutts you so affectionately you nearly fall over. Then it trots off into the dark — toward the Big Top. Something tells you it will be there when you need it.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'menagerie_alarm': ModNode(
      title: 'The Menagerie',
      loc: 'camp',
      time: 'night',
      mood: 'combat',
      text: 'A bell above the cage clangs. Two burly handlers in greasepaint stomp into the ring with clubs.',
      combat: ModCombat([
        {'name': 'Greasepaint Bruiser', 'monster': 'bandit', 'count': 2},
      ], win: 'menagerie_free'),
    ),
    'fortune': ModNode(
      title: 'Fortune Tent',
      loc: 'temple',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'Fortune Tent',
      sets: ['fortune_done'],
      speaker: 'Madame Ysolde',
      text:
          'Incense curls around an old woman with a crystal eye. "Sit, sit. I am no friend of Grinsworth\'s — he took my laugh too, forty years ago." She fans three cards face-down. "Choose. The cards are honest, even if I am not."',
      events: [
        {'type': 'npc', 'name': 'Madame Ysolde', 'role': 'fortune teller', 'disposition': 35, 'description': 'A sly old witch with a crystal eye.'},
      ],
      choices: [
        ModChoice('Draw a card', type: ChoiceType.magic, random: ['card_tower', 'card_moon', 'card_fool']),
        ModChoice('Read her instead', type: ChoiceType.explore, check: 'Insight', dc: 12, ok: 'fortune_truth', fail: 'card_fool'),
      ],
    ),
    'card_tower': ModNode(
      title: 'Fortune Tent',
      loc: 'temple',
      time: 'night',
      mood: 'mystery',
      speaker: 'Madame Ysolde',
      text: '"The Tower. Something tall will fall tonight." She presses a warm red vial into your hand. "For when it lands on you."',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'potion_healing', 'name': 'Potion of Healing'},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'card_moon': ModNode(
      title: 'Fortune Tent',
      loc: 'temple',
      time: 'night',
      mood: 'mystery',
      speaker: 'Madame Ysolde',
      sets: ['weakness'],
      text: '"The Moon. Truth hidden in a joke." She taps the card. "He feeds on stolen laughter, child. Real laughter, freely given, is poison to him."',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'card_fool': ModNode(
      title: 'Fortune Tent',
      loc: 'temple',
      time: 'night',
      mood: 'calm',
      speaker: 'Madame Ysolde',
      text: '"The Fool!" She cackles. "Brave, reckless, lucky. Go on, then — the Fool never knows when to stop, and sometimes that is exactly right."',
      events: [
        {'type': 'heal', 'target': 'hero', 'amount': 5},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'fortune_truth': ModNode(
      title: 'Fortune Tent',
      loc: 'temple',
      time: 'night',
      mood: 'mystery',
      speaker: 'Madame Ysolde',
      sets: ['weakness', 'hat'],
      text:
          'You catch the tremble in her hands. She stops pretending. "Fine. Two things. The jars are under his hat. And he cannot abide true laughter. Give the crowd something honest to laugh at, and he\'ll burst like a bad sausage."',
      events: [
        {'type': 'xp', 'amount': 50},
        {'type': 'disposition', 'name': 'Madame Ysolde', 'change': 20},
      ],
      choices: [
        ModChoice('Return to the Midway', type: ChoiceType.explore, go: 'midway'),
      ],
    ),
    'bigtop': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Big Top',
      speaker: 'Mister Grinsworth',
      text:
          'Under the great striped tent, an audience of silent children sits in neat rows. In the ring stands Mister Grinsworth: thin as a candle, coat of patchwork moonlight, and a hat so tall it disappears into the dark. It clinks when he bows.\n\n"A volunteer!" he purrs, spotting you. "How delicious. Come, come — make them laugh, if you can."',
      events: [
        {'type': 'npc', 'name': 'Mister Grinsworth', 'role': 'ringmaster', 'race': 'elf', 'disposition': -40, 'description': 'A fey ringmaster who bottles laughter.'},
      ],
      choices: [
        ModChoice('Perform something truly funny', type: ChoiceType.dialogue, check: 'Performance', dc: 15, easierIf: 'weakness', ok: 'end_laugh', fail: 'boss_fight'),
        ModChoice('Knock his hat off', type: ChoiceType.action, check: 'Acrobatics', dc: 15, easierIf: 'hat', ok: 'end_hat', fail: 'boss_fight'),
        ModChoice('Uncork the Jar of Giggles in front of everyone', type: ChoiceType.magic, requires: 'item:Jar of Giggles', go: 'end_laugh'),
        ModChoice('Whistle for Biscuit', type: ChoiceType.action, requires: 'biscuit', go: 'boss_biscuit'),
        ModChoice('Attack the ringmaster', type: ChoiceType.combat, go: 'boss_fight'),
      ],
    ),
    'boss_fight': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'combat',
      speaker: 'Mister Grinsworth',
      text: '"How DULL." Grinsworth snaps his fingers, and two grinning carnival hands drop from the trapeze.',
      combat: ModCombat([
        {'name': 'Mister Grinsworth', 'monster': 'dark_acolyte', 'count': 1, 'hp': 30, 'ac': 13, 'attack_bonus': 4, 'damage': '1d10+1', 'attack_name': 'Cane of Mockery'},
        {'name': 'Carnival Hand', 'monster': 'goblin', 'count': 1},
      ], win: 'end_fight', lose: 'end_lost', boss: true),
    ),
    'boss_biscuit': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'combat',
      text:
          'With a joyful hoot, Biscuit the owlbear cub barrels through the tent flap and bowls Grinsworth over like a skittle. Jars rattle in his hat. The children gasp — and one of them, just one, hiccups something that is almost a giggle. Grinsworth staggers up, furious and wounded.',
      combat: ModCombat([
        {'name': 'Mister Grinsworth', 'monster': 'dark_acolyte', 'count': 1, 'hp': 16, 'ac': 13, 'attack_bonus': 4, 'damage': '1d10', 'attack_name': 'Cane of Mockery'},
      ], win: 'end_hat', lose: 'end_lost', boss: true),
    ),
    'end_laugh': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text:
          'It starts with one child — a snort, a wheeze — and then the whole tent erupts. Real laughter, loud and messy and free. Grinsworth\'s hat shudders. Pop. Pop-pop-pop. A hundred jars burst, and golden giggles fly home like sparrows.\n\nThe ringmaster shrinks to the size of a teacup and scampers away squeaking. By dawn, the carnival is just a turnip field again — except for one owlbear cub, asleep in the turnips, and a village that cannot stop laughing.',
      events: [
        {'type': 'quest', 'title': 'The Stolen Laughter', 'status': 'completed'},
        {'type': 'xp', 'amount': 300},
        {'type': 'gold', 'amount': 60},
        {'type': 'item', 'action': 'add', 'name': 'Ringmaster\'s Ticket', 'description': 'Admit one. Forever.'},
      ],
    ),
    'end_hat': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text:
          'The towering hat topples. Jars spill across the sawdust and shatter, releasing a storm of golden giggles that pour into the children like sunlight. Grinsworth shrieks, clutching his bare head, and the whole carnival folds in on itself like a paper lantern.\n\nThistlewick throws you a feast. Widow Pell bakes you a pie the size of a cartwheel.',
      events: [
        {'type': 'quest', 'title': 'The Stolen Laughter', 'status': 'completed'},
        {'type': 'xp', 'amount': 250},
        {'type': 'gold', 'amount': 50},
      ],
    ),
    'end_fight': ModNode(
      title: 'The Big Top',
      loc: 'tavern',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text:
          'Grinsworth collapses into a heap of moonlit patches, and his hat cracks open. Most of the jars break, and the laughter rushes home. A few roll away into the dark, glinting — and somewhere, somebody will find them.\n\nThe children are giggling by morning. Mostly.',
      events: [
        {'type': 'quest', 'title': 'The Stolen Laughter', 'status': 'completed'},
        {'type': 'xp', 'amount': 200},
        {'type': 'gold', 'amount': 40},
      ],
    ),
    'end_lost': ModNode(
      title: 'Thistlewick Green',
      loc: 'town',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'You wake in the turnip field at dawn. The carnival is gone. You feel fine — healthy, rested — and when Widow Pell tells you a joke, you smile politely.\n\nYou cannot remember how to laugh. Somewhere far away, a calliope plays. Perhaps it will come back next year.',
      events: [
        {'type': 'quest', 'title': 'The Stolen Laughter', 'status': 'failed'},
      ],
    ),
  },
);

const goblinToll = AdventureModule(
  id: 'goblin_toll',
  title: 'The Goblin King\'s Toll',
  tagline: 'A goblin with a paper crown has seized the only bridge. The Cheese Festival is in danger.',
  description:
      'King Grubnose the Magnificent (self-appointed) has claimed the Snarlwater Bridge and demands tolls in pies, songs and shinies. Merchant Bartholomew Plum needs his cart of prize cheese across before sundown. Bluff, sing, befriend a grumpy troll, or win a cheese-eating contest.',
  levels: '1–2',
  minutes: 20,
  tone: 'Comedic',
  setting: 'High fantasy',
  coverLoc: 'road',
  coverTime: 'day',
  mapKind: MapKind.overworld,
  mapName: 'The Snarlwater Crossing',
  locations: ['Plum\'s Wagon', 'Toll Gate', 'Under the Bridge', 'The Barrel Throne', 'Cheesefair Meadow'],
  tags: ['Comedy', 'Short', 'Social'],
  start: 'start',
  nodes: {
    'start': ModNode(
      title: 'Plum\'s Wagon',
      loc: 'road',
      time: 'day',
      mood: 'festive',
      mapLoc: 'Plum\'s Wagon',
      speaker: 'Bartholomew Plum',
      text:
          'A round man in a round hat waves you down from a wagon stacked with enormous wheels of cheese. "Oh thank the gods, an adventurer! I\'m Bartholomew Plum, and this is the finest Gildwater Blue in the realm. The Cheese Festival starts at sundown — but goblins have taken the bridge!"\n\nAcross the field, a banner flaps over the bridge: KING GRUBNOSE THE MAGNIFICENT. TOLLS APPLY.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'description': 'Get Bartholomew Plum\'s cheese across the Snarlwater Bridge.', 'status': 'new'},
        {'type': 'npc', 'name': 'Bartholomew Plum', 'role': 'cheese merchant', 'race': 'human', 'disposition': 40, 'description': 'Round, anxious, and devoted to cheese.'},
      ],
      choices: [
        ModChoice('Walk up to the toll gate', type: ChoiceType.explore, go: 'gate'),
        ModChoice('Scout along the riverbank first', type: ChoiceType.stealth, check: 'Stealth', dc: 10, ok: 'under', fail: 'gate'),
      ],
    ),
    'gate': ModNode(
      title: 'Toll Gate',
      loc: 'road',
      time: 'day',
      mood: 'festive',
      mapLoc: 'Toll Gate',
      speaker: 'Nib',
      text:
          'Two goblins in mismatched armor block the bridge with a broom. "HALT!" says the first. "In the name of—" "—KING GRUBNOSE," says the second. "I was saying that, Nob." "You said it last time, Nib." They glare at each other, then at you. "Toll is ten gold. Or a song. Or a shiny."',
      events: [
        {'type': 'npc', 'name': 'Nib', 'role': 'goblin guard', 'race': 'gnome', 'disposition': 0, 'description': 'Half of a bickering goblin double act.'},
      ],
      choices: [
        ModChoice('Pay the ten-gold toll', type: ChoiceType.action, requires: 'gold:10', go: 'throne', effects: [
          {'type': 'gold', 'amount': -10},
        ]),
        ModChoice('Sing them a song', type: ChoiceType.dialogue, check: 'Performance', dc: 11, ok: 'throne', fail: 'gate_boo'),
        ModChoice('Claim you\'re a royal bridge inspector', type: ChoiceType.dialogue, check: 'Deception', dc: 12, ok: 'throne', fail: 'gate_fight', set: 'inspector'),
        ModChoice('Start an argument between Nib and Nob', type: ChoiceType.dialogue, check: 'Insight', dc: 12, ok: 'gate_squabble', fail: 'gate_fight'),
        ModChoice('Clear the bridge by force', type: ChoiceType.combat, go: 'gate_fight'),
      ],
    ),
    'gate_boo': ModNode(
      title: 'Toll Gate',
      loc: 'road',
      time: 'day',
      mood: 'festive',
      speaker: 'Nob',
      text: '"Boo!" says Nob. "Booooo," agrees Nib. They throw a turnip at you. It\'s a pretty good turnip, actually. You keep it.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'A Pretty Good Turnip', 'description': 'Thrown with conviction.'},
      ],
      choices: [
        ModChoice('Try a different song', type: ChoiceType.dialogue, check: 'Performance', dc: 13, ok: 'throne', fail: 'gate_fight'),
        ModChoice('Climb down under the bridge', type: ChoiceType.explore, go: 'under'),
        ModChoice('Fight your way through', type: ChoiceType.combat, go: 'gate_fight'),
      ],
    ),
    'gate_squabble': ModNode(
      title: 'Toll Gate',
      loc: 'road',
      time: 'day',
      mood: 'festive',
      text: '"Nob says Nib is the King\'s FAVORITE," you whisper. Within seconds they are rolling on the planks, biting ears. You stroll past.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Approach the throne', type: ChoiceType.explore, go: 'throne'),
      ],
    ),
    'gate_fight': ModNode(
      title: 'Toll Gate',
      loc: 'road',
      time: 'day',
      mood: 'combat',
      text: '"INTRUDER!" Nib and Nob charge with the broom and a very sharp spoon.',
      combat: ModCombat([
        {'name': 'Nib', 'monster': 'goblin', 'count': 1},
        {'name': 'Nob', 'monster': 'goblin', 'count': 1},
      ], win: 'throne'),
    ),
    'under': ModNode(
      title: 'Under the Bridge',
      loc: 'swamp',
      time: 'day',
      mood: 'mystery',
      mapLoc: 'Under the Bridge',
      speaker: 'Gudrun',
      text:
          'In the shade beneath the bridge sits an enormous troll with a knitting project. She has bags under her eyes the size of saddlebags. "Every night," she rumbles, "they sing. Up there. Badly. Gudrun has not slept in a week." She points a knitting needle at you. "You. Fix it."',
      events: [
        {'type': 'npc', 'name': 'Gudrun', 'role': 'sleepy troll', 'race': 'half-orc', 'disposition': 0, 'description': 'A troll who just wants some quiet.'},
      ],
      choices: [
        ModChoice('Promise to stop the singing', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'under_friend', fail: 'under_grumpy'),
        ModChoice('Answer her riddle for passage', type: ChoiceType.dialogue, go: 'under_riddle'),
        ModChoice('Offer her the turnip', type: ChoiceType.dialogue, requires: 'item:A Pretty Good Turnip', go: 'under_friend', effects: [
          {'type': 'item', 'action': 'remove', 'name': 'A Pretty Good Turnip'},
        ]),
        ModChoice('Climb back up to the gate', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'under_riddle': ModNode(
      title: 'Under the Bridge',
      loc: 'swamp',
      time: 'day',
      mood: 'mystery',
      speaker: 'Gudrun',
      text: '"What has a neck but no head, and wears a cap?" Gudrun asks, needles clicking.',
      choices: [
        ModChoice('"A bottle."', type: ChoiceType.dialogue, go: 'under_friend'),
        ModChoice('"A goblin."', type: ChoiceType.dialogue, go: 'under_grumpy'),
        ModChoice('"A mushroom."', type: ChoiceType.dialogue, go: 'under_grumpy'),
      ],
    ),
    'under_friend': ModNode(
      title: 'Under the Bridge',
      loc: 'swamp',
      time: 'day',
      mood: 'calm',
      speaker: 'Gudrun',
      sets: ['troll'],
      text: 'Gudrun\'s face cracks into a boulder-sized smile. "Good. When you need it, shout GUDRUN. Gudrun will lift the bridge and shake the noisy ones off." She goes back to knitting what appears to be a scarf for a horse.',
      events: [
        {'type': 'disposition', 'name': 'Gudrun', 'change': 50},
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Climb up to the throne', type: ChoiceType.explore, go: 'throne'),
      ],
    ),
    'under_grumpy': ModNode(
      title: 'Under the Bridge',
      loc: 'swamp',
      time: 'day',
      mood: 'tense',
      speaker: 'Gudrun',
      text: '"Wrong." Gudrun flicks you into the river with one finger. You crawl out, dripping and humbled.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 3, 'reason': 'troll flick'},
      ],
      choices: [
        ModChoice('Climb up to the gate', type: ChoiceType.explore, go: 'gate'),
      ],
    ),
    'throne': ModNode(
      title: 'The Barrel Throne',
      loc: 'road',
      time: 'dusk',
      mood: 'festive',
      mapLoc: 'The Barrel Throne',
      speaker: 'King Grubnose',
      text:
          'In the middle of the bridge, on a barrel draped in a bedsheet, sits King Grubnose the Magnificent. His crown is made of paper and his cape is a tablecloth. Twelve goblins stand at attention behind him, mostly.\n\n"Who dares approach the King?" he squeaks, then lowers his voice. "I mean — WHO DARES."',
      events: [
        {'type': 'npc', 'name': 'King Grubnose', 'role': 'goblin king (self-appointed)', 'race': 'gnome', 'disposition': -10, 'description': 'Desperate to be taken seriously.'},
      ],
      choices: [
        ModChoice('Bow deeply and praise his majesty', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'end_knight', fail: 'throne_offended'),
        ModChoice('Present your inspector\'s findings: the bridge is unsafe', type: ChoiceType.dialogue, requires: 'inspector', check: 'Deception', dc: 10, ok: 'end_inspector', fail: 'boss'),
        ModChoice('Challenge him to a cheese-eating contest', type: ChoiceType.action, check: 'CON', dc: 13, ok: 'end_cheese', fail: 'throne_offended'),
        ModChoice('Shout "GUDRUN!"', type: ChoiceType.action, requires: 'troll', go: 'end_troll'),
        ModChoice('Draw your weapon', type: ChoiceType.combat, go: 'boss'),
      ],
    ),
    'throne_offended': ModNode(
      title: 'The Barrel Throne',
      loc: 'road',
      time: 'dusk',
      mood: 'tense',
      speaker: 'King Grubnose',
      text: 'Grubnose turns purple. "SEIZE THEM! And the cheese! ESPECIALLY THE CHEESE!"',
      choices: [
        ModChoice('Fight!', type: ChoiceType.combat, go: 'boss'),
        ModChoice('Shout "GUDRUN!"', type: ChoiceType.action, requires: 'troll', go: 'end_troll'),
      ],
    ),
    'boss': ModNode(
      title: 'The Barrel Throne',
      loc: 'road',
      time: 'dusk',
      mood: 'combat',
      speaker: 'King Grubnose',
      text: 'Grubnose leaps from his barrel brandishing a soup ladle. "FOR THE CROWN!" Three of his bravest goblins follow. The other nine hide behind the barrel.',
      combat: ModCombat([
        {'name': 'King Grubnose', 'monster': 'goblin', 'count': 1, 'hp': 22, 'ac': 15, 'attack_bonus': 4, 'damage': '1d8+2', 'attack_name': 'Royal Ladle'},
        {'name': 'Royal Guard', 'monster': 'goblin', 'count': 2},
      ], win: 'end_victory', lose: 'end_lost', boss: true),
    ),
    'end_knight': ModNode(
      title: 'Cheesefair Meadow',
      loc: 'plains',
      time: 'dusk',
      mood: 'triumph',
      mapLoc: 'Cheesefair Meadow',
      end: 'victory',
      text:
          'Grubnose is so moved he weeps into his tablecloth. "Finally, someone who UNDERSTANDS." He taps you on each shoulder with a soup ladle. "Arise, Sir {first} of the Bridge!"\n\nThe goblins escort Plum\'s wagon across with a fanfare of kazoos. The Gildwater Blue wins first prize. You are made an honorary member of the Cheesemongers\' Guild, which comes with a lifetime supply of crackers.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'completed'},
        {'type': 'xp', 'amount': 200},
        {'type': 'gold', 'amount': 40},
        {'type': 'item', 'action': 'add', 'name': 'Knighthood of the Bridge', 'description': 'A paper medal signed by King Grubnose.'},
      ],
    ),
    'end_inspector': ModNode(
      title: 'Cheesefair Meadow',
      loc: 'plains',
      time: 'dusk',
      mood: 'triumph',
      mapLoc: 'Cheesefair Meadow',
      end: 'victory',
      text: '"UNSAFE?!" Grubnose evacuates his entire kingdom in under a minute. You wheel the cheese across an empty bridge. Behind you, the goblins are frantically building a "safer" bridge out of sticks. It will not be safer.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'completed'},
        {'type': 'xp', 'amount': 200},
        {'type': 'gold', 'amount': 30},
      ],
    ),
    'end_cheese': ModNode(
      title: 'Cheesefair Meadow',
      loc: 'plains',
      time: 'dusk',
      mood: 'triumph',
      mapLoc: 'Cheesefair Meadow',
      end: 'victory',
      text:
          'Eleven wheels later, Grubnose lies on his back groaning. You eat a twelfth for style. The goblins chant your name, badly. Plum is torn between gratitude and grief for his inventory, but the one wheel left wins first prize anyway.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'completed'},
        {'type': 'xp', 'amount': 200},
        {'type': 'heal', 'target': 'hero', 'amount': 10},
      ],
    ),
    'end_troll': ModNode(
      title: 'Cheesefair Meadow',
      loc: 'plains',
      time: 'dusk',
      mood: 'triumph',
      mapLoc: 'Cheesefair Meadow',
      end: 'victory',
      text:
          '"GUDRUN!" The bridge rises like a seesaw. Goblins slide off the far end into the river, followed by a barrel, a bedsheet and a very surprised king. Gudrun sets the bridge down gently, gives you a thumbs-up the size of a ham, and goes to sleep for the first time in a week.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'completed'},
        {'type': 'xp', 'amount': 250},
        {'type': 'gold', 'amount': 25},
      ],
    ),
    'end_victory': ModNode(
      title: 'Cheesefair Meadow',
      loc: 'plains',
      time: 'dusk',
      mood: 'triumph',
      mapLoc: 'Cheesefair Meadow',
      end: 'victory',
      text: 'Grubnose surrenders his ladle with great ceremony. You let him keep the crown. The cheese crosses the bridge just as the festival bells ring, and you dine on Gildwater Blue until you can\'t see straight.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'completed'},
        {'type': 'xp', 'amount': 150},
        {'type': 'gold', 'amount': 30},
      ],
    ),
    'end_lost': ModNode(
      title: 'Snarlwater River',
      loc: 'swamp',
      time: 'night',
      mood: 'sad',
      end: 'bittersweet',
      text: 'You wake up downriver, tangled in reeds, smelling strongly of cheese. In the distance you can hear goblins singing — badly — and a troll weeping into her knitting. The festival will have to do without the Gildwater Blue this year.',
      events: [
        {'type': 'quest', 'title': 'Cheese Before Sundown', 'status': 'failed'},
      ],
    ),
  },
);

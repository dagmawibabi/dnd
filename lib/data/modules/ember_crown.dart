import '../../game/module_engine.dart';
import '../../models/adventure.dart';

// The Ember Crown: a three-part arc played as a campaign.

const emberCrown1 = AdventureModule(
  id: 'ember_crown_1',
  title: 'The Ember Crown I: The Ashen Road',
  tagline: 'A god\'s burning heart has been stolen. Follow the smoke.',
  description:
      'The Ember Crown, a relic said to hold the heart of a dead fire god, has been stolen from the temple at Emberfall by the Cinder Choir. Chase the cult down the Ashen Road through burned villages and bandit country, find an unlikely ally, and learn where the crown is going. Part one of three.',
  levels: '1–3',
  minutes: 30,
  tone: 'Epic',
  setting: 'High fantasy',
  coverLoc: 'road',
  coverTime: 'dusk',
  mapKind: MapKind.overworld,
  mapName: 'The Ashen Road',
  locations: ['Emberfall Temple', 'The Ashen Road', 'Cinderbrook', 'Wolfsbane Pass', 'Old Watchtower', 'Lake Morrow'],
  tags: ['Campaign', 'Part 1 of 3', 'Companion'],
  seriesId: 'ember_crown',
  seriesName: 'The Ember Crown',
  part: 1,
  start: 'temple',
  nodes: {
    'temple': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'tense',
      mapLoc: 'Emberfall Temple',
      speaker: 'High Keeper Ansa',
      text:
          'The sanctum still smells of smoke. Where the Ember Crown rested for three hundred years there is only a scorched cushion and a ring of melted candles.\n\n"They sang as they took it," says High Keeper Ansa, her hands bandaged. "Hymns of ash. The Cinder Choir. If they wake what sleeps inside that crown, Emberfall will be the first city to burn, not the last."',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'Recover the Ember Crown from the Cinder Choir before they wake the god inside it.', 'status': 'new'},
        {'type': 'npc', 'name': 'High Keeper Ansa', 'role': 'temple keeper', 'race': 'human', 'disposition': 40, 'description': 'Stern, scorched and determined.'},
      ],
      choices: [
        ModChoice('Search the sanctum for clues', type: ChoiceType.explore, check: 'Investigation', dc: 12, ok: 'temple_clue', fail: 'temple_nothing', set: 'searched'),
        ModChoice('Ask Ansa what the crown can do', type: ChoiceType.dialogue, check: 'Religion', dc: 11, ok: 'temple_lore', fail: 'temple_vague', set: 'asked'),
        ModChoice('Request supplies for the road', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'temple_supplies', fail: 'temple_road', set: 'supplies'),
        ModChoice('Take the Ashen Road at once', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_clue': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'mystery',
      sets: ['clue_map'],
      text:
          'Under the altar you find a scrap of charred vellum: a map fragment with a lake drawn in blue ink and the words "the Archive drinks beneath Morrow". Someone dropped it in a hurry.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Charred Map Fragment', 'description': 'Shows a lake marked "Morrow" and a sunken building.'},
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Ask Ansa what the crown can do', type: ChoiceType.dialogue, check: 'Religion', dc: 11, ok: 'temple_lore', fail: 'temple_vague', set: 'asked', unless: 'asked'),
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_nothing': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'tense',
      text: 'Soot, wax and footprints that go everywhere and nowhere. Whoever planned this was careful.',
      choices: [
        ModChoice('Ask Ansa what the crown can do', type: ChoiceType.dialogue, check: 'Religion', dc: 11, ok: 'temple_lore', fail: 'temple_vague', set: 'asked', unless: 'asked'),
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_lore': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'mystery',
      speaker: 'High Keeper Ansa',
      sets: ['lore'],
      text:
          '"The crown is a cage," Ansa says. "Saint Calder forged it to hold the heart of Ithrax, the god of wildfire. Whoever wears it commands fire. Whoever breaks it in the forge where it was made frees the god or ends him. Nobody remembers which."',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Search the sanctum for clues', type: ChoiceType.explore, check: 'Investigation', dc: 12, ok: 'temple_clue', fail: 'temple_nothing', set: 'searched', unless: 'searched'),
        ModChoice('Request supplies for the road', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'temple_supplies', fail: 'temple_road', set: 'supplies', unless: 'supplies'),
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_vague': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'tense',
      speaker: 'High Keeper Ansa',
      text: '"It is holy, and it is dangerous, and it is gone," Ansa says flatly. "That is all you need to know tonight."',
      choices: [
        ModChoice('Search the sanctum for clues', type: ChoiceType.explore, check: 'Investigation', dc: 12, ok: 'temple_clue', fail: 'temple_nothing', set: 'searched', unless: 'searched'),
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_supplies': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'calm',
      text: 'Ansa presses a vial of blessed water and a purse into your hands. "The temple\'s last coin. Spend it on staying alive."',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'potion_healing', 'name': 'Potion of Healing'},
        {'type': 'gold', 'amount': 30},
      ],
      choices: [
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'temple_road': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'dusk',
      mood: 'tense',
      text: '"We have nothing left to give," Ansa says, not unkindly. "Only our prayers. Go."',
      choices: [
        ModChoice('Take the Ashen Road', type: ChoiceType.explore, go: 'road'),
      ],
    ),
    'road': ModNode(
      title: 'The Ashen Road',
      loc: 'road',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Ashen Road',
      text:
          'The road north is grey with ash, and the ash holds footprints: a dozen pairs, walking in perfect step. Ahead, a glow on the horizon. A village is burning.\n\nTo the east, a narrow path cuts toward Wolfsbane Pass, a shortcut that would put you ahead of the cult.',
      choices: [
        ModChoice('Run toward the burning village', type: ChoiceType.action, go: 'village'),
        ModChoice('Take the shortcut through the pass', type: ChoiceType.explore, go: 'pass', set: 'skipped_village'),
        ModChoice('Track the cult by their footprints', type: ChoiceType.explore, check: 'Survival', dc: 12, ok: 'road_tracks', fail: 'village'),
      ],
    ),
    'road_tracks': ModNode(
      title: 'The Ashen Road',
      loc: 'road',
      time: 'night',
      mood: 'mystery',
      sets: ['tracked'],
      text:
          'The footprints split: most of the choir marched on toward the lake, but three pairs turned into the village. Someone stayed behind to light the fires. Someone who might talk.',
      events: [
        {'type': 'xp', 'amount': 25},
      ],
      choices: [
        ModChoice('Go after the arsonists in the village', type: ChoiceType.action, go: 'village'),
        ModChoice('Take the shortcut through the pass', type: ChoiceType.explore, go: 'pass', set: 'skipped_village'),
      ],
    ),
    'village': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'combat',
      mapLoc: 'Cinderbrook',
      text:
          'Cinderbrook is half aflame. Villagers form a bucket line while three robed figures stand in the square, singing as the thatch catches. A knight in dented armor lies beneath a fallen beam, sword just out of reach.',
      choices: [
        ModChoice('Attack the singers', type: ChoiceType.combat, go: 'village_fight'),
        ModChoice('Lift the beam off the knight', type: ChoiceType.action, check: 'Athletics', dc: 13, ok: 'knight_saved', fail: 'knight_hurt'),
        ModChoice('Organize the bucket line first', type: ChoiceType.dialogue, check: 'Persuasion', dc: 12, ok: 'fire_out', fail: 'village_fight', set: 'saved_village'),
      ],
    ),
    'knight_saved': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      speaker: 'Ser Odile',
      sets: ['odile'],
      text:
          'The beam groans and lifts. The knight rolls free, grabs her sword and spits soot. "Ser Odile, of the Order of the Hearth. I was guarding that crown when they took it. I owe you a life, and them a death." She turns toward the singers.',
      events: [
        {'type': 'companion_join', 'name': 'Ser Odile', 'race': 'human', 'class': 'paladin', 'personality': 'Proud, honorable, haunted by failing her oath'},
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Fight the singers together', type: ChoiceType.combat, go: 'village_fight'),
      ],
    ),
    'knight_hurt': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      speaker: 'Ser Odile',
      sets: ['odile'],
      text:
          'The beam slips and comes down on your arm before you heave it aside. The knight crawls free, coughing. "Ser Odile. Thank you, fool. That looked like it hurt." She hauls herself up beside you.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 4, 'reason': 'falling beam'},
        {'type': 'companion_join', 'name': 'Ser Odile', 'race': 'human', 'class': 'paladin', 'personality': 'Proud, honorable, haunted by failing her oath'},
      ],
      choices: [
        ModChoice('Fight the singers together', type: ChoiceType.combat, go: 'village_fight'),
      ],
    ),
    'fire_out': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      text:
          'Your voice cuts through the panic and the bucket line becomes a river. The flames hiss and die. The singers stop, furious that their hymn has failed, and draw curved knives.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Face them', type: ChoiceType.combat, go: 'village_fight'),
        ModChoice('Free the trapped knight while they hesitate', type: ChoiceType.action, go: 'knight_saved', unless: 'odile'),
      ],
    ),
    'village_fight': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'combat',
      text: 'The hymn breaks into a scream. The choir-cultists rush you, knives glowing orange.',
      combat: ModCombat([
        {'name': 'Choir Cultist', 'monster': 'cultist', 'count': 2},
        {'name': 'Ash Singer', 'monster': 'cult_fanatic', 'count': 1, 'hp': 22},
      ], win: 'village_after'),
    ),
    'village_after': ModNode(
      title: 'Cinderbrook',
      loc: 'town',
      time: 'night',
      mood: 'calm',
      text:
          'The last singer falls. One of them is still breathing, staring at the sky. "Vael will wear the crown on the Throne of Embers," he whispers. "But first the Archive must teach him the words." Then he is still.',
      events: [
        {'type': 'xp', 'amount': 50},
        {'type': 'gold', 'amount': 25},
        {'type': 'item', 'action': 'add', 'name': 'Choir Hymnal', 'description': 'A book of ash-black pages. Some of the hymns mention "the Archive beneath Morrow".'},
      ],
      choices: [
        ModChoice('Rest in the grateful village', type: ChoiceType.rest, go: 'village_rest'),
        ModChoice('Press on toward Wolfsbane Pass', type: ChoiceType.explore, go: 'pass'),
      ],
    ),
    'village_rest': ModNode(
      title: 'Cinderbrook',
      loc: 'tavern',
      time: 'dawn',
      mood: 'calm',
      text: 'The villagers give you their best beds and a breakfast of burnt bread and honey. A trader offers to sell you supplies at a hero\'s discount.',
      events: [
        {'type': 'rest', 'kind': 'long'},
        {'type': 'shop', 'kind': 'general', 'name': 'Cinderbrook Trader'},
      ],
      choices: [
        ModChoice('Set out for Wolfsbane Pass', type: ChoiceType.explore, go: 'pass'),
      ],
    ),
    'pass': ModNode(
      title: 'Wolfsbane Pass',
      loc: 'mountain',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Wolfsbane Pass',
      text:
          'The pass is a crooked throat of rock. Howls echo from both directions. Then eyes, lots of them, catch your torchlight. A pack of wolves, and behind them something bigger with a rider\'s saddle.',
      choices: [
        ModChoice('Stand your ground', type: ChoiceType.combat, go: 'pass_fight'),
        ModChoice('Scare them off with fire and noise', type: ChoiceType.action, check: 'Intimidation', dc: 14, ok: 'pass_clear', fail: 'pass_fight'),
        ModChoice('Calm the animals', type: ChoiceType.magic, check: 'Animal Handling', dc: 13, ok: 'pass_clear', fail: 'pass_fight'),
        ModChoice('Climb above them', type: ChoiceType.stealth, check: 'Athletics', dc: 13, ok: 'tower', fail: 'pass_fight'),
        ModChoice('Trigger a rockslide onto the pack', type: ChoiceType.action, check: 'DEX save', dc: 13, ok: 'pass_clear', fail: 'pass_fight', failEffects: [
          {'type': 'damage', 'target': 'hero', 'amount': 5, 'reason': 'falling rocks'},
        ]),
      ],
    ),
    'pass_fight': ModNode(
      title: 'Wolfsbane Pass',
      loc: 'mountain',
      time: 'night',
      mood: 'combat',
      text: 'The pack lunges.',
      combat: ModCombat([
        {'name': 'Ash Wolf', 'monster': 'wolf', 'count': 2},
        {'name': 'Choir Worg', 'monster': 'worg', 'count': 1},
      ], win: 'pass_clear'),
    ),
    'pass_clear': ModNode(
      title: 'Wolfsbane Pass',
      loc: 'mountain',
      time: 'night',
      mood: 'calm',
      text: 'The way is clear. At the top of the pass, an old watchtower leans against the stars, and a light flickers in its highest window.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Approach the watchtower', type: ChoiceType.explore, go: 'tower'),
      ],
    ),
    'tower': ModNode(
      title: 'Old Watchtower',
      loc: 'ruins',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'Old Watchtower',
      text:
          'Inside the tower, a bandit captain and her crew are dividing a pile of loot, including censers and robes stamped with the choir\'s flame. "Bought from some singing lunatics," she says, hand on her sword. "They paid us to slow down anyone following them."',
      events: [
        {'type': 'npc', 'name': 'Captain Rook', 'role': 'bandit captain', 'race': 'half-elf', 'disposition': -10, 'description': 'Sharp, greedy, not entirely without honor.'},
      ],
      choices: [
        ModChoice('Offer more than the cult paid', type: ChoiceType.dialogue, requires: 'gold:40', go: 'tower_deal', effects: [
          {'type': 'gold', 'amount': -40},
        ]),
        ModChoice('Convince her the cult will burn her too', type: ChoiceType.dialogue, check: 'Persuasion', dc: 14, ok: 'tower_deal', fail: 'tower_fight', easierIf: 'lore'),
        ModChoice('Draw steel', type: ChoiceType.combat, go: 'tower_fight'),
      ],
    ),
    'tower_deal': ModNode(
      title: 'Old Watchtower',
      loc: 'ruins',
      time: 'night',
      mood: 'calm',
      speaker: 'Captain Rook',
      sets: ['rook_friend'],
      text: 'Rook grins. "Fine. They went to the lake. There\'s a drowned library under it; they had a boat waiting. And take this, I don\'t want cursed junk."',
      events: [
        {'type': 'disposition', 'name': 'Captain Rook', 'change': 40},
        {'type': 'item', 'action': 'add', 'id': 'cloak_protection', 'name': 'Cloak of Protection'},
        {'type': 'xp', 'amount': 75},
      ],
      choices: [
        ModChoice('Ride for Lake Morrow', type: ChoiceType.explore, go: 'lake'),
      ],
    ),
    'tower_fight': ModNode(
      title: 'Old Watchtower',
      loc: 'ruins',
      time: 'night',
      mood: 'combat',
      text: 'Rook kicks the table over. "Your funeral."',
      combat: ModCombat([
        {'name': 'Captain Rook', 'monster': 'bandit_captain', 'count': 1},
        {'name': 'Bandit', 'monster': 'bandit', 'count': 2},
      ], win: 'tower_won', lose: 'end_captured', boss: true),
    ),
    'tower_won': ModNode(
      title: 'Old Watchtower',
      loc: 'ruins',
      time: 'night',
      mood: 'calm',
      text: 'Rook yields, bleeding. "The lake. Under the lake. Go and drown, hero." Among the loot you find something that hums with protective magic.',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'cloak_protection', 'name': 'Cloak of Protection'},
        {'type': 'gold', 'amount': 40},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Ride for Lake Morrow', type: ChoiceType.explore, go: 'lake'),
      ],
    ),
    'lake': ModNode(
      title: 'Lake Morrow',
      loc: 'coast',
      time: 'dawn',
      mood: 'mystery',
      mapLoc: 'Lake Morrow',
      text:
          'Dawn lights a lake as flat as a mirror. In the middle, the roof of a drowned building breaks the surface like the spine of a whale: the Sunken Archive. A cult boat is moored beside it, empty. Bubbles rise where the choir went down.\n\nYou have found the trail. The crown is below.',
      choices: [
        ModChoice('Mark the spot and prepare to descend', type: ChoiceType.explore, go: 'end', unless: 'skipped_village'),
        ModChoice('Look back toward the smoke of Cinderbrook', type: ChoiceType.explore, go: 'end_ash', requires: 'skipped_village'),
      ],
    ),
    'end_ash': ModNode(
      title: 'Lake Morrow',
      loc: 'coast',
      time: 'day',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'You beat the cult to the lake, but behind you a column of smoke stands over the horizon where Cinderbrook used to be. Speed has its price. The crown is below, and you carry the village with you.\n\nTo be continued in The Ember Crown II: The Sunken Archive.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'The trail leads beneath Lake Morrow to the Sunken Archive.', 'status': 'update'},
        {'type': 'xp', 'amount': 150},
      ],
    ),
    'end_captured': ModNode(
      title: 'Old Watchtower',
      loc: 'ruins',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'You wake tied to a chair with a headache and an empty purse. Rook is gone, but she left the door unlocked and a note: "Lake Morrow. Don\'t follow me." It seems even bandits hate the Choir.\n\nTo be continued in The Ember Crown II: The Sunken Archive.',
      events: [
        {'type': 'xp', 'amount': 75},
      ],
    ),
    'end': ModNode(
      title: 'Lake Morrow',
      loc: 'coast',
      time: 'day',
      mood: 'triumph',
      end: 'victory',
      text:
          'The Ashen Road is behind you. Whatever waits in the Sunken Archive, you are no longer a stranger to the Cinder Choir, and they are no longer strangers to you.\n\nTo be continued in The Ember Crown II: The Sunken Archive.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'The trail leads beneath Lake Morrow to the Sunken Archive.', 'status': 'update'},
        {'type': 'xp', 'amount': 150},
      ],
    ),
  },
);

const emberCrown2 = AdventureModule(
  id: 'ember_crown_2',
  title: 'The Ember Crown II: The Sunken Archive',
  tagline: 'A drowned library holds the words that wake a god.',
  description:
      'Beneath Lake Morrow lies the Sunken Archive, a library swallowed by water and memory. The Cinder Choir has come to learn the hymn that wakes the god inside the Ember Crown. Solve the archive\'s riddles, bargain with a ghostly librarian, survive the sahuagin, and discover the crown\'s true nature. Part two of three.',
  levels: '3–5',
  minutes: 35,
  tone: 'Mysterious',
  setting: 'High fantasy',
  coverLoc: 'dungeon',
  coverTime: 'night',
  mapKind: MapKind.dungeon,
  mapName: 'The Sunken Archive',
  locations: ['Drowned Stair', 'Reading Room', 'The Stacks', 'Librarian\'s Office', 'Flooded Vault', 'Hymn Chamber'],
  tags: ['Campaign', 'Part 2 of 3', 'Puzzles'],
  seriesId: 'ember_crown',
  seriesName: 'The Ember Crown',
  part: 2,
  start: 'stair',
  nodes: {
    'stair': ModNode(
      title: 'Drowned Stair',
      loc: 'dungeon',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Drowned Stair',
      text:
          'A spiral stair corkscrews down through the archive\'s roof. Lake water laps at the walls but stops at the threshold, held back by an old enchantment that hums in your teeth. Below, lamps of green fire light a reading room where every book has swollen to twice its size.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'Find the Cinder Choir in the Sunken Archive before they learn the waking hymn.', 'status': 'update'},
      ],
      choices: [
        ModChoice('Descend carefully', type: ChoiceType.stealth, check: 'Stealth', dc: 12, ok: 'reading_quiet', fail: 'reading'),
        ModChoice('Study the enchantment on the walls', type: ChoiceType.magic, check: 'Arcana', dc: 13, ok: 'stair_ward', fail: 'reading'),
        ModChoice('Walk down openly', type: ChoiceType.explore, go: 'reading'),
      ],
    ),
    'stair_ward': ModNode(
      title: 'Drowned Stair',
      loc: 'dungeon',
      time: 'night',
      mood: 'mystery',
      sets: ['ward_known'],
      text: 'The ward keeps the lake out, but it is failing. Each spell cast in the archive drains it a little more. If the choir works great magic here, the whole library will flood.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Continue down', type: ChoiceType.explore, go: 'reading'),
      ],
    ),
    'reading_quiet': ModNode(
      title: 'Reading Room',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Reading Room',
      sets: ['surprise'],
      text: 'You slip down unseen. Two fish-scaled sahuagin are tearing books apart at a reading table, looking for something. They have not noticed you.',
      choices: [
        ModChoice('Ambush them', type: ChoiceType.combat, go: 'reading_ambush'),
        ModChoice('Sneak past into the stacks', type: ChoiceType.stealth, check: 'Stealth', dc: 13, ok: 'stacks', fail: 'reading_fight'),
      ],
    ),
    'reading': ModNode(
      title: 'Reading Room',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Reading Room',
      text: 'Two sahuagin raiders look up from the books they are shredding. Their eyes are flat and black. They hiss and reach for tridents.',
      choices: [
        ModChoice('Fight', type: ChoiceType.combat, go: 'reading_fight'),
        ModChoice('Speak to them in their tongue', type: ChoiceType.dialogue, requires: 'race:elf|half-elf|dragonborn', check: 'Persuasion', dc: 13, ok: 'reading_talk', fail: 'reading_fight'),
      ],
    ),
    'reading_talk': ModNode(
      title: 'Reading Room',
      loc: 'dungeon',
      time: 'night',
      mood: 'calm',
      sets: ['sahuagin_truce'],
      text: 'The sahuagin lower their tridents. "Fire-singers came into our water," one gurgles. "Made the deep hot. We look for the book that sends them away." They point you to the Librarian\'s Office.',
      events: [
        {'type': 'xp', 'amount': 75},
      ],
      choices: [
        ModChoice('Go to the stacks', type: ChoiceType.explore, go: 'stacks'),
      ],
    ),
    'reading_ambush': ModNode(
      title: 'Reading Room',
      loc: 'dungeon',
      time: 'night',
      mood: 'combat',
      text: 'You strike from the shadows.',
      combat: ModCombat([
        {'name': 'Sahuagin Raider', 'monster': 'sahuagin', 'count': 2},
      ], win: 'stacks', surprise: 'enemies'),
    ),
    'reading_fight': ModNode(
      title: 'Reading Room',
      loc: 'dungeon',
      time: 'night',
      mood: 'combat',
      text: 'The sahuagin attack with eerie coordination.',
      combat: ModCombat([
        {'name': 'Sahuagin Raider', 'monster': 'sahuagin', 'count': 2},
        {'name': 'Giant Crab', 'monster': 'giant_crab', 'count': 1},
      ], win: 'stacks'),
    ),
    'stacks': ModNode(
      title: 'The Stacks',
      loc: 'dungeon',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'The Stacks',
      text:
          'Shelves rise into darkness, linked by rope bridges. A suit of armor stands at the crossing, holding a lantern and a ledger. "Borrower," it booms. "State the title you seek, or return what you have taken."',
      choices: [
        ModChoice('Ask for "the Hymn of Ithrax"', type: ChoiceType.dialogue, check: 'History', dc: 13, ok: 'stacks_pass', fail: 'stacks_fight', easierIf: 'lore'),
        ModChoice('Show it the Choir Hymnal', type: ChoiceType.dialogue, requires: 'item:Choir Hymnal', go: 'stacks_pass'),
        ModChoice('Claim to be a librarian', type: ChoiceType.dialogue, check: 'Deception', dc: 14, ok: 'stacks_pass', fail: 'stacks_fight'),
        ModChoice('Push past it', type: ChoiceType.combat, go: 'stacks_fight'),
      ],
    ),
    'stacks_pass': ModNode(
      title: 'The Stacks',
      loc: 'dungeon',
      time: 'night',
      mood: 'calm',
      text: '"Restricted section," the armor intones, and steps aside. "Consult the Librarian. She has been waiting a very long time."',
      events: [
        {'type': 'xp', 'amount': 75},
      ],
      choices: [
        ModChoice('Visit the Librarian\'s Office', type: ChoiceType.explore, go: 'office'),
      ],
    ),
    'stacks_fight': ModNode(
      title: 'The Stacks',
      loc: 'dungeon',
      time: 'night',
      mood: 'combat',
      text: '"OVERDUE," the armor roars.',
      combat: ModCombat([
        {'name': 'Archive Warden', 'monster': 'animated_armor', 'count': 1, 'hp': 40},
      ], win: 'office'),
    ),
    'office': ModNode(
      title: 'Librarian\'s Office',
      loc: 'crypt',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Librarian\'s Office',
      speaker: 'Librarian Wynne',
      text:
          'A translucent woman sits at a desk sorting index cards that pass through her fingers. "Visitors. How rare. The singers took the hymn and went to the Hymn Chamber. They do not know the hymn has two verses. The first wakes Ithrax. The second unmakes him. They tore out the second."\n\nShe smiles sadly. "I kept a copy. Everyone forgets librarians keep copies."',
      events: [
        {'type': 'npc', 'name': 'Librarian Wynne', 'role': 'ghostly librarian', 'race': 'human', 'disposition': 20, 'description': 'Dead for two centuries and still cataloguing.'},
      ],
      choices: [
        ModChoice('Ask for the second verse', type: ChoiceType.dialogue, check: 'Persuasion', dc: 13, ok: 'office_verse', fail: 'office_price'),
        ModChoice('Offer to finish her last task', type: ChoiceType.dialogue, go: 'office_task'),
        ModChoice('Ask what really happened to the archive', type: ChoiceType.explore, check: 'Insight', dc: 12, ok: 'office_truth', fail: 'office_price', unless: 'truth'),
      ],
    ),
    'office_truth': ModNode(
      title: 'Librarian\'s Office',
      loc: 'crypt',
      time: 'night',
      mood: 'sad',
      speaker: 'Librarian Wynne',
      sets: ['truth'],
      text: '"The Choir came once before, two hundred years ago," she says. "I flooded the archive myself rather than let them have the hymn. I drowned with my books. I would do it again."',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Ask for the second verse', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'office_verse', fail: 'office_price'),
      ],
    ),
    'office_price': ModNode(
      title: 'Librarian\'s Office',
      loc: 'crypt',
      time: 'night',
      mood: 'mystery',
      speaker: 'Librarian Wynne',
      text: '"Nothing leaves without a return," she says. "Bring back the Index Stone from the Flooded Vault and the verse is yours."',
      choices: [
        ModChoice('Dive into the Flooded Vault', type: ChoiceType.explore, go: 'vault'),
      ],
    ),
    'office_task': ModNode(
      title: 'Librarian\'s Office',
      loc: 'crypt',
      time: 'night',
      mood: 'mystery',
      speaker: 'Librarian Wynne',
      text: '"The Index Stone," she says. "It fell into the Flooded Vault when the water came. Without it, nothing here can ever be found again. Bring it to me."',
      choices: [
        ModChoice('Dive into the Flooded Vault', type: ChoiceType.explore, go: 'vault'),
      ],
    ),
    'vault': ModNode(
      title: 'Flooded Vault',
      loc: 'cave',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Flooded Vault',
      text: 'Cold black water up to your chest. Something glows at the bottom: the Index Stone. Something else moves in the dark, a cold presence that drinks the warmth from the water.',
      choices: [
        ModChoice('Dive for the stone', type: ChoiceType.action, check: 'Athletics', dc: 13, ok: 'vault_stone', fail: 'vault_fight'),
        ModChoice('Lure the presence away with light', type: ChoiceType.magic, check: 'Arcana', dc: 13, ok: 'vault_stone', fail: 'vault_fight'),
        ModChoice('Confront the presence', type: ChoiceType.combat, go: 'vault_fight'),
      ],
    ),
    'vault_fight': ModNode(
      title: 'Flooded Vault',
      loc: 'cave',
      time: 'night',
      mood: 'combat',
      text: 'A specter rises from the water, a drowned choir-singer still mouthing the hymn.',
      combat: ModCombat([
        {'name': 'Drowned Singer', 'monster': 'specter', 'count': 1},
        {'name': 'Will-o\'-Wisp', 'monster': 'will_o_wisp', 'count': 1, 'hp': 18},
      ], win: 'vault_stone'),
    ),
    'vault_stone': ModNode(
      title: 'Flooded Vault',
      loc: 'cave',
      time: 'night',
      mood: 'triumph',
      sets: ['stone'],
      text: 'You surface gasping with the Index Stone. Beside it on the vault floor lay an old knight\'s bracer, still gleaming.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Index Stone', 'description': 'A smooth stone that hums with the location of every book in the archive.'},
        {'type': 'item', 'action': 'add', 'id': 'ring_protection', 'name': 'Ring of Protection'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Return the stone to Wynne', type: ChoiceType.explore, go: 'office_verse'),
      ],
    ),
    'office_verse': ModNode(
      title: 'Librarian\'s Office',
      loc: 'crypt',
      time: 'night',
      mood: 'calm',
      speaker: 'Librarian Wynne',
      sets: ['verse'],
      text:
          'Wynne writes the second verse onto a card in a hand like falling rain. "Sung in the forge where the crown was made, it ends Ithrax forever. Sung anywhere else, it only puts him back to sleep." She pauses. "Vael is singing the first verse now. Hurry."',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'The Second Verse', 'description': 'The hymn that unmakes Ithrax, if sung in the forge where the Ember Crown was made.'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Run to the Hymn Chamber', type: ChoiceType.action, go: 'chamber'),
      ],
    ),
    'chamber': ModNode(
      title: 'Hymn Chamber',
      loc: 'temple',
      time: 'night',
      mood: 'combat',
      mapLoc: 'Hymn Chamber',
      speaker: 'Prophet Vael',
      text:
          'A domed chamber full of singing. At its heart, a gaunt man in white robes holds the Ember Crown above his head. It blazes, and the water beyond the walls begins to boil.\n\n"You are too late," says Prophet Vael, not turning. "Ithrax stirs. I go to crown him on his throne." A burning skull drifts down from the dome to bar your way.',
      choices: [
        ModChoice('Sing the second verse to disrupt the ritual', type: ChoiceType.magic, requires: 'verse', check: 'Performance', dc: 13, ok: 'chamber_disrupt', fail: 'chamber_fight'),
        ModChoice('Charge Vael', type: ChoiceType.combat, go: 'chamber_fight'),
        ModChoice('Collapse the failing ward and drown the ritual', type: ChoiceType.magic, requires: 'ward_known', check: 'Arcana', dc: 14, ok: 'end_flood', fail: 'chamber_fight'),
      ],
    ),
    'end_flood': ModNode(
      title: 'Lake Morrow',
      loc: 'coast',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'The ward shatters and Lake Morrow comes home. The hymn drowns mid-verse. You claw your way to the surface through a storm of floating books, and watch as two centuries of knowledge sink forever. Vael escaped through a door of fire, but his choir did not.\n\nTo be continued in The Ember Crown III: Throne of Embers.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'Vael has fled to the Throne of Embers to crown the god Ithrax.', 'status': 'update'},
        {'type': 'xp', 'amount': 200},
      ],
    ),
    'chamber_disrupt': ModNode(
      title: 'Hymn Chamber',
      loc: 'temple',
      time: 'night',
      mood: 'combat',
      sets: ['disrupted'],
      text: 'Your voice cracks the hymn like ice. The crown dims. Vael screams, and his guardians come at you weakened and wild.',
      combat: ModCombat([
        {'name': 'Flameskull', 'monster': 'flameskull', 'count': 1, 'hp': 25},
        {'name': 'Choir Fanatic', 'monster': 'cult_fanatic', 'count': 1},
      ], win: 'end', lose: 'end_lost', boss: true),
    ),
    'chamber_fight': ModNode(
      title: 'Hymn Chamber',
      loc: 'temple',
      time: 'night',
      mood: 'combat',
      text: 'The flameskull cackles and the choir draws steel.',
      combat: ModCombat([
        {'name': 'Flameskull', 'monster': 'flameskull', 'count': 1},
        {'name': 'Choir Fanatic', 'monster': 'cult_fanatic', 'count': 2},
      ], win: 'end', lose: 'end_lost', boss: true),
    ),
    'end': ModNode(
      title: 'Hymn Chamber',
      loc: 'temple',
      time: 'night',
      mood: 'triumph',
      end: 'victory',
      text:
          'The guardians fall, but Vael is gone: a door of fire closes behind him, leaving the smell of a volcano. The archive groans as the ward fails. You scramble up the Drowned Stair as the lake pours in, and break the surface at dawn.\n\nVael has gone to the Throne of Embers. And you know how to end this.\n\nTo be continued in The Ember Crown III: Throne of Embers.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'Vael has fled to the Throne of Embers to crown the god Ithrax.', 'status': 'update'},
        {'type': 'xp', 'amount': 250},
        {'type': 'gold', 'amount': 120},
      ],
    ),
    'end_lost': ModNode(
      title: 'Lake Morrow',
      loc: 'coast',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text:
          'You wake on the shore of Lake Morrow, coughing water. Someone dragged you out. Perhaps Wynne, perhaps the sahuagin, perhaps luck. Vael is gone with the crown. But you heard where he is going.\n\nTo be continued in The Ember Crown III: Throne of Embers.',
      events: [
        {'type': 'xp', 'amount': 100},
      ],
    ),
  },
);

const emberCrown3 = AdventureModule(
  id: 'ember_crown_3',
  title: 'The Ember Crown III: Throne of Embers',
  tagline: 'Climb the volcano. Face the prophet. Decide the fate of a god.',
  description:
      'The Throne of Embers is a fortress carved into a living volcano. Vael means to crown the fire god Ithrax there and burn the world clean. Fight through hell hounds and gargoyles, reach the ancient forge, and choose: destroy the crown, put the god back to sleep, or wear it yourself. Part three of three.',
  levels: '5–7',
  minutes: 40,
  tone: 'Epic',
  setting: 'High fantasy',
  coverLoc: 'mountain',
  coverTime: 'night',
  mapKind: MapKind.dungeon,
  mapName: 'Throne of Embers',
  locations: ['Obsidian Steps', 'The Ash Gate', 'Hall of Furnaces', 'Calder\'s Forge', 'The Throne'],
  tags: ['Campaign', 'Part 3 of 3', 'Boss', 'Multiple endings'],
  seriesId: 'ember_crown',
  seriesName: 'The Ember Crown',
  part: 3,
  start: 'steps',
  nodes: {
    'steps': ModNode(
      title: 'Obsidian Steps',
      loc: 'mountain',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Obsidian Steps',
      text:
          'A thousand steps of black glass climb the volcano\'s flank. The sky glows red from beneath. Halfway up, the mountain shudders, and you hear it: a heartbeat, enormous and slow, coming from inside the rock.\n\nIthrax is waking.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'description': 'Stop Prophet Vael at the Throne of Embers and decide the fate of Ithrax.', 'status': 'update'},
      ],
      choices: [
        ModChoice('Climb quickly and quietly', type: ChoiceType.stealth, check: 'Stealth', dc: 14, ok: 'gate_quiet', fail: 'hounds'),
        ModChoice('Climb steadily, weapons ready', type: ChoiceType.explore, go: 'hounds'),
        ModChoice('Pray at the shrine of Saint Calder on the steps', type: ChoiceType.magic, check: 'Religion', dc: 12, ok: 'steps_blessing', fail: 'hounds', unless: 'blessed'),
      ],
    ),
    'steps_blessing': ModNode(
      title: 'Obsidian Steps',
      loc: 'mountain',
      time: 'night',
      mood: 'calm',
      sets: ['blessed'],
      text: 'A cool wind answers your prayer. For a moment you feel Saint Calder\'s hand on your shoulder, and the heat of the mountain cannot touch you.',
      events: [
        {'type': 'heal', 'target': 'hero', 'amount': 20},
        {'type': 'item', 'action': 'add', 'id': 'potion_resistance', 'name': 'Potion of Fire Resistance'},
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Continue the climb', type: ChoiceType.explore, go: 'hounds'),
      ],
    ),
    'hounds': ModNode(
      title: 'Obsidian Steps',
      loc: 'mountain',
      time: 'night',
      mood: 'combat',
      text: 'Smoke pours down the steps, and out of it come hounds with coals for eyes, breathing fire.',
      combat: ModCombat([
        {'name': 'Hell Hound', 'monster': 'hell_hound', 'count': 2},
      ], win: 'gate'),
    ),
    'gate_quiet': ModNode(
      title: 'The Ash Gate',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Ash Gate',
      sets: ['quiet'],
      text: 'You reach the gate unseen. Two stone gargoyles perch on the arch, and you can tell by the way the soot has settled that they have not moved in a week.',
      choices: [
        ModChoice('Slip past the gargoyles', type: ChoiceType.stealth, check: 'Stealth', dc: 14, ok: 'furnaces', fail: 'gate_fight'),
        ModChoice('Smash them while they sleep', type: ChoiceType.combat, go: 'gate_ambush'),
      ],
    ),
    'gate': ModNode(
      title: 'The Ash Gate',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Ash Gate',
      text: 'The Ash Gate is a mouth of iron set into the mountain. Two gargoyles on the arch unfold their wings with a sound like grinding millstones.',
      choices: [
        ModChoice('Fight your way in', type: ChoiceType.combat, go: 'gate_fight'),
        ModChoice('Speak the words on the Choir Hymnal', type: ChoiceType.dialogue, requires: 'item:Choir Hymnal', check: 'Deception', dc: 13, ok: 'furnaces', fail: 'gate_fight'),
      ],
    ),
    'gate_ambush': ModNode(
      title: 'The Ash Gate',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      text: 'Stone cracks under your first blow.',
      combat: ModCombat([
        {'name': 'Gargoyle', 'monster': 'gargoyle', 'count': 2},
      ], win: 'furnaces', surprise: 'enemies'),
    ),
    'gate_fight': ModNode(
      title: 'The Ash Gate',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      text: 'The gargoyles drop on you with stone claws.',
      combat: ModCombat([
        {'name': 'Gargoyle', 'monster': 'gargoyle', 'count': 2},
      ], win: 'furnaces'),
    ),
    'furnaces': ModNode(
      title: 'Hall of Furnaces',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Hall of Furnaces',
      text:
          'A hall of furnaces, each one holding a prisoner in a cage above the coals: villagers taken along the Ashen Road. "Fuel for the coronation," a guard says, bored, before he sees you.\n\nTwo paths: the ramp up to the Throne, where Vael\'s singing grows louder, or the side tunnel marked with Saint Calder\'s hammer, leading to the old forge.',
      choices: [
        ModChoice('Free the prisoners', type: ChoiceType.action, check: 'Athletics', dc: 13, ok: 'freed', fail: 'furnace_fight', set: 'freeing'),
        ModChoice('Hurry to the forge', type: ChoiceType.explore, go: 'forge'),
        ModChoice('Go straight for the Throne', type: ChoiceType.explore, go: 'throne'),
      ],
    ),
    'furnace_fight': ModNode(
      title: 'Hall of Furnaces',
      loc: 'dungeon',
      time: 'night',
      mood: 'combat',
      text: 'The guards rush you while the cages swing.',
      combat: ModCombat([
        {'name': 'Choir Fanatic', 'monster': 'cult_fanatic', 'count': 1},
        {'name': 'Choir Thug', 'monster': 'thug', 'count': 2},
      ], win: 'freed'),
    ),
    'freed': ModNode(
      title: 'Hall of Furnaces',
      loc: 'dungeon',
      time: 'night',
      mood: 'triumph',
      sets: ['freed'],
      text:
          'The cages come down one by one. A blacksmith from Cinderbrook grips your hand. "The forge," he says. "Calder\'s forge still burns. I heard them say the crown must not go near it. That means it\'s where you want it to go."',
      events: [
        {'type': 'xp', 'amount': 150},
        {'type': 'item', 'action': 'add', 'id': 'potion_superior', 'name': 'Potion of Superior Healing'},
      ],
      choices: [
        ModChoice('Head to the forge', type: ChoiceType.explore, go: 'forge'),
        ModChoice('Go straight for the Throne', type: ChoiceType.explore, go: 'throne'),
      ],
    ),
    'forge': ModNode(
      title: 'Calder\'s Forge',
      loc: 'temple',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'Calder\'s Forge',
      sets: ['forge_seen'],
      text:
          'An anvil the size of a cart sits in a pool of white-hot metal that has not cooled in three hundred years. Hammer marks the size of your fist cover the walls in a script you somehow understand: here the crown was made, here it may be unmade.\n\nOn the anvil lies a hammer. It is not heavy at all.',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Calder\'s Hammer', 'description': 'The hammer that forged the Ember Crown. It could unmake it.'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Climb to the Throne', type: ChoiceType.explore, go: 'throne'),
      ],
    ),
    'throne': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'night',
      mood: 'combat',
      mapLoc: 'The Throne',
      speaker: 'Prophet Vael',
      text:
          'The volcano\'s crater opens to a red sky. On a throne of cooling lava sits Prophet Vael, the Ember Crown on his brow, his skin cracking with light. Beneath the crater floor, something vast turns over in its sleep.\n\n"Kneel," Vael says, and every flame in the crater bows. "Or burn with the rest."',
      choices: [
        ModChoice('Sing the second verse', type: ChoiceType.magic, requires: 'item:The Second Verse', check: 'Performance', dc: 14, ok: 'vael_weak', fail: 'vael_fight'),
        ModChoice('Appeal to the man beneath the crown', type: ChoiceType.dialogue, check: 'Persuasion', dc: 17, ok: 'vael_weak', fail: 'vael_fight', easierIf: 'freed'),
        ModChoice('Attack', type: ChoiceType.combat, go: 'vael_fight'),
      ],
    ),
    'vael_weak': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'night',
      mood: 'combat',
      text: 'Vael flinches as if struck. The crown flickers, and for a heartbeat he is only a frightened old man. Then the fire floods back, and he rises screaming, weaker than before.',
      combat: ModCombat([
        {'name': 'Prophet Vael', 'monster': 'lich_apprentice', 'count': 1, 'hp': 55, 'ac': 15, 'attack_bonus': 7, 'damage': '3d8+3', 'attack_name': 'Crown-fire'},
        {'name': 'Hell Hound', 'monster': 'hell_hound', 'count': 1},
      ], win: 'choice', lose: 'end_burn', boss: true),
    ),
    'vael_fight': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'night',
      mood: 'combat',
      text: 'Fire answers him. The crater floor splits, and a young red dragon claws its way out of the magma at Vael\'s side.',
      combat: ModCombat([
        {'name': 'Prophet Vael', 'monster': 'lich_apprentice', 'count': 1, 'hp': 70, 'ac': 15, 'attack_bonus': 7, 'damage': '3d8+3', 'attack_name': 'Crown-fire'},
        {'name': 'Ember Wyrmling', 'monster': 'young_dragon', 'count': 1, 'hp': 60},
      ], win: 'choice', lose: 'end_burn', boss: true),
    ),
    'choice': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'dawn',
      mood: 'tense',
      text:
          'Vael falls, and the Ember Crown rolls across the glass floor and stops at your feet. It is warm. It whispers. It knows your name.\n\nWith it you could command fire, end every war, warm every winter. Or you could carry it to the forge. Or simply sing it back to sleep.',
      choices: [
        ModChoice('Take it to Calder\'s Forge and strike', type: ChoiceType.action, requires: 'item:Calder\'s Hammer', go: 'end_destroy'),
        ModChoice('Sing Ithrax back to sleep', type: ChoiceType.magic, requires: 'item:The Second Verse', go: 'end_sleep'),
        ModChoice('Return the crown to Emberfall', type: ChoiceType.dialogue, go: 'end_return'),
        ModChoice('Put on the crown', type: ChoiceType.magic, go: 'end_wear'),
      ],
    ),
    'end_destroy': ModNode(
      title: 'Calder\'s Forge',
      loc: 'temple',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      text:
          'You lay the crown on Calder\'s anvil and bring the hammer down. The sound is every bell in the world ringing once. Light pours out of the broken crown and up through the mountain, and the heartbeat beneath the rock slows, and stops, and is gone.\n\nThe volcano sleeps. Emberfall will remember your name for three hundred years.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'status': 'completed'},
        {'type': 'xp', 'amount': 800},
        {'type': 'gold', 'amount': 300},
        {'type': 'item', 'action': 'add', 'id': 'flame_tongue', 'name': 'Flame Tongue'},
      ],
    ),
    'end_sleep': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'dawn',
      mood: 'calm',
      end: 'victory',
      text:
          'You sing, and the crater listens. The heartbeat slows to a crawl. Ithrax sleeps again, perhaps for another three centuries. Perhaps someone better will know what to do with him then. You carry the crown home, heavy and quiet.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'status': 'completed'},
        {'type': 'xp', 'amount': 700},
        {'type': 'gold', 'amount': 250},
      ],
    ),
    'end_return': ModNode(
      title: 'Emberfall Temple',
      loc: 'temple',
      time: 'day',
      mood: 'triumph',
      end: 'bittersweet',
      text:
          'High Keeper Ansa weeps when she sees the crown. It is placed back on its cushion with a hundred new candles. But at night, the temple keepers say, they can still hear a heartbeat under the floor. The Choir has other prophets.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'status': 'completed'},
        {'type': 'xp', 'amount': 600},
        {'type': 'gold', 'amount': 400},
      ],
    ),
    'end_wear': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'dawn',
      mood: 'eerie',
      end: 'bittersweet',
      text:
          'The crown fits perfectly. Warmth floods you, then power, then a voice that is not yours saying thank you. The dragon bows. The mountain bows. Somewhere far away, Emberfall\'s candles all go out at once.\n\nThey will tell stories about you. Not all of them will be kind.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'status': 'completed'},
        {'type': 'xp', 'amount': 800},
        {'type': 'item', 'action': 'add', 'name': 'The Ember Crown', 'description': 'It whispers in a voice like a forest fire. You are never cold any more.'},
      ],
    ),
    'end_burn': ModNode(
      title: 'The Throne',
      loc: 'mountain',
      time: 'night',
      mood: 'sad',
      end: 'defeat',
      text: 'Fire takes everything. Vael\'s laughter is the last thing you hear as Ithrax opens his eyes beneath the world.',
      events: [
        {'type': 'quest', 'title': 'The Ember Crown', 'status': 'failed'},
      ],
    ),
  },
);

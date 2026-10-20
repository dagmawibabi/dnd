import '../../game/module_engine.dart';
import '../../models/adventure.dart';

const gildedHeist = AdventureModule(
  id: 'gilded_heist',
  title: 'The Gilded Heist',
  tagline: 'One vault. One night. One very bad merchant prince.',
  description:
      'The Countinghouse of Varn is the most secure building in the city, and Prince Aurex keeps something in its vault worth more than gold. Assemble a crew, case the joint, choose your way in and decide what to walk out with. Written for rogues and bards, playable by anyone with quick hands or a quicker tongue.',
  levels: '2–4',
  minutes: 30,
  tone: 'Lighthearted',
  setting: 'City intrigue',
  coverLoc: 'town',
  coverTime: 'night',
  mapKind: MapKind.town,
  mapName: 'The City of Varn',
  locations: ['The Crooked Flagon', 'Countinghouse Square', 'The Sewers', 'The Rooftops', 'The Vault Hall', 'The Vault'],
  tags: ['Heist', 'Rogue', 'Bard', 'Multiple endings'],
  classes: ['rogue', 'bard'],
  start: 'flagon',
  nodes: {
    'flagon': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'night',
      mood: 'festive',
      mapLoc: 'The Crooked Flagon',
      speaker: 'Mother Mags',
      text:
          'The back room of the Crooked Flagon smells of pipe smoke and bad decisions. Mother Mags, fence and grandmother of half the thieves in Varn, slides a sketch across the table.\n\n"The Countinghouse vault. Prince Aurex keeps his gold there, and something else: a ledger. Whatever is in it scares the city council more than he does. Bring me either, and you\'ll never pay for a drink here again."',
      events: [
        {'type': 'quest', 'title': 'The Gilded Heist', 'description': 'Break into the Countinghouse vault and get out with the prince\'s gold, or his ledger.', 'status': 'new'},
        {'type': 'npc', 'name': 'Mother Mags', 'role': 'fence', 'race': 'halfling', 'disposition': 30, 'description': 'Knits while she plans crimes.'},
      ],
      choices: [
        ModChoice('Recruit Pip the forger', type: ChoiceType.dialogue, go: 'crew_forger', unless: 'crew'),
        ModChoice('Recruit Brannigan the muscle', type: ChoiceType.dialogue, go: 'crew_muscle', unless: 'crew'),
        ModChoice('Work alone', type: ChoiceType.action, go: 'square', unless: 'crew'),
        ModChoice('Case the Countinghouse', type: ChoiceType.explore, go: 'square', requires: 'crew'),
      ],
    ),
    'crew_forger': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'night',
      mood: 'festive',
      sets: ['crew', 'forger'],
      text: 'Pip, an ink-stained gnome, waggles her fingers. "Need a guild seal? Writ of entry? A letter from your mother saying you\'re allowed out after dark? I do it all."',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Forged Writ', 'description': 'An auditor\'s writ of entry to the Countinghouse. Almost real.'},
      ],
      choices: [
        ModChoice('Case the Countinghouse', type: ChoiceType.explore, go: 'square'),
      ],
    ),
    'crew_muscle': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'night',
      mood: 'festive',
      sets: ['crew', 'muscle'],
      text: 'Brannigan, a half-orc built like a door, cracks his knuckles. "I don\'t do sneaking. I do lifting. Heavy things. People, sometimes."',
      events: [
        {'type': 'companion_join', 'name': 'Brannigan', 'race': 'half-orc', 'class': 'barbarian', 'personality': 'Gentle giant, loves cats, hates bankers'},
      ],
      choices: [
        ModChoice('Case the Countinghouse', type: ChoiceType.explore, go: 'square'),
      ],
    ),
    'square': ModNode(
      title: 'Countinghouse Square',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      mapLoc: 'Countinghouse Square',
      text:
          'The Countinghouse squats in the square like a golden toad. Guards change every hour. A sewer grate breathes steam nearby, and the roofs of the neighboring guildhalls nearly touch its upper windows.',
      choices: [
        ModChoice('Study the guard rotation', type: ChoiceType.explore, check: 'Perception', dc: 12, ok: 'square_timing', fail: 'square_plan', set: 'cased', unless: 'cased'),
        ModChoice('Go in through the sewers', type: ChoiceType.stealth, go: 'sewers'),
        ModChoice('Cross the rooftops', type: ChoiceType.stealth, go: 'roofs'),
        ModChoice('Walk in the front door with the writ', type: ChoiceType.dialogue, requires: 'item:Forged Writ', go: 'front'),
        ModChoice('Talk your way in as an entertainer', type: ChoiceType.dialogue, requires: 'class:bard', go: 'front_bard'),
      ],
    ),
    'square_timing': ModNode(
      title: 'Countinghouse Square',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      sets: ['timing'],
      text: 'At the half-bell, the guards on the vault hall swap posts and there are forty heartbeats when nobody is watching the inner door. That will make things easier.',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Go in through the sewers', type: ChoiceType.stealth, go: 'sewers'),
        ModChoice('Cross the rooftops', type: ChoiceType.stealth, go: 'roofs'),
        ModChoice('Walk in the front door with the writ', type: ChoiceType.dialogue, requires: 'item:Forged Writ', go: 'front'),
      ],
    ),
    'square_plan': ModNode(
      title: 'Countinghouse Square',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      text: 'The guards are irregular, bored and sharp-eyed. You will have to improvise.',
      choices: [
        ModChoice('Go in through the sewers', type: ChoiceType.stealth, go: 'sewers'),
        ModChoice('Cross the rooftops', type: ChoiceType.stealth, go: 'roofs'),
        ModChoice('Walk in the front door with the writ', type: ChoiceType.dialogue, requires: 'item:Forged Writ', go: 'front'),
      ],
    ),
    'sewers': ModNode(
      title: 'The Sewers',
      loc: 'sewer',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'The Sewers',
      text: 'Ankle-deep water, then knee-deep. Ahead, the Countinghouse drain is barred, and something big and many-legged is nesting in the pipe above it.',
      choices: [
        ModChoice('Bend the bars', type: ChoiceType.action, check: 'Athletics', dc: 13, ok: 'hall', fail: 'sewer_fight', easierIf: 'muscle'),
        ModChoice('Pick the old lock on the grate', type: ChoiceType.stealth, check: 'Sleight of Hand', dc: 13, ok: 'hall', fail: 'sewer_fight'),
        ModChoice('Deal with the creature first', type: ChoiceType.combat, go: 'sewer_fight'),
      ],
    ),
    'sewer_fight': ModNode(
      title: 'The Sewers',
      loc: 'sewer',
      time: 'night',
      mood: 'combat',
      text: 'The nest erupts.',
      combat: ModCombat([
        {'name': 'Sewer Spider', 'monster': 'giant_spider', 'count': 1},
        {'name': 'Giant Rat', 'monster': 'giant_rat', 'count': 2},
      ], win: 'hall'),
    ),
    'roofs': ModNode(
      title: 'The Rooftops',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Rooftops',
      text: 'The city spreads below you like spilled coins. The gap to the Countinghouse window is long, and a lookout with a crossbow is dozing on the next roof.',
      choices: [
        ModChoice('Leap the gap', type: ChoiceType.action, check: 'Acrobatics', dc: 13, ok: 'hall', fail: 'roof_fall'),
        ModChoice('Knock out the lookout quietly', type: ChoiceType.stealth, check: 'Stealth', dc: 13, ok: 'roof_rope', fail: 'roof_fight'),
      ],
    ),
    'roof_rope': ModNode(
      title: 'The Rooftops',
      loc: 'town',
      time: 'night',
      mood: 'calm',
      text: 'The lookout slumps with barely a sigh. He was carrying a grappling rope, which makes the gap considerably less exciting.',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'rope', 'name': 'Rope'},
      ],
      choices: [
        ModChoice('Swing across', type: ChoiceType.action, go: 'hall'),
      ],
    ),
    'roof_fall': ModNode(
      title: 'The Rooftops',
      loc: 'town',
      time: 'night',
      mood: 'tense',
      text: 'You catch the window ledge with your fingertips and your shins with the wall. It hurts, but you\'re in.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 5, 'reason': 'a hard landing'},
      ],
      choices: [
        ModChoice('Climb inside', type: ChoiceType.explore, go: 'hall'),
      ],
    ),
    'roof_fight': ModNode(
      title: 'The Rooftops',
      loc: 'town',
      time: 'night',
      mood: 'combat',
      text: 'The lookout wakes with a yell and whistles for help.',
      combat: ModCombat([
        {'name': 'Rooftop Lookout', 'monster': 'scout', 'count': 1},
        {'name': 'Thug', 'monster': 'thug', 'count': 1},
      ], win: 'hall'),
    ),
    'front': ModNode(
      title: 'The Vault Hall',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      speaker: 'Clerk Ormond',
      text: 'A nervous clerk squints at your writ. "An audit? At this hour? The prince didn\'t mention..."',
      choices: [
        ModChoice('Insist with official impatience', type: ChoiceType.dialogue, check: 'Deception', dc: 12, ok: 'hall', fail: 'hall_alarm', easierIf: 'forger'),
        ModChoice('Bribe him', type: ChoiceType.dialogue, requires: 'gold:30', go: 'hall', effects: [
          {'type': 'gold', 'amount': -30},
        ]),
      ],
    ),
    'front_bard': ModNode(
      title: 'The Vault Hall',
      loc: 'castle',
      time: 'night',
      mood: 'festive',
      text: 'You announce yourself as the prince\'s birthday surprise and launch into a song so rousing the guards start clapping along. Nobody notices you drifting toward the vault.',
      events: [
        {'type': 'xp', 'amount': 75},
      ],
      choices: [
        ModChoice('Slip into the vault hall', type: ChoiceType.stealth, go: 'hall'),
      ],
    ),
    'hall_alarm': ModNode(
      title: 'The Vault Hall',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      text: 'The clerk yanks a bell rope. Guards pour in.',
      combat: ModCombat([
        {'name': 'Countinghouse Guard', 'monster': 'bandit', 'count': 2, 'ac': 15},
        {'name': 'Guard Captain', 'monster': 'bandit_captain', 'count': 1},
      ], win: 'hall'),
    ),
    'hall': ModNode(
      title: 'The Vault Hall',
      loc: 'castle',
      time: 'night',
      mood: 'tense',
      mapLoc: 'The Vault Hall',
      text:
          'A long marble hall ends in a round vault door covered in seven brass dials. A suit of gilded armor stands beside it, perfectly still. Too still.',
      choices: [
        ModChoice('Crack the dials', type: ChoiceType.stealth, check: 'Sleight of Hand', dc: 15, ok: 'vault', fail: 'hall_guardian', easierIf: 'timing'),
        ModChoice('Work out the combination from the prince\'s portrait', type: ChoiceType.explore, check: 'Investigation', dc: 14, ok: 'vault', fail: 'hall_guardian'),
        ModChoice('Disable the armor first', type: ChoiceType.combat, go: 'hall_guardian'),
      ],
    ),
    'hall_guardian': ModNode(
      title: 'The Vault Hall',
      loc: 'castle',
      time: 'night',
      mood: 'combat',
      text: 'The gilded armor turns its head toward you with a creak of brass.',
      combat: ModCombat([
        {'name': 'Gilded Guardian', 'monster': 'animated_armor', 'count': 1, 'hp': 38},
      ], win: 'vault'),
    ),
    'vault': ModNode(
      title: 'The Vault',
      loc: 'dungeon',
      time: 'night',
      mood: 'mystery',
      mapLoc: 'The Vault',
      text:
          'Gold. Mountains of it, in neat stacks. At the center, on a plinth, sits a leather ledger and a chest that is just slightly too eager to be opened.\n\nThe ledger\'s first page lists payments to the river poisoners of Lowtown, signed by Prince Aurex.',
      choices: [
        ModChoice('Open the eager chest', type: ChoiceType.explore, check: 'Perception', dc: 14, ok: 'vault_mimic_spotted', fail: 'vault_mimic'),
        ModChoice('Take the ledger', type: ChoiceType.action, go: 'end_ledger'),
        ModChoice('Fill your bags with gold', type: ChoiceType.action, go: 'end_gold'),
        ModChoice('Take the ledger and as much gold as you can carry', type: ChoiceType.action, check: 'Athletics', dc: 15, ok: 'end_both', fail: 'vault_caught', easierIf: 'muscle'),
      ],
    ),
    'vault_mimic_spotted': ModNode(
      title: 'The Vault',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      text: 'The chest\'s hinges are breathing. You spot the teeth just in time and back away. The mimic sulks, but it was sitting on a pair of very fine boots.',
      events: [
        {'type': 'item', 'action': 'add', 'id': 'boots_elvenkind', 'name': 'Boots of Elvenkind'},
        {'type': 'xp', 'amount': 75},
      ],
      choices: [
        ModChoice('Take the ledger', type: ChoiceType.action, go: 'end_ledger'),
        ModChoice('Fill your bags with gold', type: ChoiceType.action, go: 'end_gold'),
      ],
    ),
    'vault_mimic': ModNode(
      title: 'The Vault',
      loc: 'dungeon',
      time: 'night',
      mood: 'combat',
      text: 'The chest opens. So does its mouth.',
      combat: ModCombat([
        {'name': 'Vault Mimic', 'monster': 'mimic', 'count': 1},
      ], win: 'vault_mimic_spotted', boss: true),
    ),
    'vault_caught': ModNode(
      title: 'The Vault',
      loc: 'dungeon',
      time: 'night',
      mood: 'tense',
      text: 'The bags split and gold cascades across the marble with a noise like a cathedral collapsing. Boots thunder in the hall. You grab the ledger and run.',
      choices: [
        ModChoice('Escape with the ledger', type: ChoiceType.action, go: 'end_ledger'),
      ],
    ),
    'end_ledger': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      speaker: 'Mother Mags',
      text:
          'By noon the ledger is on the council\'s table. By evening Prince Aurex is in chains, and the river in Lowtown runs clean for the first time in years. Mags raises a glass. "Best heist this city ever saw, and you didn\'t steal a single coin. I\'m almost ashamed of you."',
      events: [
        {'type': 'quest', 'title': 'The Gilded Heist', 'status': 'completed'},
        {'type': 'xp', 'amount': 300},
        {'type': 'gold', 'amount': 100},
      ],
    ),
    'end_gold': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'dawn',
      mood: 'festive',
      end: 'bittersweet',
      speaker: 'Mother Mags',
      text: 'You walk out rich. Mags counts it twice and pours you her best brandy. Down in Lowtown, the river is still poisoned, and the prince is still smiling.',
      events: [
        {'type': 'quest', 'title': 'The Gilded Heist', 'status': 'completed'},
        {'type': 'xp', 'amount': 200},
        {'type': 'gold', 'amount': 500},
      ],
    ),
    'end_both': ModNode(
      title: 'The Crooked Flagon',
      loc: 'tavern',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      text: 'Ledger in one hand, gold on your back, you vanish into the dawn. The prince falls, the river runs clean, and the Crooked Flagon throws a party that the city will talk about for a decade.',
      events: [
        {'type': 'quest', 'title': 'The Gilded Heist', 'status': 'completed'},
        {'type': 'xp', 'amount': 350},
        {'type': 'gold', 'amount': 350},
      ],
    ),
  },
);

const lichOfHollowmere = AdventureModule(
  id: 'lich_hollowmere',
  title: 'The Lich of Hollowmere',
  tagline: 'The dead of Hollowmere are walking home.',
  description:
      'Every night the dead of Hollowmere climb out of their graves and walk back to the houses they lived in. The village priest is missing. Somewhere beneath the old abbey, a would-be lich is building an army. Written for clerics and paladins, with holy options at every turn, but any brave soul is welcome.',
  levels: '4–6',
  minutes: 35,
  tone: 'Grim',
  setting: 'Dark fantasy',
  coverLoc: 'crypt',
  coverTime: 'night',
  mapKind: MapKind.overworld,
  mapName: 'Hollowmere',
  locations: ['Hollowmere Village', 'The Graveyard', 'Abbey Ruins', 'The Ossuary', 'The Phylactery Vault'],
  tags: ['Undead', 'Cleric', 'Paladin', 'Boss'],
  classes: ['cleric', 'paladin'],
  start: 'village',
  nodes: {
    'village': ModNode(
      title: 'Hollowmere Village',
      loc: 'town',
      time: 'dusk',
      mood: 'eerie',
      mapLoc: 'Hollowmere Village',
      speaker: 'Elder Bramm',
      text:
          'Doors are nailed shut and salt lines every threshold. Elder Bramm meets you with a lantern and a pitchfork. "They come at moonrise. My wife came home last night. Knocked on the door. I didn\'t open it." His voice breaks. "Father Aldo went to the abbey to find out why. That was four days ago."',
      events: [
        {'type': 'quest', 'title': 'The Walking Dead', 'description': 'Find out why the dead of Hollowmere rise, and find Father Aldo.', 'status': 'new'},
        {'type': 'npc', 'name': 'Elder Bramm', 'role': 'village elder', 'race': 'human', 'disposition': 30, 'description': 'Exhausted and grieving.'},
      ],
      choices: [
        ModChoice('Bless the village wards', type: ChoiceType.magic, requires: 'class:cleric|paladin', go: 'village_blessed'),
        ModChoice('Ask about the abbey', type: ChoiceType.dialogue, check: 'Persuasion', dc: 11, ok: 'village_lore', fail: 'graveyard'),
        ModChoice('Wait for moonrise in the graveyard', type: ChoiceType.explore, go: 'graveyard'),
      ],
    ),
    'village_blessed': ModNode(
      title: 'Hollowmere Village',
      loc: 'town',
      time: 'dusk',
      mood: 'calm',
      sets: ['blessed', 'lore'],
      text: 'You walk the salt lines with a prayer, and they glow faintly silver. The villagers come out of their houses for the first time in days. A child gives you a sprig of rosemary. Bramm tells you the abbey\'s ossuary was sealed a century ago for a reason.',
      events: [
        {'type': 'xp', 'amount': 75},
        {'type': 'item', 'action': 'add', 'name': 'Holy Water', 'description': 'Blessed by your own prayers. Undead fear it.'},
      ],
      choices: [
        ModChoice('Go to the graveyard', type: ChoiceType.explore, go: 'graveyard'),
      ],
    ),
    'village_lore': ModNode(
      title: 'Hollowmere Village',
      loc: 'town',
      time: 'dusk',
      mood: 'mystery',
      sets: ['lore'],
      text: '"The old abbots buried something under the ossuary," Bramm says. "A wizard who wanted to live forever. We thought it was a story to scare children."',
      events: [
        {'type': 'xp', 'amount': 50},
      ],
      choices: [
        ModChoice('Go to the graveyard', type: ChoiceType.explore, go: 'graveyard'),
      ],
    ),
    'graveyard': ModNode(
      title: 'The Graveyard',
      loc: 'crypt',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'The Graveyard',
      text: 'The moon rises. The earth stirs. Hands, then heads, then whole bodies push up from the graves and turn, as one, toward the village.',
      choices: [
        ModChoice('Turn the undead', type: ChoiceType.magic, requires: 'class:cleric|paladin', check: 'Religion', dc: 12, ok: 'graveyard_turned', fail: 'graveyard_fight'),
        ModChoice('Throw holy water', type: ChoiceType.action, requires: 'item:Holy Water', go: 'graveyard_turned'),
        ModChoice('Fight them in the gate', type: ChoiceType.combat, go: 'graveyard_fight'),
        ModChoice('Follow one back to where it came from', type: ChoiceType.stealth, check: 'Stealth', dc: 13, ok: 'abbey', fail: 'graveyard_fight'),
      ],
    ),
    'graveyard_turned': ModNode(
      title: 'The Graveyard',
      loc: 'crypt',
      time: 'night',
      mood: 'triumph',
      text: 'Radiance bursts from you. The dead stumble back, shielding empty eyes, and flee toward the abbey ruins on the hill. They are showing you the way.',
      events: [
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Follow them to the abbey', type: ChoiceType.explore, go: 'abbey'),
      ],
    ),
    'graveyard_fight': ModNode(
      title: 'The Graveyard',
      loc: 'crypt',
      time: 'night',
      mood: 'combat',
      text: 'The dead lurch toward you.',
      combat: ModCombat([
        {'name': 'Risen Villager', 'monster': 'zombie', 'count': 2},
        {'name': 'Grave Ghoul', 'monster': 'ghoul', 'count': 1},
      ], win: 'abbey'),
    ),
    'abbey': ModNode(
      title: 'Abbey Ruins',
      loc: 'ruins',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'Abbey Ruins',
      speaker: 'Father Aldo',
      text:
          'In the roofless chapel, a priest is chained to the altar, praying through cracked lips. "Thank the gods. Don\'t touch the chains, they\'re warded. The thing below is called Morvane. He is almost a lich. He needs one more soul for his phylactery. Mine."',
      events: [
        {'type': 'npc', 'name': 'Father Aldo', 'role': 'village priest', 'race': 'human', 'disposition': 50, 'description': 'Brave, terrified, still praying.'},
      ],
      choices: [
        ModChoice('Dispel the ward on the chains', type: ChoiceType.magic, check: 'Arcana', dc: 14, ok: 'aldo_free', fail: 'aldo_ward'),
        ModChoice('Break the chains by force', type: ChoiceType.action, check: 'Athletics', dc: 15, ok: 'aldo_free', fail: 'aldo_ward'),
        ModChoice('Pray with him for the strength to break them', type: ChoiceType.magic, requires: 'class:cleric|paladin', go: 'aldo_free'),
      ],
    ),
    'aldo_ward': ModNode(
      title: 'Abbey Ruins',
      loc: 'ruins',
      time: 'night',
      mood: 'tense',
      text: 'The ward bites, cold and hungry. Necrotic frost crawls up your arms, but the chains crack and fall.',
      events: [
        {'type': 'damage', 'target': 'hero', 'amount': 8, 'reason': 'a necrotic ward'},
      ],
      choices: [
        ModChoice('Help Aldo up', type: ChoiceType.action, go: 'aldo_free'),
      ],
    ),
    'aldo_free': ModNode(
      title: 'Abbey Ruins',
      loc: 'ruins',
      time: 'night',
      mood: 'calm',
      speaker: 'Father Aldo',
      sets: ['aldo'],
      text: '"Morvane\'s phylactery is in the vault under the ossuary," Aldo says. "Destroy it and he dies for good. Fight him without destroying it and he\'ll just come back." He presses his holy symbol into your hand. "Take this. It knows the way."',
      events: [
        {'type': 'item', 'action': 'add', 'name': 'Aldo\'s Holy Symbol', 'description': 'It grows warm near evil.'},
        {'type': 'item', 'action': 'add', 'id': 'potion_greater', 'name': 'Potion of Greater Healing'},
        {'type': 'xp', 'amount': 100},
      ],
      choices: [
        ModChoice('Descend into the ossuary', type: ChoiceType.explore, go: 'ossuary'),
        ModChoice('Rest a while before descending', type: ChoiceType.rest, go: 'abbey_rest'),
      ],
    ),
    'abbey_rest': ModNode(
      title: 'Abbey Ruins',
      loc: 'ruins',
      time: 'dawn',
      mood: 'calm',
      text: 'You rest beneath the broken roof while Aldo keeps watch and sings old hymns. The dead do not come near.',
      events: [
        {'type': 'rest', 'kind': 'long'},
      ],
      choices: [
        ModChoice('Descend into the ossuary', type: ChoiceType.explore, go: 'ossuary'),
      ],
    ),
    'ossuary': ModNode(
      title: 'The Ossuary',
      loc: 'crypt',
      time: 'night',
      mood: 'eerie',
      mapLoc: 'The Ossuary',
      text: 'Walls of skulls, floors of bones, ceilings of crossed femurs. A dozen skeletons stand in alcoves. In the center, a wight in rusted armor guards a stair leading further down.',
      choices: [
        ModChoice('Fight the wight', type: ChoiceType.combat, go: 'ossuary_fight'),
        ModChoice('Follow the holy symbol\'s warmth to a hidden passage', type: ChoiceType.explore, requires: 'item:Aldo\'s Holy Symbol', check: 'Perception', dc: 13, ok: 'vault', fail: 'ossuary_fight'),
        ModChoice('Command the dead to rest', type: ChoiceType.magic, requires: 'class:cleric|paladin', check: 'Religion', dc: 15, ok: 'vault', fail: 'ossuary_fight'),
      ],
    ),
    'ossuary_fight': ModNode(
      title: 'The Ossuary',
      loc: 'crypt',
      time: 'night',
      mood: 'combat',
      text: 'The wight raises its blade and the skeletons step from their alcoves.',
      combat: ModCombat([
        {'name': 'Ossuary Wight', 'monster': 'wight', 'count': 1},
        {'name': 'Skeleton', 'monster': 'skeleton', 'count': 2},
      ], win: 'vault'),
    ),
    'vault': ModNode(
      title: 'The Phylactery Vault',
      loc: 'crypt',
      time: 'night',
      mood: 'combat',
      mapLoc: 'The Phylactery Vault',
      speaker: 'Morvane',
      text:
          'A vault lit by a single green flame trapped in a crystal: the phylactery. Beside it stands Morvane, more bone than man, his robes stitched from burial shrouds. "A priest\'s errand runner," he sneers. "Your soul will do just as well."',
      choices: [
        ModChoice('Smash the phylactery first', type: ChoiceType.action, check: 'Athletics', dc: 14, ok: 'vault_cracked', fail: 'vault_fight'),
        ModChoice('Hurl holy water at the crystal', type: ChoiceType.action, requires: 'item:Holy Water', go: 'vault_cracked'),
        ModChoice('Attack Morvane', type: ChoiceType.combat, go: 'vault_fight'),
      ],
    ),
    'vault_cracked': ModNode(
      title: 'The Phylactery Vault',
      loc: 'crypt',
      time: 'night',
      mood: 'combat',
      sets: ['phylactery'],
      text: 'The crystal cracks. Morvane screams as the green flame gutters. Now he can die, and he knows it.',
      combat: ModCombat([
        {'name': 'Morvane', 'monster': 'lich_apprentice', 'count': 1, 'hp': 48},
        {'name': 'Skeleton', 'monster': 'skeleton', 'count': 1},
      ], win: 'end_victory', lose: 'end_defeat', boss: true),
    ),
    'vault_fight': ModNode(
      title: 'The Phylactery Vault',
      loc: 'crypt',
      time: 'night',
      mood: 'combat',
      text: 'Morvane laughs and the dead answer.',
      combat: ModCombat([
        {'name': 'Morvane', 'monster': 'lich_apprentice', 'count': 1, 'hp': 60},
        {'name': 'Wraith', 'monster': 'wraith', 'count': 1},
      ], win: 'vault_after', lose: 'end_defeat', boss: true),
    ),
    'vault_after': ModNode(
      title: 'The Phylactery Vault',
      loc: 'crypt',
      time: 'night',
      mood: 'tense',
      text: 'Morvane crumbles to dust, but the green flame in the crystal flares. Dust is already swirling back together. You have moments.',
      choices: [
        ModChoice('Shatter the phylactery', type: ChoiceType.action, check: 'Athletics', dc: 12, ok: 'end_victory', fail: 'end_bitter'),
        ModChoice('Exorcise it with a prayer', type: ChoiceType.magic, requires: 'class:cleric|paladin', go: 'end_victory'),
      ],
    ),
    'end_victory': ModNode(
      title: 'Hollowmere Village',
      loc: 'town',
      time: 'dawn',
      mood: 'triumph',
      end: 'victory',
      text:
          'The phylactery bursts into green sparks that fade like fireflies. Across Hollowmere, the walking dead lie down where they stand, peaceful at last. The villagers bury them again, properly, with songs. Elder Bramm brings flowers to his wife\'s grave and, for the first time in weeks, he sleeps.',
      events: [
        {'type': 'quest', 'title': 'The Walking Dead', 'status': 'completed'},
        {'type': 'xp', 'amount': 600},
        {'type': 'gold', 'amount': 150},
        {'type': 'item', 'action': 'add', 'id': 'mace_disruption', 'name': 'Mace of Disruption'},
      ],
    ),
    'end_bitter': ModNode(
      title: 'Hollowmere Village',
      loc: 'town',
      time: 'dawn',
      mood: 'sad',
      end: 'bittersweet',
      text: 'The crystal skitters away into a crack in the floor and is gone. The dead rest for now. But one day, in some other village, the moon will rise and the graves will stir again.',
      events: [
        {'type': 'quest', 'title': 'The Walking Dead', 'status': 'completed'},
        {'type': 'xp', 'amount': 400},
      ],
    ),
    'end_defeat': ModNode(
      title: 'The Phylactery Vault',
      loc: 'crypt',
      time: 'night',
      mood: 'sad',
      end: 'defeat',
      text: 'Morvane\'s cold hand closes on your heart. Far above, in Hollowmere, someone knocks on Elder Bramm\'s door.',
      events: [
        {'type': 'quest', 'title': 'The Walking Dead', 'status': 'failed'},
      ],
    ),
  },
);

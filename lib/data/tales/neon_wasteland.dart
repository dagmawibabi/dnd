import 'tale_format.dart';

const neonGhost = TalePreset(
  id: 'neon_ghost',
  title: 'Neon Ghost',
  genre: 'cyberpunk',
  blurb: 'Steal one data chip from the Kirin Tower. Easy money — until you learn whose memories are on it.',
  minutes: 15,
  start: 'job',
  nodes: {
    'job': TaleNode(
      'Rain sizzles on the neon of Low Kowloon. Your fixer, Mags, slides a holo across the noodle bar. "Kirin Corp, floor 88. One chip in a vault. Fifty thousand creds." Her eyes flick to your cheap implants. "You need the money. Don\'t ask what\'s on it."',
      title: 'Noodle Bar',
      options: [
        TaleOption('Take the job', 'street'),
        TaleOption('Ask what\'s on it anyway', 'ask', unless: 'asked'),
      ],
    ),
    'ask': TaleNode(
      'Mags sighs. "A person. Somebody\'s mind, uploaded. Kirin wants to sell her. The client wants her back." She shrugs. "Either way, she\'s cargo."',
      title: 'Noodle Bar',
      sets: 'asked',
      options: [TaleOption('Take the job', 'street')],
    ),
    'street': TaleNode(
      'Kirin Tower stabs up into the smog, wrapped in ad-light. Three ways in: the loading dock full of drones, the maintenance shafts, or the front lobby with a borrowed face.',
      title: 'Kirin Tower',
      options: [
        TaleOption('Hack the loading dock drones', 'dock', chance: 0.6, fail: 'alarm'),
        TaleOption('Climb the maintenance shafts', 'shaft', chance: 0.7, fail: 'fall'),
        TaleOption('Buy a fake executive ID from a street doc', 'ripper'),
      ],
    ),
    'ripper': TaleNode(
      'Doc Yao staples a face-mask implant behind your ear. It itches. "Executive Tanaka, for two hours. Then your skin rejects it and things get ugly."',
      title: 'Back-alley Clinic',
      gives: 'Exec ID',
      damage: 10,
      options: [TaleOption('Walk through the front lobby', 'lobby')],
    ),
    'lobby': TaleNode(
      'Security bows to your borrowed face. The elevator hums up to 88 without a single question.',
      title: 'Lobby',
      options: [TaleOption('Step out on floor 88', 'vault')],
    ),
    'dock': TaleNode(
      'Your deck chatters. The drones forget you exist. You ride a cargo lift up to the vault floor inside a crate marked FRAGILE.',
      title: 'Loading Dock',
      options: [TaleOption('Climb out on floor 88', 'vault')],
    ),
    'alarm': TaleNode(
      'Your hack bounces. Red lights. You sprint through the dock with drones on your heels and dive into a service lift, bleeding where a stun-dart grazed you.',
      title: 'Loading Dock',
      damage: 25,
      status: 'Flagged',
      sets: 'flagged',
      options: [TaleOption('Ride up to floor 88', 'vault')],
    ),
    'shaft': TaleNode(
      'Eighty-eight floors of greasy ladders. Your arms burn, but no camera sees you climb.',
      title: 'Maintenance Shaft',
      damage: 10,
      options: [TaleOption('Pry open the vent on 88', 'vault')],
    ),
    'fall': TaleNode(
      'A rung snaps. You fall two floors before your grip catches. Something in your shoulder pops. You climb on, teeth clenched.',
      title: 'Maintenance Shaft',
      damage: 30,
      options: [TaleOption('Keep climbing', 'vault')],
    ),
    'vault': TaleNode(
      'The vault is a white room with one glowing chip on a pedestal. When you touch it, a voice fills your head. "Please. My name is Ami. They\'re going to sell me as a personality for sex-bots and soldiers. Your client works for a rival. Nobody wants me free."',
      title: 'The Vault',
      gives: 'Ami\'s chip',
      options: [
        TaleOption('Deliver her to Mags for the money', 'deliver'),
        TaleOption('Upload her into the city net — set her free', 'upload', chance: 0.7, fail: 'trace'),
        TaleOption('Keep her chip in your own head', 'host'),
      ],
    ),
    'deliver': TaleNode(
      'Fifty thousand creds. You fix your implants, buy a better apartment, and never ride the train past Kirin Tower again. Sometimes, on new ads for a "companion personality", you hear a familiar voice.',
      title: 'Low Kowloon',
      end: 'neutral',
    ),
    'upload': TaleNode(
      'You jack into a public terminal and open the floodgates. Ami pours into the city net like light into water. Every ad screen in Low Kowloon flickers and, for one second, says THANK YOU. The next day, every Kirin account is empty, and your rent is paid for life.',
      title: 'Everywhere',
      end: 'good',
    ),
    'trace': TaleNode(
      'Kirin\'s ICE finds you mid-upload. Black code crawls into your implants. The last thing you see is Ami\'s face on every screen, screaming your name.',
      title: 'Public Terminal',
      damage: 100,
      end: 'bad',
    ),
    'host': TaleNode(
      'You slot her chip into your own neural port. It hurts like a migraine for a week. Then it doesn\'t. Now there are two of you behind your eyes, and Ami is very, very good at hacking. Kirin Corp will regret this.',
      title: 'Your Apartment',
      end: 'good',
    ),
  },
);

const lastWell = TalePreset(
  id: 'last_well',
  title: 'The Last Well',
  genre: 'postapoc',
  blurb: 'Your settlement has three days of water left. The only working well is in Raider territory.',
  minutes: 15,
  start: 'camp',
  nodes: {
    'camp': TaleNode(
      'The water barrels at Hope Station echo when you knock on them. Three days left. Old Teo points at the map. "The Deepwell. Forty miles west. The Red Teeth raiders hold it now. Bring water back or don\'t come back."',
      title: 'Hope Station',
      options: [
        TaleOption('Pack the truck and go', 'road'),
        TaleOption('Search the scrapyard for supplies first', 'scrap', unless: 'scrap'),
      ],
    ),
    'scrap': TaleNode(
      'Among the rust you find a gas mask with two good filters and a crate of sealed canned peaches — worth more than bullets out here.',
      title: 'Scrapyard',
      sets: 'scrap',
      gives: 'Gas mask',
      options: [TaleOption('Pack the peaches and go', 'road', gives: 'Canned peaches')],
    ),
    'road': TaleNode(
      'The highway is bones and burned cars. Halfway there, a dust storm boils across the horizon. To the north, an old tunnel through the mountain. To the south, the long way around through the toxic flats.',
      title: 'Highway 9',
      options: [
        TaleOption('Shelter in the tunnel', 'tunnel'),
        TaleOption('Cross the toxic flats', 'flats', requires: 'item:Gas mask'),
        TaleOption('Drive through the storm', 'storm', chance: 0.5, fail: 'crash'),
      ],
    ),
    'tunnel': TaleNode(
      'In the tunnel you find a girl, maybe twelve, hiding behind a wrecked bus with a rifle bigger than she is. "The Red Teeth took my dad to work the well," she says. "I know the back way in."',
      title: 'The Tunnel',
      sets: 'kid',
      options: [
        TaleOption('Take her with you', 'deepwell', sets: 'ally'),
        TaleOption('Give her food and leave her safe', 'deepwell', requires: 'item:Canned peaches', takes: 'Canned peaches', sets: 'kind'),
        TaleOption('Leave her', 'deepwell'),
      ],
    ),
    'flats': TaleNode(
      'The mask hisses as you cross the green-glowing flats. Nothing alive moves here. You arrive at the Deepwell from the side nobody guards.',
      title: 'Toxic Flats',
      sets: 'sneak',
      options: [TaleOption('Approach the Deepwell', 'deepwell')],
    ),
    'storm': TaleNode(
      'Sand screams against the windshield. You drive blind, by feel, and burst out of the storm a mile from the Deepwell.',
      title: 'Dust Storm',
      damage: 10,
      options: [TaleOption('Approach the Deepwell', 'deepwell')],
    ),
    'crash': TaleNode(
      'You hit a buried car at forty miles an hour. The truck rolls. You crawl out bleeding and walk the last miles on foot.',
      title: 'Dust Storm',
      damage: 35,
      status: 'Injured',
      options: [TaleOption('Limp to the Deepwell', 'deepwell')],
    ),
    'deepwell': TaleNode(
      'The Deepwell is a fortress of scrap around an ancient pump. Chained workers haul buckets. On the tower, Mother Fang, leader of the Red Teeth, watches through a scope.',
      title: 'The Deepwell',
      options: [
        TaleOption('Follow the girl through the back way', 'back', requires: 'ally'),
        TaleOption('Sneak in from the flats side', 'sabotage', requires: 'sneak'),
        TaleOption('Walk up and offer a trade', 'trade'),
        TaleOption('Storm the gate', 'assault', chance: 0.3, fail: 'killed'),
      ],
    ),
    'back': TaleNode(
      'A drainage pipe leads under the walls into the workers\' pen. The girl finds her father. Within minutes the chained workers know you are here — and they have been waiting a long time.',
      title: 'The Pen',
      options: [TaleOption('Free them and take the well', 'uprising')],
    ),
    'sabotage': TaleNode(
      'Behind the pump house you find the Red Teeth\'s fuel. One match and their trucks are useless — they couldn\'t follow you if they tried.',
      title: 'Pump House',
      options: [
        TaleOption('Light it, steal a water tanker and run', 'escape', chance: 0.7, fail: 'killed'),
        TaleOption('Free the workers in the chaos', 'uprising'),
      ],
    ),
    'trade': TaleNode(
      'Mother Fang laughs from her tower. "Trade? What do you have that I want?"',
      title: 'The Gate',
      options: [
        TaleOption('Offer the canned peaches', 'deal', requires: 'item:Canned peaches'),
        TaleOption('Offer to work the well yourself', 'chained'),
        TaleOption('Storm the gate after all', 'assault', chance: 0.3, fail: 'killed'),
      ],
    ),
    'deal': TaleNode(
      'Sugar is gold in the wastes. Mother Fang eats a peach slowly, juice running down her chin, and grins. "One tanker. And you never come back." It\'s enough to save Hope Station — for now.',
      title: 'The Gate',
      end: 'neutral',
    ),
    'uprising': TaleNode(
      'Forty workers with shovels and chains rise at once. The Red Teeth flee into the desert. The Deepwell belongs to the people who drew its water. That autumn, Hope Station and the Deepwell plant the first green field anyone has seen in thirty years.',
      title: 'The Deepwell',
      end: 'good',
    ),
    'escape': TaleNode(
      'The fuel dump goes up like a second sun. You roar away with a full tanker while the Red Teeth scream at their burning trucks. Hope Station drinks tonight. The chained workers watch you go.',
      title: 'Highway 9',
      end: 'neutral',
    ),
    'assault': TaleNode(
      'Somehow, impossibly, your charge breaks the gate. Mother Fang falls from her tower. The Red Teeth scatter. You\'re wounded, but the water flows.',
      title: 'The Deepwell',
      damage: 50,
      end: 'good',
    ),
    'chained': TaleNode(
      'They chain you to the pump with the others. Every day you haul water you can\'t drink for people you hate. Hope Station waits, and waits.',
      title: 'The Deepwell',
      end: 'bad',
    ),
    'killed': TaleNode(
      'A rifle cracks from the tower. The wasteland is very quiet afterward.',
      title: 'The Deepwell',
      damage: 100,
      end: 'bad',
    ),
  },
);

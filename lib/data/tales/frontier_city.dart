import 'tale_format.dart';

const redMesa = TalePreset(
  id: 'red_mesa',
  title: 'Showdown at Red Mesa',
  genre: 'western',
  blurb: 'Your brother owes the Calloway gang two thousand dollars. They\'re riding in at noon to collect.',
  minutes: 15,
  start: 'town',
  nodes: {
    'town': TaleNode(
      'Red Mesa bakes under a white sun. Your brother Eli sits on the saloon steps with a black eye and an empty holster. "They\'ll be here at noon," he says. "Calloway and four men. I\'m sorry."\n\nYou have three hours.',
      title: 'Main Street',
      options: [
        TaleOption('Visit the sheriff', 'sheriff', unless: 'sheriff'),
        TaleOption('Ask around the saloon', 'saloon', unless: 'saloon'),
        TaleOption('Ride out to the gold claim', 'claim', unless: 'claim'),
        TaleOption('Wait for noon', 'noon'),
      ],
    ),
    'sheriff': TaleNode(
      'Sheriff Dunn is packing his saddlebags. "Calloway pays better than the county," he says without shame. But on his way out he drops a box of cartridges on the desk. "Didn\'t see me leave these."',
      title: 'Sheriff\'s Office',
      sets: 'sheriff',
      gives: 'Cartridges',
      options: [
        TaleOption('Back to Main Street', 'town'),
      ],
    ),
    'saloon': TaleNode(
      'Rosa, who runs the saloon, polishes a glass. "Calloway\'s got a weakness," she says. "Vanity. Called a man out for a duel once just because he laughed at his hat. Never misses a chance to show off." She slides a whiskey toward you. "On the house. For courage."',
      title: 'The Lucky Spur',
      sets: 'saloon',
      gives: 'Whiskey',
      options: [
        TaleOption('Ask Rosa to stand with you', 'rosa', unless: 'rosa'),
        TaleOption('Back to Main Street', 'town'),
      ],
    ),
    'rosa': TaleNode(
      'Rosa laughs, then stops laughing. She lifts a double-barreled shotgun from under the bar. "I\'ll be at the upstairs window. Make it worth it."',
      title: 'The Lucky Spur',
      sets: 'rosa',
      options: [TaleOption('Back to Main Street', 'town')],
    ),
    'claim': TaleNode(
      'Out at the creek, Eli\'s gold claim is just a hole in the hill. But in the dirt you find the truth: the claim deed, signed by Calloway himself, selling the land to Eli fair and square. The debt is a lie.',
      title: 'The Claim',
      sets: 'claim',
      gives: 'Claim deed',
      options: [
        TaleOption('Ride back to town', 'town'),
      ],
    ),
    'noon': TaleNode(
      'At noon five riders come down Main Street in a cloud of dust. Silas Calloway, silver spurs and a white hat, stops ten paces away. "Two thousand dollars," he says, "or I take it out of your brother."',
      title: 'High Noon',
      options: [
        TaleOption('Show the deed to the whole town', 'deed', requires: 'item:Claim deed'),
        TaleOption('Mock his hat and challenge him to a duel', 'duel', requires: 'saloon'),
        TaleOption('Draw on all five of them', 'gunfight', chance: 0.35, fail: 'shot'),
        TaleOption('Offer him everything you own', 'pay'),
      ],
    ),
    'deed': TaleNode(
      'You hold the deed high. "Calloway sold this claim fair. There\'s no debt — just a thief in a clean hat." Doors open along Main Street. Townsfolk step out, one by one, holding rifles. Calloway\'s men look at each other, then at him.',
      title: 'High Noon',
      options: [
        TaleOption('Tell his men to ride away', 'disband'),
        TaleOption('Challenge Calloway anyway', 'duel'),
      ],
    ),
    'disband': TaleNode(
      'One by one his men turn their horses. Calloway is left alone in the street with a whole town watching. He tips his hat, very carefully, and rides out. Red Mesa elects you sheriff by Sunday.',
      title: 'Red Mesa',
      end: 'good',
    ),
    'duel': TaleNode(
      'Calloway\'s face goes red. "Nobody laughs at the hat." His men step back to give him room — he wants an audience. Ten paces. The town holds its breath.',
      title: 'The Duel',
      options: [
        TaleOption('Load fresh cartridges and draw', 'win', requires: 'item:Cartridges'),
        TaleOption('Take a slug of whiskey and draw', 'draw', requires: 'item:Whiskey', takes: 'Whiskey', chance: 0.6, fail: 'shot'),
        TaleOption('Draw', 'draw', chance: 0.5, fail: 'shot'),
      ],
    ),
    'win': TaleNode(
      'Fresh powder, true aim. Your shot takes the silver pistol clean out of his hand. His men look at the dust, at you, and ride. Calloway walks out of Red Mesa on foot, hatless.',
      title: 'Main Street',
      end: 'good',
    ),
    'draw': TaleNode(
      'Two shots, one echo. Calloway\'s bullet tugs your sleeve. Yours does not miss. The white hat rolls in the dust, and his men have no reason left to stay.',
      title: 'Main Street',
      end: 'good',
    ),
    'gunfight': TaleNode(
      'Lead flies. You dive behind a water trough and empty both cylinders. When the smoke clears, three men are down and two are riding hard for the hills — Calloway among them. You\'re bleeding, but Eli is safe.',
      title: 'Main Street',
      damage: 40,
      end: 'neutral',
    ),
    'shot': TaleNode(
      'You\'re fast. He\'s faster. The sky is very blue as you lie in the street, and the last thing you hear is Eli shouting your name.',
      title: 'Main Street',
      damage: 100,
      end: 'bad',
    ),
    'pay': TaleNode(
      'You hand over your horse, your savings and your father\'s watch. Calloway smiles and rides off. Eli lives. You walk home, poorer and wiser, and swear you\'ll never let a lie like that win again.',
      title: 'Main Street',
      end: 'neutral',
    ),
  },
);

const rainLedger = TalePreset(
  id: 'rain_ledger',
  title: 'The Rain-Soaked Ledger',
  genre: 'noir',
  blurb: 'A banker is dead in his office, the window open, the rain coming in. Everyone has an alibi but the rain.',
  minutes: 15,
  start: 'office',
  nodes: {
    'office': TaleNode(
      'Rain hammers the city like it owes it money. Your office smells of cold coffee and old regrets. The woman in your doorway wears a black veil and a diamond ring. "My husband, Arthur Vance, fell from his office window last night. The police say suicide. I say murder. I\'ll pay double."',
      title: 'Your Office',
      options: [
        TaleOption('Take the case', 'bank'),
        TaleOption('Ask why she thinks it was murder', 'why', unless: 'why'),
      ],
    ),
    'why': TaleNode(
      '"Arthur kept a ledger," she says. "Every bribe, every name in this city. It\'s missing." She lights a cigarette with a hand that does not shake at all.',
      title: 'Your Office',
      sets: 'why',
      options: [TaleOption('Take the case', 'bank')],
    ),
    'bank': TaleNode(
      'Vance & Sons Bank, eighth floor. The window is still open. Rain has soaked the carpet. Three people were in the building that night: Clara the secretary, Moretti the night guard, and Vance\'s partner, Mr. Hale.',
      title: 'The Bank',
      options: [
        TaleOption('Search the office', 'search', unless: 'searched'),
        TaleOption('Question Clara', 'clara', unless: 'clara'),
        TaleOption('Question Moretti', 'moretti', unless: 'moretti'),
        TaleOption('Question Mr. Hale', 'hale', unless: 'hale'),
        TaleOption('Make your accusation', 'accuse'),
      ],
    ),
    'search': TaleNode(
      'Under the soaked carpet near the window, you find a dry rectangle — something sat here after the rain started. A heavy book. And on the windowsill, a smear of lipstick, deep red.',
      title: 'Vance\'s Office',
      sets: 'searched',
      gives: 'Lipstick smear',
      options: [TaleOption('Back to the hallway', 'bank')],
    ),
    'clara': TaleNode(
      'Clara has been crying. "Mr. Vance was kind. He was going to the district attorney tomorrow — with the ledger." She hesitates. "Mrs. Vance came by at nine. She left at ten. I heard them shouting."',
      title: 'Front Desk',
      sets: 'clara',
      options: [TaleOption('Back to the hallway', 'bank')],
    ),
    'moretti': TaleNode(
      'The guard sweats through his collar. Money changes hands, then his story changes too: "Mr. Hale left at ten-thirty with a briefcase. Heavy. Real heavy. Told me I never saw him."',
      title: 'Guard Post',
      sets: 'moretti',
      options: [TaleOption('Back to the hallway', 'bank')],
    ),
    'hale': TaleNode(
      'Hale is all teeth and tailoring. "Arthur was unwell. Tragic." On his desk, half under a newspaper, you spot it: a leather ledger, the edges still damp.',
      title: 'Hale\'s Office',
      sets: 'hale',
      options: [
        TaleOption('Snatch the ledger and run', 'grab', chance: 0.6, fail: 'beaten'),
        TaleOption('Pretend you didn\'t see it', 'bank'),
      ],
    ),
    'grab': TaleNode(
      'You grab the ledger and take the stairs three at a time. In a doorway out of the rain, you read it: bribes, names, dates. Hale\'s name is on every page. So is Mrs. Vance\'s — she was in on it.',
      title: 'The Stairwell',
      gives: 'Ledger',
      options: [TaleOption('Go back and confront them', 'accuse')],
    ),
    'beaten': TaleNode(
      'Hale\'s hired muscle is faster than he looks. You wake in an alley with a split lip, the rain washing the blood off. No ledger. But you know where it is.',
      title: 'An Alley',
      damage: 30,
      status: 'Bruised',
      options: [TaleOption('Go back to the bank', 'bank')],
    ),
    'accuse': TaleNode(
      'You gather them in Vance\'s office, rain blowing through the window. Mrs. Vance arrives in her veil. "Well, detective?"',
      title: 'Vance\'s Office',
      options: [
        TaleOption('Hale and Mrs. Vance did it together', 'both', requires: 'item:Ledger'),
        TaleOption('Mrs. Vance did it — the lipstick proves it', 'widow', requires: 'item:Lipstick smear'),
        TaleOption('It was Hale', 'hale_only', requires: 'moretti'),
        TaleOption('It really was suicide', 'suicide'),
      ],
    ),
    'both': TaleNode(
      'You drop the ledger on the desk. "Arthur was taking this to the DA. His wife held him by the window while his partner took the book." Mrs. Vance laughs once and lifts her veil. "You\'ll never prove it." The police lieutenant in the doorway says: "He just did." Rain never sounded so sweet.',
      title: 'Case Closed',
      end: 'good',
    ),
    'widow': TaleNode(
      'Mrs. Vance goes pale, then cold. She\'s arrested, but Hale walks free with the ledger and half the city in his pocket. You get paid. You don\'t feel paid.',
      title: 'Half the Truth',
      end: 'neutral',
    ),
    'hale_only': TaleNode(
      'Hale is cuffed. Mrs. Vance squeezes your hand with gratitude and pays double. A week later you read that she has taken over the bank — and the ledger has vanished again. You were never really working for the truth.',
      title: 'Played',
      end: 'neutral',
    ),
    'suicide': TaleNode(
      'You close the case. Mrs. Vance pays you, smiling under her veil. A month later the DA who was waiting for Arthur\'s ledger is found at the bottom of a window too.',
      title: 'Rain',
      end: 'bad',
    ),
  },
);

import 'tale_format.dart';
import 'extended_chapters.dart';

const silentShip = TalePreset(
  id: 'silent_ship',
  title: 'The Silent Ship',
  genre: 'scifi',
  blurb: 'A freighter has been drifting for nine years. Its distress beacon switched on yesterday.',
  minutes: 30,
  start: 'dock',
  nodes: {
    ...shipChapter,
    'dock': TaleNode(
      'Your salvage tug kisses the hull of the Meridian with a soft clang. Nine years adrift, every light dead, and yet the distress beacon began transmitting yesterday — your name, repeated, in your own voice.\n\nThe airlock wheel turns too easily. As if someone oiled it.',
      title: 'Docking Ring',
      options: [
        TaleOption('Cycle the airlock and go in', 'corridor'),
        TaleOption('Scan the ship from the tug first', 'scan', unless: 'scanned'),
        TaleOption('Call it in to the salvage guild', 'guild', unless: 'called'),
      ],
    ),
    'scan': TaleNode(
      'The scanner paints the Meridian in ghost-green lines. Life support: off. Reactor: cold. And one heat signature, thirty-seven degrees, standing perfectly still on the bridge.',
      title: 'Docking Ring',
      sets: 'scanned',
      options: [
        TaleOption('Go in anyway', 'corridor'),
        TaleOption('Call it in to the salvage guild', 'guild', unless: 'called'),
      ],
    ),
    'guild': TaleNode(
      'Static. Then the guild operator: "Meridian? Copy, Tug Seven. Wait — your transponder says you\'re already aboard her. Have been for six hours." The line clicks dead.',
      title: 'Docking Ring',
      sets: 'called',
      status: 'Uneasy',
      options: [
        TaleOption('Go in. You need to know.', 'corridor'),
        TaleOption('Undock and burn for home', 'flee'),
      ],
    ),
    'flee': TaleNode(
      'You punch the thrusters and the Meridian shrinks behind you. Three days later you dock at Ceres Station. The harbor master frowns at her screen. "Tug Seven? You logged in this morning. You\'re in the bar right now." Through the glass you see yourself, raising a drink.',
      title: 'Ceres Station',
      end: 'bad',
    ),
    'corridor': TaleNode(
      'Frost furs the walls. Your helmet lamp catches footprints in the frost — boot prints, your size, your tread pattern, leading deeper. To the left, the engineering hatch. Ahead, the long spine corridor to the bridge.',
      title: 'Spine Corridor',
      options: [
        TaleOption('Follow the footprints to the bridge', 'signal_lock'),
        TaleOption('Detour through engineering', 'engineering', unless: 'engine_done'),
        TaleOption('Check the crew quarters', 'quarters', unless: 'quarters_done'),
      ],
    ),
    'quarters': TaleNode(
      'Twelve bunks, twelve frozen crew still strapped in, peaceful as sleepers. Taped above one bunk is a photo of your tug, Tug Seven, docked to this ship. The photo is dated nine years ago.\n\nIn the captain\'s locker: a cutting torch and a handwritten note. "It copies what it finds. Don\'t let it find the reactor."',
      title: 'Crew Quarters',
      sets: 'quarters_done',
      gives: 'Cutting torch',
      options: [
        TaleOption('Go to engineering', 'engineering', unless: 'engine_done'),
        TaleOption('Head for the bridge', 'signal_lock'),
      ],
    ),
    'engineering': TaleNode(
      'The reactor is cold but intact. A manual restart lever glows faintly, and next to it a scuttle panel under a cracked glass cover: SELF-DESTRUCT, 5 MINUTE DELAY.',
      title: 'Engineering',
      sets: 'engine_done',
      options: [
        TaleOption('Restart the reactor', 'reactor', chance: 0.6, fail: 'burned'),
        TaleOption('Prime the self-destruct (don\'t start it yet)', 'corridor2', sets: 'primed'),
        TaleOption('Leave it alone', 'corridor2'),
      ],
    ),
    'burned': TaleNode(
      'The lever kicks back and a jet of coolant flash-freezes across your arm. Your suit seals the breach with a hiss, but the cold bites deep. The lights stutter on anyway — dim, emergency red.',
      title: 'Engineering',
      damage: 25,
      sets: 'power',
      status: 'Suit breached',
      options: [TaleOption('Stagger on to the bridge', 'signal_lock')],
    ),
    'reactor': TaleNode(
      'The reactor coughs, then hums. Lights flood the ship. Somewhere far forward, something screams — not in pain. In delight.',
      title: 'Engineering',
      sets: 'power',
      options: [TaleOption('Run to the bridge', 'signal_lock')],
    ),
    'corridor2': TaleNode(
      'You leave engineering. The footprints in the frost have changed: now they come back toward you, and stop right where you stand.',
      title: 'Spine Corridor',
      status: 'Being watched',
      options: [
        TaleOption('Go to the bridge', 'signal_lock'),
        TaleOption('Check the crew quarters', 'quarters', unless: 'quarters_done'),
      ],
    ),
    'bridge': TaleNode(
      'The bridge door opens. In the captain\'s chair sits you — same face, same scar, same suit, without a helmet, breathing vacuum like air. It smiles with your smile.\n\n"Took you long enough," it says in your voice. "Nine years I\'ve been practising. Now I just need your ship."',
      title: 'Bridge',
      options: [
        TaleOption('Cut it apart with the torch', 'torch_fight', requires: 'item:Cutting torch'),
        TaleOption('Start the self-destruct and run', 'boom', requires: 'primed'),
        TaleOption('Lock it in the bridge and run for the tug', 'run', chance: 0.5, fail: 'caught'),
        TaleOption('Talk to it', 'talk'),
      ],
    ),
    'talk': TaleNode(
      '"Why me?" you ask. It tilts its head. "Your tug was the first thing to come close in nine years. I copied the sound of you from the radio. I copied your face from the photo. I am lonely, salvager. Take me with you. I will be you, and you can rest."',
      title: 'Bridge',
      options: [
        TaleOption('Refuse — and reach for the torch', 'torch_fight', requires: 'item:Cutting torch'),
        TaleOption('Offer it the ship instead of yours', 'deal'),
        TaleOption('Run', 'run', chance: 0.5, fail: 'caught'),
      ],
    ),
    'deal': TaleNode(
      'You restart the Meridian\'s nav computer and hand it the controls. "It\'s yours. Go somewhere far." The copy weeps — your tears, your face — and the Meridian burns away toward the outer dark as you watch from your tug. Sometimes, late at night, you get a postcard in your own handwriting.',
      title: 'Open Space',
      end: 'good',
    ),
    'torch_fight': TaleNode(
      'The torch roars blue. The copy screams and comes apart like wet paper — and under the skin there is only frost, shaped like a person. It melts across the deck into nothing. The beacon goes quiet. You salvage the Meridian and never, ever sleep with the lights off again.',
      title: 'Bridge',
      end: 'good',
    ),
    'boom': TaleNode(
      'You slam the button. FIVE MINUTES. You run. Behind you the copy sprints, faster than you, laughing your laugh — and you make the airlock by a hair. From the tug you watch the Meridian bloom into a silent white flower. Your transponder blinks once, twice, then shows only one of you.',
      title: 'Open Space',
      end: 'good',
    ),
    'run': TaleNode(
      'You slap the door controls and the bridge seals. You run down the spine, footsteps echoing, into the airlock and away. The Meridian drifts on. Its beacon still calls your name. You stop listening.',
      title: 'Open Space',
      end: 'neutral',
    ),
    'caught': TaleNode(
      'The door jams halfway. A cold hand — your hand — closes on your shoulder. "Shh," it says, kindly. "I\'ll take good care of the tug."\n\nThe guild logs show Tug Seven returning to Ceres on schedule. Its pilot seems happier than ever.',
      title: 'Bridge',
      damage: 100,
      end: 'bad',
    ),
  },
);

const hollowLane = TalePreset(
  id: 'hollow_lane',
  title: 'The House on Hollow Lane',
  genre: 'horror',
  blurb: 'You inherited a house from a grandmother you never met. The neighbors will not look at it.',
  minutes: 30,
  start: 'arrive',
  nodes: {
    ...houseChapter,
    'arrive': TaleNode(
      'The house on Hollow Lane leans like it is listening. The estate lawyer handed you the keys and refused to drive past the gate. A note is pinned to the front door in shaky handwriting: "Don\'t answer the knocking after midnight. — Gran"',
      title: 'Hollow Lane',
      options: [
        TaleOption('Go inside', 'hall'),
        TaleOption('Walk around the house first', 'garden', unless: 'garden'),
      ],
    ),
    'garden': TaleNode(
      'Behind the house is a garden of dead roses and a small stone with no name, freshly weeded. Someone tends it. In the dirt beside it you find an old brass key.',
      title: 'Garden',
      sets: 'garden',
      gives: 'Brass key',
      options: [TaleOption('Go inside', 'hall')],
    ),
    'hall': TaleNode(
      'Dust sheets over every chair. A grandfather clock stopped at 11:59. On the wall, a row of family portraits — and in every one, the eyes have been scratched out except the last, which is a portrait of you, painted when you were a child. You have never been here.',
      title: 'Front Hall',
      status: 'Uneasy',
      options: [
        TaleOption('Explore the study', 'study', unless: 'study'),
        TaleOption('Go up to the bedroom', 'bedroom'),
        TaleOption('Open the locked cellar door', 'cellar', requires: 'item:Brass key'),
      ],
    ),
    'study': TaleNode(
      'Your grandmother\'s diary lies open. The last entry: "It wants to come in. It knocks every night at midnight and it uses voices it has stolen. If it is invited it can never be sent away. The salt line holds it. Keep the salt line whole."\n\nA jar of coarse salt sits on the desk.',
      title: 'Study',
      sets: 'study',
      gives: 'Salt',
      options: [
        TaleOption('Go up to the bedroom', 'bedroom'),
        TaleOption('Open the cellar', 'cellar', requires: 'item:Brass key'),
      ],
    ),
    'cellar': TaleNode(
      'The cellar stinks of earth. Chalk circles cover the floor and in the middle sits a cradle, rocking gently by itself. Carved into the wall, over and over: HER NAME IS NOT GRAN.',
      title: 'Cellar',
      damage: 15,
      sets: 'cellar',
      status: 'Shaken',
      options: [
        TaleOption('Smash the cradle', 'smash'),
        TaleOption('Back away upstairs', 'bedroom'),
      ],
    ),
    'smash': TaleNode(
      'The cradle splinters. Every clock in the house starts ticking at once. Upstairs, the grandfather clock strikes midnight — though it is barely evening.',
      title: 'Cellar',
      sets: 'broken',
      options: [TaleOption('Run upstairs', 'clock_wakes')],
    ),
    'bedroom': TaleNode(
      'You make the bed in your grandmother\'s room and lie down fully clothed. You do not remember falling asleep.\n\nYou wake to the clock striking midnight.',
      title: 'Bedroom',
      options: [TaleOption('Listen', 'clock_wakes')],
    ),
    'midnight': TaleNode(
      'Knock. Knock. Knock.\n\nFrom the front door, a voice you know: your mother\'s. "Sweetheart? It\'s cold out here. Let me in." Your mother has been dead for six years.',
      title: 'Midnight',
      damage: 10,
      options: [
        TaleOption('Pour a salt line across the doorway', 'salt', requires: 'item:Salt'),
        TaleOption('Answer: "Who are you really?"', 'ask'),
        TaleOption('Open the door', 'open'),
        TaleOption('Hide under the bed until dawn', 'hide', chance: 0.5, fail: 'found'),
      ],
    ),
    'ask': TaleNode(
      'Silence. Then, in your own voice: "I am the one who was here before her. Before you. Let me in and I will tell you everything about your family. Everything they hid." The door handle begins to turn.',
      title: 'Midnight',
      damage: 10,
      options: [
        TaleOption('Pour the salt line', 'salt', requires: 'item:Salt'),
        TaleOption('Open the door', 'open'),
        TaleOption('Run out the back', 'run', chance: 0.6, fail: 'found'),
      ],
    ),
    'salt': TaleNode(
      'The salt hisses where it touches the threshold. The thing outside screams in a hundred stolen voices, then goes quiet. At dawn you find the garden stone has been dug up — and under it, a small box with your grandmother\'s real name and a lock of your hair. You burn the box. The knocking never comes again.',
      title: 'Dawn',
      end: 'good',
    ),
    'open': TaleNode(
      'The door swings open on an empty porch. Behind you, in the hall, something says "Thank you" in your mother\'s voice, and all the portraits turn to face you.\n\nThe neighbors still don\'t look at the house. Sometimes they hear two people laughing inside.',
      title: 'Midnight',
      damage: 100,
      end: 'bad',
    ),
    'hide': TaleNode(
      'You hold your breath under the bed while footsteps circle the room until the sky goes grey. At dawn you leave the keys in the mailbox and never come back. The house is still for sale.',
      title: 'Dawn',
      end: 'neutral',
    ),
    'run': TaleNode(
      'You sprint through the kitchen and out the back door into the dead roses. You don\'t stop until you reach the main road. When you look back, every window in the house is lit, and someone in each of them is waving.',
      title: 'Hollow Lane',
      end: 'neutral',
    ),
    'found': TaleNode(
      'A hand closes around your ankle and pulls, gently, the way a mother would tuck a child into bed.',
      title: 'Bedroom',
      damage: 100,
      end: 'bad',
    ),
  },
);

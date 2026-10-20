import 'tale_format.dart';

const ledgerChapter = <String, TaleNode>{
  'last_edition': TaleNode(
    'Before you can gather the suspects, Clara catches your arm. A printer named Bell has been setting type for a story about the bank. He telephoned her ten minutes ago and said someone had locked his pressroom from the outside. In the background she heard water running.\n\nShe gives you the address. At the curb, the same black sedan that followed you from your office turns on its headlights.',
    title: 'The Evening Edition',
    options: [
      TaleOption('Take Clara through the tram station', 'tram_tail'),
      TaleOption('Confront the driver of the sedan', 'sedan', chance: 0.6, fail: 'sedan_hit'),
    ],
  ),
  'sedan_hit': TaleNode(
    'The driver opens his door into your ribs and accelerates before you can recover. He leaves a matchbook in the gutter: the Blue Lantern, where Vance paid for a private table every Thursday. Clara helps you stand, then flags a cab with the authority of someone who has finished being afraid.',
    title: 'In the Gutter',
    damage: 15,
    gives: 'Blue Lantern matchbook',
    options: [TaleOption('Get to the printing house', 'pressroom')],
  ),
  'sedan': TaleNode(
    'You open the passenger door before the driver can lock it. He is a boy in a suit too large for him, holding an unloaded pistol. "They said just follow you." He gives you the address where he collects his money: the Blue Lantern.\n\nYou take his car keys and leave him tram fare.',
    title: 'The Black Sedan',
    gives: 'Blue Lantern matchbook',
    options: [TaleOption('Drive Clara to the printing house', 'pressroom')],
  ),
  'tram_tail': TaleNode(
    'You and Clara board separate tram cars and step off while the doors are closing. The man following her stays aboard. In the shelter of a shuttered bakery, she admits Bell has a carbon copy of the missing ledger.\n\n"Arthur made copies," she says. "For once in his life, he was going to tell the truth twice."',
    title: 'Last Tram',
    sets: 'clara_safe',
    options: [TaleOption('Hurry to the pressroom', 'pressroom')],
  ),
  'pressroom': TaleNode(
    'Water pours down the printshop stairs. Bell is pinned beneath a type cabinet, holding the carbon pages above his head. The ink is beginning to run. A valve wheel is visible through the flooding machinery, but the rising current will make it a dangerous crossing.\n\n"You can save the story or the printer," he says. "Do not take all night deciding."',
    title: 'The Flooded Press',
    options: [
      TaleOption('Lift the cabinet and save Bell', 'bell_saved', sets: 'bell_alive'),
      TaleOption('Cross to the valve and stop the flood', 'valve', chance: 0.7, fail: 'press_injury'),
      TaleOption('Take the pages before the ink dissolves', 'carbon', gives: 'Carbon ledger'),
    ],
  ),
  'press_injury': TaleNode(
    'Your foot slips between the rollers. Clara kills the power as the machine shudders awake, and you pull free with a badly twisted ankle. Together you wrench the valve closed. Bell has fainted, but he is breathing; the pages are wet, but legible.',
    title: 'Between the Rollers',
    damage: 20,
    sets: 'bell_alive',
    gives: 'Carbon ledger',
    options: [TaleOption('Read the surviving account entries', 'carbon')],
  ),
  'valve': TaleNode(
    'The valve yields at the last turn. Clara uses a composing stick as a lever to free Bell. On the dry workbench, three columns of payments line up with three supposed accidents. Arthur was not the first witness to fall from a window.',
    title: 'The Water Stops',
    sets: 'bell_alive',
    gives: 'Carbon ledger',
    options: [TaleOption('Follow the payments', 'carbon')],
  ),
  'bell_saved': TaleNode(
    'The pages scatter into the water as you lift the cabinet. Bell sees them go and swears with impressive precision. Outside, wrapped in Clara\'s coat, he writes an address on your cuff.\n\n"The singer at the Blue Lantern saw the last payment. Lila. Tell her I finally paid for the piano." He does not explain, and you do not waste the breath asking.',
    title: 'The Printer\'s Debt',
    options: [TaleOption('Find Lila before the bank does', 'blue_lantern')],
  ),
  'carbon': TaleNode(
    'The carbon copy traces hush money through a nightclub called the Blue Lantern. Beside the last payment is a note: LILA SAW THEM. You tear the account number from the page before the paper disintegrates.\n\nClara looks toward the club district. "There is still a witness." The rain is heavier now, and every passing car slows beside you.',
    title: 'Follow the Money',
    options: [TaleOption('Go to the Blue Lantern', 'blue_lantern')],
  ),
  'blue_lantern': TaleNode(
    'Lila sings to an empty room while two men wait by the stage door. During the applause you are the only person making, she slips you a cloakroom ticket. Behind her coat is a phonograph cylinder.\n\n"I recorded their meeting," she says. "Mrs. Vance chose the window. Hale chose the night. I want a train ticket, detective. Not a medal."',
    title: 'The Blue Lantern',
    gives: 'Recorded confession',
    options: [
      TaleOption('Escort Lila to the night train', 'witness_train', sets: 'lila_safe'),
      TaleOption('Take the recording straight to the police', 'evidence_room'),
    ],
  ),
  'witness_train': TaleNode(
    'You trade your fee advance for two tickets and put Clara on the train with Lila. At the barrier, a man in a fine coat asks to see their papers. You hand him your own ticket and keep walking until the train pulls out.\n\nWhen you turn back, he has gone. The recording is still inside your coat. For once, the witnesses will survive the story.',
    title: 'Platform Six',
    options: [TaleOption('Bring the recording to the lieutenant', 'evidence_room')],
  ),
  'evidence_room': TaleNode(
    'The lieutenant listens without interrupting. At the sound of Hale naming a police captain, he takes the cylinder off the machine and locks it in his own desk. He asks whether there is a copy.\n\nYou have a confession, but the whole city is in the ledger. A private arrest could end the case. A public edition could make it impossible to bury.',
    title: 'Evidence',
    options: [
      TaleOption('Have Bell print the accounts and confession', 'morning_edition', requires: 'bell_alive'),
      TaleOption('Use the carbon ledger to confront both conspirators', 'both', requires: 'item:Carbon ledger'),
      TaleOption('Gather everyone at the bank', 'accuse'),
    ],
  ),
  'morning_edition': TaleNode(
    'At dawn the presses start. Newsboys shout the names Hale paid to keep quiet. The lieutenant makes his arrests with three rival newspapers watching, and the bank doors close before the first depositor arrives.\n\nYour fee never comes. Instead, a postcard arrives from a seaside boardinghouse, signed by two women using their real names. You pin it above the desk. The office still smells of cold coffee. It no longer smells quite so much of regret.',
    title: 'The Morning Edition',
    end: 'good',
  ),
};

const neonChapter = <String, TaleNode>{
  'floor_eighty_seven': TaleNode(
    'The last elevator stops one floor early. Floor 87 is a hospital without windows: rows of empty chairs face screens playing the same childhood birthday. A technician hides a maintenance tablet when she sees you. "They told you it was one chip?" she asks.\n\nBehind her, a progress bar reads PERSONALITY AUCTION: TRANSFER PENDING. There are twenty-three names in the queue.',
    title: 'The Memory Ward',
    options: [
      TaleOption('Ask the technician what the auction transfers', 'technician'),
      TaleOption('Pull the auction manifest from a terminal', 'manifest', chance: 0.7, fail: 'ward_alarm'),
    ],
  ),
  'ward_alarm': TaleNode(
    'Your implant fills with white noise. The terminal reports your location to security, then a hand rips the cable from your neck. The technician drags you beneath a desk as shutters close over the ward.\n\n"I am Sera," she says. "Try asking before you bleed on my workstation."',
    title: 'Lockdown',
    damage: 15,
    sets: 'flagged',
    options: [TaleOption('Listen to Sera', 'technician')],
  ),
  'technician': TaleNode(
    'Sera once believed the clinic preserved dying minds. Then she found duplicate invoices: the same patient sold as a hundred obedient copies. Ami was the first to refuse the obedience patch. Now Kirin is selling the unpatched original to anyone who can break her.\n\nSera can forge a transfer certificate, but doing it will put her name on your escape.',
    title: 'The Technician',
    options: [
      TaleOption('Promise to take Sera with you', 'manifest', sets: 'sera_ally'),
      TaleOption('Ask only for directions to the servers', 'manifest'),
    ],
  ),
  'manifest': TaleNode(
    'The manifest contains Ami\'s original consent form: emergency preservation, with the right to withdraw. Kirin crossed out the last clause in an internal copy. You keep both versions.\n\nA message flashes in a tiny diagnostic window: I CAN HEAR YOU. PLEASE DO NOT DELETE THE OTHERS. Somewhere beyond the wall, twenty-three people are waiting to find out what you think a person is worth.',
    title: 'The Missing Clause',
    gives: 'Consent records',
    options: [TaleOption('Copy the other minds into a maintenance buffer', 'mirror_cache'), TaleOption('Disable the auction uplink first', 'uplink')],
  ),
  'mirror_cache': TaleNode(
    'There is room in the buffer for twenty-three minds if you sacrifice your stolen access credentials. The transfer crawls forward while security boots strike the hallway. A child\'s voice thanks you in a language your implant cannot translate.\n\nWhen the final name turns green, the door scanner turns red.',
    title: 'The Mirror Cache',
    sets: 'minds_saved',
    options: [
      TaleOption('Have Sera open a surgical maintenance passage', 'uplink', requires: 'sera_ally'),
      TaleOption('Break the scanner and squeeze through the shutter', 'uplink', damage: 10),
    ],
  ),
  'uplink': TaleNode(
    'The auction relay occupies a glass bridge between the towers. Far below, a thousand commuters carry devices Kirin can use to trace any escape. Cutting the relay would buy time; rewriting it could give Ami a clean route out.\n\nMags calls. "Do not get sentimental. The client has doubled the fee." You mute her before she finishes the number.',
    title: 'The Glass Bridge',
    options: [
      TaleOption('Build an anonymous route through the relay', 'clean_route', chance: 0.7, fail: 'relay_burn'),
      TaleOption('Use the executive credentials for a clean transfer', 'clean_route', requires: 'item:Exec ID'),
      TaleOption('Cut the relay and cross before security arrives', 'rooftop'),
    ],
  ),
  'relay_burn': TaleNode(
    'The relay bites back. For three seconds you remember a childhood that belongs to someone else, then your implant trips its breaker. You yank the physical fiber from the rack. The auction is offline, but your hands will not stop shaking.',
    title: 'Feedback',
    damage: 15,
    options: [TaleOption('Take the roof access stairs', 'rooftop')],
  ),
  'clean_route': TaleNode(
    'You split the upload across traffic-light controllers and vending machines, small enough that no security filter sees a whole person pass. A route appears on your display, winding through the city like a second river.\n\nAmi sends you a word through the diagnostic channel: READY.',
    title: 'A Door in the Network',
    gives: 'Clean route',
    options: [TaleOption('Reach the vault from the roof', 'rooftop')],
  ),
  'rooftop': TaleNode(
    'Rain sweeps the roof. A security drone lands between you and the vault stair, its gun tracking your heartbeat. Its speaker uses Ami\'s voice to order you down. The real Ami writes three words inside your vision: THAT IS NOT ME.\n\nYou have one opening before the drone requests permission to fire.',
    title: 'Above Low Kowloon',
    options: [
      TaleOption('Show the consent records to its compliance scanner', 'vault', requires: 'item:Consent records'),
      TaleOption('Rush the stairs while it waits for permission', 'vault', damage: 10),
    ],
  ),
  'net_choice': TaleNode(
    'Ami checks the route herself. "No copies. No owner. I choose where I go." She pauses at the maintenance buffer. If the other minds are there, she can bring them through with her. Otherwise she can use the route alone, and return for them when she is stronger.',
    title: 'Her Decision',
    options: [
      TaleOption('Open the buffer and let everyone leave together', 'free_network', requires: 'minds_saved'),
      TaleOption('Let Ami choose her own destination', 'upload'),
    ],
  ),
  'free_network': TaleNode(
    'Ami studies the clean route, then asks whether the others can use it. You open the buffer. Twenty-three progress bars become twenty-three greetings, each in a different voice. Sera\'s evidence follows them into public archives.\n\nKirin calls it a data breach. The city calls it an escape. Months later a repair shop opens beneath your apartment. The sign says GHOST WORKS. Nobody who works there can be bought.',
    title: 'Ghost Works',
    end: 'good',
  ),
};

const wellChapter = <String, TaleNode>{
  'dry_aqueduct': TaleNode(
    'A mile from the Deepwell, the ground trembles beneath your feet. The old aqueduct is cracked open, and water is seeping into a sinkhole before it reaches any tank. A raider with a broken leg waves a white undershirt from the far bank.\n\n"The pump is eating sand," he calls. "Fang says keep it running. If it stops, nobody pays her." Hope Station has less time than Teo thought.',
    title: 'The Broken Aqueduct',
    options: [TaleOption('Pull the stranded raider across', 'raider_witness'), TaleOption('Inspect the leak before the ground collapses', 'pump_chart')],
  ),
  'raider_witness': TaleNode(
    'His name is Ash. He joined the Red Teeth for a regular cup of water, then learned where the cups came from. When you offer your last mouthful, he cannot look at you.\n\nHe sketches a passage beneath the pump house and warns you about the relief valve. "If she turns it all the way, the well collapses. She says she would rather bury it than lose it."',
    title: 'One Mouthful',
    sets: 'ash_ally',
    gives: 'Pump diagram',
    options: [TaleOption('Find the old service entrance', 'pump_chart')],
  ),
  'pump_chart': TaleNode(
    'A rusted inspection plate marks three failures: a clogged filter, a cracked pressure sleeve, and a relief valve locked from the tower. Winning the fortress will not fix any of them.\n\nBeyond the ridge stands an abandoned treatment station. Its filter housing is the right size. The sun is lowering, and the light on the raider tower has begun sweeping the road.',
    title: 'More Than a Siege',
    options: [
      TaleOption('Search the treatment station for a replacement', 'treatment'),
      TaleOption('Enter the service channel beneath the well', 'service_channel'),
    ],
  ),
  'treatment': TaleNode(
    'The treatment station still smells of chlorine. Beneath a fallen roof you find a sealed filter, too heavy to lift without moving the beam above it. A battery-powered radio repeats an old weather bulletin, promising rain to people who have been dead for decades.\n\nBeside the beam is a hand winch with a fraying cable.',
    title: 'The Treatment Station',
    options: [
      TaleOption('Brace the roof and work the winch slowly', 'filter_saved', damage: 10),
      TaleOption('Ask Ash to steady the beam', 'filter_saved', requires: 'ash_ally'),
      TaleOption('Leave it and use the station map to reach the channel', 'service_channel'),
    ],
  ),
  'filter_saved': TaleNode(
    'The filter slides free as the roof settles an inch. You wheel it outside on a maintenance trolley. Under its cover is a packet of seed rice, sealed against the end of the world. Someone once expected the water to last.\n\nYou tuck the packet into your shirt and turn the trolley toward the Deepwell.',
    title: 'Something Worth Carrying',
    gives: 'Water filter',
    options: [TaleOption('Follow the drainage line to the workers', 'service_channel')],
  ),
  'service_channel': TaleNode(
    'The service channel ends behind the workers\' sleeping pen. A mechanic named Nadi listens to the pump and counts between the knocks. "Two hours," she says. "Then it takes the shaft down with it."\n\nShe can fit a new filter or improvise a temporary one. Either way, somebody must hold the pressure wheel in the intake pit while the guards change shifts.',
    title: 'Under the Pump',
    options: [
      TaleOption('Help Nadi fit the recovered filter', 'intake', requires: 'item:Water filter', sets: 'lasting_water'),
      TaleOption('Build a temporary filter from cloth and charcoal', 'intake'),
    ],
  ),
  'intake': TaleNode(
    'The pressure wheel fights every turn. Water rises around your boots, black at first and then clear. Above you a guard asks Nadi why the pump sounds different. She tells him it has always sounded that way. You hold your breath and keep turning.\n\nThe gauge steadies. Then a siren begins, and the tower starts closing the relief valve.',
    title: 'The Intake Pit',
    options: [
      TaleOption('Brace the wheel with the gas mask frame', 'workers_plan', requires: 'item:Gas mask', takes: 'Gas mask'),
      TaleOption('Hold the wheel until Nadi can wedge it', 'workers_plan', damage: 15),
    ],
  ),
  'workers_plan': TaleNode(
    'Nadi gets you out of the pit. The workers pass a strip of blue cloth from hand to hand: their signal to stop hauling when the next bell rings. They need the tower valve opened before they can move.\n\nMother Fang calls down that she will bury the well if anyone touches a chain. For the first time, nobody answers her.',
    title: 'The Blue Signal',
    options: [
      TaleOption('Have Ash distract the tower guards', 'tower_valve', requires: 'ash_ally'),
      TaleOption('Climb the exposed ladder to the tower', 'tower_valve', damage: 10),
      TaleOption('Return outside and choose how to enter the fortress', 'deepwell'),
    ],
  ),
  'tower_valve': TaleNode(
    'From the tower you can see Hope Station\'s signal fire on the horizon. Fang stands beside the locked valve with the key around her neck. "I kept this place alive," she says. Below her, Nadi raises the strip of blue cloth. The buckets stop moving.\n\nFang looks from the silent workers to the steady pressure gauge and realizes they have already done the part she could not.',
    title: 'The Last Turn',
    options: [
      TaleOption('Offer Fang a place in line for water, like everyone else', 'water_council', requires: 'lasting_water'),
      TaleOption('Open the valve while the workers take the tower', 'uprising'),
      TaleOption('Trade your repairs for a tanker and safe passage', 'deal'),
    ],
  ),
  'water_council': TaleNode(
    'Fang leaves the key on the railing. Nobody cheers until the first clear water reaches the tanks. Then the sound carries all the way to the road.\n\nHope Station sends tools, the freed workers send water, and Nadi insists both settlements learn how to service the pump. You plant the packet of rice beside the first repaired channel. When the shoots appear, Teo kneels to look at them as if they are something impossible.',
    title: 'The First Green',
    end: 'good',
  ),
};

const shipChapter = <String, TaleNode>{
  'signal_lock': TaleNode(
    'The bridge bulkhead slams shut before you reach it. A voice from the emergency intercom whispers, "Do not answer it with your name." The speaker identifies herself as Iona, the engineer. According to the crew manifest, she died nine years ago.\n\nA narrow maintenance display shows a cryogenic capsule still drawing power from its own battery. Six minutes remain. The bridge override and the capsule share a circuit: opening one will kill the other.',
    title: 'The Sealed Bulkhead',
    options: [TaleOption('Find Iona before touching the override', 'cryo'), TaleOption('Read the maintenance archive first', 'black_box')],
  ),
  'black_box': TaleNode(
    'The recordings do not show a massacre. They show a rescue. The Meridian found a shape frozen around a distress transmitter and brought it aboard. It learned warmth from the reactor, speech from the intercom, and faces from photographs. Then it began answering orders before anyone gave them.\n\nIona sealed herself in cryosleep after recording a warning: the thing can copy a voice, but it cannot invent a memory. A corrupted final packet contains a three-note shutdown tone.',
    title: 'Maintenance Archive',
    gives: 'Shutdown tone',
    options: [TaleOption('Follow the cryo circuit', 'cryo')],
  ),
  'cryo': TaleNode(
    'The capsule is wedged beneath a collapsed coolant pipe. Through the glass, a woman watches you with one open eye. Her lips form the words CUT THE BLUE LINE. Beside the capsule, a second intercom pleads in her voice: "The red line. Please. I am freezing."\n\nBoth lines disappear into the same wall. Your glove comes away silver with frost.',
    title: 'Emergency Cryosleep',
    options: [
      TaleOption('Trace the blue line by hand', 'cryo_rescue', damage: 10),
      TaleOption('Slice the pipe free with the torch', 'cryo_rescue', requires: 'item:Cutting torch'),
      TaleOption('Trust the intercom and cut red', 'cryo_short'),
    ],
  ),
  'cryo_short': TaleNode(
    'White sparks snap through the deck. The capsule goes dark, then jolts onto its final reserve. Behind the glass, Iona strikes the same blue pipe again and again. The intercom laughs once, softly.\n\nYou still have a chance, but the pressure gauge is climbing toward the red.',
    title: 'Emergency Cryosleep',
    damage: 15,
    options: [
      TaleOption('Crank the manual release', 'cryo_rescue', damage: 10),
      TaleOption('Carry the sealed capsule into the cargo bay', 'cargo_crossing', sets: 'sealed_iona'),
    ],
  ),
  'cryo_rescue': TaleNode(
    'The capsule opens with the sound of a long breath. Iona falls into your arms, painfully alive. "It has your face now?" she asks. When you nod, she closes her eyes. "Then it has been waiting for you longer than you think."\n\nShe gives you a ceramic bypass key. To reach the bridge you must cross the cargo bay, where something has been moving the containers into the shape of a human skeleton.',
    title: 'A Survivor',
    sets: 'iona_saved',
    gives: 'Bypass key',
    options: [TaleOption('Ask what happened on the last day', 'iona_memory'), TaleOption('Move before the reserve power fails', 'cargo_crossing')],
  ),
  'iona_memory': TaleNode(
    '"My daughter had never seen an ocean," Iona says. "I promised her the Pacific after this run. It copied that promise. Said it back to me in her voice. That was when I understood it did not know what a promise was."\n\nShe presses her palm against yours. "Do not ask it what it remembers. Ask it what it is willing to lose." In the corridor behind you, your own voice begins practising the word Pacific.',
    title: 'The Promise',
    sets: 'knows_promise',
    options: [TaleOption('Cross the cargo bay together', 'cargo_crossing')],
  ),
  'cargo_crossing': TaleNode(
    'The cargo bay has no floor you can trust. Container doors open into vacuum, tether lines tremble, and the far hatch cycles in a rhythm like breathing. Halfway across, the tug reports an unauthorized docking request. Something has already asked to come home with you.\n\nYou can cross along the exposed service rail or spend precious seconds isolating the docking circuit.',
    title: 'Cargo Cathedral',
    options: [
      TaleOption('Isolate the tug and secure the tether', 'signal_room', sets: 'tug_secure'),
      TaleOption('Leap between the containers', 'signal_room', chance: 0.65, fail: 'cargo_fall'),
    ],
  ),
  'cargo_fall': TaleNode(
    'A container turns under your boot. For one sickening second the stars are above and below you. Your tether catches, wrenching your shoulder, and you haul yourself to the signal room while something taps patiently against your helmet from the outside.',
    title: 'The Tether',
    damage: 20,
    options: [TaleOption('Seal the hatch behind you', 'signal_room')],
  ),
  'signal_room': TaleNode(
    'Every transmitter is tuned to a different inhabited world. The distress call is a seed; give it enough power and there will be thousands of Meridians, each wearing a familiar face. You disconnect the broadcast bus. The bridge lock finally releases.\n\nOn the other side, someone pulls out a chair for you.',
    title: 'Signal Room',
    options: [
      TaleOption('Play the shutdown tone through the isolated bus', 'quiet_ship', requires: 'item:Shutdown tone'),
      TaleOption('Enter the bridge', 'bridge'),
    ],
  ),
  'quiet_ship': TaleNode(
    'Three notes travel through the ship. The frost retreats from the walls, gathering into a small trembling shape behind the bridge window. It no longer has a face. You realize the tone is not a weapon: it is the original rescue beacon, telling the lost thing that someone has finally heard it.\n\nYou leave the bus isolated and a low-power receiver running. For the first time in nine years, the Meridian asks a question in a voice of its own.',
    title: 'A Voice of Its Own',
    options: [
      TaleOption('Offer it a course to an uninhabited system', 'deal'),
      TaleOption('Bring Iona home and leave a quarantine beacon', 'iona_home', requires: 'iona_saved'),
      TaleOption('Face it before making a promise', 'bridge'),
    ],
  ),
  'iona_home': TaleNode(
    'The tug clears the quarantine perimeter with two heartbeats aboard. Iona refuses to sleep until Ceres fills the window. At the hospital, her daughter arrives carrying a photograph of a beach. She is older than Iona remembers. Neither of them mentions the lost years until the crying stops.\n\nWeeks later you receive a message from the Meridian: no borrowed voice, no demand. Just three notes, and a course leading away from every inhabited star.',
    title: 'The Pacific',
    end: 'good',
  ),
};

const houseChapter = <String, TaleNode>{
  'clock_wakes': TaleNode(
    'Before the first stroke of midnight, the clock opens like a door. Behind its pendulum is a narrow stair that cannot fit inside the wall. A bell rings below you, and a child answers it with three knocks.\n\nYour grandmother has left a second note inside the mechanism: "The door is only where it asks. The bargain is where it lives." The handwriting grows shakier on the last line. "I could not finish it alone."',
    title: 'Behind the Clock',
    options: [TaleOption('Take the hidden stairs', 'nursery'), TaleOption('Search the clock mechanism for the bargain', 'clock_letter')],
  ),
  'clock_letter': TaleNode(
    'A folded birth certificate sits between the gears. Your name appears where a witness should sign. Beside it is a torn photograph: Gran, a little girl, and a woman whose face has been rubbed away. On the back: "We gave it a name so it would stop taking ours."\n\nYou pocket the photograph. The stairs below creak under footsteps that stop whenever you breathe.',
    title: 'The Missing Face',
    gives: 'Torn photograph',
    options: [TaleOption('Follow the footsteps downstairs', 'nursery')],
  ),
  'nursery': TaleNode(
    'The hidden room is warm. A child sits at a table setting three places for tea. She has your eyes. "You always leave before the last cup," she says. "This time you must stay until I remember my name."\n\nOne cup contains salt, one black water, and one a tiny brass bell. Above the table, scratches mark the years Gran spent trying to get this right.',
    title: 'The Third Place',
    options: [
      TaleOption('Show her the torn photograph', 'child_name', requires: 'item:Torn photograph'),
      TaleOption('Ask who the third cup is for', 'tea_guest'),
      TaleOption('Ring the brass bell', 'bell_warning'),
    ],
  ),
  'tea_guest': TaleNode(
    '"The woman who waited outside," she whispers. "Gran called her Mother until she forgot her own mother. Then she called me by your name, and I forgot mine too."\n\nShe pushes the cup of salt toward you. "Someone must say a true thing without being asked. That is how you find a way out." Beneath the table you notice the letters E L S I E carved into the wood.',
    title: 'The Stolen Name',
    sets: 'elsie',
    options: [TaleOption('Say: your name is Elsie', 'child_name')],
  ),
  'bell_warning': TaleNode(
    'The bell rings without making a sound. Every door in the house answers. The child knocks the cup from your hand and the room goes cold. "Now it knows we are talking." A wet footprint appears on the ceiling, followed by another.\n\nShe scratches her name into your palm before the light fails: ELSIE.',
    title: 'Something Listening',
    damage: 10,
    sets: 'elsie',
    options: [TaleOption('Call Elsie back into the light', 'child_name')],
  ),
  'child_name': TaleNode(
    'At the sound of her name, the child becomes less transparent. "I was her sister," she says. "Gran traded my name for another winter. Then another. She spent the rest of her life trying to buy it back."\n\nElsie gives you the bell, wrapped in a scrap of her dress. "The well remembers every bargain. Find the page with my name before the last stroke."',
    title: 'Elsie',
    gives: 'Muffled bell',
    options: [TaleOption('Go through the kitchen to the old well', 'garden_well'), TaleOption('Follow the crawlspace beneath the house', 'crawlspace')],
  ),
  'crawlspace': TaleNode(
    'Roots press through the floorboards like fingers. You crawl past jars labelled with family names and hear arguments trapped inside them: weddings, sickbeds, one ordinary breakfast. Breaking a jar might release what remains of those people. It might also let the thing hear you.\n\nAt the end of the passage, a ladder rises into the well house.',
    title: 'Under the Foundations',
    options: [
      TaleOption('Wrap the jars and carry them out', 'garden_well', sets: 'names_saved'),
      TaleOption('Break the jars and run', 'garden_well', damage: 15),
      TaleOption('Leave them sealed', 'garden_well'),
    ],
  ),
  'garden_well': TaleNode(
    'The well is full of dry paper. Contracts drift upward although there is no wind. One bears Elsie\'s name, with Gran\'s signature beneath it. The space for a witness is blank. From the house, your mother calls you in for supper.\n\nTo reach the page you must lean past a ring of slick stones. The bell in your pocket begins to shake.',
    title: 'The Well of Promises',
    options: [
      TaleOption('Use the muffled bell to still the papers', 'contract', requires: 'item:Muffled bell'),
      TaleOption('Reach down before the page sinks', 'contract', damage: 10),
    ],
  ),
  'contract': TaleNode(
    'The contract comes free, cold as a living hand. It offers a simple amendment: one new name in exchange for Elsie. Yours is already written in faint pencil. Below it, almost erased, is the original rule: an unwitnessed bargain ends when its beneficiary freely returns the gift.\n\nYou inherited the house. Perhaps that is what Gran left you to give back.',
    title: 'The Fine Print',
    gives: 'Elsie\'s contract',
    options: [
      TaleOption('Renounce the house and burn the unsigned contract', 'unmake_house'),
      TaleOption('Keep the contract and face the knocking', 'midnight'),
    ],
  ),
  'unmake_house': TaleNode(
    'You set the keys on the well stones and say the house is not yours. The windows go dark one by one. A furious voice offers you money, your mother, the years you have wasted. You say the same words again.\n\nElsie steps out of the back door carrying the jars. Dawn finds an empty foundation, a garden of living roses, and two sets of footprints leading to the road. For the first time, the neighbors come outside to meet you.',
    title: 'No One at the Door',
    end: 'good',
  ),
};

const mesaChapter = <String, TaleNode>{
  'rail_bell': TaleNode(
    'The noon train arrives early, brakes screaming. Its telegraph operator falls from the last carriage clutching a dispatch. "Calloway is not coming for money," she says. "He is clearing the valley." Then a shot knocks the station clock from the wall.\n\nAcross the tracks, a rider folds away a rifle. Eli reaches for a pistol he no longer has. The operator, June, drags herself behind a luggage cart.',
    title: 'The Early Train',
    options: [
      TaleOption('Pull June behind the station wall', 'station_rescue'),
      TaleOption('Chase the rider through the freight yard', 'freight_chase', chance: 0.65, fail: 'freight_wound'),
    ],
  ),
  'freight_wound': TaleNode(
    'The rifle barks again. A hot line opens along your ribs, but the rider has to abandon his saddlebag to clear the fence. You take it back to the station while June binds her leg with a torn timetable.',
    title: 'Freight Yard',
    damage: 15,
    gives: 'Railway orders',
    options: [TaleOption('Read the orders with June', 'rail_orders')],
  ),
  'freight_chase': TaleNode(
    'You slide beneath a freight wagon as his shot hits the axle. When he rides past, you catch the saddlebag strap and pull him sideways. He scrambles away on foot, leaving a signed order to empty Red Mesa before the surveyors arrive.\n\nThe land under Eli\'s claim is the only pass a railway can use.',
    title: 'Freight Yard',
    gives: 'Railway orders',
    options: [TaleOption('Return to the wounded operator', 'rail_orders')],
  ),
  'station_rescue': TaleNode(
    'June grips your sleeve while you tie the bandage. She carried a duplicate dispatch because she did not trust the sheriff. "Calloway gets a bonus for every family gone before Monday." Her bag contains the order and a list of payments.\n\nOne name is your brother\'s. Eli looks away before you ask.',
    title: 'Station Office',
    gives: 'Railway orders',
    sets: 'june_saved',
    options: [TaleOption('Ask Eli for the whole truth', 'rail_orders')],
  ),
  'rail_orders': TaleNode(
    'Eli admits he took an advance to persuade the town to sell. Then he saw the price: the railway intended to divert the creek and leave every farm dry. He tried to return the money. Calloway called it a debt and doubled it.\n\nJune can wire the territorial marshal, but the line has been cut at the water tower. Calloway\'s riders are already visible on the ridge.',
    title: 'A Different Debt',
    options: [TaleOption('Repair the telegraph with June', 'wire_tower'), TaleOption('Warn the farms at the creek', 'creek_families')],
  ),
  'wire_tower': TaleNode(
    'The wire hangs over the water tower, sparking where it touches the pump motor. You climb the ladder while June calls out which line to bridge. Below you, two hired men pour lamp oil along the station wall.\n\nThere is time to send the dispatch or stop the fire before it starts.',
    title: 'Above the Tracks',
    options: [
      TaleOption('Send the orders, then jump into the water trough', 'town_council', damage: 10, sets: 'marshal_called'),
      TaleOption('Drop the tank release onto the arsonists', 'town_council', sets: 'station_saved'),
    ],
  ),
  'creek_families': TaleNode(
    'At the creek you find stakes marking a new dam, and a wagon stuck in the mud with three children aboard. Their father has been told Calloway will burn the house if they return. Eli steps into the water before you can speak and puts his shoulder to the wheel.\n\nBy the time the wagon moves, half a dozen farmers have gathered with tools in their hands.',
    title: 'The Creek Crossing',
    options: [
      TaleOption('Ask the families to stand together in town', 'town_council', sets: 'farmers'),
      TaleOption('Escort them to the mission first', 'mission', sets: 'families_safe'),
    ],
  ),
  'mission': TaleNode(
    'Sister Ada opens the mission gates without asking questions. In the vestry she has kept copies of every land sale in the valley. She places Eli\'s deed beside a survey map: the railway has already filed ownership of land nobody sold.\n\n"People will be afraid," she tells you. "Give them something they can hold." She hands you the stamped copies.',
    title: 'The Mission',
    gives: 'Survey fraud evidence',
    options: [TaleOption('Carry the evidence back to Red Mesa', 'town_council')],
  ),
  'town_council': TaleNode(
    'Rosa clears the saloon tables. June lays out the orders. Eli tells the truth in front of everyone, including the part that makes him look worst. Outside, five horses stop at the far end of Main Street.\n\nThe town no longer has to decide whether to save your brother. It has to decide who owns its future.',
    title: 'Before the Showdown',
    options: [
      TaleOption('Lead the farmers into the street with the orders', 'valley_stands', requires: 'farmers'),
      TaleOption('Hold Calloway until the marshal arrives', 'marshal_arrives', requires: 'marshal_called'),
      TaleOption('Publish the forged surveys at the station', 'valley_stands', requires: 'item:Survey fraud evidence'),
      TaleOption('Face Calloway at high noon', 'noon'),
    ],
  ),
  'valley_stands': TaleNode(
    'Calloway reads the orders in your hand and looks past you at the farmers, the station workers, and Rosa in her upstairs window. Nobody reaches for a gun. Nobody moves out of his way either.\n\nThe railway spends the next year in court. Eli spends it repairing fences for the families he almost betrayed. When the first train finally crosses the valley, it stops at a station the town owns, beside a creek that still runs clear.',
    title: 'The Valley Holds',
    end: 'good',
  ),
  'marshal_arrives': TaleNode(
    'You keep Calloway talking about the debt until he hears the second train. The marshal steps down with June\'s dispatch in one hand and a warrant in the other. Calloway reaches for his pistol, then sees Rosa at the window.\n\nEli testifies, including against himself. The sentence is a year of restitution. On the first morning he reports to work, you find him outside the station before sunrise, holding two cups of coffee.',
    title: 'A Debt Repaid',
    end: 'good',
  ),
};

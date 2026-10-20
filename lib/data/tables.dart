// Random tables for solo play and improvisation.
import '../game/dice.dart';

class RandomTable {
  const RandomTable(this.id, this.name, this.description, this.icon, this.entries);
  final String id;
  final String name;
  final String description;
  final String icon;
  final List<String> entries;

  String roll([Rng? rng]) => (rng ?? Rng.unseeded()).pick(entries);
}

const randomTables = <RandomTable>[
  RandomTable('tavern', 'Tavern names', 'A name for the next inn on the road.', 'local_bar', [
    'The Gilded Gryphon', 'The Drunken Kraken', 'The Last Lantern', 'The Rusty Flagon', 'The Sleeping Giant', 'The Crooked Crown',
    'The Wandering Owl', 'The Three Ravens', 'The Salted Eel', 'The Broken Oar', 'The Silver Stag', 'The Hearth & Hound',
    'The Laughing Lich', 'The Copper Kettle', 'The Weeping Willow', 'The Blind Basilisk', 'The Merry Mimic', 'The Tipsy Treant',
    'The Ember & Ale', 'The Moonlit Mug',
  ]),
  RandomTable('rumor', 'Rumors', 'Whispers overheard in taverns and markets.', 'hearing', [
    'The miller\'s daughter vanished on the night of the red moon, and she isn\'t the first.',
    'Someone has been buying every silver mirror in town. Every single one.',
    'An old dwarf swears the abandoned mine is singing again.',
    'The lord\'s new advisor casts no shadow. Ask anyone who has seen him at noon.',
    'Wolves have been seen walking on their hind legs near the old shrine.',
    'A merchant caravan arrived with no merchants, just horses that knew the way.',
    'The bell in the drowned chapel rang last night. The bell has no clapper.',
    'There\'s a reward for anyone who can read the letters found on the dead courier.',
    'A dragon was seen over the mountains, smaller than the stories, but very hungry.',
    'The thieves\' guild is recruiting, and they are paying in gold that crumbles at dawn.',
    'Fishermen are pulling up nets full of ancient coins stamped with a forgotten king.',
    'The witch in the woods is offering to grant wishes. Only small ones. For now.',
    'Graves in the old cemetery have been dug up, from the inside.',
    'A traveling circus came to town and the children keep humming its tune in their sleep.',
    'The river ran backwards for an hour on midsummer\'s eve.',
    'Someone is leaving a single black rose on the doorstep of the city\'s judges.',
  ]),
  RandomTable('weather', 'Weather', 'What the sky is doing today.', 'cloud', [
    'Clear skies and a crisp wind.', 'Heavy fog rolls in, limiting sight to a few yards.', 'A warm drizzle that never quite stops.',
    'A sudden thunderstorm with hail.', 'Blistering heat; water runs low.', 'Bitter cold and snow flurries.', 'An eerie stillness. No birds sing.',
    'Strong winds that make arrows unreliable.', 'A blood-red sunset that has the locals nervous.', 'Gentle sunshine, perfect for travel.',
    'Ash falls like snow from a distant fire.', 'A rainbow arcs over the road; the superstitious call it a blessing.',
  ]),
  RandomTable('quirk', 'NPC quirks', 'Make a character memorable in one line.', 'face', [
    'Speaks only in questions.', 'Constantly polishing a coin that isn\'t there.', 'Laughs at the worst possible moments.',
    'Refers to themselves in the third person.', 'Has a pet rat named after a dead king.', 'Whispers everything, even greetings.',
    'Collects teeth. Not their own.', 'Overly formal; insists on full titles.', 'Hums war songs while working.', 'Can\'t resist a wager.',
    'Terrified of birds.', 'Tells the same story every time you meet, slightly differently.', 'Missing two fingers and proud of it.',
    'Smells strongly of cinnamon.', 'Constantly checks over their shoulder.', 'Ends every sentence with a proverb.',
    'Wears an enormous hat indoors.', 'Absolutely sure you\'ve met before.',
  ]),
  RandomTable('names', 'Names', 'A name for anyone you meet.', 'badge', [
    'Aldous Vane', 'Brisa Coldwater', 'Corwin Ashby', 'Della Thorne', 'Edrin Moss', 'Fennick Graves', 'Gilda Ironwood', 'Hollis Reed',
    'Isolde Marrow', 'Jory Quell', 'Kestra Dunmore', 'Lorcan Pike', 'Mabel Hearth', 'Niall Crane', 'Oona Bright', 'Pell Whistler',
    'Quenna Starling', 'Roderic Hale', 'Sable Winters', 'Tobin Burrows', 'Ulla Frost', 'Vesper Lark', 'Wren Holloway', 'Yorick Stone',
  ]),
  RandomTable('trinket', 'Trinkets', 'A strange little thing found in a pocket.', 'diamond', [
    'A glass eye that sometimes blinks.', 'A key to a door you\'ve never seen.', 'A tiny painting of you, aged eighty.',
    'A music box that plays a song nobody knows.', 'A dried flower that never wilts further.', 'A coin with two heads, both frowning.',
    'A vial of seawater that is always warm.', 'A chess piece carved from bone.', 'A love letter addressed to a dead queen.',
    'A compass that points to the nearest lie.', 'A feather that floats upward when dropped.', 'A wooden whistle no one can hear but dogs and ghosts.',
  ]),
  RandomTable('complication', 'Travel complications', 'Something goes wrong on the road.', 'alt_route', [
    'A bridge is out, washed away by last night\'s storm.', 'A merchant\'s cart has overturned, blocking the road.',
    'Toll collectors demand payment, and they aren\'t official.', 'A horse throws a shoe.', 'You are being followed.',
    'A sudden landslide splits the path.', 'A wounded stranger begs for help.', 'Your rations have spoiled.',
    'A patrol mistakes you for wanted criminals.', 'The map is wrong; this road doesn\'t exist.', 'A swarm of insects descends.',
    'A child claims you are their long-lost parent.',
  ]),
  RandomTable('hook', 'Adventure hooks', 'A reason to go somewhere dangerous.', 'flag', [
    'A noble offers a fortune to recover a stolen family portrait, but won\'t say why it matters.',
    'The village well has been poisoned, and the culprit left a signature.',
    'A ghost asks you to finish the delivery it died trying to make.',
    'An heir to the throne is hiding in a monastery, and assassins are coming.',
    'A tower appeared overnight on the hill. Its door is open.',
    'Pirates are selling maps to a treasure that can\'t possibly exist.',
    'A druid circle needs someone to carry a seed to the heart of a dead forest.',
    'Every animal in the region is fleeing in the same direction.',
    'A golem walks into town, sits down and waits for a command.',
    'Someone has stolen the sound of the temple bells.',
  ]),
  RandomTable('dungeon', 'Dungeon features', 'What\'s in the next room?', 'castle', [
    'A collapsed ceiling, with a narrow crawl space beyond.', 'A pool of black water reflecting a different room.', 'Statues that face a different way each time you look.',
    'An altar with fresh offerings.', 'Bones arranged in a careful spiral.', 'A trapdoor, poorly hidden. Too poorly.', 'A mural that tells your own story.',
    'A locked iron cage, empty, still warm.', 'Glowing fungi that pulse when you speak.', 'A table set for a feast, food untouched for centuries.',
    'A mechanical door with a riddle carved above it.', 'A room full of mirrors, one missing its reflection.',
  ]),
  RandomTable('event', 'City events', 'Something happening in town today.', 'location_city', [
    'A public execution draws a restless crowd.', 'A festival of masks fills the streets.', 'A fire breaks out in the merchant quarter.',
    'The guard is searching every house for a fugitive.', 'A famous bard is performing in the square tonight.', 'A plague doctor has arrived.',
    'Two noble houses are feuding openly in the streets.', 'A wizard\'s experiment has turned the fountain water purple.', 'A great auction of a dead collector\'s estate.',
    'Riots over the price of bread.',
  ]),
  RandomTable('loot', 'Minor loot', 'What\'s in the chest?', 'inventory_2', [
    '2d6 silver coins and a moth-eaten glove.', 'A potion of healing, label smudged.', 'A silver ring worth 25 gp.', 'A map fragment showing a nearby cave.',
    'A set of fine clothes, slightly bloodstained.', '15 gp in a pouch with a family crest.', 'A dagger with a jeweled pommel (50 gp).', 'Three torches and a coil of rope.',
    'A scroll case holding a letter of credit.', 'An ivory dice set, loaded.', 'A small idol of a forgotten god.', 'A bag of exotic spices worth 30 gp.',
  ]),
  RandomTable('npc_motive', 'NPC motives', 'What does this person want?', 'psychology', [
    'Revenge for a wrong long past.', 'Enough coin to leave this town forever.', 'To protect a secret at any cost.', 'Recognition from someone who ignores them.',
    'To be forgiven.', 'Power over their rivals.', 'Safety for their family.', 'Knowledge that was forbidden to them.', 'Love, unrequited.',
    'To prove a prophecy wrong.', 'A quiet life, which you are disrupting.', 'To find someone who went missing.',
  ]),
];

RandomTable? tableById(String id) => randomTables.where((t) => t.id == id).firstOrNull;

// Companion personalities: approval reactions and personal quests.
import '../models/character.dart';

const likeReasons = <String, List<String>>{
  'paladin': ['You chose mercy and words over blades.', 'That was the honorable path.', 'You protect the weak. Good.'],
  'cleric': ['Compassion is its own prayer.', 'You listened before you judged.', 'Rest and reflection serve the soul.'],
  'rogue': ['Quiet and clever. My kind of plan.', 'Nobody saw that coming. Nice.', 'Poking around pays off.'],
  'monk': ['Patience and focus. Well done.', 'Observation before action.', 'A balanced choice.'],
  'barbarian': ['Ha! Straight at them!', 'Finally, some action!', 'No hesitation. I like it.'],
  'fighter': ['Decisive. That\'s how you win.', 'Good tactical call.', 'You led from the front.'],
  'wizard': ['Fascinating! Let\'s learn more.', 'A properly arcane solution.', 'Curiosity rewarded.'],
  'sorcerer': ['Now that is real magic.', 'Bold. I approve.', 'Let the power flow!'],
  'warlock': ['Knowledge is power, and power is everything.', 'The arcane always has a price, but you paid it well.'],
  'ranger': ['Moving with the land, not against it.', 'Careful tracking. Wise.', 'The wild respects caution.'],
  'druid': ['Nature thanks you.', 'You walked lightly here.', 'Balance is kept.'],
  'bard': ['What a story this will make!', 'Charming! Truly charming.', 'Words are the sharpest blades.'],
};

const dislikeReasons = <String, List<String>>{
  'paladin': ['Skulking in shadows isn\'t honorable.', 'There was a more righteous way.'],
  'cleric': ['Deceit stains the soul.', 'I will pray for that choice.'],
  'barbarian': ['Sneaking? Boring.', 'We rest while enemies gather?'],
  'rogue': ['Charging in? We\'ll get ourselves killed.', 'There was a smarter way to do that.'],
  'wizard': ['Violence is the last refuge of the unimaginative.', 'Must everything be solved with steel?'],
};

/// (title, description, what the companion says when revealing it).
(String, String, String) personalQuestFor(Character c) {
  final cls = c.classLevels.keys.isEmpty ? 'fighter' : c.classLevels.keys.first;
  final options = _quests[cls] ?? _quests['fighter']!;
  final q = options[c.name.length % options.length];
  return (q.$1, q.$2, q.$3);
}

const _quests = <String, List<(String, String, String)>>{
  'fighter': [
    ('The Broken Banner', 'Recover the standard of the company that abandoned them at Redhollow.', 'I was a sergeant once. My company left me for dead at Redhollow, and took our banner with them. I want it back.'),
    ('A Duel Deferred', 'Find the champion who scarred them and finish the duel.', 'See this scar? A man named Varric gave it to me, then walked away laughing. One day I\'ll finish that fight.'),
  ],
  'paladin': [
    ('The Oath Unspoken', 'Find the shrine where their order was founded and renew their broken oath.', 'I broke my oath once. I\'ve never told anyone. There is a shrine where I could make it right.'),
  ],
  'cleric': [
    ('Silent God', 'Discover why their deity stopped answering prayers in their home temple.', 'My temple\'s god has gone quiet. Every prayer echoes back empty. I need to know why.'),
  ],
  'rogue': [
    ('The Debt Ledger', 'Steal back the ledger that records a debt they owe the Velvet Hand.', 'There\'s a book with my name in it, and a number I can\'t pay. I need that book to disappear.'),
    ('Sister in Chains', 'Free their sister from a gang that holds her as collateral.', 'I don\'t steal for fun, whatever I say. My sister is held by the Grey Rats. Every coin I take is for her.'),
  ],
  'wizard': [
    ('The Missing Chapter', 'Recover the torn pages of their master\'s spellbook.', 'My master\'s grimoire was torn apart when she died. Three pages are missing. They hold something she feared.'),
  ],
  'sorcerer': [
    ('Blood Answers', 'Find the source of the power in their bloodline.', 'The magic in my blood came from somewhere. Someone. I keep dreaming of a tower made of glass.'),
  ],
  'warlock': [
    ('Terms and Conditions', 'Find a way to renegotiate, or break, their pact.', 'My patron is calling in a favor soon. I\'ve read the contract a hundred times. There has to be a loophole.'),
  ],
  'ranger': [
    ('The White Stag', 'Track the white stag their people believe heralds a great change.', 'My people say the white stag appears once a century. I saw its tracks last spring. I have to find it.'),
  ],
  'druid': [
    ('The Withering Grove', 'Heal the dying grove where they were raised.', 'My grove is dying, root by root. Something poisons the soil. I\'ve felt it for months.'),
  ],
  'bard': [
    ('The Lost Verse', 'Find the final verse of a song that can wake the dead.', 'There\'s a song with a missing last verse. They say whoever sings it complete can call back the dead. I want to hear it. Just once.'),
  ],
  'barbarian': [
    ('Return to the Steppe', 'Return to their tribe and prove themselves to the elders who exiled them.', 'My tribe cast me out for a reason I won\'t speak of yet. One day I go back. With you, maybe.'),
  ],
  'monk': [
    ('The Empty Monastery', 'Learn why their monastery was abandoned overnight.', 'I came back from a pilgrimage and my monastery was empty. Tea still warm on the tables. No one has ever explained it.'),
  ],
};

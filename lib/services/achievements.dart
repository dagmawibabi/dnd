import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AchievementDef {
  const AchievementDef(this.id, this.name, this.description, this.icon, this.stat, this.goal, {this.secret = false});
  final String id;
  final String name;
  final String description;
  final IconData icon;

  /// The stat that unlocks it once it reaches [goal].
  final String stat;
  final int goal;
  final bool secret;
}

/// Lifetime stat keys.
class Stat {
  static const adventures = 'adventures';
  static const completed = 'completed';
  static const turns = 'turns';
  static const kills = 'kills';
  static const crits = 'crits';
  static const nat1s = 'nat1s';
  static const nat20Checks = 'nat20_checks';
  static const damage = 'damage';
  static const healed = 'healed';
  static const gold = 'gold';
  static const spells = 'spells';
  static const levels = 'levels';
  static const maxLevel = 'max_level';
  static const deaths = 'deaths';
  static const deathSaves = 'death_saves';
  static const fled = 'fled';
  static const oracle = 'oracle';
  static const checks = 'checks';
  static const checksPassed = 'checks_passed';
  static const companions = 'companions';
  static const npcs = 'npcs';
  static const items = 'items';
  static const magicItems = 'magic_items';
  static const rests = 'rests';
  static const modules = 'modules';
  static const campaigns = 'campaigns';
  static const chapters = 'chapters';
  static const bosses = 'bosses';
  static const characters = 'characters';
  static const purchases = 'purchases';
  static const rolls = 'dice_rolls';
  static const tales = 'tales';
  static const talesFinished = 'tales_finished';
  static const playSeconds = 'play_seconds';
  static const chats = 'chat_messages';
  static const approaches = 'approaches_answered';
  static const romances = 'romances';
  static const enemies = 'enemies_made';
  static const bestFriends = 'best_friends';
  static const places = 'places_visited';
  static const readings = 'items_read';
  static const crafted = 'items_created';
  static const pictures = 'ai_pictures';
  static const listened = 'passages_listened';
  static const goals = 'goals_completed';
  static const quests = 'quests_completed';
  static const storyAwards = 'story_awards';
  static const shares = 'cards_shared';
  static const notes = 'notes_written';
  static const aiTools = 'ai_tools_used';
}

const statLabels = <String, String>{
  Stat.adventures: 'Adventures started',
  Stat.completed: 'Adventures finished',
  Stat.turns: 'Turns played',
  Stat.kills: 'Enemies defeated',
  Stat.crits: 'Critical hits',
  Stat.nat1s: 'Natural 1s',
  Stat.damage: 'Damage dealt',
  Stat.healed: 'HP healed',
  Stat.gold: 'Gold earned',
  Stat.spells: 'Spells cast',
  Stat.levels: 'Levels gained',
  Stat.maxLevel: 'Highest level',
  Stat.deaths: 'Heroes fallen',
  Stat.checks: 'Ability checks',
  Stat.checksPassed: 'Checks passed',
  Stat.oracle: 'Oracle questions',
  Stat.companions: 'Companions recruited',
  Stat.npcs: 'NPCs met',
  Stat.items: 'Items found',
  Stat.magicItems: 'Magic items found',
  Stat.rests: 'Rests taken',
  Stat.modules: 'Modules completed',
  Stat.chapters: 'Campaign chapters',
  Stat.bosses: 'Bosses defeated',
  Stat.characters: 'Heroes created',
  Stat.purchases: 'Purchases',
  Stat.rolls: 'Dice rolled',
  Stat.tales: 'Text adventures started',
  Stat.talesFinished: 'Text adventures finished',
  Stat.chats: 'Messages to characters',
  Stat.approaches: 'Conversations they started',
  Stat.romances: 'Romances',
  Stat.enemies: 'Enemies made',
  Stat.bestFriends: 'Best friends',
  Stat.places: 'Places visited',
  Stat.readings: 'Writings read',
  Stat.crafted: 'Items created',
  Stat.pictures: 'AI pictures',
  Stat.listened: 'Passages listened to',
  Stat.goals: 'Goals completed',
  Stat.quests: 'Quests completed',
  Stat.storyAwards: 'Story awards',
  Stat.shares: 'Cards shared',
  Stat.aiTools: 'AI tools used',
};

const achievementDefs = <AchievementDef>[
  AchievementDef('first_step', 'First Step', 'Begin your first adventure.', Icons.flag_outlined, Stat.adventures, 1),
  AchievementDef('maker', 'Maker of Heroes', 'Create 3 heroes.', Icons.person_add_alt, Stat.characters, 3),
  AchievementDef('first_blood', 'First Blood', 'Defeat an enemy.', Icons.bolt_outlined, Stat.kills, 1),
  AchievementDef('slayer', 'Slayer', 'Defeat 50 enemies.', Icons.local_fire_department_outlined, Stat.kills, 50),
  AchievementDef('legend_blade', 'Legendary Blade', 'Defeat 250 enemies.', Icons.whatshot_outlined, Stat.kills, 250),
  AchievementDef('crit', 'Natural Twenty', 'Land a critical hit.', Icons.star_outline, Stat.crits, 1),
  AchievementDef('crit_25', 'Fortune Favors', 'Land 25 critical hits.', Icons.auto_awesome_outlined, Stat.crits, 25),
  AchievementDef('nat1', 'It Happens', 'Roll a natural 1.', Icons.sentiment_dissatisfied_outlined, Stat.nat1s, 1),
  AchievementDef('nat1_20', 'Cursed Dice', 'Roll 20 natural 1s.', Icons.casino_outlined, Stat.nat1s, 20, secret: true),
  AchievementDef('finisher', 'The End', 'Finish an adventure.', Icons.emoji_events_outlined, Stat.completed, 1),
  AchievementDef('veteran', 'Veteran', 'Finish 10 adventures.', Icons.military_tech_outlined, Stat.completed, 10),
  AchievementDef('modules_5', 'Bookworm', 'Complete 5 handcrafted adventures.', Icons.menu_book_outlined, Stat.modules, 5),
  AchievementDef('level_5', 'Tier Two', 'Reach level 5.', Icons.trending_up, Stat.maxLevel, 5),
  AchievementDef('level_10', 'Paragon', 'Reach level 10.', Icons.workspace_premium_outlined, Stat.maxLevel, 10),
  AchievementDef('level_20', 'Living Legend', 'Reach level 20.', Icons.diamond_outlined, Stat.maxLevel, 20),
  AchievementDef('rich', 'Coin Purse', 'Earn 500 gold.', Icons.paid_outlined, Stat.gold, 500),
  AchievementDef('dragon_hoard', 'Dragon Hoard', 'Earn 10,000 gold.', Icons.savings_outlined, Stat.gold, 10000),
  AchievementDef('caster', 'Spellslinger', 'Cast 100 spells.', Icons.auto_fix_high, Stat.spells, 100),
  AchievementDef('healer', 'Field Medic', 'Heal 500 HP.', Icons.healing_outlined, Stat.healed, 500),
  AchievementDef('dmg', 'Heavy Hitter', 'Deal 5,000 damage.', Icons.sports_mma_outlined, Stat.damage, 5000),
  AchievementDef('friend', 'Good Company', 'Recruit a companion.', Icons.group_add_outlined, Stat.companions, 1),
  AchievementDef('socialite', 'Socialite', 'Meet 30 NPCs.', Icons.forum_outlined, Stat.npcs, 30),
  AchievementDef('collector', 'Collector', 'Find 50 items.', Icons.inventory_2_outlined, Stat.items, 50),
  AchievementDef('attuned', 'Attuned', 'Find a magic item.', Icons.auto_awesome, Stat.magicItems, 1),
  AchievementDef('oracle', 'Ask the Fates', 'Ask the oracle 10 questions.', Icons.help_outline, Stat.oracle, 10),
  AchievementDef('skilled', 'Jack of All Trades', 'Pass 100 ability checks.', Icons.psychology_outlined, Stat.checksPassed, 100),
  AchievementDef('campaigner', 'Saga', 'Play 3 chapters of a campaign.', Icons.auto_stories_outlined, Stat.chapters, 3),
  AchievementDef('boss', 'Giant Killer', 'Defeat a boss.', Icons.shield_moon_outlined, Stat.bosses, 1),
  AchievementDef('death', 'Rest in Peace', 'Let a hero fall.', Icons.sentiment_very_dissatisfied_outlined, Stat.deaths, 1, secret: true),
  AchievementDef('coward', 'Strategic Retreat', 'Flee from 5 battles.', Icons.directions_run, Stat.fled, 5, secret: true),
  AchievementDef('shopper', 'Retail Therapy', 'Buy 10 things.', Icons.storefront_outlined, Stat.purchases, 10),
  AchievementDef('turns_500', 'Storyteller', 'Play 500 turns.', Icons.chat_outlined, Stat.turns, 500),
  AchievementDef('tale_first', 'Page Turner', 'Finish a text adventure.', Icons.menu_book_outlined, Stat.talesFinished, 1),
  AchievementDef('tale_genres', 'Genre Hopper', 'Finish 6 text adventures.', Icons.collections_bookmark_outlined, Stat.talesFinished, 6),
  AchievementDef('tale_20', 'Library Card', 'Start 20 text adventures.', Icons.local_library_outlined, Stat.tales, 20),
  AchievementDef('turns_100', 'Getting Started', 'Play 100 turns.', Icons.directions_walk, Stat.turns, 100),
  AchievementDef('turns_2000', 'Epic Saga', 'Play 2,000 turns.', Icons.history_edu_outlined, Stat.turns, 2000),
  AchievementDef('hour', 'Lost in the Story', 'Play for an hour.', Icons.hourglass_bottom, Stat.playSeconds, 3600),
  AchievementDef('ten_hours', 'Devoted Adventurer', 'Play for 10 hours.', Icons.schedule, Stat.playSeconds, 36000),
  AchievementDef('hundred_hours', 'A Life of Adventure', 'Play for 100 hours.', Icons.all_inclusive, Stat.playSeconds, 360000, secret: true),
  AchievementDef('crit_100', 'Lucky Star', 'Land 100 critical hits.', Icons.stars_outlined, Stat.crits, 100),
  AchievementDef('nat20_check', 'Against All Odds', 'Roll a natural 20 on an ability check.', Icons.casino, Stat.nat20Checks, 1),
  AchievementDef('skilled_500', 'Master of Many', 'Pass 500 ability checks.', Icons.psychology_alt_outlined, Stat.checksPassed, 500),
  AchievementDef('bosses_10', 'Monster Hunter', 'Defeat 10 bosses.', Icons.castle_outlined, Stat.bosses, 10),
  AchievementDef('healer_5k', 'Lifebinder', 'Heal 5,000 HP.', Icons.volunteer_activism_outlined, Stat.healed, 5000),
  AchievementDef('spells_500', 'Archmage', 'Cast 500 spells.', Icons.blur_on, Stat.spells, 500),
  AchievementDef('magic_10', 'Treasure Trove', 'Find 10 magic items.', Icons.diamond, Stat.magicItems, 10),
  AchievementDef('rests_25', 'Campfire Stories', 'Rest 25 times.', Icons.bedtime_outlined, Stat.rests, 25),
  AchievementDef('party_5', 'Fellowship', 'Recruit 5 companions.', Icons.groups_outlined, Stat.companions, 5),
  AchievementDef('npcs_100', 'Everyone Knows You', 'Meet 100 characters.', Icons.diversity_3_outlined, Stat.npcs, 100),
  AchievementDef('chat_1', 'Let\'s Talk', 'Send a private message to a character.', Icons.chat_bubble_outline, Stat.chats, 1),
  AchievementDef('chat_100', 'Confidant', 'Send 100 private messages.', Icons.forum, Stat.chats, 100),
  AchievementDef('approached', 'Someone Wants a Word', 'Answer a character who came to you.', Icons.waving_hand_outlined, Stat.approaches, 1),
  AchievementDef('romance', 'Heartstrings', 'Begin a romance.', Icons.favorite_border, Stat.romances, 1),
  AchievementDef('best_friend', 'Ride or Die', 'Become someone\'s best friend.', Icons.handshake_outlined, Stat.bestFriends, 1),
  AchievementDef('enemy', 'Nemesis', 'Make a true enemy.', Icons.gpp_bad_outlined, Stat.enemies, 1, secret: true),
  AchievementDef('places_25', 'Wanderer', 'Visit 25 places.', Icons.explore_outlined, Stat.places, 25),
  AchievementDef('places_100', 'Cartographer', 'Visit 100 places.', Icons.public, Stat.places, 100),
  AchievementDef('reader', 'Between the Lines', 'Read a book, letter or note you found.', Icons.chrome_reader_mode_outlined, Stat.readings, 1),
  AchievementDef('reader_20', 'Scholar', 'Read 20 writings.', Icons.import_contacts_outlined, Stat.readings, 20),
  AchievementDef('maker_item', 'Conjurer', 'Create an item with the item tool.', Icons.add_box_outlined, Stat.crafted, 1),
  AchievementDef('gallery_50', 'Patron of the Arts', 'Have 50 AI pictures painted.', Icons.palette_outlined, Stat.pictures, 50),
  AchievementDef('listener', 'Bedtime Story', 'Listen to 50 passages read aloud.', Icons.headphones_outlined, Stat.listened, 50),
  AchievementDef('goals_10', 'Objective Complete', 'Complete 10 goals in text adventures.', Icons.task_alt, Stat.goals, 10),
  AchievementDef('quests_25', 'Questmaster', 'Complete 25 quests.', Icons.flag_circle_outlined, Stat.quests, 25),
  AchievementDef('awarded', 'Remarkable', 'Earn an award from the storyteller.', Icons.workspace_premium, Stat.storyAwards, 1),
  AchievementDef('awarded_10', 'The Stuff of Legends', 'Earn 10 awards from the storyteller.', Icons.emoji_events, Stat.storyAwards, 10),
  AchievementDef('sharer', 'Show and Tell', 'Share a card.', Icons.ios_share, Stat.shares, 1),
  AchievementDef('ai_tools', 'Second Opinion', 'Use the AI tools 10 times.', Icons.psychology_outlined, Stat.aiTools, 10),
];

/// An achievement the storyteller awarded for something you did in a story.
class StoryAchievement {
  StoryAchievement({required this.id, required this.title, required this.description, this.icon = 'star', this.story = '', this.storyId = '', DateTime? at}) : at = at ?? DateTime.now();
  final String id;
  final String title;
  final String description;
  final String icon;
  final String story;
  final String storyId;
  final DateTime at;

  IconData get iconData => storyAwardIcon(icon);

  AchievementDef get def => AchievementDef(id, title, description, iconData, Stat.storyAwards, 0);

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'd': description, 'i': icon, 's': story, 'sid': storyId, 'at': at.millisecondsSinceEpoch};
  factory StoryAchievement.fromJson(Map<String, dynamic> j) => StoryAchievement(
        id: j['id'] ?? '',
        title: j['t'] ?? '',
        description: j['d'] ?? '',
        icon: j['i'] ?? 'star',
        story: j['s'] ?? '',
        storyId: j['sid'] ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

IconData storyAwardIcon(String name) => switch (name) {
      'sword' => Icons.sports_martial_arts,
      'heart' => Icons.favorite,
      'crown' => Icons.workspace_premium,
      'skull' => Icons.dangerous_outlined,
      'map' => Icons.map_outlined,
      'book' => Icons.menu_book,
      'shield' => Icons.shield_outlined,
      'fire' => Icons.local_fire_department,
      'moon' => Icons.nightlight_round,
      _ => Icons.star,
    };

/// Lifetime stats and achievement unlocks.
class Achievements extends ChangeNotifier {
  Achievements(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const _key = 'achievements.v1';

  final Map<String, int> stats = {};
  final Map<String, int> unlocked = {}; // id -> epoch ms

  /// Awards the storyteller gave in stories, newest last.
  final List<StoryAchievement> storyAwards = [];

  /// Called when something unlocks, so the UI can toast it.
  void Function(AchievementDef a)? onUnlock;

  int stat(String k) => stats[k] ?? 0;
  bool isUnlocked(String id) => unlocked.containsKey(id);
  int get unlockedCount => unlocked.length;

  /// Every achievement there is to unlock (story awards are extra).
  int get total => achievementDefs.length;

  /// The storyteller recognizes a deed. The same title in the same story counts once.
  StoryAchievement? award({required String title, required String description, String icon = 'star', String story = '', String storyId = ''}) {
    final t = title.trim();
    if (t.isEmpty || storyAwards.any((a) => a.storyId == storyId && a.title.toLowerCase() == t.toLowerCase())) return null;
    final a = StoryAchievement(id: 'story_${DateTime.now().microsecondsSinceEpoch}', title: t, description: description.trim(), icon: icon, story: story, storyId: storyId);
    storyAwards.add(a);
    onUnlock?.call(a.def);
    add(Stat.storyAwards);
    return a;
  }

  /// When an achievement was unlocked, if it was.
  DateTime? unlockedAt(String id) => unlocked[id] == null ? null : DateTime.fromMillisecondsSinceEpoch(unlocked[id]!);

  void add(String key, [int by = 1]) {
    if (by == 0) return;
    stats[key] = stat(key) + by;
    _check();
  }

  void max(String key, int value) {
    if (value <= stat(key)) return;
    stats[key] = value;
    _check();
  }

  void _check() {
    for (final a in achievementDefs) {
      if (unlocked.containsKey(a.id)) continue;
      if (stat(a.stat) >= a.goal) {
        unlocked[a.id] = DateTime.now().millisecondsSinceEpoch;
        onUnlock?.call(a);
      }
    }
    notifyListeners();
    _save();
  }

  void reset() {
    stats.clear();
    unlocked.clear();
    storyAwards.clear();
    notifyListeners();
    _save();
  }

  Map<String, dynamic> toJson() => {'stats': stats, 'unlocked': unlocked, if (storyAwards.isNotEmpty) 'awards': storyAwards.map((a) => a.toJson()).toList()};

  void restore(Map<String, dynamic> j) {
    stats
      ..clear()
      ..addAll(Map<String, int>.from(j['stats'] ?? {}));
    unlocked
      ..clear()
      ..addAll(Map<String, int>.from(j['unlocked'] ?? {}));
    storyAwards
      ..clear()
      ..addAll([for (final a in (j['awards'] as List? ?? const [])) StoryAchievement.fromJson(Map<String, dynamic>.from(a))]);
    notifyListeners();
    _save();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      stats.addAll(Map<String, int>.from(j['stats'] ?? {}));
      unlocked.addAll(Map<String, int>.from(j['unlocked'] ?? {}));
      storyAwards.addAll([for (final a in (j['awards'] as List? ?? const [])) StoryAchievement.fromJson(Map<String, dynamic>.from(a))]);
    } catch (_) {}
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode(toJson()));
}

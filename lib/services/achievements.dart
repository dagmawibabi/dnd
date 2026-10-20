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
];

/// Lifetime stats and achievement unlocks.
class Achievements extends ChangeNotifier {
  Achievements(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const _key = 'achievements.v1';

  final Map<String, int> stats = {};
  final Map<String, int> unlocked = {}; // id -> epoch ms

  /// Called when something unlocks, so the UI can toast it.
  void Function(AchievementDef a)? onUnlock;

  int stat(String k) => stats[k] ?? 0;
  bool isUnlocked(String id) => unlocked.containsKey(id);
  int get unlockedCount => unlocked.length;

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
    notifyListeners();
    _save();
  }

  Map<String, dynamic> toJson() => {'stats': stats, 'unlocked': unlocked};

  void restore(Map<String, dynamic> j) {
    stats
      ..clear()
      ..addAll(Map<String, int>.from(j['stats'] ?? {}));
    unlocked
      ..clear()
      ..addAll(Map<String, int>.from(j['unlocked'] ?? {}));
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
    } catch (_) {}
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode(toJson()));
}

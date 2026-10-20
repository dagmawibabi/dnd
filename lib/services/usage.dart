import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/adventure.dart';
import 'ai/gateway_client.dart';
import 'ai/model_catalog.dart';
import 'settings.dart';

/// Running totals for one bucket (a model, a day, an adventure…).
class UsageTotals {
  int inputTokens = 0;
  int outputTokens = 0;
  int calls = 0;
  int images = 0;
  int videos = 0;
  int seconds = 0;
  int characters = 0;
  double cost = 0;

  int get tokens => inputTokens + outputTokens;

  void add(UsageEvent e, double c) {
    inputTokens += e.inputTokens;
    outputTokens += e.outputTokens;
    images += e.images;
    videos += e.videos;
    seconds += e.seconds;
    characters += e.characters;
    calls++;
    cost += c;
  }

  /// "1.2K tokens · 3 images · 1 video (4s) · 2.1K chars voiced · 9 calls"
  String get detail => [
        if (tokens > 0) '${fmtTokens(tokens)} tokens',
        if (images > 0) '$images image${images == 1 ? '' : 's'}',
        if (videos > 0) '$videos video${videos == 1 ? '' : 's'} (${seconds}s)',
        if (characters > 0) '${fmtTokens(characters)} chars voiced',
        '$calls call${calls == 1 ? '' : 's'}',
      ].join(' · ');

  Map<String, dynamic> toJson() => {'i': inputTokens, 'o': outputTokens, 'c': calls, 'img': images, 'vid': videos, 'sec': seconds, 'ch': characters, 'usd': cost};
  static UsageTotals fromJson(Map<String, dynamic> j) => UsageTotals()
    ..inputTokens = (j['i'] ?? 0) as int
    ..outputTokens = (j['o'] ?? 0) as int
    ..calls = (j['c'] ?? 0) as int
    ..images = (j['img'] ?? 0) as int
    ..videos = (j['vid'] ?? 0) as int
    ..seconds = (j['sec'] ?? 0) as int
    ..characters = (j['ch'] ?? 0) as int
    ..cost = ((j['usd'] ?? 0) as num).toDouble();
}

class UsageInsight {
  const UsageInsight(this.title, this.text, {this.tip = false});
  final String title;
  final String text;
  final bool tip;
}

/// Tracks tokens and estimated spend for every AI Gateway call.
class UsageTracker extends ChangeNotifier {
  UsageTracker(this._prefs, this._catalog, {this.settings}) {
    _load();
    GatewayClient.onUsage = record;
    GatewayClient.usageTarget = () => current?.usage ?? sink;
    GatewayClient.beforeRequest = reserve;
    GatewayClient.priceOf = costOf;
  }

  final SettingsController? settings;
  final List<({String day, int tokens, double cost, Map<String, num>? target})> _pending = [];

  /// Reserve estimated usage before dispatch, including concurrent image calls.
  VoidCallback reserve(String model, int input, int output, int images, Map<String, num>? target, {int characters = 0, int seconds = 0}) {
    final s = settings;
    final day = _day(DateTime.now());
    final info = _catalog.byId(model);
    final hasCostLimit = (s?.dailyCostLimit ?? 0) > 0 || (target != null && (s?.adventureCostLimit ?? 0) > 0);
    final priced = info != null &&
        (seconds > 0
            ? info.videoPrice != null
            : characters > 0
                ? info.speechPrice != null
                : images > 0
                    ? info.imagePrice != null || (info.inputPrice != null && info.outputPrice != null)
                    : info.inputPrice != null && info.outputPrice != null);
    if (hasCostLimit && !priced && !(info?.isFree ?? false)) {
      throw GatewayException('Pricing is unavailable for ${AiRoute.bare(model)}. Refresh the model list or choose a priced model to use a cost limit.');
    }
    if (target != null) {
      if (images > 0 && (s?.adventureImageLimit ?? 0) > 0 && (target['images'] ?? 0) >= s!.adventureImageLimit) {
        throw GatewayException('This story reached its limit of ${s.adventureImageLimit} images. Raise it in Settings → Usage & limits.');
      }
      if (seconds > 0 && (s?.adventureVideoLimit ?? 0) > 0 && (target['videos'] ?? 0) >= s!.adventureVideoLimit) {
        throw GatewayException('This story reached its limit of ${s.adventureVideoLimit} videos. Raise it in Settings → Usage & limits.');
      }
    }
    final cost = costOf(UsageEvent(model: model, inputTokens: input, outputTokens: output, images: images, videos: seconds > 0 ? 1 : 0, seconds: seconds, characters: characters));
    final tokens = input + output;
    void check(num used, num requested, num limit, String label) {
      if (limit > 0 && used + requested > limit) {
        throw GatewayException('$label limit would be exceeded. Adjust Usage limits in Settings or wait for the daily reset.');
      }
    }
    final dailyPending = _pending.where((r) => r.day == day);
    check(today.tokens + dailyPending.fold<int>(0, (n, r) => n + r.tokens), tokens, s?.dailyTokenLimit ?? 0, 'Daily token');
    check(today.cost + dailyPending.fold<double>(0, (n, r) => n + r.cost), cost, s?.dailyCostLimit ?? 0, 'Daily cost');
    if (target != null) {
      final pending = _pending.where((r) => identical(r.target, target));
      check((target['in'] ?? 0) + (target['out'] ?? 0) + pending.fold<int>(0, (n, r) => n + r.tokens), tokens, s?.adventureTokenLimit ?? 0, 'Adventure token');
      check((target['cost'] ?? 0) + pending.fold<double>(0, (n, r) => n + r.cost), cost, s?.adventureCostLimit ?? 0, 'Adventure cost');
    }
    final reservation = (day: day, tokens: tokens, cost: cost, target: target);
    _pending.add(reservation);
    return () => _pending.remove(reservation);
  }

  final SharedPreferences _prefs;
  final ModelCatalog _catalog;
  static const _key = 'usage.v1';

  final UsageTotals total = UsageTotals();
  final Map<String, UsageTotals> byModel = {};
  final Map<String, UsageTotals> byCategory = {};
  final Map<String, UsageTotals> byDay = {};

  /// The adventure currently being played; calls are also added to it.
  Adventure? current;

  /// Usage totals of whatever else is being played (a text adventure).
  Map<String, num>? sink;
  void Function()? onCurrentChanged;

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double costOf(UsageEvent e) {
    if (e.reportedCost != null) return e.reportedCost!;
    final m = _catalog.byId(e.model);
    if (m == null) return 0;
    var c = e.inputTokens / 1e6 * (m.inputPrice ?? 0) + e.outputTokens / 1e6 * (m.outputPrice ?? 0);
    if (e.images > 0 && m.imagePrice != null && (m.type == 'image' || e.outputTokens == 0)) {
      c = e.images * m.imagePrice! + e.inputTokens / 1e6 * (m.inputPrice ?? 0);
    }
    if (e.seconds > 0) c += e.seconds * (m.videoPrice ?? 0);
    if (e.characters > 0) c += e.characters * (m.speechPrice ?? 0);
    return c;
  }

  void record(UsageEvent e) {
    final c = costOf(e);
    total.add(e, c);
    byCategory.putIfAbsent(e.category, UsageTotals.new).add(e, c);
    byModel.putIfAbsent(e.model, UsageTotals.new).add(e, c);
    byDay.putIfAbsent(_day(DateTime.now()), UsageTotals.new).add(e, c);
    final u0 = e.target;
    if (u0 != null) {
      final u = u0;
      u['in'] = (u['in'] ?? 0) + e.inputTokens;
      u['out'] = (u['out'] ?? 0) + e.outputTokens;
      u['calls'] = (u['calls'] ?? 0) + 1;
      u['images'] = (u['images'] ?? 0) + e.images;
      if (e.videos > 0) u['videos'] = (u['videos'] ?? 0) + e.videos;
      if (e.seconds > 0) u['seconds'] = (u['seconds'] ?? 0) + e.seconds;
      if (e.characters > 0) u['chars'] = (u['chars'] ?? 0) + e.characters;
      u['cost'] = (u['cost'] ?? 0) + c;
      for (final prefix in ['category:${e.category}', 'model:${Uri.encodeComponent(e.model)}', 'categoryModel:${e.category}:${Uri.encodeComponent(e.model)}']) {
        final bucket = UsageTotals()..add(e, c);
        final values = {'in': bucket.inputTokens, 'out': bucket.outputTokens, 'calls': bucket.calls, 'images': bucket.images, 'videos': bucket.videos, 'seconds': bucket.seconds, 'chars': bucket.characters, 'cost': bucket.cost};
        values.forEach((key, value) => u['$prefix:$key'] = (u['$prefix:$key'] ?? 0) + value);
      }
      onCurrentChanged?.call();
    }
    notifyListeners();
    _save();
  }

  UsageTotals get today => byDay[_day(DateTime.now())] ?? UsageTotals();

  UsageTotals last7Days() {
    final t = UsageTotals();
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final d = byDay[_day(now.subtract(Duration(days: i)))];
      if (d == null) continue;
      t
        ..inputTokens += d.inputTokens
        ..outputTokens += d.outputTokens
        ..calls += d.calls
        ..images += d.images
        ..cost += d.cost;
    }
    return t;
  }

  /// Daily totals for the last [days] days, oldest first.
  List<(String, UsageTotals)> recentDays([int days = 14]) {
    final now = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final k = _day(now.subtract(Duration(days: i)));
          return (k, byDay[k] ?? UsageTotals());
        }(),
    ];
  }

  List<UsageInsight> insights({Map<String, num>? story, int turns = 0, String? textModel, String? fastModel}) {
    final out = <UsageInsight>[];
    if (total.calls == 0) {
      out.add(const UsageInsight('No usage yet', 'Costs will appear here once the AI narrates or paints something.'));
      return out;
    }
    final a = story;
    if (a != null && (a['calls'] ?? 0) > 0 && turns > 0) {
      final perTurn = (a['cost'] ?? 0) / turns;
      out.add(UsageInsight('This story', '${fmtCost((a['cost'] ?? 0).toDouble())} over $turns turns · about ${fmtCost(perTurn.toDouble())} per turn.'));
      final media = usageBreakdown(a, 'category');
      final pics = (media['images']?.cost ?? 0) + (media['effects']?.cost ?? 0) + (media['video']?.cost ?? 0);
      if ((a['cost'] ?? 0) > 0 && pics / (a['cost'] ?? 1) > 0.6) {
        out.add(const UsageInsight('Art is most of this story\'s cost', 'Turn off special effects or scene art in Settings → Images, or set an image cap in Usage & limits.', tip: true));
      }
    }
    final textCalls = byModel.entries.where((e) => e.value.images == 0).toList();
    if (textCalls.isNotEmpty) {
      final t = textCalls.fold(UsageTotals(), (acc, e) {
        acc.inputTokens += e.value.inputTokens;
        acc.outputTokens += e.value.outputTokens;
        acc.calls += e.value.calls;
        return acc;
      });
      if (t.calls > 0) {
        final avgIn = t.inputTokens ~/ t.calls;
        final avgOut = t.outputTokens ~/ t.calls;
        out.add(UsageInsight('Average call', '$avgIn tokens in · $avgOut out. Input is mostly the story so far, the canon and your hero sheet.'));
        if (avgIn > 6000) {
          out.add(const UsageInsight('Long prompts', 'Prompts are getting large. Unpin old canon entries or end the chapter as a campaign to start fresh with a summary.', tip: true));
        }
      }
    }
    final sorted = byModel.entries.toList()..sort((x, y) => y.value.cost.compareTo(x.value.cost));
    if (sorted.isNotEmpty && sorted.first.value.cost > 0) {
      final share = total.cost == 0 ? 0 : sorted.first.value.cost / total.cost * 100;
      out.add(UsageInsight('Biggest spender', '${sorted.first.key} · ${share.round()}% of all spend.'));
    }
    final imgCost = byModel.values.fold<double>(0, (s, t) => s + (t.images > 0 ? t.cost : 0));
    if (total.cost > 0 && imgCost / total.cost > 0.5) {
      out.add(const UsageInsight('Images dominate', 'Most spend goes to images. Turn off AI scene art and keep portraits to cut costs, or use on-device art.', tip: true));
    }
    final week = last7Days();
    if (week.cost > 0) {
      out.add(UsageInsight('Last 7 days', '${fmtCost(week.cost)} · projected ${fmtCost(week.cost / 7 * 30)} per month at this pace.'));
    }
    if (textModel != null && fastModel != null && textModel != fastModel) {
      final main = _catalog.byId(textModel);
      final fast = _catalog.byId(fastModel);
      if (main != null && fast != null && (main.outputPrice ?? 0) > (fast.outputPrice ?? 0) * 3) {
        out.add(UsageInsight('Save on narration', '${fast.name} costs ${(((main.outputPrice ?? 0) / (fast.outputPrice ?? 1))).toStringAsFixed(0)}× less per output token than ${main.name}. Switch the storyteller for casual sessions.', tip: true));
      }
    }
    return out;
  }

  void reset() {
    total
      ..inputTokens = 0
      ..outputTokens = 0
      ..calls = 0
      ..images = 0
      ..videos = 0
      ..seconds = 0
      ..characters = 0
      ..cost = 0;
    byModel.clear();
    byCategory.clear();
    byDay.clear();
    notifyListeners();
    _save();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = UsageTotals.fromJson(Map<String, dynamic>.from(j['total'] ?? {}));
      total
        ..inputTokens = t.inputTokens
        ..outputTokens = t.outputTokens
        ..calls = t.calls
        ..images = t.images
        ..videos = t.videos
        ..seconds = t.seconds
        ..characters = t.characters
        ..cost = t.cost;
      (j['categories'] as Map? ?? {}).forEach((k, v) => byCategory[k as String] = UsageTotals.fromJson(Map<String, dynamic>.from(v)));
      (j['models'] as Map? ?? {}).forEach((k, v) => byModel[k as String] = UsageTotals.fromJson(Map<String, dynamic>.from(v)));
      (j['days'] as Map? ?? {}).forEach((k, v) => byDay[k as String] = UsageTotals.fromJson(Map<String, dynamic>.from(v)));
    } catch (_) {}
  }

  Future<void> _save() async {
    // Keep only the last 60 days.
    if (byDay.length > 60) {
      final keys = byDay.keys.toList()..sort();
      for (final k in keys.take(byDay.length - 60)) {
        byDay.remove(k);
      }
    }
    await _prefs.setString(
      _key,
      jsonEncode({
        'total': total.toJson(),
        'categories': byCategory.map((k, v) => MapEntry(k, v.toJson())),
        'models': byModel.map((k, v) => MapEntry(k, v.toJson())),
        'days': byDay.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }
}

Map<String, UsageTotals> usageBreakdown(Map<String, num> usage, String dimension) {
  final out = <String, UsageTotals>{};
  for (final key in usage.keys.where((k) => k.startsWith('$dimension:') && k.endsWith(':calls'))) {
    final prefix = key.substring(0, key.length - 6);
    final name = Uri.decodeComponent(prefix.substring(dimension.length + 1));
    out[name] = UsageTotals()
      ..inputTokens = (usage['$prefix:in'] ?? 0).toInt()
      ..outputTokens = (usage['$prefix:out'] ?? 0).toInt()
      ..calls = (usage['$prefix:calls'] ?? 0).toInt()
      ..images = (usage['$prefix:images'] ?? 0).toInt()
      ..videos = (usage['$prefix:videos'] ?? 0).toInt()
      ..seconds = (usage['$prefix:seconds'] ?? 0).toInt()
      ..characters = (usage['$prefix:chars'] ?? 0).toInt()
      ..cost = (usage['$prefix:cost'] ?? 0).toDouble();
  }
  return out;
}

String usageCategoryLabel(String value) => switch (value) {
  'story' => 'Story',
  'npc' => 'Character chats',
  'images' => 'Images',
  'video' => 'Videos',
  'voice' => 'Voices',
  'effects' => 'Special effects',
  'tools' => 'AI tools (recaps, ideas, lore)',
  'character' => 'Character creation',
  _ => value,
};

IconData usageCategoryIcon(String value) => switch (value) {
  'story' => Icons.auto_stories_outlined,
  'npc' => Icons.forum_outlined,
  'images' => Icons.image_outlined,
  'video' => Icons.movie_outlined,
  'voice' => Icons.record_voice_over_outlined,
  'effects' => Icons.auto_awesome_outlined,
  'tools' => Icons.psychology_outlined,
  'character' => Icons.person_add_alt,
  _ => Icons.toll_outlined,
};

/// Short "1.2K tok · $0.004" label for one message, image or video.
String itemCostLabel(num tokens, num cost) => [if (tokens > 0) '${fmtTokens(tokens)} tok', fmtCost(cost.toDouble())].join(' · ');

String fmtCost(double usd) {
  if (usd == 0) return '\$0';
  if (usd < 0.01) return '\$${usd.toStringAsFixed(4)}';
  if (usd < 1) return '\$${usd.toStringAsFixed(3)}';
  return '\$${usd.toStringAsFixed(2)}';
}

String fmtTokens(num n) {
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return '${n.toInt()}';
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/tale_genres.dart';
import '../data/tales/tales.dart';
import '../models/adventure.dart';
import '../models/tale.dart';
import '../models/world.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../services/achievements.dart';
import '../services/app_lifecycle.dart';
import '../services/ai/ai_trace.dart';
import '../services/ai/story_ai.dart';
import '../services/ai/tale_narrator.dart';
import '../services/audio/audio_service.dart';
import '../services/image_service.dart';
import '../services/narrator.dart';
import '../services/settings.dart';
import '../services/tale_store.dart';
import '../services/usage.dart';
import 'module_engine.dart' show matchChoice;
import 'story_host.dart';
import 'approaches.dart';
import 'character_life.dart';
import 'money.dart';

/// Runs a text adventure: handcrafted scenes or an AI narrator.
class TaleController extends ChangeNotifier implements StoryHost {
  TaleController({
    required this.tale,
    required this.settings,
    required this.store,
    required this.audio,
    this.narrator,
    this.usage,
    this.achievements,
    this.images,
  }) : _ai = TaleNarrator(settings),
       storyAi = StoryAi(settings) {
    usage?.sink = tale.usage;
    _castNarrator();
    narrator
      ?..usageTarget = tale.usage
      ..storyTitle = tale.title
      ..storyId = tale.id;
    AppLifecycle.instance.addResumeListener(_resumed);
  }

  /// Images cut off while the app was away are painted again on return.
  void _resumed() {
    if (!_disposed) unawaited(generateMissingImages());
  }

  final Tale tale;
  @override
  final SettingsController settings;
  final TaleStore store;
  final AudioService audio;
  @override
  final Narrator? narrator;
  final UsageTracker? usage;
  final Achievements? achievements;
  @override
  final ImageService? images;
  final TaleNarrator _ai;
  final StoryAi storyAi;
  final _rng = math.Random();

  @override
  bool busy = false;
  String? streaming;
  String? error;
  bool _disposed = false;

  TaleGenre get genre => genreById(tale.genre);
  TalePreset? get preset => taleById(tale.presetId);
  @override
  bool get isAi => tale.engine == TaleEngine.ai;

  // ------------------------------------------------------------ StoryHost

  @override
  String get storyId => tale.id;
  @override
  String get storyTitle => tale.title;
  @override
  String get storySubtitle => '${genre.name}${isAi ? ' · AI' : ''}';
  @override
  StoryRecord get record => tale;
  @override
  WorldData get world => tale;
  @override
  List<Npc> get people => tale.npcs;
  @override
  String get playerName => tale.protagonist == 'You' ? 'you' : tale.protagonist;
  @override
  List<CanonEntry> get canon => tale.canon;
  @override
  String get summary => tale.memory;
  @override
  set summary(String value) => tale.memory = value;
  @override
  Map<String, num> get usageTotals => tale.usage;
  @override
  List<LogEntry> get log => tale.log;
  @override
  SceneInfo get scene => tale.scene;
  @override
  MapState? get map => tale.map;
  @override
  int get turns => tale.turns;
  @override
  String get aiContext =>
      'A ${genre.name} interactive story, "${tale.title}".\n${taleStateBlock(tale)}';
  @override
  String get worldStyle => 'Genre: ${genre.name}. ${genre.style}';
  @override
  String get artStyle => taleArtStyle(genre);
  @override
  String portraitKey(Npc npc) => 'npc_${tale.id}_${npc.id}';
  @override
  void note(String text) {
    if (!isAi) return;
    tale.pendingNotes.add(text);
    if (tale.pendingNotes.length > 20) tale.pendingNotes.removeAt(0);
  }

  @override
  Future<void> act(String text, {List<String> images = const []}) =>
      freeText(text, images: images);

  @override
  Future<void> illustrate(String text, {bool video = false}) {
    images?.resume();
    final short = text.length > 400 ? '${text.substring(0, 400)}…' : text;
    return effect('moment', short, force: true, video: video);
  }

  /// The story before the last AI turn, for regenerating it.
  String? _snapshot;
  int _snapshotLog = 0;

  void _takeSnapshot() {
    _snapshot = jsonEncode(tale.toJson());
    _snapshotLog = tale.log.length;
  }

  @override
  bool get canRegenerate =>
      isAi &&
      _snapshot != null &&
      !busy &&
      !tale.finished &&
      tale.log.length > _snapshotLog;

  @override
  Future<void> regenerate() async {
    if (!canRegenerate) return;
    final action = tale.log[_snapshotLog];
    final restored = Tale.fromJson(
      jsonDecode(_snapshot!) as Map<String, dynamic>,
    );
    tale.restoreFrom(restored);
    _snapshot = null;
    error = null;
    narrator?.stop();
    _notify();
    if (action.kind == LogKind.player) {
      await freeText(action.text);
    } else {
      await retry();
    }
  }

  DateTime _clock = DateTime.now();

  /// Adds the time since the last save to this story's play time.
  void _bankTime() {
    final now = DateTime.now();
    final secs = now.difference(_clock).inSeconds;
    _clock = now;
    if (secs <= 0 || secs > 6 * 3600) return;
    tale.playSeconds += secs;
    // Deferred: this can run while a screen is being torn down.
    final ach = achievements;
    if (ach != null) Future(() => ach.add(Stat.playSeconds, secs));
  }

  @override
  void save() => _save();
  @override
  void refresh() => _notify();

  bool _casting = false;

  /// Lets the AI pick fitting voices for characters who have none.
  Future<void> castVoices() async {
    final n = narrator;
    if (_casting || n == null || _disposed) return;
    _casting = true;
    try {
      await storyAi.assignVoices(this, n);
    } catch (_) {
      // Voices fall back to stable automatic picks.
    } finally {
      _casting = false;
    }
  }

  /// Reference portraits of the characters in [text] (or recently on stage).
  List<(String, String)> faceRefs(String text) {
    final t =
        '${text.toLowerCase()} ${tale.log.reversed.take(6).map((e) => '${e.speaker ?? ''} ${e.text}').join(' ').toLowerCase()}';
    final out = <(String, String)>[];
    for (final n in tale.npcs.reversed) {
      final first = n.name.split(' ').first.toLowerCase();
      final path = n.portrait.aiImagePath;
      if (path != null && first.length >= 3 && t.contains(first))
        out.add((n.name, path));
      if (out.length >= 3) break;
    }
    return out;
  }

  String? _voiceOf(String speaker) {
    final p = tale.personNamed(speaker);
    return p == null ? null : tale.voices[p.id];
  }

  /// Tells the narrator who sounds like what. A character's first automatic
  /// voice is saved, so they keep it for the rest of the story.
  void _castNarrator() {
    final n = narrator;
    if (n == null) return;
    n.voiceResolver = _voiceOf;
    n.genderResolver = (s) => tale.personNamed(s)?.gender ?? '';
    n.usedVoices = () => tale.voices.values.toSet();
    n.onAutoAssign = (s, v) {
      final p = tale.personNamed(s);
      if (p == null || tale.voices[p.id] != null || _disposed) return;
      tale.voices[p.id] = v;
      _save();
    };
  }

  @override
  String? bringCompanion(Companion c) {
    final why = bringCompanionTo(tale, c);
    if (why != null) return why;
    _notify();
    _save();
    return null;
  }

  @override
  Npc meet(String name, {String role = '', String description = ''}) {
    final known = tale.personNamed(name);
    final n = tale.meet(name, role: role, description: description);
    if (known == null) {
      if (description.isNotEmpty) tale.remember('npc', n.name, description);
      if (settings.aiAutoImages && settings.useAiNpcPortraits)
        unawaited(paintPortrait(n));
      _notify();
      _save();
    }
    return n;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Timer? _saveTimer;
  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      settleMoney(this);
      CompanionStore.instance.syncFrom(this);
      store.save(tale);
    });
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _bankTime();
    settleMoney(this);
    CompanionStore.instance.syncFrom(this);
    return store.save(tale);
  }

  @override
  void dispose() {
    _disposed = true;
    AppLifecycle.instance.removeResumeListener(_resumed);
    if (usage?.sink == tale.usage) usage?.sink = null;
    if (narrator?.usageTarget == tale.usage) {
      narrator?.usageTarget = null;
      narrator?.storyTitle = null;
      narrator?.storyId = null;
      narrator?.voiceResolver = null;
      narrator?.genderResolver = null;
      narrator?.onAutoAssign = null;
      narrator?.usedVoices = null;
    }
    narrator?.stop();
    if (_saveTimer?.isActive ?? false) flush();
    super.dispose();
  }

  void _say(String text, {String? speaker}) =>
      narrator?.say(text, speaker: speaker);

  Future<void> start() async {
    audio.music(genre.music);
    audio.ambience(
      tale.scene.title.isEmpty ? genre.ambience : tale.scene.ambience,
    );
    unawaited(castVoices());
    if (tale.log.isNotEmpty) {
      unawaited(generateMissingImages());
      return;
    }
    achievements?.add(Stat.tales);
    if (isAi) {
      await _runAi((t) => _ai.begin(tale, onNarration: _onStream, trace: t));
    } else {
      final p = preset;
      if (p == null) {
        error = 'This story is no longer available.';
        _notify();
        return;
      }
      _enter(p.start);
      _notify();
      _save();
    }
  }

  void _onStream(String partial) {
    streaming = partial;
    _notify();
  }

  // ---------------------------------------------------------------- preset

  bool _gate(String g) {
    final neg = g.startsWith('!');
    final key = neg ? g.substring(1) : g;
    final has = key.startsWith('item:')
        ? tale.inventory.any(
            (i) => i.toLowerCase() == key.substring(5).toLowerCase(),
          )
        : tale.flags.contains(key);
    return neg ? !has : has;
  }

  bool _visible(TaleOption o) =>
      (o.requires == null || _gate(o.requires!)) &&
      (o.unless == null || !_gate(o.unless!));

  void _give(String item) {
    if (tale.inventory.any((i) => i.toLowerCase() == item.toLowerCase()))
      return;
    tale.inventory.add(item);
    tale.log.add(LogEntry(kind: LogKind.loot, text: 'You take: $item'));
    audio.play('coin');
  }

  void _hurt(int amount) {
    if (amount <= 0) return;
    tale.health = (tale.health - amount).clamp(0, 100);
    tale.log.add(
      LogEntry(
        kind: LogKind.combat,
        text:
            '−$amount ${genre.healthLabel.toLowerCase()} (${tale.health}/100)',
        meta: const {'fx': 'hit'},
      ),
    );
    audio.play('hit');
  }

  /// Moves the story to a new place: scene card, map pin, ambience and art.
  void _scene(
    String title, {
    String? location,
    String? time,
    String? mood,
    String? imagePrompt,
  }) {
    final s = tale.scene;
    final changed = title != s.title;
    tale.scene = SceneInfo(
      title: title,
      location: location ?? (changed ? genre.scene : s.location),
      time: time ?? (changed ? genre.time : s.time),
      mood: mood ?? (changed ? 'mystery' : s.mood),
      imagePrompt: imagePrompt ?? (changed ? '' : s.imagePrompt),
      seed: changed ? title.hashCode & 0x7fffffff : s.seed,
    );
    if (!changed) return;
    achievements?.add(Stat.places);
    tale.log.add(
      LogEntry(
        kind: LogKind.system,
        text: title,
        meta: {'scene': tale.scene.toJson()},
      ),
    );
    final m = tale.map ??= MapState(
      kind: MapKind.overworld,
      seed: tale.seed | 1,
      name: tale.title,
    );
    var idx = m.locations.indexWhere(
      (l) => l.name.toLowerCase() == title.toLowerCase(),
    );
    if (idx < 0) {
      m.locations.add(MapLocation(name: title, type: tale.scene.location));
      idx = m.locations.length - 1;
    }
    m.locations[idx].visited = true;
    m.current = idx;
    tale.sceneImagePath = tale.sceneImages[title];
    audio.ambience(tale.scene.ambience);
    if (tale.sceneImagePath == null) unawaited(_maybeSceneArt());
  }

  void _enter(String id) {
    final p = preset!;
    final n = p.nodes[id];
    if (n == null) return;
    tale.node = id;
    final title = n.title;
    if (title != null && title != tale.scene.title) _scene(title);
    tale.log.add(LogEntry(kind: LogKind.narration, text: n.text));
    _say(n.text);
    if (n.gives != null) _give(n.gives!);
    if (n.sets != null) tale.flags.add(n.sets!);
    if (n.status != null) tale.status = n.status!;
    _hurt(n.damage);
    if (n.end != null || tale.health <= 0) {
      _finish(n.end ?? 'bad');
      return;
    }
    tale.choices = [
      for (final (i, o) in n.options.indexed)
        if (_visible(o))
          TaleChoice(
            o.text,
            data: {'i': i, if (o.chance != null) 'risk': o.chance},
          ),
    ];
    if (tale.choices.isEmpty) _finish('neutral');
  }

  void _finish(String ending) {
    tale.finished = true;
    tale.ending = ending;
    tale.choices = [];
    achievements?.add(Stat.talesFinished);
    audio.play(ending == 'bad' ? 'death' : 'levelup');
    audio.music(ending == 'bad' ? 'mystery' : 'triumph');
    unawaited(
      effect(
        ending == 'bad' ? 'defeat' : 'victory',
        'The ending of "${tale.title}": ${tale.log.lastWhere(
          (e) => e.kind == LogKind.narration,
          orElse: () => LogEntry(kind: LogKind.narration, text: tale.title),
        ).text}',
      ),
    );
  }

  // ------------------------------------------------------------------ play

  Future<void> choose(TaleChoice c) async {
    if (busy || tale.finished) return;
    // You moved on: what was still being read aloud is skipped.
    narrator?.stop();
    if (c.data['retry'] == true) {
      tale.choices = [];
      await retry();
      return;
    }
    audio.play('click');
    if (isAi) _takeSnapshot();
    tale.turns++;
    tale.vitals.tick();
    tale.log.add(LogEntry(kind: LogKind.player, text: c.text));
    if (isAi) {
      await _runAi(
        (t) => _ai.act(
          tale,
          'The player chooses: "${c.text}"',
          onNarration: _onStream,
          trace: t,
        ),
      );
      return;
    }
    final node = preset!.nodes[tale.node]!;
    final o = node.options[c.data['i'] as int];
    if (o.takes != null)
      tale.inventory.removeWhere(
        (i) => i.toLowerCase() == o.takes!.toLowerCase(),
      );
    if (o.gives != null) _give(o.gives!);
    if (o.sets != null) tale.flags.add(o.sets!);
    if (o.heal > 0) tale.health = (tale.health + o.heal).clamp(0, 100);
    _hurt(o.damage);
    var next = o.go;
    if (o.chance != null) {
      final ok = _rng.nextDouble() < o.chance!;
      tale.log.add(
        LogEntry(
          kind: LogKind.roll,
          text: ok ? 'Luck is with you.' : 'Luck turns against you.',
          meta: {
            'ok': ok,
            'label': 'Risk',
            'chance': (o.chance! * 100).round(),
          },
        ),
      );
      audio.play(ok ? 'success' : 'fail');
      if (!ok && o.fail != null) next = o.fail!;
    }
    busy = true;
    _notify();
    await Future.delayed(const Duration(milliseconds: 250));
    busy = false;
    _enter(next);
    _notify();
    _save();
    unawaited(_maybeApproach());
  }

  bool _approaching = false;

  /// Someone who likes the player may come to them about what just happened.
  Future<void> _maybeApproach() async {
    if (_approaching ||
        _disposed ||
        !settings.companionApproaches ||
        tale.finished)
      return;
    final a = pickApproach(this);
    if (a == null) return;
    _approaching = true;
    try {
      await deliverApproach(this, a, ai: storyAi);
      if (!_disposed) audio.play('chime');
    } finally {
      _approaching = false;
    }
  }

  /// Free-form action, with any pictures the player attached (file paths).
  Future<void> freeText(String text, {List<String> images = const []}) async {
    var t = text.trim();
    if ((t.isEmpty && images.isEmpty) || busy || tale.finished) return;
    narrator?.stop();
    if (isAi) {
      _takeSnapshot();
      tale.turns++;
      tale.vitals.tick();
      if (t.isEmpty) t = 'I show this.';
      tale.log.add(
        LogEntry(
          kind: LogKind.player,
          text: t,
          meta: {if (images.isNotEmpty) 'images': images},
        ),
      );
      _notify();
      final seen = this.images == null
          ? const <String>[]
          : await this.images!.dataUrls(images);
      final said = seen.isEmpty
          ? 'The player says/does: "$t"'
          : 'The player says/does: "$t" (and shows the attached picture${seen.length == 1 ? '' : 's'}: describe what is in ${seen.length == 1 ? 'it' : 'them'} as the protagonist sees it and let it matter to the story)';
      await _runAi(
        (tr) => _ai.act(
          tale,
          said,
          onNarration: _onStream,
          trace: tr,
          images: seen,
        ),
      );
      return;
    }
    final asChoices = [for (final c in tale.choices) Choice(text: c.text)];
    final m = matchChoice(t, asChoices);
    if (m != null) {
      await choose(tale.choices[asChoices.indexOf(m)]);
    } else {
      tale.log.add(LogEntry(kind: LogKind.player, text: t));
      tale.log.add(
        LogEntry(
          kind: LogKind.system,
          text: 'Pick one of the numbered options, or type part of it.',
        ),
      );
      _notify();
    }
  }

  // -------------------------------------------------------------------- AI

  /// What the storyteller is doing (or last did): steps, context, thinking.
  @override
  AiTrace? aiTrace;

  /// The last AI request, for Retry.
  Future<TaleTurn> Function(AiTrace trace)? _lastAiCall;

  @override
  void stopAi() => aiTrace?.stop();

  @override
  Future<void> retryAi() async {
    final call = _lastAiCall;
    if (call == null || busy) return retry();
    tale.choices = tale.choices.where((c) => c.data['retry'] != true).toList();
    await _runAi(call);
  }

  Future<void> _runAi(Future<TaleTurn> Function(AiTrace trace) call) async {
    if (!settings.useAiText) {
      error = settings.hasApiKey
          ? 'AI story is turned off. Turn it on in Settings to continue this story.'
          : 'This story is narrated by AI. Add an AI key in Settings → AI providers to continue.';
      _notify();
      return;
    }
    _lastAiCall = call;
    final trace = aiTrace = AiTrace(
      label: tale.title,
      model: settings.textModel,
    );
    busy = true;
    error = null;
    streaming = '';
    _notify();
    final epoch = AppLifecycle.instance.epoch;
    try {
      final turn = await call(trace);
      trace.finish(tokens: turn.tokens, cost: turn.cost);
      streaming = null;
      _applyTurn(turn);
      unawaited(castVoices());
      if (tale.aiHistory.length >= 24) {
        if (settings.useAiSummaries) {
          unawaited(_ai.summarize(tale).then((_) => _save()));
        } else {
          tale.aiHistory = tale.aiHistory.sublist(tale.aiHistory.length - 16);
        }
      }
    } catch (e) {
      streaming = null;
      trace.finish(error: trace.stopped ? 'Stopped' : e.toString());
      if (trace.stopped) {
        tale.choices = [
          const TaleChoice('Try again', data: {'retry': true}),
          ...tale.choices.where((c) => c.data['retry'] != true),
        ];
        return;
      }
      if (AppLifecycle.instance.cutOff(e, epoch) && !_disposed) {
        // The phone dropped the connection while the app was in the background:
        // ask again once the player is back instead of showing an error.
        busy = false;
        AppLifecycle.instance.whenForeground(
          () => Future(() {
            if (!_disposed && !busy) unawaited(_runAi(call));
          }),
        );
        return;
      }
      error = e.toString();
      if (tale.choices.isEmpty)
        tale.choices = [
          const TaleChoice('Try again', data: {'retry': true}),
        ];
    } finally {
      busy = false;
      _notify();
      _save();
    }
    if (error == null) unawaited(_maybeApproach());
  }

  void _applyTurn(TaleTurn turn) {
    for (final p in turn.people) {
      final fresh = tale.personNamed(p['name']) == null;
      final n = meet(
        p['name']!,
        role: p['role'] ?? '',
        description: p['description'] ?? '',
      );
      if (normalizeGender(p['gender']).isNotEmpty) n.gender = p['gender']!;
      if (introduceCharacter(tale, n, p, fresh: fresh))
        achievements?.add(Stat.enemies);
    }
    for (final c in turn.characters) {
      final who = tale.personNamed(c['name']);
      if (who == null) continue;
      final changes = growCharacter(tale, who, c, tale.turns);
      if (changes.isNotEmpty)
        tale.log.add(
          LogEntry(
            kind: LogKind.system,
            text: '${who.name} · ${changes.join(' · ')}',
            meta: {'growth': who.id},
          ),
        );
    }
    if (turn.title != null && turn.title != tale.scene.title) {
      _scene(
        turn.title!,
        location: turn.location,
        time: turn.time,
        mood: turn.mood,
        imagePrompt: turn.imagePrompt,
      );
    } else if (turn.imagePrompt != null || turn.mood != null) {
      tale.scene
        ..mood = turn.mood ?? tale.scene.mood
        ..imagePrompt = turn.imagePrompt ?? tale.scene.imagePrompt;
    }
    final speaker = turn.speaker == null
        ? null
        : tale.personNamed(turn.speaker) ?? meet(turn.speaker!);
    tale.log.add(
      LogEntry(
        kind: speaker != null ? LogKind.dialogue : LogKind.narration,
        text: turn.narration,
        speaker: speaker?.name,
        meta: {
          if (turn.tokens > 0) 'tok': turn.tokens,
          if (turn.cost > 0) 'usd': turn.cost,
        },
      ),
    );
    _say(turn.narration, speaker: speaker?.name);
    for (final (name, line) in turn.dialogue) {
      final who = tale.personNamed(name) ?? meet(name);
      tale.log.add(
        LogEntry(kind: LogKind.companion, text: line, speaker: who.name),
      );
      // Character replies follow "Speak chat replies".
      if (settings.speakChatReplies) _say(line, speaker: who.name);
    }
    for (final m in turn.memory) {
      tale.remember(m['kind'] ?? 'fact', m['name'] ?? '', m['text'] ?? '');
    }
    for (final r in turn.relationships) {
      final who = tale.personNamed(r['name']?.toString());
      if (who == null) continue;
      int n(String k) =>
          (r[k] is num ? r[k] as num : num.tryParse('${r[k]}') ?? 0).toInt();
      final status = (r['status'] ?? '').toString().trim();
      _bond(
        who,
        friendship: n('friendship'),
        romance: n('romance'),
        status: status.isEmpty ? null : status,
        reason: (r['reason'] ?? '').toString(),
      );
    }
    for (final g in turn.goals) {
      final title = g['title']!;
      final st = switch (g['status']) {
        'done' || 'completed' => QuestStatus.completed,
        'failed' => QuestStatus.failed,
        _ => QuestStatus.active,
      };
      final desc = (g['description'] ?? '').trim();
      final update = (g['update'] ?? '').trim();
      final existing = tale.goals
          .where((q) => q.title.toLowerCase() == title.toLowerCase())
          .firstOrNull;
      if (existing == null) {
        final q = Quest(
          id: '${tale.goals.length}-${title.hashCode}',
          title: title,
          status: st,
          description: desc,
          startTurn: tale.turns,
          giver: g['giver'] ?? '',
          reward: g['reward'] ?? '',
        );
        q.log(
          update.isNotEmpty ? update : (desc.isNotEmpty ? desc : 'Goal set.'),
          tale.turns,
        );
        tale.goals.add(q);
        tale.log.add(
          LogEntry(
            kind: LogKind.levelup,
            text: 'New goal: $title',
            meta: {
              'quest': {
                'title': title,
                'state': 'new',
                'goal': true,
                if (desc.isNotEmpty) 'desc': desc,
              },
            },
          ),
        );
      } else {
        if (desc.isNotEmpty) existing.description = desc;
        if ((g['giver'] ?? '').isNotEmpty) existing.giver = g['giver']!;
        if ((g['reward'] ?? '').isNotEmpty) existing.reward = g['reward']!;
        if (update.isNotEmpty) existing.log(update, tale.turns);
        if (existing.status != st) {
          existing.status = st;
          if (st != QuestStatus.active) {
            existing.endTurn = tale.turns;
            existing.log(
              st == QuestStatus.completed ? 'Completed.' : 'Failed.',
              tale.turns,
            );
          }
          if (st == QuestStatus.completed) achievements?.add(Stat.goals);
          tale.log.add(
            LogEntry(
              kind: LogKind.levelup,
              text:
                  '${st == QuestStatus.completed ? 'Goal complete' : 'Goal failed'}: $title',
              meta: {
                'quest': {
                  'title': title,
                  'state': st == QuestStatus.completed ? 'done' : 'failed',
                  'goal': true,
                },
              },
            ),
          );
          if (st == QuestStatus.completed) audio.play('levelup');
        } else if (update.isNotEmpty) {
          tale.log.add(
            LogEntry(
              kind: LogKind.levelup,
              text: 'Goal updated: $title',
              meta: {
                'quest': {
                  'title': title,
                  'state': 'update',
                  'goal': true,
                  'desc': update,
                },
              },
            ),
          );
        }
      }
    }
    for (final c in turn.consequences) {
      final kind =
          const {
            'faction',
            'place',
            'promise',
            'fact',
            'clue',
          }.contains(c['kind'])
          ? c['kind']!
          : 'fact';
      final changed = tale.chronicle.record(
        kind: kind,
        name: c['name']!,
        state: c['state']!,
        reason: c['reason'] ?? 'A consequence of the story.',
        chapter: tale.id,
        chapterTitle: tale.title,
        turn: tale.turns,
      );
      if (changed)
        tale.log.add(
          LogEntry(
            kind: LogKind.system,
            text: 'World changed · ${c['name']}: ${c['state']}',
            meta: {'world': true},
          ),
        );
    }
    for (final e in turn.writings.entries) {
      tale.writings[e.key.toLowerCase()] = ItemWriting(
        title: e.key,
        kind: writingKind(e.key),
        text: e.value,
      );
    }
    for (final m in turn.money) {
      final line = applyMoneyEvent(this, m);
      if (line != null) {
        tale.log.add(
          LogEntry(kind: LogKind.loot, text: line, meta: {'money': true}),
        );
        audio.play('coin');
      }
    }
    if (turn.vitals.isNotEmpty) {
      final changes = tale.vitals.apply(turn.vitals);
      if (changes.isNotEmpty)
        tale.log.add(
          LogEntry(
            kind: LogKind.system,
            text: changes.join(' · '),
            meta: {'vitals': true},
          ),
        );
    }
    final award = turn.achievement;
    if (award != null) {
      final a = achievements?.award(
        title: award['title'] ?? '',
        description: award['description'] ?? '',
        icon: award['icon'] ?? 'star',
        story: tale.title,
        storyId: tale.id,
      );
      if (a != null) {
        tale.storyAwards.add(a.title);
        tale.log.add(
          LogEntry(
            kind: LogKind.levelup,
            text: 'Award: ${a.title}',
            meta: {'award': a.toJson()},
          ),
        );
        audio.play('levelup');
      }
    }
    for (final i in turn.add) {
      _give(i);
    }
    for (final i in turn.remove) {
      if (tale.inventory.remove(i))
        tale.log.add(LogEntry(kind: LogKind.loot, text: 'Lost: $i'));
    }
    if (turn.health < 0) _hurt(-turn.health);
    if (turn.health > 0) {
      tale.health = (tale.health + turn.health).clamp(0, 100);
      tale.log.add(
        LogEntry(
          kind: LogKind.loot,
          text:
              '+${turn.health} ${genre.healthLabel.toLowerCase()} (${tale.health}/100)',
        ),
      );
    }
    if (turn.status != null) tale.status = turn.status!;
    if (turn.moment != null) unawaited(effect('moment', turn.moment!));
    if (turn.ending != null || tale.health <= 0) {
      _finish(turn.ending ?? 'bad');
    } else {
      tale.choices = [for (final c in turn.choices.take(5)) TaleChoice(c)];
      if (tale.choices.isEmpty) tale.choices = [const TaleChoice('Continue')];
    }
  }

  /// Retries the last AI request after an error.
  Future<void> retry() async {
    final again = _lastAiCall;
    if (again != null && !busy) {
      tale.choices = tale.choices
          .where((c) => c.data['retry'] != true)
          .toList();
      await _runAi(again);
      return;
    }
    final last =
        tale.aiHistory.isNotEmpty && tale.aiHistory.last.startsWith('P:')
        ? tale.aiHistory.removeLast().substring(2)
        : null;
    if (tale.log
        .where((e) => e.kind == LogKind.narration || e.kind == LogKind.dialogue)
        .isEmpty) {
      await _runAi((t) => _ai.begin(tale, onNarration: _onStream, trace: t));
    } else {
      await _runAi(
        (t) => _ai.act(
          tale,
          last ?? 'Continue the story.',
          onNarration: _onStream,
          trace: t,
        ),
      );
    }
  }

  // ---------------------------------------------------------- characters

  String? _bond(
    Npc npc, {
    int friendship = 0,
    int romance = 0,
    String? status,
    bool? romanceClosed,
    String reason = '',
    bool quiet = false,
  }) {
    final wasRomance = tale.bondFor(npc).romance;
    final wasFriend = tale.bondFor(npc).friendship;
    final change = applyBondChange(
      tale,
      npc,
      friendship: friendship,
      romance: romance,
      status: status,
      romanceClosed: romanceClosed,
      reason: reason,
      turn: tale.turns,
    );
    if (change == null) return null;
    final b = tale.bondFor(npc);
    if (wasRomance < 20 && b.isRomantic) achievements?.add(Stat.romances);
    if (wasFriend < 80 && b.friendship >= 80)
      achievements?.add(Stat.bestFriends);
    if (wasFriend > -65 && b.friendship <= -65) achievements?.add(Stat.enemies);
    tale.log.add(
      LogEntry(
        kind: LogKind.system,
        text: change,
        meta: {
          'bond': npc.id,
          'details': {
            'title': npc.name,
            'subtitle': reason.isEmpty ? 'Relationship' : reason,
            'outcome': b.label,
            'ok': friendship + romance >= 0,
            'lines': [
              ['Friendship', '${b.friendship}/100 · ${b.friendshipLabel}'],
              if (b.romance > 0 || b.romanceClosed)
                ['Romance', '${b.romance}/100 · ${b.romanceLabel}'],
            ],
          },
        },
      ),
    );
    if (!quiet && (romance >= 8 || (wasRomance < 45 && b.romance >= 45))) {
      unawaited(
        effect(
          'romance',
          'A tender moment between the protagonist and ${npc.name}${reason.isEmpty ? '' : ': $reason'}.',
        ),
      );
    }
    return change;
  }

  @override
  Future<ChatLine> talkTo(
    Npc npc,
    String line, {
    List<String> images = const [],
  }) async {
    final chat = tale.chatWith(npc.id);
    if (chat.isNotEmpty && !chat.last.fromPlayer && chat.last.opener.isNotEmpty)
      achievements?.add(Stat.approaches);
    achievements?.add(Stat.chats);
    chat.add(ChatLine(fromPlayer: true, text: line, images: images));
    _notify();
    ChatLine reply;
    if (settings.useAiNpcChat) {
      final model = images.isEmpty && settings.fastModel.isNotEmpty
          ? settings.fastModel
          : settings.textModel;
      final trace = aiTrace =
          AiTrace(label: 'Reply from ${npc.name}', model: model)..step(
            'Gathering the conversation',
            detail: '${chat.length} messages · ${npc.name}',
          );
      _notify();
      late final CharacterReply r;
      try {
        final seen = images.isEmpty || this.images == null
            ? const <String>[]
            : await this.images!.dataUrls(images);
        r = await storyAi.reply(this, npc, line, images: seen, trace: trace);
        trace.finish(tokens: r.tokens, cost: r.cost);
      } catch (e) {
        trace.finish(error: trace.stopped ? 'Stopped' : e.toString());
        rethrow;
      }
      reply = ChatLine(
        fromPlayer: false,
        text: r.text,
        tokens: r.tokens,
        cost: r.cost,
      );
      final change = _bond(
        npc,
        friendship: r.friendship,
        romance: r.romance,
        status: r.status,
        romanceClosed: r.romanceClosed,
        reason:
            'Talking: "${line.length > 60 ? '${line.substring(0, 60)}…' : line}"',
        quiet: true,
      );
      if (r.note.isNotEmpty) {
        npc.notes = '${npc.notes} ${r.note}'.trim();
        tale.profileOf(npc).remember(r.note, turn: tale.turns, source: 'chat');
      }
      if (r.memory.isNotEmpty) tale.remember('npc', npc.name, r.memory);
      note(
        'In a private conversation, the player told ${npc.name}: "$line" and ${npc.name} replied: "${r.text}"${change == null ? '' : ' ($change)'}.',
      );
    } else {
      const lines = [
        'They study you for a long moment and say nothing.',
        '"Not now. Later, maybe."',
        '"Keep your voice down."',
        '"You and me both, friend."',
      ];
      reply = ChatLine(
        fromPlayer: false,
        text: lines[(line.length + chat.length) % lines.length],
      );
    }
    chat.add(reply);
    if (settings.ttsEnabled && settings.speakChatReplies)
      narrator?.say(reply.text, speaker: npc.name);
    _notify();
    _save();
    return reply;
  }

  // -------------------------------------------------------------- media

  int _lastEffectTurn = -10;

  bool get _canPaint => images != null && settings.aiAutoImages;

  Future<void> generateMissingImages() async {
    if (!_canPaint || _disposed) return;
    for (final n in tale.npcs.toList()) {
      if (_disposed) return;
      if (settings.useAiNpcPortraits && n.portrait.aiImagePath == null)
        await paintPortrait(n);
    }
    if (tale.scene.title.isNotEmpty && tale.sceneImagePath == null)
      await _maybeSceneArt();
  }

  String _scenePrompt() {
    final s = tale.scene;
    final what = s.imagePrompt.isNotEmpty
        ? s.imagePrompt
        : '${s.title}, ${s.time}, ${s.mood} mood';
    return 'Wide cinematic establishing shot for a ${genre.name} story: $what. ${tale.premise.isEmpty ? '' : 'Story: ${tale.premise}'}${_castLooks(what)}';
  }

  /// How the people named in a picture look, so they match their portraits.
  String _castLooks(String text) {
    final t = text.toLowerCase();
    final looks = [
      for (final p in tale.npcs)
        if (p.name.split(' ').first.length >= 3 &&
            t.contains(p.name.split(' ').first.toLowerCase()) &&
            p.description.trim().isNotEmpty)
          '${p.name}: ${p.description.trim()}',
    ].take(3);
    return looks.isEmpty ? '' : ' Characters who appear: ${looks.join('; ')}.';
  }

  /// Another painted portrait from this story, so everyone looks drawn alike.
  String? _portraitStyleRef(String excludeId) => tale.npcs
      .where((p) => p.id != excludeId && p.portrait.aiImagePath != null)
      .firstOrNull
      ?.portrait
      .aiImagePath;

  Future<void> _maybeSceneArt({bool force = false}) async {
    final img = images;
    if (img == null ||
        (!force && (!settings.aiAutoImages || settings.sceneArt == 'manual')))
      return;
    final s = tale.scene;
    // Only new kinds of places get new art; similar ones reuse what was painted.
    if (!force && settings.sceneArt == 'places') {
      final reuse = reusableSceneArt(tale.log, tale.sceneImages, s);
      if (reuse != null) {
        tale.sceneImages[s.title] = reuse;
        tale.sceneImagePath = reuse;
        _notify();
        _save();
        return;
      }
    }
    final key = 'scene_${tale.id}_${s.title.hashCode}';
    var video =
        settings.useAiVideo &&
        settings.videoScenes &&
        !img.isSuspended('video');
    var path = video
        ? await img.generateVideo(key, _scenePrompt(), usageTarget: tale.usage)
        : null;
    if (path == null &&
        settings.useAiScenes &&
        !img.isSuspended('image') &&
        !_disposed) {
      video = false;
      path = await img.generate(
        key,
        _scenePrompt(),
        size: '1536x1024',
        usageTarget: tale.usage,
        style: artStyle,
        references: faceRefs(tale.scene.imagePrompt),
        styleReference: latestScenePicture(tale.gallery),
      );
    }
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    if (tale.scene.title == s.title) tale.sceneImagePath = path;
    tale.addMedia(
      MediaItem(
        path: path,
        video: video,
        kind: 'scene',
        caption: s.title,
        turn: tale.turns,
        cost: img.costs[path] ?? 0,
      ),
    );
    _notify();
    _save();
  }

  @override
  Future<void> paintScene() async {
    final img = images;
    if (img == null) return;
    img.resume();
    final s = tale.scene;
    final path = await img.generate(
      'scene_${tale.id}_${s.title.hashCode}',
      _scenePrompt(),
      size: '1536x1024',
      usageTarget: tale.usage,
      style: artStyle,
      references: faceRefs(s.imagePrompt),
      styleReference: latestScenePicture(tale.gallery),
    );
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    tale.sceneImagePath = path;
    tale.addMedia(
      MediaItem(
        path: path,
        kind: 'scene',
        caption: s.title,
        turn: tale.turns,
        cost: img.costs[path] ?? 0,
      ),
    );
    _notify();
    _save();
  }

  @override
  Future<void> filmScene() async {
    final img = images;
    if (img == null) return;
    img.resume();
    final s = tale.scene;
    final path = await img.generateVideo(
      'scene_${tale.id}_${s.title.hashCode}',
      _scenePrompt(),
      usageTarget: tale.usage,
    );
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    tale.sceneImagePath = path;
    tale.addMedia(
      MediaItem(
        path: path,
        video: true,
        kind: 'scene',
        caption: s.title,
        turn: tale.turns,
        cost: img.costs[path] ?? 0,
      ),
    );
    _notify();
    _save();
  }

  @override
  Future<void> paintPortrait(Npc npc) async {
    final img = images;
    if (img == null) return;
    final path = await img.generate(
      portraitKey(npc),
      'Character portrait of ${npc.name}${npc.gender.isEmpty ? '' : ' (${npc.gender})'}${npc.role.isEmpty ? '' : ', ${npc.role}'}, from a ${genre.name} story. ${npc.description} Simple atmospheric background, looking at the viewer.',
      usageTarget: tale.usage,
      style: artStyle,
      styleReference: _portraitStyleRef(npc.id),
    );
    if (path == null || _disposed) return;
    npc.portrait.useAiImage(path);
    tale.addMedia(
      MediaItem(
        path: path,
        kind: 'portrait',
        caption: npc.name,
        turn: tale.turns,
        cost: img.costs[path] ?? 0,
      ),
    );
    _notify();
    _save();
  }

  @override
  Future<void> generateMapImage() async {
    final img = images, m = tale.map;
    if (img == null || m == null) return;
    final path = await img.generate(
      'map_${tale.id}',
      'An illustrated ${genre.name} map or schematic titled "${m.name}", showing: ${m.locations.map((l) => l.name).join(', ')}. Readable layout, no real text.',
      usageTarget: tale.usage,
      style: artStyle,
    );
    if (path == null || _disposed) return;
    m.aiImagePath = path;
    tale.addMedia(
      MediaItem(
        path: path,
        kind: 'map',
        caption: m.name,
        turn: tale.turns,
        cost: img.costs[path] ?? 0,
      ),
    );
    _notify();
    _save();
  }

  @override
  bool canTravelTo(MapLocation location) =>
      isAi && !busy && !tale.finished && location.name != tale.scene.title;

  @override
  Future<void> travelTo(MapLocation location) =>
      freeText('I go back to ${location.name}.');

  /// A special-effect image (or video) for a dramatic beat, if enabled.
  Future<void> effect(
    String moment,
    String description, {
    bool force = false,
    bool? video,
  }) async {
    final img = images;
    if (img == null || _disposed) return;
    if (!force && (!settings.aiAutoImages || !settings.effectOn(moment)))
      return;
    if (!force &&
        tale.turns - _lastEffectTurn < 2 &&
        moment != 'victory' &&
        moment != 'defeat')
      return;
    _lastEffectTurn = tale.turns;
    final prompt =
        'A dramatic, cinematic special-effect moment from a ${genre.name} story: $description Dynamic composition, striking light and motion.';
    final key = 'fx_${tale.id}_${DateTime.now().millisecondsSinceEpoch}';
    var film =
        video ??
        (settings.useAiVideo &&
            settings.videoEffects &&
            !img.isSuspended('video'));
    var path = film
        ? await img.generateVideo(key, prompt, usageTarget: tale.usage)
        : null;
    if (path == null &&
        settings.useAiImages &&
        !img.isSuspended('image') &&
        !_disposed) {
      film = false;
      path = await img.generate(
        key,
        '$prompt${_castLooks(description)}',
        size: '1536x1024',
        usageTarget: tale.usage,
        category: 'effects',
        style: artStyle,
        references: faceRefs(description),
        styleReference: latestScenePicture(tale.gallery),
      );
    }
    if (path == null || _disposed) return;
    final cost = img.costs[path] ?? 0;
    tale.log.add(
      LogEntry(
        kind: LogKind.system,
        text: description,
        meta: {
          'media': path,
          'video': film,
          'moment': moment,
          if (cost > 0) 'usd': cost,
        },
      ),
    );
    tale.addMedia(
      MediaItem(
        path: path,
        video: film,
        kind: 'effect',
        caption: description,
        turn: tale.turns,
        cost: cost,
      ),
    );
    _notify();
    _save();
  }
}

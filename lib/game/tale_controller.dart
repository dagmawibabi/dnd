import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/tale_genres.dart';
import '../data/tales/tales.dart';
import '../models/adventure.dart';
import '../models/tale.dart';
import '../models/world.dart';
import '../services/achievements.dart';
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

/// Runs a text adventure: handcrafted scenes or an AI narrator.
class TaleController extends ChangeNotifier implements StoryHost {
  TaleController({required this.tale, required this.settings, required this.store, required this.audio, this.narrator, this.usage, this.achievements, this.images})
      : _ai = TaleNarrator(settings),
        storyAi = StoryAi(settings) {
    usage?.sink = tale.usage;
    narrator?.voiceResolver = _voiceOf;
    narrator?.usageTarget = tale.usage;
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
  String get aiContext => 'A ${genre.name} interactive story, "${tale.title}".\n${taleStateBlock(tale)}';
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
  Future<void> act(String text) => freeText(text);
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

  String? _voiceOf(String speaker) {
    final p = tale.personNamed(speaker);
    return p == null ? null : tale.voices[p.id];
  }

  @override
  Npc meet(String name, {String role = '', String description = ''}) {
    final known = tale.personNamed(name);
    final n = tale.meet(name, role: role, description: description);
    if (known == null) {
      if (description.isNotEmpty) tale.remember('npc', n.name, description);
      if (settings.aiAutoImages && settings.useAiNpcPortraits) unawaited(paintPortrait(n));
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
    _saveTimer = Timer(const Duration(milliseconds: 500), () => store.save(tale));
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    return store.save(tale);
  }

  @override
  void dispose() {
    _disposed = true;
    if (usage?.sink == tale.usage) usage?.sink = null;
    if (narrator?.usageTarget == tale.usage) {
      narrator?.usageTarget = null;
      narrator?.voiceResolver = null;
    }
    narrator?.stop();
    if (_saveTimer?.isActive ?? false) flush();
    super.dispose();
  }

  void _say(String text, {String? speaker}) => narrator?.say(text, speaker: speaker);

  Future<void> start() async {
    audio.music(genre.music);
    audio.ambience(tale.scene.title.isEmpty ? genre.ambience : tale.scene.ambience);
    unawaited(castVoices());
    if (tale.log.isNotEmpty) {
      unawaited(generateMissingImages());
      return;
    }
    achievements?.add(Stat.tales);
    if (isAi) {
      await _runAi(() => _ai.begin(tale, onNarration: _onStream));
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
    final has = key.startsWith('item:') ? tale.inventory.any((i) => i.toLowerCase() == key.substring(5).toLowerCase()) : tale.flags.contains(key);
    return neg ? !has : has;
  }

  bool _visible(TaleOption o) => (o.requires == null || _gate(o.requires!)) && (o.unless == null || !_gate(o.unless!));

  void _give(String item) {
    if (tale.inventory.any((i) => i.toLowerCase() == item.toLowerCase())) return;
    tale.inventory.add(item);
    tale.log.add(LogEntry(kind: LogKind.loot, text: 'You take: $item'));
    audio.play('coin');
  }

  void _hurt(int amount) {
    if (amount <= 0) return;
    tale.health = (tale.health - amount).clamp(0, 100);
    tale.log.add(LogEntry(kind: LogKind.combat, text: '−$amount ${genre.healthLabel.toLowerCase()} (${tale.health}/100)', meta: const {'fx': 'hit'}));
    audio.play('hit');
  }

  /// Moves the story to a new place: scene card, map pin, ambience and art.
  void _scene(String title, {String? location, String? time, String? mood, String? imagePrompt}) {
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
    tale.log.add(LogEntry(kind: LogKind.system, text: title, meta: {'scene': tale.scene.toJson()}));
    final m = tale.map ??= MapState(kind: MapKind.overworld, seed: tale.seed | 1, name: tale.title);
    var idx = m.locations.indexWhere((l) => l.name.toLowerCase() == title.toLowerCase());
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
        if (_visible(o)) TaleChoice(o.text, data: {'i': i, if (o.chance != null) 'risk': o.chance}),
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
    unawaited(effect(ending == 'bad' ? 'defeat' : 'victory', 'The ending of "${tale.title}": ${tale.log.lastWhere((e) => e.kind == LogKind.narration, orElse: () => LogEntry(kind: LogKind.narration, text: tale.title)).text}'));
  }

  // ------------------------------------------------------------------ play

  Future<void> choose(TaleChoice c) async {
    if (busy || tale.finished) return;
    if (c.data['retry'] == true) {
      tale.choices = [];
      await retry();
      return;
    }
    audio.play('click');
    tale.turns++;
    tale.log.add(LogEntry(kind: LogKind.player, text: c.text));
    if (isAi) {
      await _runAi(() => _ai.act(tale, 'The player chooses: "${c.text}"', onNarration: _onStream));
      return;
    }
    final node = preset!.nodes[tale.node]!;
    final o = node.options[c.data['i'] as int];
    if (o.takes != null) tale.inventory.removeWhere((i) => i.toLowerCase() == o.takes!.toLowerCase());
    if (o.gives != null) _give(o.gives!);
    if (o.sets != null) tale.flags.add(o.sets!);
    if (o.heal > 0) tale.health = (tale.health + o.heal).clamp(0, 100);
    _hurt(o.damage);
    var next = o.go;
    if (o.chance != null) {
      final ok = _rng.nextDouble() < o.chance!;
      tale.log.add(LogEntry(kind: LogKind.roll, text: ok ? 'Luck is with you.' : 'Luck turns against you.', meta: {'ok': ok, 'label': 'Risk', 'chance': (o.chance! * 100).round()}));
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
  }

  Future<void> freeText(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy || tale.finished) return;
    if (isAi) {
      tale.turns++;
      tale.log.add(LogEntry(kind: LogKind.player, text: t));
      _notify();
      await _runAi(() => _ai.act(tale, 'The player says/does: "$t"', onNarration: _onStream));
      return;
    }
    final asChoices = [for (final c in tale.choices) Choice(text: c.text)];
    final m = matchChoice(t, asChoices);
    if (m != null) {
      await choose(tale.choices[asChoices.indexOf(m)]);
    } else {
      tale.log.add(LogEntry(kind: LogKind.player, text: t));
      tale.log.add(LogEntry(kind: LogKind.system, text: 'Pick one of the numbered options, or type part of it.'));
      _notify();
    }
  }

  // -------------------------------------------------------------------- AI

  Future<void> _runAi(Future<TaleTurn> Function() call) async {
    if (!settings.useAiText) {
      error = settings.hasApiKey ? 'AI story is turned off. Turn it on in Settings to continue this story.' : 'This story is narrated by AI. Add an AI key in Settings → AI providers to continue.';
      _notify();
      return;
    }
    busy = true;
    error = null;
    streaming = '';
    _notify();
    try {
      final turn = await call();
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
      error = e.toString();
      streaming = null;
      if (tale.choices.isEmpty) tale.choices = [const TaleChoice('Try again', data: {'retry': true})];
    } finally {
      busy = false;
      _notify();
      _save();
    }
  }

  void _applyTurn(TaleTurn turn) {
    for (final p in turn.people) {
      meet(p['name']!, role: p['role'] ?? '', description: p['description'] ?? '');
    }
    if (turn.title != null && turn.title != tale.scene.title) {
      _scene(turn.title!, location: turn.location, time: turn.time, mood: turn.mood, imagePrompt: turn.imagePrompt);
    } else if (turn.imagePrompt != null || turn.mood != null) {
      tale.scene
        ..mood = turn.mood ?? tale.scene.mood
        ..imagePrompt = turn.imagePrompt ?? tale.scene.imagePrompt;
    }
    final speaker = turn.speaker == null ? null : tale.personNamed(turn.speaker) ?? meet(turn.speaker!);
    tale.log.add(LogEntry(
      kind: speaker != null ? LogKind.dialogue : LogKind.narration,
      text: turn.narration,
      speaker: speaker?.name,
      meta: {if (turn.tokens > 0) 'tok': turn.tokens, if (turn.cost > 0) 'usd': turn.cost},
    ));
    _say(turn.narration, speaker: speaker?.name);
    for (final (name, line) in turn.dialogue) {
      final who = tale.personNamed(name) ?? meet(name);
      tale.log.add(LogEntry(kind: LogKind.companion, text: line, speaker: who.name));
      _say(line, speaker: who.name);
    }
    for (final m in turn.memory) {
      tale.remember(m['kind'] ?? 'fact', m['name'] ?? '', m['text'] ?? '');
    }
    for (final r in turn.relationships) {
      final who = tale.personNamed(r['name']?.toString());
      if (who == null) continue;
      int n(String k) => (r[k] is num ? r[k] as num : num.tryParse('${r[k]}') ?? 0).toInt();
      final status = (r['status'] ?? '').toString().trim();
      _bond(who, friendship: n('friendship'), romance: n('romance'), status: status.isEmpty ? null : status, reason: (r['reason'] ?? '').toString());
    }
    for (final g in turn.goals) {
      final title = g['title']!;
      final st = switch (g['status']) { 'done' || 'completed' => QuestStatus.completed, 'failed' => QuestStatus.failed, _ => QuestStatus.active };
      final existing = tale.goals.where((q) => q.title.toLowerCase() == title.toLowerCase()).firstOrNull;
      if (existing == null) {
        tale.goals.add(Quest(id: '${tale.goals.length}-${title.hashCode}', title: title, status: st));
        tale.log.add(LogEntry(kind: LogKind.levelup, text: 'New goal: $title', meta: {'quest': {'title': title, 'state': 'new', 'goal': true}}));
      } else if (existing.status != st) {
        existing.status = st;
        tale.log.add(LogEntry(kind: LogKind.levelup, text: '${st == QuestStatus.completed ? 'Goal complete' : 'Goal failed'}: $title', meta: {'quest': {'title': title, 'state': st == QuestStatus.completed ? 'done' : 'failed', 'goal': true}}));
        if (st == QuestStatus.completed) audio.play('levelup');
      }
    }
    for (final i in turn.add) {
      _give(i);
    }
    for (final i in turn.remove) {
      if (tale.inventory.remove(i)) tale.log.add(LogEntry(kind: LogKind.loot, text: 'Lost: $i'));
    }
    if (turn.health < 0) _hurt(-turn.health);
    if (turn.health > 0) {
      tale.health = (tale.health + turn.health).clamp(0, 100);
      tale.log.add(LogEntry(kind: LogKind.loot, text: '+${turn.health} ${genre.healthLabel.toLowerCase()} (${tale.health}/100)'));
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
    final last = tale.aiHistory.isNotEmpty && tale.aiHistory.last.startsWith('P:') ? tale.aiHistory.removeLast().substring(2) : null;
    if (tale.log.where((e) => e.kind == LogKind.narration || e.kind == LogKind.dialogue).isEmpty) {
      await _runAi(() => _ai.begin(tale, onNarration: _onStream));
    } else {
      await _runAi(() => _ai.act(tale, last ?? 'Continue the story.', onNarration: _onStream));
    }
  }

  // ---------------------------------------------------------- characters

  String? _bond(Npc npc, {int friendship = 0, int romance = 0, String? status, bool? romanceClosed, String reason = '', bool quiet = false}) {
    final wasRomance = tale.bondFor(npc).romance;
    final change = applyBondChange(tale, npc, friendship: friendship, romance: romance, status: status, romanceClosed: romanceClosed, reason: reason, turn: tale.turns);
    if (change == null) return null;
    final b = tale.bondFor(npc);
    tale.log.add(LogEntry(kind: LogKind.system, text: change, meta: {
      'bond': npc.id,
      'details': {
        'title': npc.name,
        'subtitle': reason.isEmpty ? 'Relationship' : reason,
        'outcome': b.label,
        'ok': friendship + romance >= 0,
        'lines': [
          ['Friendship', '${b.friendship}/100 · ${b.friendshipLabel}'],
          if (b.romance > 0 || b.romanceClosed) ['Romance', '${b.romance}/100 · ${b.romanceLabel}'],
        ],
      },
    }));
    if (!quiet && (romance >= 8 || (wasRomance < 45 && b.romance >= 45))) {
      unawaited(effect('romance', 'A tender moment between the protagonist and ${npc.name}${reason.isEmpty ? '' : ': $reason'}.'));
    }
    return change;
  }

  @override
  Future<ChatLine> talkTo(Npc npc, String line) async {
    final chat = tale.chatWith(npc.id);
    chat.add(ChatLine(fromPlayer: true, text: line));
    _notify();
    ChatLine reply;
    if (settings.useAiNpcChat) {
      final r = await storyAi.reply(this, npc, line);
      reply = ChatLine(fromPlayer: false, text: r.text, tokens: r.tokens, cost: r.cost);
      final change = _bond(npc, friendship: r.friendship, romance: r.romance, status: r.status, romanceClosed: r.romanceClosed, reason: 'Talking: "${line.length > 60 ? '${line.substring(0, 60)}…' : line}"', quiet: true);
      if (r.note.isNotEmpty) npc.notes = '${npc.notes} ${r.note}'.trim();
      if (r.memory.isNotEmpty) tale.remember('npc', npc.name, r.memory);
      note('In a private conversation, the player told ${npc.name}: "$line" and ${npc.name} replied: "${r.text}"${change == null ? '' : ' ($change)'}.');
    } else {
      const lines = ['They study you for a long moment and say nothing.', '"Not now. Later, maybe."', '"Keep your voice down."', '"You and me both, friend."'];
      reply = ChatLine(fromPlayer: false, text: lines[(line.length + chat.length) % lines.length]);
    }
    chat.add(reply);
    if (settings.ttsEnabled && settings.speakChatReplies) narrator?.say(reply.text, speaker: npc.name);
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
      if (settings.useAiNpcPortraits && n.portrait.aiImagePath == null) await paintPortrait(n);
    }
    if (tale.scene.title.isNotEmpty && tale.sceneImagePath == null) await _maybeSceneArt();
  }

  String _scenePrompt() {
    final s = tale.scene;
    final what = s.imagePrompt.isNotEmpty ? s.imagePrompt : '${s.title}, ${s.time}, ${s.mood} mood';
    return 'Wide cinematic establishing shot for a ${genre.name} story: $what. ${tale.premise.isEmpty ? '' : 'Story: ${tale.premise}'}';
  }

  Future<void> _maybeSceneArt({bool force = false}) async {
    final img = images;
    if (img == null || (!force && !settings.aiAutoImages)) return;
    final s = tale.scene;
    final key = 'scene_${tale.id}_${s.title.hashCode}';
    var video = settings.useAiVideo && settings.videoScenes && !img.isSuspended('video');
    var path = video ? await img.generateVideo(key, _scenePrompt(), usageTarget: tale.usage) : null;
    if (path == null && settings.useAiScenes && !img.isSuspended('image') && !_disposed) {
      video = false;
      path = await img.generate(key, _scenePrompt(), size: '1536x1024', usageTarget: tale.usage, style: artStyle);
    }
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    if (tale.scene.title == s.title) tale.sceneImagePath = path;
    tale.addMedia(MediaItem(path: path, video: video, kind: 'scene', caption: s.title, turn: tale.turns, cost: img.costs[path] ?? 0));
    _notify();
    _save();
  }

  @override
  Future<void> paintScene() async {
    final img = images;
    if (img == null) return;
    img.resume();
    final s = tale.scene;
    final path = await img.generate('scene_${tale.id}_${s.title.hashCode}', _scenePrompt(), size: '1536x1024', usageTarget: tale.usage, style: artStyle);
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    tale.sceneImagePath = path;
    tale.addMedia(MediaItem(path: path, kind: 'scene', caption: s.title, turn: tale.turns, cost: img.costs[path] ?? 0));
    _notify();
    _save();
  }

  @override
  Future<void> filmScene() async {
    final img = images;
    if (img == null) return;
    img.resume();
    final s = tale.scene;
    final path = await img.generateVideo('scene_${tale.id}_${s.title.hashCode}', _scenePrompt(), usageTarget: tale.usage);
    if (path == null || _disposed) return;
    tale.sceneImages[s.title] = path;
    tale.sceneImagePath = path;
    tale.addMedia(MediaItem(path: path, video: true, kind: 'scene', caption: s.title, turn: tale.turns, cost: img.costs[path] ?? 0));
    _notify();
    _save();
  }

  @override
  Future<void> paintPortrait(Npc npc) async {
    final img = images;
    if (img == null) return;
    final path = await img.generate(
      portraitKey(npc),
      'Character portrait of ${npc.name}${npc.role.isEmpty ? '' : ', ${npc.role}'}, from a ${genre.name} story. ${npc.description} Simple atmospheric background, looking at the viewer.',
      usageTarget: tale.usage,
      style: artStyle,
    );
    if (path == null || _disposed) return;
    npc.portrait.aiImagePath = path;
    tale.addMedia(MediaItem(path: path, kind: 'portrait', caption: npc.name, turn: tale.turns, cost: img.costs[path] ?? 0));
    _notify();
    _save();
  }

  @override
  Future<void> generateMapImage() async {
    final img = images, m = tale.map;
    if (img == null || m == null) return;
    final path = await img.generate('map_${tale.id}', 'An illustrated ${genre.name} map or schematic titled "${m.name}", showing: ${m.locations.map((l) => l.name).join(', ')}. Readable layout, no real text.', usageTarget: tale.usage, style: artStyle);
    if (path == null || _disposed) return;
    m.aiImagePath = path;
    tale.addMedia(MediaItem(path: path, kind: 'map', caption: m.name, turn: tale.turns, cost: img.costs[path] ?? 0));
    _notify();
    _save();
  }

  @override
  bool canTravelTo(MapLocation location) => isAi && !busy && !tale.finished && location.name != tale.scene.title;

  @override
  Future<void> travelTo(MapLocation location) => freeText('I go back to ${location.name}.');

  /// A special-effect image (or video) for a dramatic beat, if enabled.
  Future<void> effect(String moment, String description, {bool force = false}) async {
    final img = images;
    if (img == null || _disposed) return;
    if (!force && (!settings.aiAutoImages || !settings.effectOn(moment))) return;
    if (!force && tale.turns - _lastEffectTurn < 2 && moment != 'victory' && moment != 'defeat') return;
    _lastEffectTurn = tale.turns;
    final prompt = 'A dramatic, cinematic special-effect moment from a ${genre.name} story: $description Dynamic composition, striking light and motion.';
    final key = 'fx_${tale.id}_${DateTime.now().millisecondsSinceEpoch}';
    var video = settings.useAiVideo && settings.videoEffects && !img.isSuspended('video');
    var path = video ? await img.generateVideo(key, prompt, usageTarget: tale.usage) : null;
    if (path == null && settings.useAiImages && !img.isSuspended('image') && !_disposed) {
      video = false;
      path = await img.generate(key, prompt, size: '1536x1024', usageTarget: tale.usage, category: 'effects', style: artStyle);
    }
    if (path == null || _disposed) return;
    final cost = img.costs[path] ?? 0;
    tale.log.add(LogEntry(kind: LogKind.system, text: description, meta: {'media': path, 'video': video, 'moment': moment, if (cost > 0) 'usd': cost}));
    tale.addMedia(MediaItem(path: path, video: video, kind: 'effect', caption: description, turn: tale.turns, cost: cost));
    _notify();
    _save();
  }
}

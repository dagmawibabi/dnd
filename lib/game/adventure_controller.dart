import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../art/map_painter.dart';
import '../data/srd.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import '../data/inventory_rules.dart';
import '../data/progression.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../services/achievements.dart';
import '../services/app_lifecycle.dart';
import '../services/ai/ai_trace.dart';
import '../services/ai/dungeon_master.dart';
import '../services/ai/gateway_client.dart';
import '../services/audio/audio_service.dart';
import '../services/audio/synth.dart';
import '../services/game_store.dart';
import '../services/image_service.dart';
import '../services/narrator.dart';
import '../services/settings.dart';
import '../services/usage.dart';
import 'combat.dart';
import 'approaches.dart';
import 'character_life.dart';
import 'money.dart';
import 'campaign_world.dart';
import 'dice.dart';
import 'module_engine.dart';
import 'offline_engine.dart';
import 'oracle.dart';
import '../data/companions.dart';
import '../data/tables.dart';
import 'story.dart';
import 'story_host.dart';
import '../models/world.dart';
import '../services/ai/story_ai.dart';

/// A roll the UI must perform with the interactive dice before continuing.
class PendingRoll {
  PendingRoll({
    required this.label,
    required this.modifier,
    this.dc,
    this.mode = RollMode.normal,
    required this.onResult,
    this.sides = 20,
    this.subtitle = '',
  });
  final String label;
  final String subtitle;
  final int modifier;
  final int? dc;
  final RollMode mode;
  final int sides;
  final FutureOr<void> Function(int natural) onResult;
}

class AdventureController extends ChangeNotifier implements StoryHost {
  AdventureController({
    required this.adventure,
    required this.settings,
    required this.store,
    required this.audio,
    required this.images,
    this.usage,
    this.narrator,
    this.achievements,
  }) : dm = AiDungeonMaster(settings),
       storyAi = StoryAi(settings) {
    usage?.current = adventure;
    _castNarrator();
    narrator
      ?..usageTarget = adventure.usage
      ..storyTitle = adventure.title
      ..storyId = adventure.id;
    _imageSettings = _imageSettingsKey;
    settings.addListener(_imagesSettingsChanged);
    seedCompanionArcs(adventure);
    AppLifecycle.instance.addResumeListener(_resumed);
  }

  /// Images cut off while the app was away are painted again on return.
  void _resumed() {
    if (!_disposed) unawaited(generateMissingImages());
  }

  Adventure adventure;
  final UsageTracker? usage;
  @override
  final Narrator? narrator;
  final Achievements? achievements;

  /// Opens a merchant (set by the screen).
  void Function(String kind, String name)? openShop;

  /// State before the last player action, for rewind.
  String? _snapshot;
  int _snapshotLogLength = 0;
  @override
  final SettingsController settings;
  final GameStore store;
  final AudioService audio;
  @override
  final ImageService images;
  final AiDungeonMaster dm;
  final StoryAi storyAi;

  // ------------------------------------------------------------ StoryHost

  @override
  String get storyId => adventure.id;
  @override
  String get storyTitle => adventure.title;
  @override
  String get storySubtitle => '${adventure.setting} · ${adventure.tone}';
  @override
  StoryRecord get record => adventure;
  @override
  WorldData get world => adventure;
  @override
  List<Npc> get people => adventure.people;
  @override
  String get playerName => hero.name;
  @override
  List<CanonEntry> get canon => adventure.canon;
  @override
  String get summary => adventure.memory;
  @override
  set summary(String value) => adventure.memory = value;
  @override
  Map<String, num> get usageTotals => adventure.usage;
  @override
  List<LogEntry> get log => adventure.log;
  @override
  SceneInfo get scene => adventure.scene;
  @override
  MapState? get map => adventure.map;
  @override
  int get turns => adventure.turns;
  @override
  String get aiContext =>
      'A solo ${adventure.setting} D&D adventure, "${adventure.title}": ${adventure.premise}\n${dmStateBlock(adventure)}';
  @override
  String get worldStyle =>
      'The world is ${adventure.setting} Dungeons & Dragons, with a ${adventure.tone.toLowerCase()} tone.';
  @override
  String get artStyle => artStyleFor(adventure.setting);
  @override
  void note(String text) => _note(text);
  @override
  Future<void> act(String text, {List<String> images = const []}) =>
      freeText(text, images: images);

  @override
  Future<void> illustrate(String text, {bool video = false}) {
    images.resume();
    final short = text.length > 400 ? '${text.substring(0, 400)}…' : text;
    return effect('moment', short, force: true, video: video);
  }

  @override
  bool get canRegenerate => isAi && canRewind;

  @override
  Future<void> regenerate() async {
    if (!canRegenerate) return;
    final action = adventure.log.length > _snapshotLogLength
        ? adventure.log[_snapshotLogLength]
        : null;
    final text = action?.kind == LogKind.player ? action!.text : null;
    rewind();
    if (text != null) await freeText(text);
  }

  DateTime _clock = DateTime.now();

  /// Adds the time since the last save to this story's play time.
  void _bankTime() {
    final now = DateTime.now();
    final secs = now.difference(_clock).inSeconds;
    _clock = now;
    if (secs <= 0 || secs > 6 * 3600) return;
    adventure.playSeconds += secs;
    // Deferred: this can run while a screen is being torn down.
    final ach = achievements;
    if (ach != null) Future(() => ach.add(Stat.playSeconds, secs));
  }

  @override
  String portraitKey(Npc npc) => 'npc_${adventure.id}_${npc.id}';

  @override
  Future<void> paintPortrait(Npc npc) async {
    final c = adventure.companions.where((c) => c.id == npc.id).firstOrNull;
    if (c != null) return generateCompanionPortrait(c);
    final real = adventure.npcs.where((n) => n.id == npc.id).firstOrNull ?? npc;
    return generateNpcPortrait(real);
  }

  @override
  Future<void> paintScene() {
    images.resume();
    return regenerateSceneImage();
  }

  @override
  Future<void> filmScene() async {
    images.resume();
    await _sceneVideo(force: true);
  }

  @override
  bool canTravelTo(MapLocation location) {
    final m = adventure.map;
    if (m == null || inCombat || busy) return false;
    final current =
        m.locations.isNotEmpty &&
        m.locations[m.current.clamp(0, m.locations.length - 1)] == location;
    return !current && (isAi || travelChoiceFor(location.name) != null);
  }

  @override
  Future<void> travelTo(MapLocation location) async {
    if (isAi) return freeText('I travel to ${location.name}.');
    final c = travelChoiceFor(location.name);
    if (c != null) await choose(c);
  }

  @override
  String? bringCompanion(Companion c) {
    final why = bringCompanionTo(adventure, c);
    if (why != null) return why;
    _notify();
    save();
    return null;
  }

  @override
  Npc meet(String name, {String role = '', String description = ''}) {
    final known = adventure.personNamed(name);
    if (known != null) return known;
    final npc = Npc(
      id: newId(),
      name: name.trim(),
      role: role,
      description: description,
      portrait: PortraitSpec.random('human', seed: stableHash(name)),
    );
    adventure.npcs.add(npc);
    adventure.remember('npc', npc.name, description);
    if (settings.aiAutoImages && settings.useAiNpcPortraits)
      unawaited(generateNpcPortrait(npc));
    _notify();
    save();
    return npc;
  }

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

  /// Reference portraits for a picture: the hero, then party members and
  /// people named in [text] (or the whole party for scenes).
  List<(String, String)> faceRefs(String text, {bool party = false}) {
    final t = text.toLowerCase();
    bool named(String name) {
      final first = name.split(' ').first.toLowerCase();
      return first.length >= 3 && t.contains(first);
    }

    final out = <(String, String)>[];
    void add(String name, String? path) {
      if (path != null && path.isNotEmpty && !out.any((r) => r.$1 == name))
        out.add((name, path));
    }

    add(hero.name, hero.portrait.aiImagePath);
    for (final c in adventure.companions) {
      if (party || named(c.name)) add(c.name, c.portrait.aiImagePath);
    }
    for (final n in adventure.npcs) {
      if (named(n.name)) add(n.name, n.portrait.aiImagePath);
    }
    return out.take(3).toList();
  }

  String? _voiceOf(String speaker) {
    final p = adventure.personNamed(speaker);
    return p == null ? null : adventure.voices[p.id];
  }

  /// Tells the narrator who sounds like what. A character's first automatic
  /// voice is saved, so they keep it for the rest of the story.
  void _castNarrator() {
    final n = narrator;
    if (n == null) return;
    n.voiceResolver = _voiceOf;
    n.genderResolver = (s) => adventure.personNamed(s)?.gender ?? '';
    n.usedVoices = () => adventure.voices.values.toSet();
    n.onAutoAssign = (s, v) {
      final p = adventure.personNamed(s);
      if (p == null || adventure.voices[p.id] != null || _disposed) return;
      adventure.voices[p.id] = v;
      save();
    };
  }

  @override
  bool busy = false;
  String? streaming;
  String? error;
  PendingRoll? pendingRoll;
  bool pendingLevelUp = false;
  bool combatBusy = false;
  bool _wasBoss = false;
  String? lastAnimatedId;
  final Set<String> animated = {};
  List<CombatEvent> lastCombatEvents = [];
  String? flashTargetId;
  bool _disposed = false;
  late String _imageSettings;
  String get _imageSettingsKey =>
      '${settings.useAiImages}:${settings.aiAutoImages}:${settings.aiPortraits}:${settings.aiNpcPortraits}:${settings.aiCompanionPortraits}:${settings.aiScenes}:${settings.aiMaps}:${settings.imageModel}';
  void _imagesSettingsChanged() {
    final key = _imageSettingsKey;
    if (key == _imageSettings || _disposed) return;
    _imageSettings = key;
    unawaited(generateMissingImages());
  }

  @override
  bool get isAi => adventure.engine == StoryEngine.ai;
  Character get hero => adventure.hero;
  CombatEngine? get combat =>
      adventure.combat == null ? null : CombatEngine(adventure);
  bool get inCombat => adventure.combat != null;

  @override
  void dispose() {
    _disposed = true;
    AppLifecycle.instance.removeResumeListener(_resumed);
    settings.removeListener(_imagesSettingsChanged);
    if (_saveTimer?.isActive ?? false) flush();
    if (usage?.current == adventure) usage?.current = null;
    if (narrator?.usageTarget == adventure.usage) {
      narrator?.usageTarget = null;
      narrator?.storyTitle = null;
      narrator?.storyId = null;
      narrator?.voiceResolver = null;
      narrator?.genderResolver = null;
      narrator?.onAutoAssign = null;
      narrator?.usedVoices = null;
    }
    narrator?.stop();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Timer? _saveTimer;

  /// Saves are coalesced: serializing a long adventure on every event is costly.
  @override
  Future<void> save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      settleMoney(this);
      CompanionStore.instance.syncFrom(this);
      store.saveAdventure(adventure);
    });
    return Future.value();
  }

  /// Writes immediately (used when leaving the adventure).
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _bankTime();
    settleMoney(this);
    CompanionStore.instance.syncFrom(this);
    return store.saveAdventure(adventure);
  }

  @override
  void refresh() => _notify();

  void _haptic() {
    if (settings.haptics) HapticFeedback.lightImpact();
  }

  void _stat(String key, [int by = 1]) => achievements?.add(key, by);

  /// Queues something the AI didn't narrate, so its next reply knows about it.
  void _note(String text) {
    if (!isAi) return;
    adventure.pendingNotes.add(text);
    if (adventure.pendingNotes.length > 20) adventure.pendingNotes.removeAt(0);
  }

  // --------------------------------------------------------------- rewind

  void _takeSnapshot() {
    if (adventure.hardcore) return;
    _snapshot = jsonEncode(adventure.toJson());
    _snapshotLogLength = adventure.log.length;
  }

  bool get canRewind =>
      _snapshot != null &&
      !adventure.hardcore &&
      !busy &&
      !inCombat &&
      pendingRoll == null &&
      adventure.log.length > _snapshotLogLength;

  /// Restores the adventure to just before the last action.
  void rewind() {
    final snap = _snapshot;
    if (snap == null || !canRewind) return;
    final restored = Adventure.fromJson(
      jsonDecode(snap) as Map<String, dynamic>,
    );
    // Rewinding game state must never rewind billed usage or pending charges,
    // paid-for results, or choices the player made outside the turn.
    restored.usage = adventure.usage;
    restored.aiNotes = adventure.aiNotes;
    restored.itemImages = adventure.itemImages;
    restored.narratorTone = adventure.narratorTone;
    restored.wrapUpTurn = adventure.wrapUpTurn;
    adventure = restored;
    usage?.current = adventure;
    _snapshot = null;
    pendingLevelUp = false;
    error = null;
    streaming = null;
    narrator?.stop();
    audio.play('page');
    _syncMusic();
    _notify();
    save();
  }

  // --------------------------------------------------------------- oracle

  final Oracle _oracle = Oracle();

  OracleResult askOracle(String question, Likelihood likelihood) {
    final r = _oracle.ask(likelihood, adventure.chaos);
    adventure.log.add(
      LogEntry(
        kind: LogKind.oracle,
        text: r.answer,
        meta: {
          'q': question,
          'roll': r.roll,
          'likelihood': likelihood.label,
          'chance': r.chance,
          'event': ?r.event,
          'meaning': ?r.meaning,
          'details': {
            'title': 'Oracle',
            'subtitle': question.isEmpty ? 'A question to fate' : question,
            'outcome': r.answer,
            'ok': r.yes,
            'groups': [
              {
                'label': 'd100',
                'dice': [
                  {'s': 100, 'v': r.roll},
                ],
                'mod': 0,
                'total': r.roll,
                'against': '≤ ${r.chance} for Yes',
              },
            ],
            'lines': [
              ['Likelihood', likelihood.label],
              ['Chaos factor', '${adventure.chaos} / 9'],
              ['Chance of yes', '${r.chance}%'],
              [
                'Exceptional',
                'Yes on ≤ ${(r.chance / 5).ceil()}, No on > ${100 - ((100 - r.chance) / 5).floor()}',
              ],
              if (r.event != null) ['Random event', r.event!],
              if (r.meaning != null) ['Meaning', r.meaning!],
            ],
            'rule': 'The oracle answers yes/no questions for solo play. Likelihood sets the base chance and the chaos factor shifts it: higher chaos makes surprising answers and random events (doubles at or below chaos) more common.',
          },
        },
      ),
    );
    if (isAi) {
      _note(
        'The player asked the oracle "$question" (${likelihood.label}) and the answer was ${r.answer}.${r.event != null ? ' Random event: ${r.event}, meaning "${r.meaning}". Introduce it.' : ''} Treat it as true.',
      );
    }
    adventure.remember(
      'fact',
      'Oracle: ${question.length > 40 ? '${question.substring(0, 40)}…' : question}',
      r.answer,
    );
    _stat(Stat.oracle);
    audio.play(r.event != null ? 'thunder' : 'chime');
    _notify();
    save();
    return r;
  }

  void setChaos(int v) {
    adventure.chaos = v.clamp(1, 9);
    _notify();
    save();
  }

  // ---------------------------------------------------------------- start

  Future<void> start() async {
    _syncMusic();
    // A portrait made after the adventure began lives on the saved character.
    final saved = store.character(hero.id);
    if (saved?.portrait.aiImagePath != null &&
        hero.portrait.aiImagePath == null) {
      hero.portrait.aiImagePath = saved!.portrait.aiImagePath;
    }
    for (final entry in adventure.log) {
      if (entry.kind == LogKind.narration || entry.kind == LogKind.dialogue) {
        try {
          entry.text = readableNarration(entry.text);
        } on FormatException {
          // Keep the original for recovery; the reader shows a retry message.
        }
      }
    }
    for (final name in [
      for (final e in adventure.log)
        if (e.speaker != null &&
            (e.kind == LogKind.dialogue || e.kind == LogKind.companion))
          e.speaker!,
      for (final c in adventure.canon)
        if (c.kind == 'npc') c.name,
    ]) {
      if (name.trim().isEmpty ||
          name == hero.name ||
          adventure.personNamed(name) != null)
        continue;
      final fact = adventure.canon
          .where((c) => c.kind == 'npc' && c.name == name)
          .firstOrNull;
      adventure.npcs.add(
        Npc(
          id: newId(),
          name: name,
          description: fact?.text ?? '',
          portrait: PortraitSpec.random('human'),
        ),
      );
    }
    unawaited(generateMissingImages());
    unawaited(castVoices());
    if (adventure.log.isNotEmpty) {
      _notify();
      save();
      if (inCombat) _continueCombat();
      return;
    }
    _stat(Stat.adventures);
    if (isAi) {
      if (_aiBlocked()) return;
      await _runAi(
        (t) => dm.begin(adventure, onNarration: _onStream, trace: t),
      );
    } else if (isModule) {
      _apply(ModuleEngine(adventure).begin());
    } else {
      if (adventure.offline.isEmpty) {
        adventure.offline = OfflineEngine.createState(
          adventure.coverSeed,
          hero,
        );
      }
      _apply(OfflineEngine(adventure).begin());
    }
  }

  bool get isModule => adventure.engine == StoryEngine.module;

  /// The available choice that travels to [location], if any.
  Choice? travelChoiceFor(String location) {
    final m = adventure.map;
    if (m == null || busy || inCombat) return null;
    if (isModule) {
      final mod = ModuleEngine(adventure).mod;
      for (final c in adventure.choices) {
        final go = c.data['go'];
        if (go is String && mod.nodes[go]?.mapLoc == location) return c;
      }
      return null;
    }
    final idx = m.locations.indexWhere((l) => l.name == location);
    if (idx != m.current + 1) return null;
    return adventure.choices.where((c) => c.data['a'] == 'next').firstOrNull;
  }

  /// AI adventures need AI story enabled; explain instead of failing.
  bool _aiBlocked() {
    if (settings.useAiText) return false;
    error = settings.hasApiKey
        ? 'AI story is turned off. Turn it on in Settings → AI to continue this adventure.'
        : 'This adventure uses the AI Dungeon Master. Add an AI Gateway key in Settings to continue.';
    _notify();
    return true;
  }

  void _onStream(String partial) {
    streaming = partial;
    _notify();
  }

  /// The last AI request, so one cut off by leaving the app can run again.
  Future<DmTurn> Function(AiTrace trace)? _lastAiCall;

  /// What the storyteller is doing (or last did): steps, context, thinking.
  @override
  AiTrace? aiTrace;

  /// Stops the storyteller mid-reply.
  @override
  void stopAi() => aiTrace?.stop();

  @override
  Future<void> retryAi() async {
    if (busy) return;
    if (_lastAiCall != null) return retryLast();
    await _askAgain();
  }

  /// Asks the storyteller again without the original request (after the app
  /// was reopened): the player's last action, or the opening scene.
  Future<void> _askAgain() async {
    final last =
        adventure.aiHistory.isNotEmpty &&
            adventure.aiHistory.last.startsWith('P:')
        ? adventure.aiHistory.removeLast().substring(2)
        : null;
    adventure.choices = adventure.choices.where((c) => c.data['retry'] != true).toList();
    if (adventure.log.where((e) => e.kind == LogKind.narration).isEmpty) {
      adventure.choices = [];
      await start();
    } else {
      await _runAi(
        (t) => dm.act(
          adventure,
          last ?? 'Continue the story.',
          onNarration: _onStream,
          trace: t,
        ),
      );
    }
  }

  Future<void> _runAi(Future<DmTurn> Function(AiTrace trace) call) async {
    _lastAiCall = call;
    final trace = aiTrace = AiTrace(
      label: adventure.title,
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
      _apply(turn);
      unawaited(castVoices());
      if (adventure.aiHistory.length >= 24) {
        if (settings.useAiSummaries) {
          unawaited(dm.summarize(adventure).then((_) => save()));
        } else {
          adventure.aiHistory = adventure.aiHistory.sublist(
            adventure.aiHistory.length - 16,
          );
        }
      }
    } catch (e) {
      streaming = null;
      trace.finish(error: trace.stopped ? 'Stopped' : e.toString());
      if (trace.stopped) {
        // Stopped on purpose: no error, just the way to ask again.
        adventure.choices = [
          Choice(
            text: 'Try again',
            type: ChoiceType.action,
            data: {'retry': true},
          ),
          ...adventure.choices.where((c) => c.data['retry'] != true),
        ];
        return;
      }
      if (AppLifecycle.instance.cutOff(e, epoch) && !_disposed) {
        // The phone closed the connection while the app was in the background:
        // ask again once the player is back instead of showing an error.
        busy = false;
        // Deferred so this attempt's cleanup runs first.
        AppLifecycle.instance.whenForeground(
          () => Future(() {
            if (!_disposed && !busy) unawaited(_runAi(call));
          }),
        );
        return;
      }
      error = e.toString();
      if (adventure.choices.isEmpty) {
        adventure.choices = [
          Choice(
            text: 'Try again',
            type: ChoiceType.action,
            data: {'retry': true},
          ),
        ];
      }
    } finally {
      busy = false;
      _notify();
      save();
    }
  }

  /// Repeats the last AI request after an error (the player's action is kept).
  Future<void> retryLast() async {
    final call = _lastAiCall;
    if (call == null || busy) return;
    adventure.choices = adventure.choices
        .where((c) => c.data['retry'] != true)
        .toList();
    await _runAi(call);
  }

  // --------------------------------------------------------------- choices

  Future<void> choose(Choice c) async {
    if (busy || inCombat) return;
    // You moved on: what was still being read aloud is skipped.
    narrator?.stop();
    audio.play('click');
    if (c.data['shop'] != null) {
      openShop?.call(
        c.data['shop'].toString(),
        (c.data['name'] ?? 'Merchant').toString(),
      );
      return;
    }
    if (c.data['retry'] != true) _takeSnapshot();
    if (c.data['retry'] == true && _lastAiCall != null) {
      await retryLast();
      return;
    }
    if (c.data['retry'] == true) {
      await _askAgain();
      return;
    }
    adventure.log.add(LogEntry(kind: LogKind.player, text: c.text));
    final check = c.check;
    if (check != null) {
      final mod = check.save
          ? hero.saveMod(check.ability)
          : (check.skill != null
                ? hero.skillMod(check.skill!)
                : hero.mod(check.ability));
      final heavy =
          hero.encumbrance >= 2 &&
          const {Ability.str, Ability.dex, Ability.con}.contains(check.ability);
      final mode = hero.conditions.contains('Poisoned') || heavy
          ? RollMode.disadvantage
          : (hero.inspiration ? RollMode.advantage : RollMode.normal);
      pendingRoll = PendingRoll(
        label: check.save
            ? '${check.ability.full} Save'
            : '${check.label} Check',
        subtitle: c.text,
        modifier: mod,
        dc: check.dc,
        mode: mode,
        onResult: (nat) => _resolveChoiceRoll(c, check, mod, mode, nat),
      );
      _notify();
      return;
    }
    await _proceed(c, null);
  }

  Future<void> _resolveChoiceRoll(
    Choice c,
    CheckSpec check,
    int mod,
    RollMode mode,
    int natural,
  ) async {
    pendingRoll = null;
    if (mode == RollMode.advantage && hero.inspiration)
      hero.inspiration = false;
    final roll = rollD20(
      modifier: mod,
      mode: mode,
      dc: check.dc,
      label: '${check.label} check',
      forcedNatural: natural,
    );
    _stat(Stat.checks);
    if (roll.success) _stat(Stat.checksPassed);
    if (roll.isFumble) _stat(Stat.nat1s);
    if (roll.isCrit) _stat(Stat.nat20Checks);
    final abilityMod = hero.mod(check.ability);
    final prof = check.save
        ? mod - abilityMod
        : (check.skill == null ? 0 : mod - abilityMod);
    adventure.log.add(
      LogEntry(
        kind: LogKind.roll,
        text: roll.describe(),
        meta: {
          'nat': roll.natural,
          'total': roll.total,
          'dc': check.dc,
          'ok': roll.success,
          'label': check.label,
          'details': {
            'title': '${check.label} check',
            'subtitle': c.text,
            'outcome': roll.isCrit
                ? 'Natural 20 · success'
                : (roll.isFumble
                      ? 'Natural 1 · failure'
                      : (roll.success ? 'Success' : 'Failure')),
            'ok': roll.success,
            'groups': [
              d20Group('d20 + modifier', roll, against: 'DC ${check.dc}'),
            ],
            'lines': [
              ['${check.ability.full} modifier', signed(abilityMod)],
              if (check.skill != null || check.save)
                ['Proficiency', prof == 0 ? 'Not proficient' : signed(prof)],
              [
                'Difficulty',
                'DC ${check.dc} (${check.dc <= 10
                    ? 'easy'
                    : check.dc <= 13
                    ? 'medium'
                    : check.dc <= 16
                    ? 'hard'
                    : 'very hard'})',
              ],
              if (mode != RollMode.normal)
                [
                  'Roll mode',
                  mode == RollMode.advantage
                      ? 'Advantage (Inspiration)'
                      : 'Disadvantage (Poisoned)',
                ],
            ],
            'rule': 'Ability check: roll a d20, add the ability modifier and your proficiency bonus if you are proficient in the skill. Meet or beat the DC to succeed. In this game a natural 20 always succeeds and a natural 1 always fails.',
          },
        },
      ),
    );
    audio.play(
      roll.isCrit
          ? 'crit'
          : roll.isFumble
          ? 'fumble'
          : roll.success
          ? 'success'
          : 'fail',
    );
    _notify();
    await _proceed(c, roll);
  }

  /// Removes conditions whose duration has run out.
  void _expireConditions() {
    for (final ch in adventure.party) {
      final gone = ch.conditionUntil.entries
          .where((e) => e.value <= adventure.turns)
          .map((e) => e.key)
          .toList();
      for (final name in gone) {
        ch.conditionUntil.remove(name);
        if (ch.conditions.remove(name)) {
          _sys('${ch.name} is no longer $name.', kind: LogKind.system);
          _note('${ch.name} is no longer $name.');
        }
      }
    }
  }

  Future<void> _proceed(Choice c, D20Result? roll) async {
    adventure.turns++;
    adventure.vitals.tick();
    _expireConditions();
    _stat(Stat.turns);
    if (!isAi) _offlineApproval(c);
    if (isAi) {
      if (_aiBlocked()) return;
      final rollText = roll == null ? '' : ' Roll: ${roll.describe()}.';
      await _runAi(
        (t) => dm.act(
          adventure,
          'The hero chooses: "${c.text}".$rollText',
          onNarration: _onStream,
          trace: t,
        ),
      );
    } else {
      busy = true;
      _notify();
      await Future.delayed(const Duration(milliseconds: 350));
      busy = false;
      _apply(
        isModule
            ? ModuleEngine(adventure).choose(c, roll)
            : OfflineEngine(adventure).choose(c, roll),
      );
    }
  }

  /// Free-form action typed by the player, with any pictures they attached
  /// (file paths) for the storyteller to look at.
  Future<void> freeText(String text, {List<String> images = const []}) async {
    var t = text.trim();
    if ((t.isEmpty && images.isEmpty) || busy || inCombat) return;
    narrator?.stop();
    final lower = t.toLowerCase();
    if (images.isEmpty && _handleCommand(lower)) return;
    if (isAi) {
      if (_aiBlocked()) return;
      _takeSnapshot();
      if (t.isEmpty) t = 'I show this.';
      adventure.log.add(
        LogEntry(
          kind: LogKind.player,
          text: t,
          meta: {if (images.isNotEmpty) 'images': images},
        ),
      );
      adventure.turns++;
      adventure.vitals.tick();
      _stat(Stat.turns);
      _notify();
      final seen = await this.images.dataUrls(images);
      final said = seen.isEmpty
          ? 'The hero says/does: "$t"'
          : 'The hero says/does: "$t" (and shows the attached picture${seen.length == 1 ? '' : 's'}: describe what is in ${seen.length == 1 ? 'it' : 'them'} as the hero sees it and let it matter to the story)';
      await _runAi(
        (tr) => dm.act(
          adventure,
          said,
          onNarration: _onStream,
          trace: tr,
          images: seen,
        ),
      );
      return;
    }
    final match = matchChoice(t, adventure.choices);
    if (match != null) {
      await choose(match);
    } else {
      adventure.log.add(LogEntry(kind: LogKind.player, text: t));
      adventure.log.add(
        LogEntry(
          kind: LogKind.system,
          text: 'The offline storyteller can\'t interpret that. Pick a numbered option, or try: look, inventory, stats, rest, roll 2d6, help.',
        ),
      );
      _notify();
    }
  }

  bool _handleCommand(String t) {
    void sys(String s) {
      adventure.log.add(LogEntry(kind: LogKind.player, text: t));
      adventure.log.add(LogEntry(kind: LogKind.system, text: s));
      _notify();
    }

    if (t == 'help' || t == '?') {
      sys(
        'Commands: 1-9 (choose), look, inventory (i), stats, quests, rest, roll <dice> (e.g. roll 1d20+3), oracle <question>, rewind, memory, export, help.${isAi ? ' Anything else is sent to the Dungeon Master as your action.' : ''}',
      );
      return true;
    }
    if (t == 'i' || t == 'inv' || t == 'inventory') {
      sys(
        'You carry: ${hero.inventory.map((i) => i.qty > 1 ? '${i.name} ×${i.qty}' : i.name).join(', ')}. Gold: ${hero.gold}.',
      );
      return true;
    }
    if (t == 'stats' || t == 'status' || t == 'hp') {
      sys(
        '${hero.name} — Level ${hero.level} ${hero.raceLabel} ${hero.classSummary}. HP ${hero.hp}/${hero.maxHp}, AC ${hero.armorClass}. ${Ability.values.map((a) => '${a.short} ${hero.score(a)}').join(' · ')}. XP ${hero.xp}/${hero.xpForNext}.',
      );
      return true;
    }
    if (t == 'quests' || t == 'journal') {
      sys(
        adventure.quests.isEmpty
            ? 'No quests yet.'
            : adventure.quests
                  .map(
                    (q) => '• ${q.title} [${q.status.name}] ${q.description}',
                  )
                  .join('\n'),
      );
      return true;
    }
    if (t == 'look' || t == 'l') {
      final last = adventure.log.lastWhere(
        (e) => e.kind == LogKind.narration,
        orElse: () => LogEntry(kind: LogKind.system, text: 'Nothing to see.'),
      );
      sys('${adventure.scene.title}: ${last.text}');
      return true;
    }
    if (t.startsWith('roll')) {
      final expr = t.substring(4).trim();
      final r = DiceExpression.parse(expr.isEmpty ? '1d20' : expr).roll();
      audio.play('dice');
      sys('🎲 ${r.expression}: ${r.breakdown} = ${r.total}');
      return true;
    }
    if (t == 'rest' && !isAi) {
      sys(_shortRestAll());
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- apply

  void _apply(DmTurn turn) {
    if (turn.title != null && turn.title!.isNotEmpty && adventure.turns == 0)
      adventure.title = turn.title!;
    if (turn.scene != null) {
      final s = turn.scene!;
      final changed =
          s.title != adventure.scene.title ||
          s.location != adventure.scene.location;
      s.seed = changed
          ? stableHash('${s.title}${s.location}')
          : adventure.scene.seed;
      if (s.title.isEmpty) s.title = adventure.scene.title;
      adventure.scene = s;
      if (changed) {
        adventure.log.add(
          LogEntry(
            kind: LogKind.system,
            text: s.title,
            meta: {'scene': s.toJson()},
          ),
        );
        adventure.sceneImagePath = null;
        _stat(Stat.places);
        _maybeSceneImage();
      }
      _syncMusic();
    }
    if (turn.narration.isNotEmpty) {
      final e = LogEntry(
        kind: turn.speaker != null ? LogKind.dialogue : LogKind.narration,
        text: turn.narration,
        speaker: turn.speaker,
        meta: {
          if (turn.tokens > 0) 'tok': turn.tokens,
          if (turn.cost > 0) 'usd': turn.cost,
        },
      );
      adventure.log.add(e);
      lastAnimatedId = '${e.at.microsecondsSinceEpoch}';
      narrator?.say(turn.narration, speaker: turn.speaker);
    }
    for (final (name, line) in turn.banter) {
      adventure.log.add(
        LogEntry(kind: LogKind.companion, text: line, speaker: name),
      );
      // Party remarks are character replies: they follow "Speak chat replies".
      if (settings.speakChatReplies) narrator?.say(line, speaker: name);
    }
    for (final m in turn.memory) {
      adventure.remember(m['kind'] ?? 'fact', m['name'] ?? '', m['text'] ?? '');
    }
    for (final (name, change, reason) in turn.approval) {
      final c = _target(name);
      if (c != null && c != hero) _changeLoyalty(c, change, reason);
    }
    adventure.choices = turn.choices;
    final combatEvents = <Map<String, dynamic>>[];
    for (final ev in turn.events) {
      if (ev['type'] == 'combat') {
        combatEvents.add(ev);
      } else {
        _applyEvent(ev);
      }
    }
    // Models sometimes introduce speakers without emitting an NPC event.
    for (final name in [
      if (turn.speaker != null) turn.speaker!,
      for (final b in turn.banter) b.$1,
      for (final m in turn.memory)
        if (m['kind'] == 'npc') m['name'] ?? '',
    ]) {
      if (name.trim().isEmpty ||
          name == hero.name ||
          adventure.personNamed(name) != null)
        continue;
      final fact = turn.memory.where((m) => m['name'] == name).firstOrNull;
      final npc = Npc(
        id: newId(),
        name: name,
        description: fact?['text'] ?? '',
        portrait: PortraitSpec.random('human'),
      );
      adventure.npcs.add(npc);
      if (settings.aiAutoImages && settings.useAiNpcPortraits)
        unawaited(generateNpcPortrait(npc));
    }
    if (_pendingShop != null) {
      adventure.choices = [
        _pendingShop!,
        ...adventure.choices.where((c) => c.data['shop'] == null),
      ];
      _pendingShop = null;
    }
    if (combatEvents.isNotEmpty) {
      _beginCombat(combatEvents.first);
    } else if (adventure.choices.isEmpty && !adventure.finished) {
      adventure.choices = [Choice(text: 'Continue', type: ChoiceType.explore)];
    }
    _checkLevelUp();
    _notify();
    save();
    unawaited(_maybeApproach());
  }

  bool _approaching = false;

  /// A companion or friend may come to the player about what just happened.
  Future<void> _maybeApproach({bool atCamp = false}) async {
    if (_approaching ||
        _disposed ||
        !settings.companionApproaches ||
        inCombat ||
        hero.dead ||
        adventure.finished)
      return;
    final a = pickApproach(
      this,
      close: {for (final c in adventure.companions) c.id},
      atCamp: atCamp,
    );
    if (a == null) return;
    _approaching = true;
    try {
      await deliverApproach(this, a, ai: storyAi);
      if (!_disposed) audio.play('chime');
    } finally {
      _approaching = false;
    }
  }

  Choice? _pendingShop;

  /// A hazard the party must resist: the app rolls each saving throw.
  void _savingThrowEvent(Map<String, dynamic> e) {
    Ability ab;
    try {
      ab = AbilityX.fromShort((e['ability'] ?? 'DEX').toString());
    } catch (_) {
      ab = Ability.dex;
    }
    final dc = ((e['dc'] ?? 12) as num).toInt().clamp(5, 30);
    final reason = (e['reason'] ?? 'danger').toString();
    final targets = (e['target'] ?? 'hero') == 'party'
        ? adventure.party.toList()
        : [_target(e['target']) ?? hero];
    final dmgExpr = e['damage']?.toString();
    final half = e['half'] != false;
    final cond = e['condition']?.toString();
    final turns = ((e['turns'] ?? 0) as num).toInt();
    final dmgRoll = dmgExpr == null
        ? null
        : DiceExpression.parse(dmgExpr).roll();
    for (final t in targets) {
      final mode = t.conditions.contains('Blessed')
          ? RollMode.advantage
          : RollMode.normal;
      final r = rollD20(
        modifier: t.saveMod(ab),
        mode: mode,
        dc: dc,
        label: '${ab.short} save',
      );
      final before = t.hp;
      var dealt = 0;
      if (dmgRoll != null) {
        final amount = r.success
            ? (half ? dmgRoll.total ~/ 2 : 0)
            : dmgRoll.total;
        dealt = t.takeDamage(amount);
        if (t.hp <= 0) t.hp = 1;
      }
      if (!r.success && cond != null && cond.isNotEmpty) {
        t.conditions.add(cond);
        if (turns > 0) t.conditionUntil[cond] = adventure.turns + turns;
      }
      _stat(Stat.checks);
      if (r.success) _stat(Stat.checksPassed);
      _sys(
        '${t.name} ${r.success ? 'resists' : 'fails to resist'} $reason. [${ab.short} save ${r.total} vs DC $dc]${dealt > 0 ? ' $dealt damage.' : ''}${!r.success && cond != null ? ' $cond${turns > 0 ? ' for $turns turns' : ''}.' : ''}',
        kind: LogKind.roll,
        meta: {
          'nat': r.natural,
          'total': r.total,
          'dc': dc,
          'ok': r.success,
          'label': '${ab.short} save',
          'details': {
            'title': '${ab.full} saving throw',
            'subtitle': '${t.name} vs $reason',
            'outcome': r.success
                ? (dealt > 0 ? 'Saved · half damage ($dealt)' : 'Saved')
                : 'Failed${dealt > 0 ? ' · $dealt damage' : ''}${cond != null ? ' · $cond' : ''}',
            'ok': r.success,
            'groups': [
              d20Group('d20 + save', r, against: 'DC $dc'),
              if (dmgRoll != null)
                diceGroup(
                  'Damage',
                  dmgRoll,
                  suffix: e['damage_type']?.toString(),
                ),
            ],
            'lines': [
              ['${ab.full} save', signed(t.saveMod(ab))],
              if (dmgRoll != null) ['HP', hpChange(before, t.hp, t.maxHp)],
              if (!r.success && cond != null)
                ['Condition', '$cond${turns > 0 ? ' for $turns turns' : ''}'],
            ],
            'rule': 'Saving throw: roll a d20 and add your ability modifier, plus proficiency if your class is proficient in that save. Meet the DC to resist the effect.',
          },
        },
      );
      audio.play(r.success ? 'success' : 'hit');
    }
  }

  // ---------------------------------------------------------- shops

  bool buyItem(ItemDef def, int price) {
    if (hero.gold < price) return false;
    hero.gold -= price;
    final existing = hero.inventory
        .where((i) => i.itemId == def.id)
        .firstOrNull;
    final bundle = (def.id == 'arrows' || def.id == 'bolts') ? 20 : 1;
    if (existing != null &&
        (def.type == ItemType.potion ||
            def.type == ItemType.food ||
            def.type == ItemType.gear ||
            def.type == ItemType.scroll)) {
      existing.qty += bundle;
    } else {
      hero.inventory.add(InventoryItem.of(def.id, qty: bundle));
    }
    _stat(Stat.purchases);
    _stat(Stat.items);
    if (def.isMagic) {
      _stat(Stat.magicItems);
      adventure.remember(
        'item',
        def.name,
        '${def.rarity} magic item bought by ${hero.name}.',
      );
    }
    _note(
      '${hero.name} bought ${def.name} for $price gp (${hero.gold} gp left).',
    );
    logMoney(this, -price.toDouble(), category: 'purchase', note: def.name);
    _sys(
      'Bought ${def.name} for $price gp',
      kind: LogKind.loot,
      meta: {
        'details': {
          'title': def.name,
          'subtitle': 'Purchase',
          'outcome': '−$price gp',
          'ok': true,
          'lines': [
            ['Purse', '${hero.gold} gp left'],
            if (def.isMagic)
              [
                'Rarity',
                '${def.rarity}${def.attune ? ' · requires attunement' : ''}',
              ],
            if ((def.effect ?? '').isNotEmpty) ['Effect', def.effect!],
            if (def.description.isNotEmpty) ['Description', def.description],
          ],
          'rule': def.attune
              ? 'Attune to a magic item from your character sheet (Inventory). You can be attuned to at most 3 items.'
              : 'Equip weapons and armor from your character sheet.',
        },
      },
    );
    audio.play('coin');
    _notify();
    save();
    return true;
  }

  void sellItem(InventoryItem item, int price) {
    item.qty--;
    if (item.qty <= 0) hero.inventory.remove(item);
    hero.gold += price;
    logMoney(this, price.toDouble(), category: 'sale', note: item.name);
    _sys('Sold ${item.name} for $price gp', kind: LogKind.loot);
    _note('${hero.name} sold ${item.name} for $price gp.');
    audio.play('coin');
    _notify();
    save();
  }

  bool get canDowntime =>
      !inCombat &&
      !busy &&
      pendingRoll == null &&
      !hero.dead &&
      (adventure.chronicle.lastActivityChapter != adventure.id ||
          adventure.chronicle.lastActivityTurn != adventure.turns);

  void _spendDowntime(String activity, String result) {
    adventure.chronicle.lastActivityChapter = adventure.id;
    adventure.chronicle.lastActivityTurn = adventure.turns;
    adventure.chronicle.day++;
    rememberWorld(
      adventure,
      'camp',
      'Last camp activity',
      'Day ${adventure.chronicle.day}: $result',
      '${hero.name} chose $activity at ${adventure.scene.title}.',
    );
  }

  /// Spend a little time in town. Returns a short result for the UI.
  String downtime(String activity) {
    if (!canDowntime)
      return 'You have already spent this stretch of time. Continue the story first.';
    if (!const {
      'work',
      'carouse',
      'train',
      'craft',
      'research',
    }.contains(activity))
      return 'Choose a camp activity.';
    if (const {'work', 'carouse', 'research'}.contains(activity) &&
        !const {
          'town',
          'tavern',
          'temple',
          'castle',
        }.contains(adventure.scene.location)) {
      return 'Visit a town, tavern, temple or castle for this activity.';
    }
    if (activity == 'craft' && hero.gold < 25)
      return 'You need 25 gp of herbs and glass.';
    if (activity == 'carouse' && hero.gold < 5)
      return 'You need 5 gp to carouse.';
    _takeSnapshot();
    final r = Rng.unseeded();
    String out;
    switch (activity) {
      case 'work':
        final skill = [
          Skill.athletics,
          Skill.performance,
          Skill.persuasion,
          Skill.sleightOfHand,
        ].reduce((x, y) => hero.skillMod(x) >= hero.skillMod(y) ? x : y);
        final roll = rollD20(modifier: hero.skillMod(skill), dc: 12);
        final pay = roll.success
            ? 5 + r.range(2, 12) + (roll.total - 12).clamp(0, 10)
            : r.range(1, 4);
        hero.gold += pay;
        _stat(Stat.gold, pay);
        logMoney(this, pay.toDouble(), category: 'wage', note: 'A day\'s work');
        out = roll.success
            ? "A good day's work (${skill.label} ${roll.total}): you earn $pay gp."
            : 'A rough day (${skill.label} ${roll.total}). You scrape together $pay gp.';
      case 'carouse':
        final cost = 5;
        if (hero.gold < cost) return 'You need $cost gp to carouse.';
        hero.gold -= cost;
        logMoney(
          this,
          -cost.toDouble(),
          category: 'purchase',
          note: 'Rounds at the tavern',
        );
        final rumor = tableById('rumor')!.roll(r);
        final name = tableById('names')!.roll(r);
        adventure.remember('lore', 'Rumor from $name', rumor);
        out = 'You spend $cost gp buying rounds. $name leans in: "$rumor"';
      case 'train':
        hero.inspiration = true;
        out = 'You drill your techniques until dusk. You gain Inspiration (advantage on your next check).';
      case 'craft':
        const cost = 25;
        if (hero.gold < cost) return 'You need $cost gp of herbs and glass.';
        hero.gold -= cost;
        logMoney(
          this,
          -cost.toDouble(),
          category: 'purchase',
          note: 'Herbs and glass',
        );
        final roll = rollD20(
          modifier: math.max(
            hero.skillMod(Skill.medicine),
            hero.skillMod(Skill.arcana),
          ),
          dc: 13,
        );
        if (roll.success) {
          hero.inventory.add(InventoryItem.of('potion_healing'));
          out = 'You brew a Potion of Healing (${roll.total} vs DC 13).';
        } else {
          out =
              'The mixture curdles (${roll.total} vs DC 13). The ingredients are lost.';
        }
      case 'research':
        final roll = rollD20(
          modifier: math.max(
            hero.skillMod(Skill.history),
            hero.skillMod(Skill.investigation),
          ),
          dc: 12,
        );
        final q = adventure.quests
            .where((q) => q.status == QuestStatus.active)
            .firstOrNull;
        if (roll.success) {
          final clue = q == null
              ? tableById('hook')!.roll(r)
              : 'Old records mention ${q.title.toLowerCase()}: ${tableById('dungeon')!.roll(r).toLowerCase()}';
          adventure.remember(
            'clue',
            q == null ? 'A lead in the archives' : 'Clue: ${q.title}',
            clue,
          );
          out = 'Your research pays off (${roll.total}). $clue';
        } else {
          out =
              'Hours among dusty shelves turn up nothing useful (${roll.total} vs DC 12).';
        }
      default:
        return 'Nothing happens.';
    }
    _spendDowntime(activity, out);
    _sys(
      out,
      kind: LogKind.loot,
      meta: {
        'details': {
          'title': 'Downtime',
          'subtitle': activity[0].toUpperCase() + activity.substring(1),
          'outcome': out,
          'ok': true,
          'rule': 'Downtime lets you work, train, craft or research between scenes. You can do one activity each turn.',
        },
      },
    );
    _note('Downtime ($activity): $out');
    audio.play('page');
    _notify();
    save();
    unawaited(_maybeApproach(atCamp: true));
    return out;
  }

  // ------------------------------------------------------------ loyalty

  /// A camp conversation is useful offline too, and can unlock a personal quest.
  String spendTimeWith(Character c) {
    if (!canDowntime || !adventure.companions.contains(c) || c.dead)
      return 'Continue the story before spending more time at camp.';
    _takeSnapshot();
    _changeLoyalty(c, 5, 'You made time to listen at camp.');
    final person = adventure.personNamed(c.name);
    if (person != null)
      _bond(person, friendship: 5, reason: 'Time together at camp');
    seedCompanionArcs(adventure);
    final result = 'You listen to ${c.name}. +5 loyalty and +5 friendship.';
    _spendDowntime('Time with ${c.name}', result);
    _note(result);
    _notify();
    save();
    unawaited(_maybeApproach(atCamp: true));
    return result;
  }

  /// A small off-screen expedition supports personal arcs in every story mode.
  String pursueCompanionLead(Character c) {
    final arc = adventure.chronicle.arcs[c.id];
    if (!canDowntime ||
        !adventure.companions.contains(c) ||
        c.dead ||
        arc == null ||
        arc.ended ||
        arc.stage == 'choice')
      return 'There is no available lead right now.';
    _takeSnapshot();
    final roll = rollD20(
      modifier: math.max(
        hero.skillMod(Skill.investigation),
        hero.skillMod(Skill.survival),
      ),
      dc: 12,
    );
    arc.stage = 'pursuing';
    if (roll.success) arc.progress = (arc.progress + 1).clamp(0, 2);
    final result = roll.success
        ? 'You and ${c.name} follow a lead toward ${arc.title} (${roll.total} vs DC 12). ${arc.progress}/2 leads secured.'
        : 'You and ${c.name} follow a false trail (${roll.total} vs DC 12). The day is spent, but the quest remains open.';
    if (arc.progress >= 2) arc.stage = 'choice';
    rememberWorld(
      adventure,
      'companion',
      c.name,
      '${arc.title}: ${arc.stage}, ${arc.progress}/2 leads.',
      result,
    );
    _spendDowntime('Pursue ${arc.title}', result);
    _sys(result, kind: LogKind.roll);
    _note(result);
    _notify();
    save();
    return result;
  }

  String resolveCompanionArc(Character c, {required bool fulfill}) {
    final arc = adventure.chronicle.arcs[c.id];
    if (busy ||
        inCombat ||
        pendingRoll != null ||
        hero.dead ||
        !adventure.companions.contains(c) ||
        c.dead ||
        arc == null ||
        arc.stage != 'choice' ||
        arc.rewarded)
      return 'This companion is not ready for a decision.';
    _takeSnapshot();
    arc.stage = 'resolved';
    arc.rewarded = true;
    arc.outcome = fulfill
        ? 'You stood beside ${c.name} and fulfilled their goal: ${arc.description} They gained Inspiration and 10 loyalty.'
        : 'You helped ${c.name} leave ${arc.title} behind and choose a new path. Both of you gained Inspiration; loyalty rose by 5.';
    c.inspiration = true;
    if (!fulfill) hero.inspiration = true;
    _changeLoyalty(c, fulfill ? 10 : 5, arc.outcome);
    final q = adventure.quests.where((q) => q.title == arc.title).firstOrNull;
    if (q != null) {
      q.status = QuestStatus.completed;
      q.description = arc.outcome;
    }
    rememberWorld(
      adventure,
      'companion',
      c.name,
      arc.outcome,
      'Your decision at the end of ${arc.title}.',
    );
    rememberWorld(
      adventure,
      'quest',
      arc.title,
      'Completed. ${arc.outcome}',
      'A companion story reached its conclusion.',
    );
    _sys(arc.outcome, kind: LogKind.levelup);
    _note(arc.outcome);
    _notify();
    save();
    return arc.outcome;
  }

  void _changeLoyalty(Character c, int change, String reason) {
    if (change == 0) return;
    final before = c.loyalty;
    c.loyalty = (c.loyalty + change).clamp(0, 100);
    _sys(
      '${c.name} ${change > 0 ? 'approves' : 'disapproves'}${reason.isEmpty ? '' : ': $reason'}',
      kind: LogKind.system,
      meta: {
        'approval': change,
        'details': {
          'title': '${c.name} ${change > 0 ? 'approves' : 'disapproves'}',
          'subtitle': reason.isEmpty ? 'Companion approval' : reason,
          'outcome': '${change > 0 ? '+' : ''}$change loyalty',
          'ok': change > 0,
          'lines': [
            ['Loyalty', '$before → ${c.loyalty} (${c.loyaltyLabel})'],
            ['Personality', c.personality.isEmpty ? '—' : c.personality],
            if (c.personalQuest.isNotEmpty) ['Personal quest', c.personalQuest],
          ],
          'rule': 'Companions react to your choices based on their personality. At 60 loyalty they share a personal quest; at 80 they are devoted and fight harder (+1 to attacks). Below 15 they may leave the party.',
        },
      },
    );
    if (c.loyalty >= 60 && before < 60 && c.personalQuest.isEmpty) {
      final q = personalQuestFor(c);
      c.personalQuest = q.$1;
      adventure.quests.add(Quest(id: newId(), title: q.$1, description: q.$2));
      adventure.remember('quest', q.$1, '${c.name}\'s personal quest. ${q.$2}');
      adventure.log.add(
        LogEntry(kind: LogKind.companion, speaker: c.name, text: q.$3),
      );
      _sys('New companion quest: ${q.$1}', kind: LogKind.levelup);
      audio.play('quest');
    }
    seedCompanionArcs(adventure);
    if (c.loyalty >= 80 && before < 80) {
      _sys('${c.name} is now devoted to you.', kind: LogKind.levelup);
      audio.play('chime');
    }
    if (c.loyalty < 15 && adventure.companions.contains(c) && !inCombat) {
      rememberDeparture(adventure, c, 'Lost faith in the hero.');
      adventure.companions.remove(c);
      _note('${c.name} lost faith in the hero and left the party.');
      adventure.log.add(
        LogEntry(
          kind: LogKind.companion,
          speaker: c.name,
          text: 'I can\'t follow you any more. Good luck — you\'ll need it.',
        ),
      );
      _sys('${c.name} has left the party.');
    }
  }

  /// Offline approval: companions judge choices by class temperament.
  void _offlineApproval(Choice c) {
    if (adventure.companions.isEmpty) return;
    final r = Rng(stableHash('${c.text}${adventure.turns}'));
    for (final comp in List<Character>.of(adventure.companions)) {
      final cls = comp.classLevels.keys.first;
      final likes = switch (cls) {
        'paladin' || 'cleric' => {ChoiceType.dialogue, ChoiceType.rest},
        'rogue' || 'monk' => {ChoiceType.stealth, ChoiceType.explore},
        'barbarian' || 'fighter' => {ChoiceType.combat, ChoiceType.action},
        'wizard' ||
        'sorcerer' ||
        'warlock' => {ChoiceType.magic, ChoiceType.explore},
        'ranger' || 'druid' => {ChoiceType.explore, ChoiceType.stealth},
        'bard' => {ChoiceType.dialogue, ChoiceType.magic},
        _ => {ChoiceType.explore},
      };
      final dislikes = switch (cls) {
        'paladin' || 'cleric' => {ChoiceType.stealth},
        'barbarian' => {ChoiceType.stealth, ChoiceType.rest},
        'rogue' => {ChoiceType.combat},
        'wizard' => {ChoiceType.combat},
        _ => <ChoiceType>{},
      };
      if (likes.contains(c.type) && r.nextInt(100) < 45) {
        _changeLoyalty(
          comp,
          2 + r.nextInt(3),
          r.pick(likeReasons[cls] ?? const ['That suits them.']),
        );
      } else if (dislikes.contains(c.type) && r.nextInt(100) < 35) {
        _changeLoyalty(
          comp,
          -(2 + r.nextInt(3)),
          r.pick(dislikeReasons[cls] ?? const ['Not their style.']),
        );
      }
    }
  }

  Character? _target(dynamic name) {
    final n = (name ?? 'hero').toString().toLowerCase();
    if (n == 'hero' ||
        n == 'player' ||
        n == 'you' ||
        n == hero.name.toLowerCase() ||
        hero.name.toLowerCase().startsWith(n))
      return hero;
    for (final c in adventure.companions) {
      if (c.name.toLowerCase() == n ||
          c.name.toLowerCase().startsWith(n) ||
          n.startsWith(c.name.toLowerCase().split(' ').first))
        return c;
    }
    return n == 'party' ? hero : null;
  }

  void _sys(
    String s, {
    LogKind kind = LogKind.system,
    Map<String, dynamic> meta = const {},
  }) => adventure.log.add(LogEntry(kind: kind, text: s, meta: meta));

  void _applyEvent(Map<String, dynamic> e) {
    final type = (e['type'] ?? '').toString();
    num n(String k, [num d = 0]) =>
        (e[k] is num) ? e[k] as num : (num.tryParse('${e[k]}') ?? d);
    switch (type) {
      case 'damage':
        final t = _target(e['target']) ?? hero;
        final amt = n('amount', 1).toInt().clamp(0, 999);
        final before = t.hp;
        final dealt = t.takeDamage(amt);
        _sys(
          '${t.name} takes $dealt damage${e['reason'] != null ? ' (${e['reason']})' : ''}. HP ${t.hp}/${t.maxHp}',
          kind: LogKind.combat,
          meta: {
            'dmg': dealt,
            'fx': 'hit',
            'details': {
              'title': 'Damage',
              'subtitle': (e['reason'] ?? 'Hazard').toString(),
              'outcome': '${t.name} takes $dealt damage',
              'ok': false,
              'lines': [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
                if (dealt != amt)
                  ['Absorbed', '${amt - dealt} by temporary HP'],
              ],
              'rule': 'Damage reduces hit points. At 0 HP outside combat you are knocked out but survive with 1 HP in this game.',
            },
          },
        );
        audio.play('hit');
        _haptic();
        if (hero.hp <= 0) {
          hero.hp = 1;
          _sys(
            '${hero.name} collapses but clings to life with 1 HP.',
            kind: LogKind.combat,
          );
        }
      case 'heal':
        final t = _target(e['target']) ?? hero;
        final amt = n('amount', 1).toInt().clamp(0, 999);
        final before = t.hp;
        t.heal(amt);
        _sys(
          '${t.name} recovers $amt HP. HP ${t.hp}/${t.maxHp}',
          kind: LogKind.loot,
          meta: {
            'details': {
              'title': 'Healing',
              'outcome': '+$amt HP',
              'ok': true,
              'lines': [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
              ],
              'rule': ruleHeal,
            },
          },
        );
        audio.play('heal');
      case 'item':
        final add = (e['action'] ?? 'add') != 'remove';
        final qty = n('qty', 1).toInt().clamp(1, 99);
        final id = e['id']?.toString();
        final name = (e['name'] ?? itemById(id ?? '')?.name ?? 'Item')
            .toString();
        if (add) {
          final existing = hero.inventory
              .where((i) => i.name.toLowerCase() == name.toLowerCase())
              .firstOrNull;
          if (existing != null) {
            existing.qty += qty;
          } else {
            final def = id != null
                ? itemById(id)
                : items
                      .where((i) => i.name.toLowerCase() == name.toLowerCase())
                      .firstOrNull;
            hero.inventory.add(
              def != null
                  ? (InventoryItem.of(def.id, qty: qty)..name = name)
                  : InventoryItem(
                      name: name,
                      qty: qty,
                      description: (e['description'] ?? '').toString(),
                    ),
            );
          }
          final def = id != null
              ? itemById(id)
              : items
                    .where((i) => i.name.toLowerCase() == name.toLowerCase())
                    .firstOrNull;
          _stat(Stat.items, qty);
          if (def?.isMagic ?? false) {
            _stat(Stat.magicItems);
            adventure.remember(
              'item',
              name,
              '${def!.rarity} magic item${def.attune ? ' (requires attunement)' : ''} carried by ${hero.name}.',
            );
          } else if ((e['description'] ?? '').toString().isNotEmpty &&
              def == null) {
            adventure.remember('item', name, e['description'].toString());
          }
          final text = (e['text'] ?? '').toString().trim();
          if (text.isNotEmpty)
            adventure.writings[name.toLowerCase()] = ItemWriting(
              title: name,
              kind: writingKind(name),
              text: text,
            );
          if ((e['description'] ?? '').toString().isNotEmpty)
            adventure.itemNotes[name.toLowerCase()] = e['description']
                .toString();
          _sys(
            'Received: $name${qty > 1 ? ' ×$qty' : ''}',
            kind: LogKind.loot,
            meta: {
              'details': {
                'title': name,
                'subtitle': def == null
                    ? 'Item'
                    : def.type.name[0].toUpperCase() +
                          def.type.name.substring(1),
                'outcome': 'Added to inventory${qty > 1 ? ' ×$qty' : ''}',
                'ok': true,
                'lines': [
                  if (def?.damage != null)
                    ['Damage', '${def!.damage} ${def.damageType ?? ''}'],
                  if (def?.ac != null)
                    [
                      'Armor class',
                      def!.type == ItemType.shield ? '+${def.ac}' : '${def.ac}',
                    ],
                  if (def?.heal != null) ['Heals', def!.heal!],
                  if (def?.isMagic ?? false)
                    [
                      'Rarity',
                      '${def!.rarity[0].toUpperCase()}${def.rarity.substring(1)}${def.attune ? ' · requires attunement' : ''}',
                    ],
                  if ((def?.effect ?? '').isNotEmpty) ['Effect', def!.effect],
                  if (def != null) ['Value', '${def.value} gp'],
                  if ((e['description'] ?? def?.description ?? '')
                      .toString()
                      .isNotEmpty)
                    [
                      'Description',
                      (e['description'] ?? def?.description).toString(),
                    ],
                ],
                'rule': 'Manage your items from the party sheet: equip weapons and armor, or drink potions to heal.',
              },
            },
          );
          audio.play('coin');
        } else {
          final existing = hero.inventory
              .where((i) => i.name.toLowerCase() == name.toLowerCase())
              .firstOrNull;
          if (existing != null) {
            existing.qty -= qty;
            if (existing.qty <= 0) hero.inventory.remove(existing);
            _sys('Lost: $name', kind: LogKind.loot);
          }
        }
      case 'coins':
      case 'gold':
        final amt = n('amount').toInt() + n('gp').toInt();
        final asked = amt + n('sp') / 10 + n('cp') / 100 + n('pp') * 10;
        // Never take more than the purse holds, and log what really moved.
        final moved = asked < 0 ? -math.min(-asked, cashOf(adventure)) : asked.toDouble();
        if (moved != 0) {
          changeCash(adventure, moved);
          if (moved > 0) _stat(Stat.gold, moved.round());
          logMoney(
            this,
            moved,
            category: moved >= 0 ? 'loot' : 'purchase',
            note: (e['reason'] ?? '').toString(),
          );
        }
        if (moved == 0) break;
        final purse = money(adventure, cashOf(adventure));
        _sys(
          moved >= 0
              ? '+${money(adventure, moved)} (total $purse)'
              : '${money(adventure, -moved)} spent (total $purse)',
          kind: LogKind.loot,
          meta: {
            'details': {
              'title': moved >= 0 ? 'Gold found' : 'Gold spent',
              'outcome': money(adventure, moved, sign: true),
              'ok': moved >= 0,
              'lines': [
                ['Purse', purse],
              ],
              'rule': 'Gold buys potions and gear from merchants you meet along the way.',
            },
          },
        );
        if (moved > 0) audio.play('coin');
      case 'xp':
        final amt = n('amount').toInt().clamp(0, 100000);
        for (final c in adventure.party) {
          c.xp += amt;
        }
        _sys(
          '+$amt XP',
          kind: LogKind.loot,
          meta: {
            'xp': amt,
            'details': {
              'title': 'Experience',
              'outcome': '+$amt XP',
              'ok': true,
              'lines': [
                [
                  hero.name,
                  '${hero.xp} / ${hero.xpForNext} XP · level ${hero.level}',
                ],
                if (hero.canLevelUp)
                  ['Level up', 'Ready!']
                else
                  ['To next level', '${hero.xpForNext - hero.xp} XP'],
              ],
              'rule': 'Experience is earned by defeating enemies, overcoming hazards and solving problems. Every party member receives the full amount.',
            },
          },
        );
      case 'npc':
        final name = (e['name'] ?? 'Stranger').toString();
        final existing = adventure.npcs
            .where((x) => x.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        if (existing == null) {
          final race = races.any((r) => r.id == e['race'])
              ? e['race'] as String
              : 'human';
          adventure.npcs.add(
            Npc(
              id: newId(),
              name: name,
              role: (e['role'] ?? '').toString(),
              disposition: n('disposition').toInt().clamp(-100, 100),
              description: (e['description'] ?? '').toString(),
              raceId: race,
              portrait: PortraitSpec.random(race, seed: stableHash(name)),
              gender: normalizeGender(e['gender']?.toString()),
            ),
          );
          final added = adventure.npcs.last;
          _introduce(added, e);
          final b = adventure.bondFor(added);
          _sys(
            '${b.isHostile ? 'New enemy' : 'New acquaintance'}: $name${e['role'] != null ? ', ${e['role']}' : ''}',
            meta: {'npc': name},
          );
          if (settings.aiAutoImages && settings.useAiNpcPortraits)
            unawaited(generateNpcPortrait(added));
          _stat(Stat.npcs);
          adventure.remember(
            'npc',
            name,
            [
              if (e['role'] != null) '${e['role']}.',
              (e['description'] ?? '').toString(),
            ].join(' ').trim(),
          );
        } else {
          if ((e['description'] ?? '').toString().isNotEmpty)
            existing.description = e['description'].toString();
          if (normalizeGender(e['gender']?.toString()).isNotEmpty)
            existing.gender = e['gender'].toString();
          _introduce(existing, e, fresh: false);
        }
      case 'money':
        final line = applyMoneyEvent(this, e);
        if (line != null) {
          final amt = ((e['amount'] ?? 0) as num).toDouble();
          if (amt > 0) _stat(Stat.gold, amt.round());
          _sys(
            line,
            kind: LogKind.loot,
            meta: {
              'money': true,
              'details': {
                'title': amt >= 0 ? 'Money in' : 'Money out',
                'subtitle': (e['category'] ?? '').toString(),
                'outcome': line,
                'ok': amt >= 0,
                'lines': [
                  ['Purse', money(adventure, cashOf(adventure))],
                  if (adventure.wallet.bank > 0)
                    ['On the card', money(adventure, adventure.wallet.bank)],
                ],
                'rule': 'Every coin is tracked in your wallet (menu → Wallet & money).',
              },
            },
          );
          audio.play('coin');
        }
      case 'character':
        final who = adventure.personNamed((e['name'] ?? '').toString());
        if (who != null) _growCharacter(who, e);
      case 'vitals':
        final changes = adventure.vitals.apply(e);
        if (changes.isNotEmpty) {
          _sys(
            '${changes.join(' · ')}${(e['reason'] ?? '').toString().isEmpty ? '' : ' — ${e['reason']}'}',
            meta: {
              'vitals': true,
              'details': {
                'title': 'Condition',
                'subtitle': (e['reason'] ?? 'How you are holding up')
                    .toString(),
                'outcome': changes.join(' · '),
                'ok': !changes.any((c) => c.contains('-')),
                'lines': [
                  for (final k in Vitals.keys)
                    [
                      Vitals.labelOf(k),
                      '${adventure.vitals.get(k)}/100 · ${Vitals.describe(k, adventure.vitals.get(k))}',
                    ],
                ],
                'rule': 'Energy, food, water, health, stamina, morale and composure change with the story. Rest, eat and drink to recover; low values make things harder.',
              },
            },
          );
        }
      case 'achievement':
        _awardStory(e);
      case 'npc_remove':
        adventure.npcs.removeWhere((x) => x.name == e['name']);
      case 'disposition':
        final npc = adventure.personNamed((e['name'] ?? '').toString());
        if (npc != null)
          _bond(
            npc,
            friendship: n('change').toInt(),
            reason: (e['reason'] ?? '').toString(),
          );
      case 'relationship':
        final npc = adventure.personNamed((e['name'] ?? '').toString());
        if (npc != null) {
          final status = (e['status'] ?? '').toString().trim();
          _bond(
            npc,
            friendship: n('friendship').toInt(),
            romance: n('romance').toInt(),
            status: status.isEmpty ? null : status,
            reason: (e['reason'] ?? '').toString(),
          );
        }
      case 'companion_join':
        if (adventure.companions.length >= 3) break;
        final c = companionFromEvent(e, hero.level);
        c.xp = hero.xp;
        c.loyalty = 50;
        adventure.companions.add(c);
        _stat(Stat.companions);
        if (settings.aiAutoImages && settings.useAiCompanionPortraits)
          unawaited(generateCompanionPortrait(c));
        adventure.remember(
          'npc',
          c.name,
          'Companion: ${c.raceLabel} ${c.classSummary}. ${c.personality}',
        );
        _sys(
          '${c.name} joins your party! (${c.raceLabel} ${c.classSummary})',
          kind: LogKind.levelup,
        );
        audio.play('quest');
        // Handcrafted stories can give a companion their personal quest up front.
        final personal = (e['personal_quest'] ?? '').toString().trim();
        if (personal.isNotEmpty) {
          c.personalQuest = personal;
          final desc = (e['quest_description'] ?? '').toString();
          if (desc.isNotEmpty &&
              !adventure.quests.any((q) => q.title == personal))
            adventure.quests.add(
              Quest(id: newId(), title: personal, description: desc),
            );
          seedCompanionArcs(adventure);
          // The story introduces this quest itself; companions shouldn't raise it again unprompted.
          final arc = adventure.chronicle.arcs[c.id];
          if (arc != null)
            adventure
                    .approachTopics['arc:${c.id}:${arc.stage}:${arc.progress}'] =
                adventure.turns;
        }
      case 'approach':
        // A scripted "someone comes to talk to you" moment.
        final who = adventure.personNamed((e['name'] ?? '').toString());
        final text = (e['text'] ?? '').toString();
        if (who != null && text.isNotEmpty && settings.companionApproaches) {
          final label = (e['label'] ?? 'A private word').toString();
          unawaited(
            deliverApproach(
              this,
              Approach(
                person: who,
                topic: 'story:${adventure.id}:${who.id}:$label',
                why: text,
                label: label,
                fallback: text,
              ),
            ),
          );
          audio.play('chime');
        }
      case 'companion_leave':
        final c = _target(e['name']);
        if (c != null && c != hero) {
          rememberDeparture(
            adventure,
            c,
            (e['reason'] ?? 'Chose to leave the party.').toString(),
          );
          adventure.companions.remove(c);
          _sys('${c.name} leaves the party.');
        }
      case 'quest':
        final title = (e['title'] ?? 'Quest').toString();
        final status = (e['status'] ?? 'new').toString();
        var q = adventure.quests
            .where((x) => x.title.toLowerCase() == title.toLowerCase())
            .firstOrNull;
        if (q == null) {
          q = Quest(
            id: newId(),
            title: title,
            description: (e['description'] ?? '').toString(),
            startTurn: adventure.turns,
            giver: (e['giver'] ?? '').toString(),
            reward: (e['reward'] ?? '').toString(),
          );
          q.log(
            q.description.isEmpty ? 'Quest begun.' : q.description,
            adventure.turns,
          );
          adventure.quests.add(q);
          adventure.remember('quest', title, q.description);
          _sys(
            'New quest: $title',
            kind: LogKind.levelup,
            meta: {
              'quest': {'title': title, 'desc': q.description, 'state': 'new'},
              'details': {
                'title': title,
                'subtitle': 'New quest',
                'outcome': 'Added to your journal',
                'ok': true,
                'lines': [
                  if (q.description.isNotEmpty) ['Objective', q.description],
                ],
                'rule': 'Open the journal from the top bar to review quests and the people you have met.',
              },
            },
          );
          audio.play('quest');
        } else if ((e['description'] ?? '').toString().isNotEmpty) {
          q.description = e['description'].toString();
          q.log(q.description, adventure.turns);
        }
        if ((e['giver'] ?? '').toString().isNotEmpty)
          q.giver = e['giver'].toString();
        if ((e['reward'] ?? '').toString().isNotEmpty)
          q.reward = e['reward'].toString();
        if ((status == 'completed' || status == 'failed') &&
            q.status == QuestStatus.active) {
          q.endTurn = adventure.turns;
          q.log(
            status == 'completed' ? 'Completed.' : 'Failed.',
            adventure.turns,
          );
          if (status == 'completed') _stat(Stat.quests);
        }
        if (status == 'completed') {
          q.status = QuestStatus.completed;
          _sys(
            'Quest complete: $title',
            kind: LogKind.levelup,
            meta: {
              'quest': {'title': title, 'desc': q.description, 'state': 'done'},
            },
          );
          audio.play('levelup');
        } else if (status == 'failed') {
          q.status = QuestStatus.failed;
          _sys(
            'Quest failed: $title',
            kind: LogKind.levelup,
            meta: {
              'quest': {
                'title': title,
                'desc': q.description,
                'state': 'failed',
              },
            },
          );
        } else if (status == 'update' &&
            (e['description'] ?? '').toString().isNotEmpty) {
          _sys(
            'Quest updated: $title',
            kind: LogKind.levelup,
            meta: {
              'quest': {
                'title': title,
                'desc': q.description,
                'state': 'update',
              },
            },
          );
        }
        rememberWorld(
          adventure,
          'quest',
          q.title,
          '${q.status.name}: ${q.description}',
          'Quest $status in the story.',
        );
        seedCompanionArcs(adventure);
        syncCompanionQuest(adventure, q);
      case 'world':
        final kind = (e['kind'] ?? 'fact').toString();
        if (const {
          'faction',
          'place',
          'promise',
          'fact',
          'clue',
        }.contains(kind)) {
          final name = (e['name'] ?? '').toString();
          final state = (e['state'] ?? '').toString();
          if (rememberWorld(
            adventure,
            kind,
            name,
            state,
            (e['reason'] ?? 'A consequence of the story.').toString(),
            reputation: n('reputation').toInt(),
          )) {
            _sys('World changed · $name: $state', meta: {'world': true});
          }
        }
      case 'condition':
        final t = _target(e['target']) ?? hero;
        final name = (e['name'] ?? '').toString();
        if (name.isEmpty) break;
        if ((e['action'] ?? 'add') == 'remove') {
          t.conditions.remove(name);
          t.conditionUntil.remove(name);
        } else {
          t.conditions.add(name);
          final turns = n('turns').toInt();
          if (turns > 0) t.conditionUntil[name] = adventure.turns + turns;
          _sys(
            '${t.name} is now $name.',
            kind: LogKind.combat,
            meta: {
              'fx': 'buff',
              'details': {
                'title': name,
                'subtitle': 'Condition on ${t.name}',
                'outcome': 'Active',
                'ok': false,
                'rule': conditionText(name).isEmpty
                    ? 'A condition that changes what ${t.name} can do. A long rest usually clears it.'
                    : '${conditionText(name)} A long rest usually clears it.',
              },
            },
          );
        }
      case 'map':
        final name = (e['name'] ?? 'Uncharted Lands').toString();
        final kindStr = (e['kind'] ?? 'overworld').toString();
        final kind = MapKind.values.firstWhere(
          (k) => k.name == kindStr,
          orElse: () => MapKind.overworld,
        );
        final locs =
            (e['locations'] is List
                    ? (e['locations'] as List).map((x) => x.toString()).toList()
                    : <String>[])
                .take(10)
                .toList();
        adventure.map = MapState(
          kind: kind,
          seed: mapSeed(name),
          name: name,
          locations: [for (final l in locs) MapLocation(name: l)],
          current: 0,
        );
        adventure.remember(
          'place',
          name,
          locs.isEmpty ? '' : 'Contains: ${locs.join(', ')}.',
        );
        if (adventure.map!.locations.isNotEmpty)
          adventure.map!.locations.first.visited = true;
        _sys('Map updated: $name', meta: {'map': true});
        if (settings.aiAutoImages && settings.useAiImages && settings.aiMaps)
          _maybeMapImage();
      case 'move':
        final m = adventure.map;
        final loc = (e['location'] ?? '').toString();
        if (m == null || loc.isEmpty) break;
        var idx = m.locations.indexWhere(
          (l) => l.name.toLowerCase() == loc.toLowerCase(),
        );
        if (idx < 0)
          idx = m.locations.indexWhere(
            (l) =>
                l.name.toLowerCase().contains(loc.toLowerCase()) ||
                loc.toLowerCase().contains(l.name.toLowerCase()),
          );
        if (idx < 0 && m.locations.length < 10) {
          m.locations.add(MapLocation(name: loc));
          idx = m.locations.length - 1;
        }
        if (idx >= 0) {
          m.current = idx;
          m.locations[idx].visited = true;
          audio.play('footsteps', volume: 0.6);
        }
      case 'sfx':
        audio.play(_sfxFor((e['sound'] ?? '').toString()));
      case 'save':
        _savingThrowEvent(e);
      case 'shop':
        final kind = (e['kind'] ?? 'general').toString();
        final name = (e['name'] ?? 'Merchant').toString();
        _pendingShop = Choice(
          text: 'Browse the wares at $name',
          type: ChoiceType.explore,
          data: {'shop': kind, 'name': name},
        );
      case 'rest':
        _stat(Stat.rests);
        if (e['kind'] == 'long') {
          adventure.lastLongRestTurn = adventure.turns;
          adventure.vitals.rest();
          for (final c in adventure.party) {
            c.longRest();
          }
          _sys(
            'Long rest complete. HP and spell slots restored.',
            kind: LogKind.loot,
          );
          audio.play('heal');
        } else {
          _sys(_shortRestAll(), kind: LogKind.loot);
        }
      case 'end':
        if (!adventure.finished) {
          _stat(Stat.completed);
          if (isModule && (e['outcome'] ?? 'victory') != 'defeat')
            _stat(Stat.modules);
          if (adventure.campaignId != null) _stat(Stat.chapters);
        }
        adventure.finished = true;
        final ep = (e['epilogue'] ?? '').toString();
        if (ep.isNotEmpty) _sys(ep, kind: LogKind.levelup);
        unawaited(
          effect(
            (e['outcome'] ?? 'victory') == 'defeat' ? 'defeat' : 'victory',
            ep.isEmpty ? 'The end of ${adventure.title}.' : ep,
          ),
        );
        audio.play('levelup');
        audio.music('triumph');
    }
  }

  /// Sets up a character the story introduced: where they stand with the hero,
  /// their backstory, personality, goal and need.
  void _introduce(Npc npc, Map<String, dynamic> e, {bool fresh = true}) {
    if (introduceCharacter(adventure, npc, e, fresh: fresh))
      _stat(Stat.enemies);
  }

  /// The story changed someone: who they are, what they want, what they remember.
  void _growCharacter(Npc npc, Map<String, dynamic> e) {
    final changes = growCharacter(adventure, npc, e, adventure.turns);
    if (changes.isNotEmpty)
      _sys('${npc.name} · ${changes.join(' · ')}', meta: {'growth': npc.id});
  }

  /// An award from the storyteller for a remarkable deed.
  void _awardStory(Map<String, dynamic> e) {
    final a = achievements?.award(
      title: (e['title'] ?? '').toString(),
      description: (e['description'] ?? '').toString(),
      icon: (e['icon'] ?? 'star').toString(),
      story: adventure.title,
      storyId: adventure.id,
    );
    if (a == null) return;
    adventure.storyAwards.add(a.title);
    _sys(
      'Award: ${a.title}',
      kind: LogKind.levelup,
      meta: {'award': a.toJson()},
    );
    audio.play('levelup');
  }

  String _sfxFor(String s) => switch (s) {
    'door' || 'creak' => 'door',
    'sword' => 'sword',
    'spell' || 'magic' => 'magic',
    'coin' => 'coin',
    'thunder' => 'thunder',
    'roar' => 'roar',
    'footsteps' => 'footsteps',
    'chime' => 'chime',
    'splash' => 'splash',
    _ => 'click',
  };

  String _shortRestAll() {
    final parts = <String>[];
    for (final c in adventure.party) {
      c.conditions.removeWhere(
        (x) =>
            x.startsWith('KiUsed') ||
            const {
              'Surge Used',
              'Channel Used',
              'Second Wind Used',
              'Inspire Used',
            }.contains(x),
      );
      final h = c.shortRestHitDie();
      if (h > 0) parts.add('${c.name} +$h HP');
    }
    audio.play('heal');
    return parts.isEmpty
        ? 'You rest briefly, but have no hit dice to spend (or are already at full health).'
        : 'Short rest: ${parts.join(', ')}.';
  }

  static const longRestCooldown = 8;

  int get turnsUntilLongRest => math.max(
    0,
    longRestCooldown - (adventure.turns - adventure.lastLongRestTurn),
  );

  /// Rests from the menu. Returns a message when the rest could not happen.
  String? restFromMenu({required bool long}) {
    if (busy || pendingRoll != null || adventure.finished || hero.dead)
      return 'You cannot rest right now.';
    if (inCombat) return 'You can\'t rest during a fight.';
    if (long && turnsUntilLongRest > 0)
      return 'You rested recently. Press on for $turnsUntilLongRest more turns before making camp again.';
    _takeSnapshot();
    _stat(Stat.rests);
    // Interruptions: the wilds are dangerous; towns and taverns are safe.
    final safe = const {
      'town',
      'tavern',
      'temple',
      'castle',
      'camp',
    }.contains(adventure.scene.location);
    final interruptChance = safe
        ? 0
        : (long ? 25 : 10) + (adventure.hardcore ? 10 : 0);
    if (rollDie(100) <= interruptChance) {
      if (long) adventure.lastLongRestTurn = adventure.turns;
      _sys(
        long
            ? 'Your camp is ambushed in the night!'
            : 'Your rest is interrupted!',
        kind: LogKind.combat,
        meta: {
          'fx': 'roar',
          'details': {
            'title': 'Rest interrupted',
            'outcome': 'Ambush',
            'ok': false,
            'lines': [
              [
                'Location',
                '${adventure.scene.title} (${adventure.scene.location})',
              ],
              ['Chance', '$interruptChance%'],
            ],
            'rule': 'Resting outside towns, taverns and temples risks a wandering encounter: 10% for a short rest, 25% for a long rest (more in hardcore). You gain no benefit from an interrupted rest.',
          },
        },
      );
      _note(
        'The party tried to rest at ${adventure.scene.title} but was ambushed.',
      );
      _beginCombat({
        'enemies': [_wanderingMonster()],
        'surprise': 'party',
      });
      return null;
    }
    if (long) {
      final ration = hero.inventory
          .where((i) => i.name.toLowerCase().contains('ration'))
          .firstOrNull;
      adventure.lastLongRestTurn = adventure.turns;
      adventure.vitals.rest(food: ration != null);
      if (ration != null) {
        ration.qty--;
        if (ration.qty <= 0) hero.inventory.remove(ration);
        for (final c in adventure.party) {
          c.longRest();
        }
        _sys(
          'You make camp, eat a ration and take a long rest. HP and spell slots restored.',
          kind: LogKind.loot,
        );
        _note(
          'The party made camp and took a long rest; HP and spell slots are restored.',
        );
      } else {
        for (final c in adventure.party) {
          final hp = c.hp;
          c.longRest();
          c.hp = math.max(hp, (c.maxHp / 2).ceil());
        }
        _sys(
          'You make camp with no rations. You recover spell slots, but hunger leaves you at half health.',
          kind: LogKind.loot,
        );
        _note(
          'The party took a long rest without food: spell slots restored, but they are hungry and only half healed.',
        );
      }
      audio.play('heal');
    } else {
      final r = _shortRestAll();
      _sys(r, kind: LogKind.loot);
      _note('The party took a short rest. $r');
    }
    _notify();
    save();
    return null;
  }

  Map<String, dynamic> _wanderingMonster() {
    final loc = adventure.scene.location;
    final maxCr = math.max(0.25, hero.level / 3);
    final pool = monsters
        .where(
          (m) =>
              m.cr <= maxCr &&
              (m.environments.isEmpty || m.environments.contains(loc)),
        )
        .toList();
    final list = pool.isEmpty
        ? monsters.where((m) => m.cr <= maxCr).toList()
        : pool;
    final m = list[rollDie(list.length) - 1];
    return {'name': m.name, 'monster': m.id, 'count': m.cr < 0.5 ? 2 : 1};
  }

  void usePotionOutOfCombat(InventoryItem item, Character target) {
    final heal = DiceExpression.parse(item.def?.heal ?? '2d4+2').roll().total;
    target.heal(heal);
    item.qty--;
    if (item.qty <= 0) hero.inventory.remove(item);
    _sys(
      '${target.name} drinks ${item.name} and recovers $heal HP.',
      kind: LogKind.loot,
    );
    _note(
      '${target.name} drank ${item.name} (HP ${target.hp}/${target.maxHp}).',
    );
    audio.play('heal');
    _notify();
    save();
  }

  void _checkLevelUp() {
    if (hero.canLevelUp && !pendingLevelUp) {
      pendingLevelUp = true;
      audio.play('levelup');
    }
    for (final c in adventure.companions) {
      while (c.canLevelUp) {
        c.levelUp(c.classLevels.keys.first);
        c.autoProgress(c.classLevels.keys.first);
        _sys('${c.name} reached level ${c.level}!', kind: LogKind.levelup);
      }
    }
  }

  void applyLevelUp(
    String classId, {
    bool roll = false,
    String? subclassId,
    Map<Ability, int>? asi,
    String? feat,
  }) {
    final gain = hero.levelUp(classId, rollHp: roll, learnSpells: false);
    if (subclassId != null) hero.chooseSubclass(classId, subclassId);
    if (asi != null || feat != null) hero.applyAsi(scores: asi, feat: feat);
    pendingLevelUp = false;
    _stat(Stat.levels);
    unawaited(
      effect(
        'levelup',
        '${hero.name}, a ${hero.raceLabel} ${hero.classSummary}, surges with new power as they reach level ${hero.level}.',
      ),
    );
    achievements?.max(Stat.maxLevel, hero.level);
    final extras = [
      if (subclassId != null) subclassById(subclassId)?.name ?? subclassId,
      if (feat != null) 'feat: ${featById(feat)?.name ?? feat}',
      if (asi != null)
        asi.entries.map((e) => '${e.key.short} +${e.value}').join(', '),
    ];
    _note(
      '${hero.name} reached level ${hero.level}${extras.isEmpty ? '' : ' (${extras.join(', ')})'}.',
    );
    _sys(
      '${hero.name} reached level ${hero.level}! (+$gain max HP${hero.classLevels[classId] == 1 ? ', new class: ${classById(classId).name}' : ''}${extras.isEmpty ? '' : ' · ${extras.join(' · ')}'})',
      kind: LogKind.levelup,
    );
    _checkLevelUp();
    _notify();
    save();
  }

  // ---------------------------------------------------------------- music

  void _syncMusic() {
    audio.ambience(adventure.scene.ambience, ducked: inCombat);
    if (inCombat) {
      audio.music(_wasBoss ? 'boss' : 'combat');
    } else if (adventure.finished) {
      audio.music('triumph');
    } else {
      audio.music(
        themeForScene(adventure.scene.location, adventure.scene.mood),
      );
    }
  }

  // --------------------------------------------------------------- images

  Future<void> generateMissingImages() async {
    if (!settings.aiAutoImages || !settings.useAiImages || _disposed) return;
    if (settings.useAiPortraits && hero.portrait.aiImagePath == null)
      await generateCompanionPortrait(hero);
    for (final c in adventure.companions.toList()) {
      if (_disposed) return;
      if (settings.useAiCompanionPortraits && c.portrait.aiImagePath == null)
        await generateCompanionPortrait(c);
    }
    for (final n in adventure.npcs.toList()) {
      if (_disposed) return;
      if (settings.useAiNpcPortraits && n.portrait.aiImagePath == null)
        await generateNpcPortrait(n);
    }
    if (_disposed) return;
    if (adventure.log.isNotEmpty && adventure.sceneImagePath == null)
      await _maybeSceneImage();
    if (settings.aiMaps &&
        adventure.map?.aiImagePath == null &&
        adventure.map != null)
      await _maybeMapImage();
  }

  String _scenePrompt(SceneInfo s) {
    final prompt = s.imagePrompt.isNotEmpty
        ? s.imagePrompt
        : '${s.title}, a ${s.location} at ${s.time}, ${s.mood} mood';
    final look = hero.appearance.isNotEmpty
        ? hero.appearance
        : '${hero.raceLabel} ${hero.classSummary}';
    return 'Wide cinematic fantasy illustration: $prompt. Setting: ${adventure.setting}. If the hero appears, they are small in frame: $look.${_castLooks(prompt)} Consistent painterly style, no text.';
  }

  /// How the people named in a picture look, so they match their portraits.
  String _castLooks(String text) {
    final t = text.toLowerCase();
    final looks = [
      for (final p in adventure.people)
        if (p.name.split(' ').first.length >= 3 &&
            t.contains(p.name.split(' ').first.toLowerCase()) &&
            p.description.trim().isNotEmpty)
          '${p.name}: ${p.description.trim()}',
    ].take(3);
    return looks.isEmpty ? '' : ' Characters who appear: ${looks.join('; ')}.';
  }

  Future<void> _maybeSceneImage() async {
    final s = adventure.scene;
    final cached = adventure.sceneImages[s.title];
    if (cached != null) {
      adventure.sceneImagePath = cached;
      _notify();
      return;
    }
    if (!settings.aiAutoImages || settings.sceneArt == 'manual') return;
    // Only new kinds of places get new art; similar ones reuse what was painted.
    if (settings.sceneArt == 'places') {
      final reuse = reusableSceneArt(adventure.log, adventure.sceneImages, s);
      if (reuse != null) {
        adventure.sceneImages[s.title] = reuse;
        adventure.sceneImagePath = reuse;
        _notify();
        save();
        return;
      }
    }
    if (settings.useAiVideo &&
        settings.videoScenes &&
        !images.isSuspended('video') &&
        await _sceneVideo())
      return;
    if (!settings.useAiScenes) return;
    final path = await images.generate(
      'scene_${adventure.id}_${stableHash(s.title)}',
      _scenePrompt(s),
      size: '1536x1024',
      usageTarget: adventure.usage,
      style: artStyle,
      references: faceRefs(s.imagePrompt, party: true),
      styleReference: latestScenePicture(adventure.gallery),
    );
    if (path != null) {
      adventure.sceneImages[s.title] = path;
      if (adventure.scene.title == s.title) adventure.sceneImagePath = path;
      adventure.addMedia(
        MediaItem(
          path: path,
          kind: 'scene',
          caption: s.title,
          turn: adventure.turns,
          cost: images.costs[path] ?? 0,
        ),
      );
      _notify();
    }
    save();
  }

  Future<void> regenerateSceneImage() => _maybeSceneImageForced();

  Future<void> _maybeSceneImageForced() async {
    final s = adventure.scene;
    final path = await images.generate(
      'scene_${adventure.id}_${stableHash(s.title)}',
      _scenePrompt(s),
      size: '1536x1024',
      usageTarget: adventure.usage,
      style: artStyle,
      references: faceRefs(s.imagePrompt, party: true),
      styleReference: latestScenePicture(adventure.gallery),
    );
    if (path != null) {
      adventure.sceneImages[s.title] = path;
      if (adventure.scene.title == s.title) adventure.sceneImagePath = path;
      adventure.addMedia(
        MediaItem(
          path: path,
          kind: 'scene',
          caption: s.title,
          turn: adventure.turns,
          cost: images.costs[path] ?? 0,
        ),
      );
      _notify();
    }
    save();
  }

  Future<void> _maybeMapImage() async {
    final m = adventure.map;
    if (m == null) return;
    final path = await images.generate(
      'map_${adventure.id}',
      'Top-down fantasy cartography map of "${m.name}" (${m.kind.name}), parchment style, showing: ${m.locations.map((l) => l.name).join(', ')}.',
      usageTarget: adventure.usage,
      style: '$artStyle Rendered as an illustrated parchment map.',
    );
    if (path != null && adventure.map == m) {
      m.aiImagePath = path;
      adventure.addMedia(
        MediaItem(
          path: path,
          kind: 'map',
          caption: m.name,
          turn: adventure.turns,
          cost: images.costs[path] ?? 0,
        ),
      );
      _notify();
    }
    save();
  }

  @override
  Future<void> generateMapImage() => _maybeMapImage();

  /// AI portrait for an NPC, consistent with the adventure's art style.
  Future<void> generateNpcPortrait(Npc npc) async {
    final race = raceById(npc.raceId).name;
    final path = await images.generate(
      'npc_${adventure.id}_${npc.id}',
      'Head-and-shoulders character portrait of ${npc.name}, ${npc.gender.isEmpty ? '' : 'a ${npc.gender} '}$race ${npc.role.isEmpty ? 'commoner' : npc.role} in a ${adventure.setting} world. ${npc.description} Neutral background, looking at the viewer.',
      usageTarget: adventure.usage,
      style: artStyle,
      styleReference: _portraitStyleRef(npc.id),
    );
    if (path != null) {
      npc.portrait.useAiImage(path);
      adventure.addMedia(
        MediaItem(
          path: path,
          kind: 'portrait',
          caption: npc.name,
          turn: adventure.turns,
          cost: images.costs[path] ?? 0,
        ),
      );
      _notify();
    }
    save();
  }

  /// Another painted portrait from this story, so everyone looks drawn alike.
  String? _portraitStyleRef(String excludeId) {
    if (hero.id != excludeId && hero.portrait.aiImagePath != null)
      return hero.portrait.aiImagePath;
    for (final p in adventure.people) {
      if (p.id != excludeId && p.portrait.aiImagePath != null)
        return p.portrait.aiImagePath;
    }
    return null;
  }

  Future<void> generateCompanionPortrait(Character c) async {
    final path = await images.generate(
      'npc_${adventure.id}_${c.id}',
      'Head-and-shoulders portrait of ${c.name}, a ${c.raceLabel} ${c.classSummary} adventurer (${c.pronouns}). ${c.appearance.isNotEmpty ? c.appearance : c.personality} Neutral background.',
      usageTarget: adventure.usage,
      style: artStyle,
      styleReference: _portraitStyleRef(c.id),
    );
    if (path != null) {
      c.portrait.useAiImage(path);
      adventure.addMedia(
        MediaItem(
          path: path,
          kind: 'portrait',
          caption: c.name,
          turn: adventure.turns,
          cost: images.costs[path] ?? 0,
        ),
      );
      _notify();
    }
    save();
  }

  // --------------------------------------------------------------- combat

  void _beginCombat(Map<String, dynamic> ev) {
    final specs = <EnemySpec>[];
    if (ev['enemies'] is List) {
      for (final x in ev['enemies'] as List) {
        if (x is Map)
          specs.add(EnemySpec.fromJson(Map<String, dynamic>.from(x)));
      }
    }
    if (specs.isEmpty)
      specs.add(EnemySpec(name: 'Shadowy Foe', monsterId: 'bandit'));
    _wasBoss = ev['boss'] == true;
    _critShown = false;
    _spellShown = false;
    final enemies = CombatEngine.buildEnemies(
      specs,
      difficulty: adventure.difficulty,
      partyLevel: hero.level,
    );
    final surprise = (ev['surprise'] ?? 'none').toString();
    final events = CombatEngine(adventure).begin(
      enemies,
      partySurprised: surprise == 'party',
      enemiesSurprised: surprise == 'enemies',
    );
    for (final e in events) {
      _sys(
        e.text,
        kind: LogKind.combat,
        meta: {'fx': 'roar', 'details': ?e.details},
      );
    }
    if (_wasBoss || enemies.length >= 4)
      unawaited(
        effect(
          'boss',
          'The party faces ${enemies.map((x) => x.name).toSet().join(', ')} in ${adventure.scene.title.isEmpty ? 'battle' : adventure.scene.title}.',
        ),
      );
    audio.play('roar');
    audio.music(_wasBoss ? 'boss' : 'combat');
    adventure.choices = [];
    _notify();
    save();
    _continueCombat();
  }

  String? _turnStarted;

  Combatant? get currentCombatant => adventure.combat?.current;
  bool get isPlayerTurn =>
      inCombat &&
      !combatBusy &&
      pendingRoll == null &&
      (currentCombatant?.isPlayer ?? false) &&
      !(currentCombatant?.down ?? true);

  /// Combat lines since the last narrated round.
  final List<String> _roundLines = [];

  /// Retells the latest round as prose (Settings → AI combat narration).
  Future<void> _narrateCombat({String? outcome}) async {
    final lines = List<String>.of(_roundLines);
    _roundLines.clear();
    if (!settings.aiCombatNarration || !settings.useAiText || _disposed) return;
    if (lines.length < 2 && outcome == null) return;
    final c = adventure.combat;
    final foes = c == null
        ? ''
        : c.combatants
              .where((x) => !x.isPlayer && !x.isAlly)
              .map((x) => x.name)
              .toSet()
              .join(', ');
    final client = GatewayClient(
      apiKey: settings.apiKey,
      target: adventure.usage,
    );
    try {
      final text = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 0.9,
        maxTokens: 1500,
        messages: [
          ChatMessage(
            'system',
            'You narrate tactical D&D combat for a solo player. Turn the combat log into ${outcome == null ? '2-3' : '2-4'} vivid sentences of second-person prose ("you" is ${hero.name}). Keep every outcome exactly as logged: who attacked whom, hits, misses, who fell. No numbers, dice or rules talk. ${settings.matureContent ? 'Grit is fine, no gore.' : 'Keep it PG-13.'} Plain prose only.',
            cache: true,
          ),
          ChatMessage(
            'user',
            'Place: ${adventure.scene.title}. Party: ${adventure.party.map((p) => p.name).join(', ')}.${foes.isEmpty ? '' : ' Foes: $foes.'}\nLOG:\n${lines.take(18).join('\n')}${outcome == null ? '' : '\nThe fight ends: $outcome. Close the scene with a strong final beat.'}',
          ),
        ],
      );
      final prose = text.trim();
      if (prose.isEmpty || _disposed) return;
      adventure.log.add(
        LogEntry(
          kind: LogKind.narration,
          text: prose,
          meta: {
            'combatTale': true,
            if (client.spentTokens > 0) 'tok': client.spentTokens,
            if (client.spentCost > 0) 'usd': client.spentCost,
          },
        ),
      );
      narrator?.say(prose);
      _notify();
      save();
    } catch (_) {
      // Narration is a flourish; the fight goes on without it.
    } finally {
      client.close();
    }
  }

  void _logCombat(List<CombatEvent> events) {
    lastCombatEvents = events;
    for (final e in events) {
      if (e.fx != CombatFx.buff || e.amount > 0) _roundLines.add(e.text);
    }
    if (_roundLines.length > 30)
      _roundLines.removeRange(0, _roundLines.length - 30);
    final partyIds =
        adventure.combat?.combatants
            .where((c) => c.isPlayer || c.isAlly)
            .map((c) => c.id)
            .toSet() ??
        {};
    for (final e in events) {
      _sys(
        e.text,
        kind: LogKind.combat,
        meta: {'fx': e.fx.name, 'details': ?e.details},
      );
      flashTargetId = e.targetId;
      if (partyIds.contains(e.actorId)) {
        if (e.fx == CombatFx.crit) {
          _stat(Stat.crits);
          if (_isHero(e.actorId) && !_critShown) {
            _critShown = true;
            unawaited(
              effect('crit', '${e.text} A devastating critical strike.'),
            );
          }
        }
        if (e.fx == CombatFx.spell &&
            _isHero(e.actorId) &&
            e.amount >= 12 &&
            !_spellShown) {
          _spellShown = true;
          unawaited(effect('spell', e.text));
        }
        if ((e.fx == CombatFx.hit ||
                e.fx == CombatFx.crit ||
                e.fx == CombatFx.spell) &&
            e.amount > 0 &&
            !partyIds.contains(e.targetId))
          _stat(Stat.damage, e.amount);
        if (e.fx == CombatFx.heal && e.amount > 0) _stat(Stat.healed, e.amount);
        if (e.roll?.isFumble ?? false) _stat(Stat.nat1s);
      }
      switch (e.fx) {
        case CombatFx.hit:
          audio.play('hit');
          _haptic();
        case CombatFx.crit:
          audio.play('crit');
          if (settings.haptics) HapticFeedback.heavyImpact();
        case CombatFx.miss:
          audio.play('miss');
        case CombatFx.spell:
          audio.play('magic');
        case CombatFx.heal:
          audio.play('heal');
        case CombatFx.death:
          audio.play('death');
        case CombatFx.buff:
          audio.play('buff');
        case CombatFx.roar:
          audio.play('roar');
        case CombatFx.flee:
          audio.play('flee');
        default:
          break;
      }
    }
  }

  Future<void> _continueCombat() async {
    if (combatBusy || adventure.combat == null) return;
    combatBusy = true;
    _notify();
    try {
      CombatEngine(adventure).ensureLayout();
      while (adventure.combat != null) {
        final engine = CombatEngine(adventure);
        final st = engine.state;
        if (st.victory) {
          await _endCombat(victory: true);
          return;
        }
        if (st.defeat) {
          await _endCombat(victory: false);
          return;
        }
        final cur = st.current;
        if (cur.down) {
          if (cur.isPlayer) {
            await _deathSave(engine, cur);
            if (adventure.combat == null) return;
          }
          engine.nextTurn();
          continue;
        }
        if (_turnStarted != '${st.round}:${st.turn}') {
          _turnStarted = '${st.round}:${st.turn}';
          final start = engine.startOfTurn();
          if (start.isNotEmpty) {
            _logCombat(start);
            _notify();
            if (st.victory || st.defeat) continue;
          }
        }
        if (cur.isPlayer) {
          unawaited(_narrateCombat());
          break;
        }
        await Future.delayed(const Duration(milliseconds: 650));
        if (_disposed) return;
        _logCombat(engine.autoTurn());
        _notify();
        await Future.delayed(const Duration(milliseconds: 450));
        flashTargetId = null;
        _logCombat(engine.legendaryActions());
        engine.nextTurn();
        _notify();
      }
    } finally {
      combatBusy = false;
      _notify();
      save();
    }
  }

  Map<String, dynamic> _deathMeta(int r) => {
    'fx': r >= 10 ? 'heal' : 'death',
    'details': {
      'title': 'Death saving throw',
      'outcome': r == 20
          ? 'Natural 20 · back on your feet'
          : (r >= 10
                ? 'Success'
                : (r == 1 ? 'Natural 1 · two failures' : 'Failure')),
      'ok': r >= 10,
      'groups': [
        {
          'label': 'd20',
          'dice': [
            {'s': 20, 'v': r},
          ],
          'mod': 0,
          'total': r,
          'against': 'DC 10',
        },
      ],
      'lines': [
        ['Successes', '${hero.deathSuccesses} / 3'],
        ['Failures', '${hero.deathFailures} / 3'],
      ],
      'rule': ruleDeathSave,
    },
  };

  Future<void> _deathSave(CombatEngine engine, Combatant cur) async {
    if (adventure.companions.every((c) => c.hp <= 0)) {
      await _endCombat(victory: false);
      return;
    }
    final r = rollDie(20);
    if (r == 20) {
      hero.hp = 1;
      hero.deathFailures = 0;
      hero.deathSuccesses = 0;
      cur.hp = 1;
      _sys(
        'Death save: natural 20! ${hero.name} surges back to consciousness!',
        kind: LogKind.combat,
        meta: _deathMeta(r),
      );
      audio.play('crit');
    } else if (r >= 10) {
      hero.deathSuccesses++;
      _sys(
        'Death save: $r — success (${hero.deathSuccesses}/3).',
        kind: LogKind.combat,
        meta: _deathMeta(r),
      );
    } else {
      hero.deathFailures += r == 1 ? 2 : 1;
      _sys(
        'Death save: $r — failure (${hero.deathFailures}/3).',
        kind: LogKind.combat,
        meta: _deathMeta(r),
      );
    }
    _notify();
    await Future.delayed(const Duration(milliseconds: 600));
    if (hero.deathFailures >= 3) {
      await _endCombat(victory: false);
    }
  }

  Future<void> playerAttack(String targetId, int natural) async {
    final engine = combat;
    if (engine == null) return;
    final t = engine.byId(targetId);
    if (t == null) return;
    final me = engine.state.current;
    final events = <CombatEvent>[];
    events.addAll(engine.attack(me, t, natural: natural));
    // extra attacks auto-resolve
    for (var i = 1; i < hero.attacksPerTurn; i++) {
      final foe = engine.state.enemies.where((e) => !e.down).firstOrNull;
      if (foe == null) break;
      events.addAll(engine.attack(me, foe));
    }
    await _afterPlayerAction(events);
  }

  Future<void> playerCast(
    SpellDef spell,
    List<String> targetIds,
    int? natural,
  ) async {
    final engine = combat;
    if (engine == null) return;
    final targets = targetIds.map(engine.byId).whereType<Combatant>().toList();
    if (targets.isEmpty) targets.add(engine.state.current);
    _stat(Stat.spells);
    await _afterPlayerAction(
      engine.castSpell(engine.state.current, spell, targets, natural: natural),
    );
  }

  /// Free movement on the player's turn (does not end the turn).
  Future<void> playerMove(int x, int y) async {
    final engine = combat;
    if (engine == null || !isPlayerTurn) return;
    final events = engine.moveTo(engine.state.current, x, y);
    _logCombat(events);
    audio.play('footsteps', volume: 0.6);
    _notify();
    save();
    if (hero.hp <= 0 || engine.state.current.down)
      await _afterPlayerAction(const []);
  }

  void orderCompanion(String combatantId, String order, {String? targetId}) {
    final engine = combat;
    final c = engine?.byId(combatantId);
    if (engine == null || c == null) return;
    engine.setOrder(c, order, targetId: targetId);
    final reply = switch (order) {
      'focus' => 'On it. That one goes down.',
      'defend' => 'I have your back.',
      'heal' => 'I will keep you standing.',
      'hold' => 'Holding back.',
      _ => 'As you wish.',
    };
    adventure.log.add(
      LogEntry(kind: LogKind.companion, text: reply, speaker: c.name),
    );
    _notify();
    save();
  }

  Future<void> playerPotion(String targetId) async {
    final engine = combat;
    if (engine == null) return;
    final t = engine.byId(targetId) ?? engine.state.current;
    await _afterPlayerAction(engine.usePotion(engine.state.current, t));
  }

  Future<void> playerAbility(String ability) async {
    final engine = combat;
    if (engine == null) return;
    final events = engine.classAbility(engine.state.current, ability);
    // Second wind / rage are bonus actions: keep the turn.
    _logCombat(events);
    if (const {
      'second_wind',
      'rage',
      'hide',
      'move',
      'smite',
      'action_surge',
      'offhand',
      'flurry',
      'inspire',
      'disengage',
    }.contains(ability)) {
      _notify();
      save();
      return;
    }
    await _afterPlayerAction(const []);
  }

  Future<void> playerFlee(int natural) async {
    final engine = combat;
    if (engine == null) return;
    final (ok, e) = engine.flee(engine.state.current, natural: natural);
    _logCombat([e]);
    if (ok) {
      await _endCombat(victory: false, fled: true);
    } else {
      await _afterPlayerAction(const []);
    }
  }

  Future<void> _afterPlayerAction(List<CombatEvent> events) async {
    _logCombat(events);
    _notify();
    await Future.delayed(const Duration(milliseconds: 500));
    flashTargetId = null;
    if (adventure.combat == null) return;
    final st = adventure.combat!;
    if (!st.victory) {
      final legendary = CombatEngine(adventure).legendaryActions();
      if (legendary.isNotEmpty) {
        _logCombat(legendary);
        _notify();
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (hero.conditions.remove('Surging') && !st.victory && !st.defeat) {
      _sys(
        'Action Surge: ${hero.name} acts again!',
        kind: LogKind.combat,
        meta: {'fx': 'buff'},
      );
      _notify();
      save();
      return;
    }
    CombatEngine(adventure).nextTurn();
    _notify();
    await _continueCombat();
  }

  Future<void> _endCombat({required bool victory, bool fled = false}) async {
    await _narrateCombat(
      outcome: victory ? 'victory' : (fled ? 'the party escapes' : 'defeat'),
    ).timeout(const Duration(seconds: 25), onTimeout: () {});
    final engine = CombatEngine(adventure);
    final xp = victory ? engine.xpReward : 0;
    final foes = engine.state.enemies.map((e) => e.name).join(', ');
    final rounds = engine.state.round;
    final defeated = engine.state.enemies.where((e) => e.down).length;
    final recovered = engine.recoverAmmo();
    engine.finish();
    if (recovered != null) _sys(recovered, kind: LogKind.loot);
    _stat(Stat.kills, defeated);
    if (fled) _stat(Stat.fled);
    if (victory && _wasBoss) _stat(Stat.bosses);
    final wasBoss = _wasBoss;
    _wasBoss = false;
    if (hero.hp <= 0) hero.hp = 1;
    hero.deathFailures = 0;
    hero.deathSuccesses = 0;
    for (final c in adventure.companions) {
      if (c.hp <= 0) c.hp = 1;
    }
    if (victory) {
      _sys(
        'VICTORY! (+$xp XP)',
        kind: LogKind.levelup,
        meta: {
          'details': {
            'title': 'Victory',
            'subtitle': 'After $rounds rounds',
            'outcome': '+$xp XP each',
            'ok': true,
            'lines': [
              ['Defeated', foes],
              for (final c in adventure.party)
                [c.name, 'HP ${c.hp}/${c.maxHp}'],
            ],
            'rule':
                'XP for each defeated enemy is awarded to every party member.',
          },
        },
      );
      for (final c in adventure.party) {
        c.xp += xp;
      }
      if (_wasBoss)
        unawaited(
          effect('victory', '${hero.name} stands victorious over $foes.'),
        );
      audio.play('levelup');
    } else if (!fled) {
      _sys('DEFEAT...', kind: LogKind.combat);
      audio.play('death');
      if (adventure.hardcore) {
        hero.dead = true;
        hero.hp = 0;
        adventure.finished = true;
        adventure.choices = [];
        _stat(Stat.deaths);
        _sys(
          '${hero.name} has fallen. In hardcore mode, death is final.',
          kind: LogKind.levelup,
          meta: {
            'details': {
              'title': 'Permadeath',
              'subtitle': 'Hardcore mode',
              'outcome': '${hero.name} is dead',
              'ok': false,
              'lines': [
                ['Level', '${hero.level}'],
                ['Turns survived', '${adventure.turns}'],
                ['Slain by', foes],
              ],
              'rule': 'Hardcore adventures have no rewind and no second chances: if the party falls, the hero dies and the adventure ends.',
            },
          },
        );
        audio.music('mystery');
        unawaited(
          effect('defeat', '${hero.name} falls in battle against $foes.'),
        );
        _notify();
        save();
        store.saveCharacter(hero);
        return;
      }
    }
    _checkLevelUp();
    _notify();
    final summary = victory
        ? 'Combat ended in VICTORY after $rounds rounds against $foes. Hero HP ${hero.hp}/${hero.maxHp}.${adventure.companions.isEmpty ? '' : ' Companions: ${adventure.companions.map((c) => '${c.name} ${c.hp}/${c.maxHp}').join(', ')}.'} Narrate the aftermath and loot (use events for gold/items).'
        : fled
        ? 'The hero FLED from combat against $foes. Narrate the escape.'
        : 'The party was DEFEATED by $foes. The hero is left at 1 HP. Narrate a dramatic but non-fatal consequence (captured, robbed, rescued) and continue.';
    if (isAi) {
      if (!_aiBlocked())
        await _runAi(
          (t) => dm.act(adventure, summary, onNarration: _onStream, trace: t),
        );
    } else {
      _apply(
        isModule
            ? ModuleEngine(adventure).afterCombat(victory: victory, fled: fled)
            : OfflineEngine(adventure).afterCombat(
                victory: victory,
                fled: fled,
                xp: xp,
                wasBoss: wasBoss,
              ),
      );
    }
    _syncMusic();
  }

  // ------------------------------------------------------------- NPC talk

  @override
  Future<ChatLine> talkTo(
    Npc npc,
    String line, {
    List<String> images = const [],
  }) async {
    final chat = adventure.chatWith(npc.id);
    if (chat.isNotEmpty &&
        !chat.last.fromPlayer &&
        chat.last.opener.isNotEmpty &&
        !chat.any((l) => l.fromPlayer && l.at.isAfter(chat.last.at)))
      _stat(Stat.approaches);
    _stat(Stat.chats);
    chat.add(ChatLine(fromPlayer: true, text: line, images: images));
    _notify();
    final companion = adventure.companions
        .where((c) => c.id == npc.id)
        .firstOrNull;
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
        final seen = images.isEmpty
            ? const <String>[]
            : await this.images.dataUrls(images);
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
        if (companion != null) {
          companion.notes = '${companion.notes} ${r.note}'.trim();
        } else {
          final real = adventure.npcs.where((n) => n.id == npc.id).firstOrNull;
          if (real != null) real.notes = '${real.notes} ${r.note}'.trim();
        }
      }
      if (r.memory.isNotEmpty) adventure.remember('npc', npc.name, r.memory);
      if (r.note.isNotEmpty)
        adventure
            .profileOf(npc)
            .remember(r.note, turn: adventure.turns, source: 'chat');
      if (companion != null && r.friendship != 0)
        companion.loyalty = (companion.loyalty + r.friendship ~/ 2).clamp(
          0,
          100,
        );
      _note(
        'In a private conversation, ${hero.name} told ${npc.name}: "$line" and ${npc.name} replied: "${r.text}"${change == null ? '' : ' ($change)'}.',
      );
    } else {
      final (text, delta) = _offlineReply(npc, line, chat.length);
      reply = ChatLine(fromPlayer: false, text: text);
      _bond(npc, friendship: delta, reason: 'Talking', quiet: true);
    }
    chat.add(reply);
    if (settings.ttsEnabled && settings.speakChatReplies)
      narrator?.say(reply.text, speaker: npc.name);
    _notify();
    save();
    return reply;
  }

  /// Applies a relationship change and logs it. Returns the summary.
  String? _bond(
    Npc npc, {
    int friendship = 0,
    int romance = 0,
    String? status,
    bool? romanceClosed,
    String reason = '',
    bool quiet = false,
  }) {
    final before = adventure.bondFor(npc);
    final wasRomance = before.romance;
    final wasFriend = before.friendship;
    final change = applyBondChange(
      adventure,
      npc,
      friendship: friendship,
      romance: romance,
      status: status,
      romanceClosed: romanceClosed,
      reason: reason,
      turn: adventure.turns,
    );
    if (change == null) return null;
    final after = adventure.bondFor(npc);
    if (wasRomance < 20 && after.isRomantic) _stat(Stat.romances);
    if (wasFriend < 80 && after.friendship >= 80) _stat(Stat.bestFriends);
    if (wasFriend > -65 && after.friendship <= -65) _stat(Stat.enemies);
    final real = adventure.npcs.where((n) => n.id == npc.id).firstOrNull;
    if (real != null) real.disposition = before.friendship;
    final b = adventure.bondFor(npc);
    _sys(
      change,
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
    );
    if (!quiet &&
        (romance >= 8 ||
            (wasRomance < 45 && b.romance >= 45) ||
            (status != null && status.toLowerCase().contains('partner')))) {
      unawaited(
        effect(
          'romance',
          'A tender moment between ${hero.name} and ${npc.name}${reason.isEmpty ? '' : ': $reason'}.',
        ),
      );
    }
    return change;
  }

  (String, int) _offlineReply(Npc npc, String line, int n) {
    final r = Rng(stableHash('${npc.name}$line$n'));
    final lower = line.toLowerCase();
    if (lower.contains('quest') ||
        lower.contains('help') ||
        lower.contains('job')) {
      final q = adventure.quests
          .where((q) => q.status == QuestStatus.active)
          .firstOrNull;
      return (
        q == null
            ? 'Help? I\'ve nothing for you, stranger.'
            : '${q.title}? Aye, I\'ve heard whispers. ${r.pick(['Be careful out there.', 'Folk say the roads are cursed now.', 'Bring a lantern. And a prayer.'])}',
        0,
      );
    }
    if (lower.contains('buy') ||
        lower.contains('trade') ||
        lower.contains('sell')) {
      return (
        npc.disposition >= 0
            ? 'I could part with a healing draught for 50 gold.'
            : 'I don\'t trade with the likes of you.',
        0,
      );
    }
    if (lower.contains('threat') ||
        lower.contains('or else') ||
        lower.contains('kill')) {
      return (
        r.pick([
          'Big words.',
          'You\'ll regret that.',
          '...Fine. Fine! Just leave me be.',
        ]),
        -10,
      );
    }
    if (lower.contains('thank') ||
        lower.contains('friend') ||
        lower.contains('kind')) {
      return (
        r.pick([
          'Kindness is rare these days. Thank you.',
          'You\'re alright, you know that?',
          'Safe travels, friend.',
        ]),
        6,
      );
    }
    return (
      switch (npc.attitude) {
        'Devoted' || 'Friendly' => r.pick([
          'Always good to see you!',
          'What can I do for you?',
          'Stay a while, rest your feet.',
        ]),
        'Neutral' => r.pick([
          'Hm. What do you want?',
          'I\'m listening.',
          'Make it quick.',
        ]),
        _ => r.pick([
          'Leave.',
          'I\'ve nothing to say to you.',
          'Get out of my sight.',
        ]),
      },
      0,
    );
  }

  // ------------------------------------------------------------ effects

  bool _isHero(String? combatantId) =>
      adventure.combat?.combatants
          .where((c) => c.id == combatantId)
          .firstOrNull
          ?.isPlayer ??
      false;

  bool _critShown = false;
  bool _spellShown = false;
  int _lastEffectTurn = -10;

  /// A special-effect image (or video) for a big moment, if enabled for it.
  Future<void> effect(
    String moment,
    String description, {
    bool force = false,
    bool? video,
  }) async {
    if (_disposed ||
        (!force && (!settings.effectOn(moment) || !settings.aiAutoImages)))
      return;
    if (!force &&
        adventure.turns - _lastEffectTurn < 2 &&
        moment != 'levelup' &&
        moment != 'victory')
      return;
    _lastEffectTurn = adventure.turns;
    final look = hero.appearance.isNotEmpty
        ? hero.appearance
        : '${hero.raceLabel} ${hero.classSummary}';
    final prompt =
        'Epic special-effect illustration of a dramatic moment: $description '
        'Setting: ${adventure.scene.title.isEmpty ? adventure.setting : adventure.scene.title}, ${adventure.scene.time}. '
        'The hero ${hero.name} looks like: $look. Dynamic composition, magical light, particles and motion.';
    final key = 'fx_${adventure.id}_${DateTime.now().millisecondsSinceEpoch}';
    var film =
        video ??
        (settings.useAiVideo &&
            settings.videoEffects &&
            !images.isSuspended('video'));
    var path = film
        ? await images.generateVideo(key, prompt, usageTarget: adventure.usage)
        : null;
    if (path == null &&
        settings.useAiImages &&
        !images.isSuspended('image') &&
        !_disposed) {
      film = false;
      path = await images.generate(
        key,
        '$prompt${_castLooks(description)}',
        size: '1536x1024',
        usageTarget: adventure.usage,
        category: 'effects',
        style: artStyle,
        references: faceRefs(description),
        styleReference: latestScenePicture(adventure.gallery),
      );
    }
    if (path == null || _disposed) return;
    final cost = images.costs[path] ?? 0;
    adventure.log.add(
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
    adventure.addMedia(
      MediaItem(
        path: path,
        video: film,
        kind: 'effect',
        caption: description,
        turn: adventure.turns,
        cost: cost,
      ),
    );
    _notify();
    save();
  }

  /// A short clip of the current scene. False if no clip was made.
  Future<bool> _sceneVideo({bool force = false}) async {
    if (!settings.useAiVideo ||
        (!force && (!settings.videoScenes || !settings.aiAutoImages)))
      return false;
    final s = adventure.scene;
    final path = await images.generateVideo(
      'scene_${adventure.id}_${stableHash(s.title)}',
      _scenePrompt(s),
      usageTarget: adventure.usage,
    );
    if (path == null) return false;
    adventure.sceneImages[s.title] = path;
    if (adventure.scene.title == s.title) adventure.sceneImagePath = path;
    adventure.addMedia(
      MediaItem(
        path: path,
        video: true,
        kind: 'scene',
        caption: s.title,
        turn: adventure.turns,
        cost: images.costs[path] ?? 0,
      ),
    );
    _notify();
    save();
    return true;
  }
}

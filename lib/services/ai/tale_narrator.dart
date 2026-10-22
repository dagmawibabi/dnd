import 'dart:convert';

import '../../data/tale_genres.dart';
import '../../game/money.dart' show walletPrompt;
import '../../game/story.dart';
import '../../models/tale.dart';
import '../../models/world.dart';
import '../settings.dart';
import 'ai_trace.dart';
import 'gateway_client.dart';

/// One reply from the AI storyteller in a text adventure.
class TaleTurn {
  TaleTurn({
    required this.narration,
    this.title,
    this.choices = const [],
    this.add = const [],
    this.remove = const [],
    this.health = 0,
    this.status,
    this.ending,
    this.speaker,
    this.people = const [],
    this.dialogue = const [],
    this.memory = const [],
    this.relationships = const [],
    this.goals = const [],
    this.location,
    this.time,
    this.mood,
    this.imagePrompt,
    this.moment,
    this.characters = const [],
    this.consequences = const [],
    this.vitals = const {},
    this.writings = const {},
    this.achievement,
    this.money = const [],
  });
  final String narration;
  final String? title;
  final List<String> choices;
  final List<String> add;
  final List<String> remove;
  final int health;
  final String? status;
  final String? ending;

  /// Who mostly speaks in the narration, if anyone.
  final String? speaker;

  /// New or updated characters: {name, role, description}.
  final List<Map<String, String>> people;

  /// Short lines spoken by characters present: (name, line).
  final List<(String, String)> dialogue;
  final List<Map<String, String>> memory;

  /// {name, friendship, romance, status, reason}
  final List<Map<String, dynamic>> relationships;

  /// {title, status: new|done|failed}
  final List<Map<String, String>> goals;

  /// Scene art and music cues.
  final String? location;
  final String? time;
  final String? mood;
  final String? imagePrompt;

  /// A dramatic beat worth a special-effect image ("the airlock blows").
  final String? moment;

  /// Changes to who characters are: {name, personality, goal, need, memory, growth}.
  final List<Map<String, String>> characters;

  /// Lasting changes to the world: {kind, name, state, reason}.
  final List<Map<String, String>> consequences;

  /// Changes to the protagonist's condition ({"energy": -10, "hunger": 20…}).
  final Map<String, dynamic> vitals;

  /// What readable items say: item name -> text.
  final Map<String, String> writings;

  /// {title, description, icon} for a remarkable deed.
  final Map<String, String>? achievement;

  /// Coins changing hands: {amount, counterparty, category, note}.
  final List<Map<String, dynamic>> money;

  int tokens = 0;
  double cost = 0;

  static TaleTurn parse(String raw) {
    final j = extractJsonObject(raw);
    if (j == null)
      return TaleTurn(
        narration: readableNarration(raw),
        choices: const ['Continue'],
      );
    List<String> list(dynamic v) =>
        v is List ? [for (final x in v) x.toString()] : const [];
    String? str(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty || t == 'null' ? null : t;
    }

    var prose = (j['narration'] ?? '').toString().trim();
    if (prose.isEmpty) {
      prose = (partialJsonString(raw, 'narration') ?? '').trim();
      if (prose.isEmpty)
        throw const FormatException(
          'The AI response was incomplete. Please try again.',
        );
    }
    final end = (j['ending'] ?? '').toString().toLowerCase();
    final scene = j['scene'] is Map
        ? Map<String, dynamic>.from(j['scene'])
        : const <String, dynamic>{};
    return TaleTurn(
      narration: prose,
      title: str(j['title'] ?? scene['title']),
      choices: [
        for (final c in (j['choices'] as List? ?? const []))
          if (c is String)
            c
          else if (c is Map && c['text'] != null)
            c['text'].toString(),
      ],
      add: [
        for (final x in (j['inventory_add'] as List? ?? const []))
          if (x is Map && str(x['name']) != null)
            x['name'].toString()
          else if (x is! Map && str(x) != null)
            x.toString(),
      ],
      writings: {
        for (final x in (j['inventory_add'] as List? ?? const []))
          if (x is Map && str(x['name']) != null && str(x['text']) != null)
            x['name'].toString(): x['text'].toString(),
      },
      remove: list(j['inventory_remove']),
      health:
          ((j['health_change'] ?? 0) is num
                  ? (j['health_change'] ?? 0) as num
                  : 0)
              .toInt()
              .clamp(-100, 100),
      status: j['status']?.toString(),
      ending: const {'good', 'bad', 'neutral'}.contains(end) ? end : null,
      speaker: str(j['speaker']),
      people: [
        for (final p in (j['people'] as List? ?? const []))
          if (p is Map && str(p['name']) != null)
            {
              for (final e in p.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            },
      ],
      dialogue: [
        for (final d in (j['dialogue'] as List? ?? const []))
          if (d is Map && str(d['name']) != null && str(d['line']) != null)
            (d['name'].toString(), d['line'].toString()),
      ],
      memory: [
        for (final m in (j['memory'] as List? ?? const []))
          if (m is Map && str(m['name']) != null)
            {
              'kind': (m['kind'] ?? 'fact').toString(),
              'name': m['name'].toString(),
              'text': (m['text'] ?? '').toString(),
            },
      ],
      relationships: [
        for (final r in (j['relationships'] as List? ?? const []))
          if (r is Map && str(r['name']) != null) Map<String, dynamic>.from(r),
      ],
      goals: [
        for (final g in (j['goals'] as List? ?? const []))
          if (g is Map && str(g['title']) != null)
            {
              'title': g['title'].toString(),
              'status': (g['status'] ?? 'new').toString(),
              'description': (g['description'] ?? '').toString(),
              'update': (g['update'] ?? '').toString(),
              'giver': (g['giver'] ?? '').toString(),
              'reward': (g['reward'] ?? '').toString(),
            },
      ],
      characters: [
        for (final c in (j['characters'] as List? ?? const []))
          if (c is Map && str(c['name']) != null)
            {
              for (final e in c.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            },
      ],
      consequences: [
        for (final c in (j['consequences'] as List? ?? const []))
          if (c is Map && str(c['name']) != null && str(c['state']) != null)
            {
              for (final e in c.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            },
      ],
      vitals: j['vitals'] is Map
          ? Map<String, dynamic>.from(j['vitals'])
          : const {},
      money: [
        for (final m in (j['money'] as List? ?? const []))
          if (m is Map && m['amount'] != null) Map<String, dynamic>.from(m),
      ],
      achievement:
          j['achievement'] is Map &&
              str((j['achievement'] as Map)['title']) != null
          ? {
              for (final e in (j['achievement'] as Map).entries)
                e.key.toString(): '${e.value}',
            }
          : null,
      location: str(scene['location_type'] ?? j['location_type']),
      time: str(scene['time']),
      mood: str(scene['mood']),
      imagePrompt: str(scene['image_prompt'] ?? j['image_prompt']),
      moment: str(j['moment']),
    );
  }
}

const _taleLocations =
    'forest|dungeon|town|tavern|cave|castle|ruins|swamp|mountain|coast|desert|temple|crypt|road|tundra|tower|sewer|plains|camp';

/// The text adventure state the AI sees every turn.
String taleStateBlock(Tale t) => [
  'PROTAGONIST: ${t.protagonist}',
  if (t.premise.isNotEmpty) 'PREMISE: ${t.premise}',
  '${genreById(t.genre).healthLabel.toUpperCase()}: ${t.health}/100',
  'INVENTORY: ${t.inventory.isEmpty ? 'nothing' : t.inventory.join(', ')}',
  if (t.status.isNotEmpty) 'STATUS: ${t.status}',
  if (t.goals.isNotEmpty)
    'GOALS: ${t.goals.map((g) => '${g.title} [${g.status.name}]${g.description.isEmpty ? '' : ': ${g.description}'}').join('; ')}',
  if (t.npcs.isNotEmpty)
    'CHARACTERS: ${t.npcs.take(14).map((n) => '${n.name}${n.role.isEmpty ? '' : ' (${n.role})'}${n.gender.isEmpty ? '' : ', ${n.gender}'}${n.alive ? '' : ' [dead]'}').join('; ')}',
  if (t.bondsPrompt(t.npcs).isNotEmpty) t.bondsPrompt(t.npcs),
  if (t.profilesPrompt(t.npcs, focus: recentFocus(t.log)).isNotEmpty)
    t.profilesPrompt(t.npcs, focus: recentFocus(t.log)),
  t.vitals.prompt(),
  walletPrompt(t),
  t.chronicle.prompt(focus: '${t.scene.title} ${recentFocus(t.log)}'),
  if (t.canon.isNotEmpty)
    'CANON (never contradict):\n${relevantCanon(t.canon, '${t.scene.title} ${recentFocus(t.log)}', max: 20).map((c) => '- [${c.kind}] ${c.name}${c.text.isEmpty ? '' : ': ${c.text}'}').join('\n')}',
  if (t.scene.title.isNotEmpty) 'SCENE: ${t.scene.title}',
  if (t.memory.isNotEmpty) 'STORY SO FAR: ${t.memory}',
  'TURN: ${t.turns}',
  if (t.directionPrompt(t.turns).isNotEmpty) t.directionPrompt(t.turns),
].join('\n');

/// AI narrator for genre text adventures (no D&D rules).
class TaleNarrator {
  TaleNarrator(this.settings);
  final SettingsController settings;

  String _system(Tale t) {
    final g = genreById(t.genre);
    final length = switch (settings.verbosity) {
      Verbosity.brief => '2-3 vivid sentences',
      Verbosity.balanced => '1-2 short paragraphs (60-140 words)',
      Verbosity.lavish => '2-3 rich paragraphs (120-220 words)',
    };
    return '''
You are the narrator of an interactive text adventure in the ${g.name} genre. ${g.style}
${settings.matureContent ? 'Mature themes are allowed, without gratuitous gore. Romance may be passionate but never explicit.' : 'Keep it PG-13; romance stays at flirting, confessions and a kiss.'}
Write in second person present tense ("you"), $length per turn. Keep the whole response concise and omit nonessential fields rather than running long. Be specific and sensory; vary rhythm; end on a hook. Never decide the player's feelings or actions for them.
Offer 3-4 distinct, interesting choices each turn. Let clever or bold choices matter. Consequences are real: the player can be hurt (${g.healthLabel}), gain or lose items, and the story can end.
Give the story memorable characters with names, wants and secrets. Introduce each new one in "people" with their gender, a short backstory, personality, goal and need, and an honest "stance" toward the player. Characters can become friends, rivals, enemies or love interests: when the player's words or actions move someone, add a "relationships" entry (usually ±2-8, ±15-35 for betrayals, rescues and declarations) and set "status" to an accurate label (Enemy, Rival, Suspicious, Ally, Friend, Mentor, Family, Partner…). Villains and anyone out to harm the player are Enemies, never acquaintances. Romance only grows if the player pursues it and it fits the character. Let relationships change how people act. When the story changes someone (a new goal, something they'll remember, how they've grown), add a "characters" entry.
"dialogue" is extra: a short reaction, aside or opinion that ADDS something. Never repeat or paraphrase lines already spoken in the narration, and don't give dialogue to someone who already spoke in it this turn. Often there is none.
Track continuity: before writing, check WORLD MEMORY, CANON, CHARACTER PROFILES and GOALS and never contradict them (names, deaths, injuries, promises, where people are). Put durable facts (names, places, items, promises, clues, secrets) in "memory" and lasting changes to the world in "consequences" with the player's action as the reason. Keep GOALS current, with a description and an "update" when they progress. The protagonist gets tired, hungry, thirsty, sick and stressed: report changes in "vitals" and let low values show. Money is real: whenever coins change hands (paying, earning, finding, stealing, being robbed, lending, repaying) add a "money" entry in the story's currency; never let the player spend more than they carry. When the player gets something readable (a note, letter, book, scroll, log, file), give its full text in inventory_add. Build toward a climax and a satisfying ending within roughly 15-30 turns.
Respond with ONE JSON object only:
{"title": "short scene name",
 "narration": "prose",
 "speaker": "optional name if the narration is mostly one character talking",
 "dialogue": [{"name": "character present", "line": "a short in-character remark"}],
 "choices": ["short option", "..."],
 "scene": {"location_type": "$_taleLocations", "time": "dawn|day|dusk|night", "mood": "calm|tense|mystery|combat|triumph|sad|eerie|festive", "image_prompt": "one-sentence visual description for an illustrator"},
 "people": [{"name": "Full Name", "role": "short role", "gender": "female|male|nonbinary", "description": "look and manner in one sentence", "backstory": "2-3 sentences", "personality": "a few words", "goal": "what they want", "need": "what they truly need", "stance": "enemy|hostile|wary|neutral|friendly|ally"}],
 "relationships": [{"name": "character", "friendship": 0, "romance": 0, "status": "accurate label", "reason": "why"}],
 "characters": [{"name": "character", "personality": "optional", "goal": "optional", "need": "optional", "memory": "optional: what they'll remember", "growth": "optional: how they changed"}],
 "memory": [{"kind": "npc|place|item|promise|clue|lore|fact", "name": "short unique name", "text": "one-sentence fact"}],
 "consequences": [{"kind": "faction|place|promise|fact|clue", "name": "what changed", "state": "how it is now", "reason": "because the player…"}],
 "goals": [{"title": "objective", "status": "new|update|done|failed", "description": "what it involves", "update": "what just changed, if anything", "giver": "optional", "reward": "optional"}],
 "inventory_add": ["item", {"name": "Torn letter", "text": "only for readable items: what it says"}], "inventory_remove": ["item"], "health_change": -20..20, "status": "short condition or empty",
 "vitals": {"energy": 0, "hunger": 0, "thirst": 0, "sickness": 0, "stamina": 0, "morale": 0, "stress": 0},
 "money": [{"amount": -5, "counterparty": "who (or empty)", "category": "purchase|sale|loot|wage|reward|gift|loan|repayment|theft|stolen|bribe|fine|tax|gamble|other", "note": "what for"}],
 "achievement": null or {"title": "2-4 words", "description": "a genuinely remarkable deed", "icon": "star|sword|heart|crown|skull|map|book|shield|fire|moon"},
 "moment": "optional: one sentence if this turn has a big dramatic beat worth an illustration",
 "ending": null or "good|bad|neutral"}
Omit empty lists. When "ending" is set, write a final epilogue as the narration and give no choices.''';
  }

  Future<TaleTurn> _run(
    Tale t,
    String userTurn,
    void Function(String)? onNarration, {
    AiTrace? trace,
    List<String> images = const [],
  }) async {
    final notes = List<String>.of(t.pendingNotes);
    if (notes.isNotEmpty)
      userTurn =
          'Since your last reply (weave in naturally if relevant): ${notes.join(' ')}\n\n$userTurn';
    trace?.step(
      'Gathering what the story remembers',
      detail:
          '${t.canon.length} facts · ${t.chronicle.facts.length} world changes · ${t.npcs.length} people · ${t.aiHistory.length ~/ 2} recent turns${notes.isEmpty ? '' : ' · ${notes.length} things you did meanwhile'}',
    );
    final client = GatewayClient(apiKey: settings.apiKey, target: t.usage);
    // Cache-friendly: a fixed setup and the whole recent history first, the changing state last.
    final msgs = <ChatMessage>[
      ChatMessage('system', _system(t), cache: true),
      ChatMessage(
        'user',
        'STORY: "${t.title}"${t.premise.isEmpty ? '' : ' — ${t.premise}'}\nPROTAGONIST: ${t.protagonist}',
      ),
      const ChatMessage(
        'assistant',
        '{"narration": "(Understood. I will narrate in JSON.)", "choices": []}',
      ),
      for (final h in t.aiHistory)
        ChatMessage(h.startsWith('P:') ? 'user' : 'assistant', h.substring(2)),
    ];
    final last = msgs.removeLast();
    msgs
      ..add(ChatMessage(last.role, last.content, cache: true))
      ..add(
        ChatMessage(
          'user',
          '$userTurn\n\n(Current state)\n${taleStateBlock(t)}\nRespond with the JSON object only.',
          images: images,
        ),
      );
    if (trace != null) {
      trace.context.addAll([
        for (final m in msgs)
          (
            m.role,
            m.images.isEmpty
                ? m.content
                : '${m.content}\n[${m.images.length} picture(s) attached]',
          ),
      ]);
      trace.client = client;
      client.onReasoning = trace.think;
      trace.step(
        'Asking ${settings.textModel.replaceFirst('or:', '')}',
        detail:
            '${msgs.length} messages · about ${(trace.contextChars / 4).round()} tokens of context',
      );
    }
    String raw;
    try {
      if (settings.streaming && onNarration != null) {
        final sb = StringBuffer();
        await for (final d in client.stream(
          model: settings.textModel,
          messages: msgs,
          temperature: settings.temperature,
          maxTokens: null,
        )) {
          sb.write(d);
          trace?.write(d);
          final p = partialJsonString(sb.toString(), 'narration');
          if (p != null) onNarration(p);
        }
        raw = sb.toString();
      } else {
        raw = await client.complete(
          model: settings.textModel,
          messages: msgs,
          temperature: settings.temperature,
          maxTokens: null,
          json: true,
        );
        trace?.write(raw);
      }
    } finally {
      client.close();
    }
    var tokens = client.spentTokens;
    var cost = client.spentCost;
    TaleTurn turn;
    trace?.step('Reading the reply');
    turn = TaleTurn.parse(raw);
    turn
      ..tokens = tokens
      ..cost = cost;
    trace?.readTools(extractJsonObject(raw));
    if (trace != null && trace.tools.isNotEmpty)
      trace.step(
        'Applying ${trace.tools.length} actions',
        detail: trace.tools.map((x) => x.$1).toSet().join(', '),
      );
    t.pendingNotes.removeRange(0, notes.length.clamp(0, t.pendingNotes.length));
    t.aiHistory.add('P:$userTurn');
    t.aiHistory.add(
      'D:${jsonEncode({'narration': turn.narration, 'choices': turn.choices})}',
    );
    return turn;
  }

  Future<TaleTurn> begin(
    Tale t, {
    void Function(String)? onNarration,
    AiTrace? trace,
  }) => _run(
    t,
    'Begin the story with a gripping opening scene that establishes who the protagonist is, where they are, what is at stake, and at least one named character. Include "people", "goals" and "scene".',
    onNarration,
    trace: trace,
  );

  Future<TaleTurn> act(
    Tale t,
    String action, {
    void Function(String)? onNarration,
    AiTrace? trace,
    List<String> images = const [],
  }) => _run(t, action, onNarration, trace: trace, images: images);

  /// Writes a title and premise for a new story.
  Future<(String, String)> idea(String genre, {String seed = ''}) async {
    final client = GatewayClient(apiKey: settings.apiKey, category: 'tools');
    try {
      final raw = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 1.0,
        maxTokens: 1500,
        json: true,
        messages: [
          ChatMessage(
            'system',
            'You pitch short interactive stories. Genre: ${genreById(genre).name}. ${genreById(genre).style} Reply ONLY JSON: {"title": "2-5 word title", "premise": "2 sentence hook in second person"}',
          ),
          ChatMessage('user', seed.isEmpty ? 'Surprise me.' : 'Idea: $seed'),
        ],
      );
      final j = extractJsonObject(raw) ?? {};
      return (
        (j['title'] ?? 'Untitled').toString(),
        (j['premise'] ?? '').toString(),
      );
    } finally {
      client.close();
    }
  }

  /// Compresses old turns into a running summary.
  Future<void> summarize(Tale t) async {
    if (t.aiHistory.length < 20) return;
    final old = t.aiHistory.sublist(0, t.aiHistory.length - 10);
    final client = GatewayClient(apiKey: settings.apiKey, target: t.usage);
    try {
      final s = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 0.3,
        maxTokens: 1500,
        messages: [
          const ChatMessage(
            'system',
            'Summarize this interactive story so far in under 140 words: key events, characters, items, open threads. Durable facts live in the canon; focus on what happened and why.',
          ),
          ChatMessage(
            'user',
            'Previous summary: ${t.memory}\n\n${old.join('\n')}',
          ),
        ],
      );
      t.memory = s.trim();
      t.aiHistory = t.aiHistory.sublist(t.aiHistory.length - 10);
    } catch (_) {
    } finally {
      client.close();
    }
  }
}

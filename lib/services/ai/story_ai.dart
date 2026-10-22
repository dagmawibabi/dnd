import '../../game/story.dart';
import '../../game/story_host.dart';
import '../../models/adventure.dart';
import '../../models/world.dart';
import '../../data/tale_genres.dart';
import '../../models/tale.dart';
import '../narrator.dart';
import 'dungeon_master.dart' show dmStateBlock;
import 'tale_narrator.dart' show taleStateBlock;
import '../settings.dart';
import 'ai_trace.dart';
import 'gateway_client.dart';

/// An AI answer and what it cost.
class AiResult<T> {
  const AiResult(this.value, {this.tokens = 0, this.cost = 0});
  final T value;
  final int tokens;
  final double cost;
}

/// A character's reply in a private conversation.
class CharacterReply {
  CharacterReply({
    required this.text,
    this.friendship = 0,
    this.romance = 0,
    this.status,
    this.romanceClosed,
    this.note = '',
    this.memory = '',
    this.tokens = 0,
    this.cost = 0,
  });
  final String text;
  final int friendship;
  final int romance;
  final String? status;
  final bool? romanceClosed;
  final String note;
  final String memory;
  final int tokens;
  final double cost;
}

/// How a character opens a conversation they started themselves.
class Opener {
  const Opener({required this.text, this.topic = '', this.skip = false});
  final String text;

  /// A few words on what it's about ("The burned bridge"), written for this moment.
  final String topic;

  /// The moment is wrong (a fight, a chase, a tense scene): they wait.
  final bool skip;
}

/// AI features shared by D&D adventures and text adventures.
class StoryAi {
  StoryAi(this.settings);
  final SettingsController settings;

  String get _fast =>
      settings.fastModel.isEmpty ? settings.textModel : settings.fastModel;

  String get _rating => settings.matureContent
      ? 'Mature themes are allowed (romance may be passionate but never explicit; no gratuitous gore).'
      : 'Keep it PG-13: romance can include flirting, confessions and kisses, nothing explicit.';

  Future<AiResult<String>> _ask(
    StoryHost host,
    String system,
    String user, {
    String category = 'tools',
    int maxTokens = 2500,
    double temperature = 0.8,
    bool json = false,
    List<String> images = const [],
    AiTrace? trace,
  }) async {
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: category,
      target: host.usageTotals,
    );
    final model = images.isEmpty ? _fast : settings.textModel;
    final messages = [
      ChatMessage('system', system),
      ChatMessage('user', user, images: images),
    ];
    if (trace != null) {
      trace.context.addAll([
        for (final m in messages)
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
        'Asking ${model.replaceFirst('or:', '')}',
        detail:
            '${messages.length} messages · about ${(trace.contextChars / 4).round()} tokens of context',
      );
    }
    try {
      final text = await client.complete(
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        json: json,
        messages: messages,
      );
      trace?.write(text);
      trace?.readTools(extractJsonObject(text));
      return AiResult(
        text.trim(),
        tokens: client.spentTokens,
        cost: client.spentCost,
      );
    } finally {
      client.close();
    }
  }

  String _context(StoryHost host) =>
      '${host.aiContext}\n\nRECENT STORY:\n${recentStory(host.log)}';

  /// In-character reply to the protagonist, with relationship changes.
  /// [images] are pictures the player shows (data URLs).
  Future<CharacterReply> reply(
    StoryHost host,
    Npc npc,
    String line, {
    List<String> images = const [],
    AiTrace? trace,
  }) async {
    final bond = host.world.bondFor(npc);
    final all = host.world.chatWith(npc.id);
    final history =
        all.isNotEmpty && all.last.fromPlayer && all.last.text == line
        ? all.sublist(0, all.length - 1)
        : all;
    final past = history.length > 16
        ? history.sublist(history.length - 16)
        : history;
    if (AiRoute.isLmStudio(_fast))
      return _localReply(host, npc, line, past, images: images, trace: trace);
    final transcript = [
      for (final l in past)
        '${l.fromPlayer ? host.playerName : npc.name}: ${l.text}',
    ].join('\n');
    final system =
        '''
You role-play ${npc.name}${npc.role.isEmpty ? '' : ', ${npc.role}'} in an interactive story. ${host.worldStyle}
About ${npc.name}: ${npc.description.isEmpty ? 'decide a consistent personality from the story so far' : npc.description}${npc.notes.isEmpty ? '' : '\nWhat ${npc.name} remembers: ${npc.notes}'}
${host.world.profileOf(npc).prompt()}
How ${npc.name} feels about ${host.playerName}: ${bond.describe(npc.name)}.
Stay in character, true to your backstory, personality, goals and memories. Reply in 1-4 sentences of natural speech (actions in *asterisks* are fine). Have your own goals, opinions and boundaries; you may refuse, tease, lie or change the subject.
Respect current world memory and your personal history. Only discuss facts your character could reasonably know; private secrets of other people are not automatically known to you.
Relationships evolve slowly and believably. Romance happens only if ${host.playerName} pursues it and it fits who ${npc.name} is; ${npc.name} can welcome it, be shy, or turn it down kindly (set "romance_closed": true only for a clear, lasting no). $_rating
Reply ONLY with JSON: {"reply": "what ${npc.name} says", "friendship_change": -10..10, "romance_change": -10..10, "status": "optional new relationship label like Friends, Partners, Rivals, or empty", "romance_closed": false, "note": "optional short thing ${npc.name} will remember about ${host.playerName}", "memory": "optional durable story fact revealed in this exchange, or empty"}''';
    final memories = host.world.chronicle.history.reversed
        .where(
          (h) =>
              h.name.toLowerCase() == npc.name.toLowerCase() ||
              line.toLowerCase().contains(h.name.toLowerCase()),
        )
        .take(8)
        .map((h) => '${h.name}: ${h.after} Because: ${h.reason}')
        .join('\n');
    final user =
        '${_context(host)}\n\nRELEVANT CHARACTER HISTORY:\n$memories\n\nCONVERSATION SO FAR:\n${transcript.isEmpty ? '(none)' : transcript}\n${host.playerName}: $line';
    final r = await _ask(
      host,
      system,
      images.isEmpty
          ? user
          : '$user\n\n(${host.playerName} shows you the attached picture${images.length == 1 ? '' : 's'}. React to what you actually see in ${images.length == 1 ? 'it' : 'them'}.)',
      category: 'npc',
      maxTokens: 2500,
      temperature: settings.temperature,
      json: true,
      images: images,
      trace: trace,
    );
    final j = extractJsonObject(r.value);
    if (j == null)
      return CharacterReply(
        text: readableNarration(r.value),
        tokens: r.tokens,
        cost: r.cost,
      );
    int n(String k) =>
        ((j[k] ?? 0) is num ? (j[k] ?? 0) as num : num.tryParse('${j[k]}') ?? 0)
            .toInt();
    final status = (j['status'] ?? '').toString().trim();
    return CharacterReply(
      text: _unquote((j['reply'] ?? '...').toString()),
      friendship: n('friendship_change').clamp(-15, 15),
      romance: n('romance_change').clamp(-15, 15),
      status: status.isEmpty ? null : status,
      romanceClosed: j['romance_closed'] == true ? true : null,
      note: (j['note'] ?? '').toString(),
      memory: (j['memory'] ?? '').toString(),
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// The first line when a character comes to the protagonist on their own.
  /// They know where the story is right now, and hold off when it's a bad moment.
  Future<AiResult<Opener>> opener(StoryHost host, Npc npc, String why) async {
    final bond = host.world.bondFor(npc);
    final past = host.world.chatWith(npc.id);
    final recent = past.length > 6 ? past.sublist(past.length - 6) : past;
    final local = AiRoute.isLmStudio(_fast);
    final system =
        '''
You are ${npc.name}${npc.role.isEmpty ? '' : ', ${npc.role}'} in an interactive story. ${host.worldStyle}
About ${npc.name}: ${npc.description.isEmpty ? 'keep a consistent personality that fits the story' : npc.description}${npc.notes.isEmpty ? '' : '\nWhat ${npc.name} remembers: ${npc.notes}'}
${host.world.profileOf(npc).prompt()}
How ${npc.name} feels about ${host.playerName}: ${bond.describe(npc.name)}.
${npc.name} wants a private word with ${host.playerName}. First read the RECENT STORY and the current scene: you are aware of exactly what is happening right now (where everyone is, any danger, who is present). If it is a bad moment for a private talk (a fight, a chase, a tense standoff, someone else mid-conversation, ${npc.name} not present), wait for a better time.
Otherwise write what ${npc.name} says to open the conversation: 1-3 sentences of natural speech in first person that fit this exact moment and place, ending with something ${host.playerName} can answer. A short action in *asterisks* is fine. Only mention facts ${npc.name} could know. $_rating
${local ? 'Reply with only the spoken line, or the single word WAIT if now is a bad moment.' : 'Reply ONLY with JSON: {"wait": false, "line": "what ${npc.name} says", "topic": "3-6 words naming what this is about, e.g. \'The deal with the smugglers\' or \'A favor to ask\'"}'}''';
    final user =
        '${_context(host)}\n\nCURRENT SCENE: ${host.scene.title.isEmpty ? 'unknown' : host.scene.title} (${host.scene.mood}).\n\nWORLD MEMORY:\n${host.world.chronicle.prompt(focus: npc.name)}\n\nTHEIR LAST WORDS TOGETHER:\n${recent.isEmpty ? '(none yet)' : recent.map((l) => '${l.fromPlayer ? host.playerName : npc.name}: ${l.text}').join('\n')}\n\nWHAT IS ON ${npc.name.toUpperCase()}\'S MIND: $why';
    final r = await _ask(
      host,
      system,
      user,
      category: 'npc',
      maxTokens: local ? 300 : 2000,
      temperature: settings.temperature,
      json: !local,
    );
    if (local) {
      final t = cleanLocalReply(r.value, npc.name);
      return AiResult(
        Opener(text: t, skip: t.trim().toUpperCase().startsWith('WAIT')),
        tokens: r.tokens,
        cost: r.cost,
      );
    }
    final j = extractJsonObject(r.value);
    final line = j == null
        ? _unquote(readableNarration(r.value))
        : _unquote((j['line'] ?? j['reply'] ?? '').toString());
    return AiResult(
      Opener(
        text: line,
        topic: (j?['topic'] ?? '').toString().trim(),
        skip: j?['wait'] == true,
      ),
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// Small local models lose track of a long JSON prompt: they narrate the
  /// player's actions instead of answering. So the conversation goes as real
  /// chat turns, the reply is plain speech, and a second short call judges
  /// how the relationship moved.
  Future<CharacterReply> _localReply(
    StoryHost host,
    Npc npc,
    String line,
    List<ChatLine> past, {
    List<String> images = const [],
    AiTrace? trace,
  }) async {
    final me = npc.name;
    final you = host.playerName;
    final bond = host.world.bondFor(npc);
    final system =
        '''
You are $me${npc.role.isEmpty ? '' : ', ${npc.role}'}, talking face to face with $you. ${host.worldStyle}
About you: ${npc.description.isEmpty ? 'keep a consistent personality that fits the story' : npc.description}${npc.notes.isEmpty ? '' : '\nYou remember: ${npc.notes}'}
${host.world.profileOf(npc).prompt(memoriesShown: 5)}
How you feel about $you: ${bond.describe(me)}.
Established world memory (respect it; only discuss what your character could know):
${host.world.chronicle.prompt(focus: '$me $line')}
What has happened lately:
${recentStory(host.log, entries: 6, maxChars: 1000)}

Rules:
- You ARE $me. Speak only as $me, in first person ("I").
- Answer exactly what $you just said to you. If asked a question, answer it.
- 1 to 3 sentences of natural speech. A short action in *asterisks* is fine.
- Never describe what $you does or feels, and never write $you's lines.
- No names before your line, no quotes around it, no JSON.
$_rating''';
    final msgs = [ChatMessage('system', system)];
    void add(String role, String text) {
      // Chat templates expect user and assistant turns to alternate.
      if (msgs.length > 1 && msgs.last.role == role) {
        msgs.add(ChatMessage(role, '${msgs.removeLast().content}\n$text'));
      } else {
        msgs.add(ChatMessage(role, text));
      }
    }

    for (final l in past.length > 12 ? past.sublist(past.length - 12) : past) {
      add(l.fromPlayer ? 'user' : 'assistant', l.text);
    }
    if (images.isEmpty) {
      add('user', line);
    } else {
      msgs.add(
        ChatMessage(
          'user',
          '$line\n(I show you this picture.)',
          images: images,
        ),
      );
    }
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'npc',
      target: host.usageTotals,
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
        'Asking ${_fast.replaceFirst('lm:', '')}',
        detail: '${msgs.length} chat messages',
      );
    }
    try {
      final raw = await client.complete(
        model: _fast,
        temperature: settings.temperature.clamp(0.2, 0.75).toDouble(),
        maxTokens: 400,
        messages: msgs,
      );
      trace?.write(raw);
      final text = cleanLocalReply(raw, me);
      var friendship = 0, romance = 0;
      try {
        trace?.step('Reading the relationship change');
        final judged = await client.complete(
          model: _fast,
          temperature: 0.2,
          maxTokens: 60,
          messages: [
            ChatMessage(
              'system',
              'You judge relationships in a story. Given one exchange, say how it changes $me\'s feelings toward $you. Small changes: usually 0, 1 or 2; at most 5 either way. Romance moves only if $you flirts or shows romantic interest. Reply with JSON only, like {"friendship": 1, "romance": 0}',
            ),
            ChatMessage('user', '$you: $line\n$me: $text'),
          ],
        );
        final j = extractJsonObject(judged);
        int n(String k) =>
            ((j?[k] ?? 0) is num
                    ? (j?[k] ?? 0) as num
                    : num.tryParse('${j?[k]}') ?? 0)
                .toInt()
                .clamp(-5, 5);
        friendship = n('friendship');
        romance = n('romance');
      } catch (_) {
        // The reply matters more than the score.
      }
      return CharacterReply(
        text: text,
        friendship: friendship,
        romance: romance,
        tokens: client.spentTokens,
        cost: client.spentCost,
      );
    } finally {
      client.close();
    }
  }

  /// Strips what small models wrap around a line of speech: code fences,
  /// a "Name:" prefix, quotes, or a stray JSON object.
  static String cleanLocalReply(String raw, String name) {
    var t = raw.trim().replaceAll(RegExp(r'^```[a-z]*\s*|\s*```$'), '').trim();
    if (t.startsWith('{')) {
      final j = extractJsonObject(t);
      final r = j?['reply'] ?? j?['text'] ?? j?['speech'];
      if (r != null) t = r.toString().trim();
    }
    for (final prefix in {name, name.split(' ').first}) {
      final m = RegExp(
        '^\\**${RegExp.escape(prefix)}\\**\\s*:\\s*\\**\\s*',
        caseSensitive: false,
      ).firstMatch(t);
      if (m != null) {
        t = t.substring(m.end);
        break;
      }
    }
    t = _unquote(t);
    return t.isEmpty ? '…' : t;
  }

  static String _unquote(String text) {
    final t = text.trim();
    for (final (o, c) in const [('"', '"'), ('“', '”')]) {
      if (t.length >= 2 &&
          t.startsWith(o) &&
          t.endsWith(c) &&
          !t.substring(1, t.length - 1).contains(o))
        return t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  /// Casts a fitting voice for every character who doesn't have one yet.
  /// Returns how many voices were assigned.
  Future<int> assignVoices(StoryHost host, Narrator narrator) async {
    if (!settings.useCloudVoice || !settings.useAiText || !settings.npcVoices)
      return 0;
    if (settings.useElevenLabs && narrator.elevenVoices.isEmpty)
      await narrator.loadElevenVoices();
    final narratorVoice = narrator.narratorVoice;
    final options = narrator.voiceChoices
        .where((o) => o.$1 != narratorVoice)
        .toList();
    if (options.length < 2) return 0;
    final ids = {for (final o in options) o.$1};
    final cast = host.people
        .where((p) => !ids.contains(host.world.voices[p.id]))
        .take(12)
        .toList();
    if (cast.isEmpty) return 0;
    final r = await _ask(
      host,
      'You cast voice actors for characters in an audio drama. Pick the best-fitting voice for each character by gender, age, personality and accent. Vary voices so characters in the same scene sound different. Use only the voice ids given. Reply ONLY JSON: {"voices": {"<character name>": "<voice id>"}}',
      'VOICES:\n${options.map((o) => '- ${o.$1}: ${o.$2}').join('\n')}\n\nCHARACTERS:\n${cast.map((p) => '- ${p.name}${p.role.isEmpty ? '' : ' (${p.role})'}: ${p.description.isEmpty ? 'no description' : p.description}').join('\n')}\n\n${host.worldStyle}',
      category: 'voice',
      temperature: 0.4,
      maxTokens: 2500,
      json: true,
    );
    final picks = extractJsonObject(r.value)?['voices'];
    if (picks is! Map) return 0;
    var n = 0;
    for (final p in cast) {
      final v =
          (picks[p.name] ??
                  picks.entries
                      .where(
                        (e) =>
                            e.key.toString().toLowerCase() ==
                            p.name.toLowerCase(),
                      )
                      .firstOrNull
                      ?.value)
              ?.toString();
      if (v != null && ids.contains(v)) {
        host.world.voices[p.id] = v;
        n++;
      }
    }
    if (n > 0) host.save();
    return n;
  }

  /// "Previously on…" for a story you are returning to.
  Future<AiResult<String>> recap(StoryHost host) => _ask(
    host,
    'Write a "Previously on…" recap for a player returning to their interactive story. Second person, 70-110 words, vivid but clear: where they are, what is at stake, who matters, and the open question. No headings.',
    _context(host),
    temperature: 0.6,
  );

  /// "Previously on…" for a story that isn't open (shown on its cover page).
  Future<AiResult<String>> recapOf(StoryRecord record) async {
    final String context;
    final Map<String, num> usage;
    if (record is Adventure) {
      context =
          'A solo ${record.setting} D&D adventure, "${record.title}": ${record.premise}\n${dmStateBlock(record)}\n\nRECENT STORY:\n${recentStory(record.log)}';
      usage = record.usage;
    } else {
      final t = record as Tale;
      context =
          'A ${genreById(t.genre).name} interactive story, "${t.title}".\n${taleStateBlock(t)}\n\nRECENT STORY:\n${recentStory(t.log)}';
      usage = t.usage;
    }
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'tools',
      target: usage,
    );
    try {
      final text = await client.complete(
        model: _fast,
        temperature: 0.6,
        maxTokens: 3000,
        messages: [
          const ChatMessage(
            'system',
            'Write a "Previously on…" recap for a player returning to their interactive story. Second person, 70-110 words, vivid but clear: where they are, what is at stake, who matters, and the open question. No headings.',
          ),
          ChatMessage('user', context),
        ],
      );
      return AiResult(
        text.trim(),
        tokens: client.spentTokens,
        cost: client.spentCost,
      );
    } finally {
      client.close();
    }
  }

  /// Answers a question about the world without advancing the story.
  Future<AiResult<String>> lore(StoryHost host, String question) => _ask(
    host,
    'You are the keeper of this story\'s lore. Answer the player\'s question in 2-5 sentences using only what the story has established; if it is unknown to the protagonist, say so in an intriguing way and suggest how they might find out. Never invent major plot facts, never advance time, no spoilers beyond what the protagonist could know.',
    '${_context(host)}\n\nQUESTION: $question',
    temperature: 0.5,
  );

  /// Three fresh ideas for what to do next.
  Future<AiResult<List<String>>> inspire(StoryHost host) async {
    final r = await _ask(
      host,
      'Suggest exactly three creative, distinct things the protagonist could do next: one bold, one clever, one personal (involving a character). Each is a short imperative sentence under 14 words. Reply ONLY JSON: {"ideas": ["...", "...", "..."]}',
      _context(host),
      temperature: 1.0,
      maxTokens: 2500,
      json: true,
    );
    final j = extractJsonObject(r.value);
    final ideas = [
      for (final x in (j?['ideas'] as List? ?? const [])) x.toString(),
    ].where((s) => s.trim().isNotEmpty).take(3).toList();
    return AiResult(
      ideas.isEmpty ? [r.value] : ideas,
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// A diary entry written by the protagonist.
  Future<AiResult<String>> diary(StoryHost host) => _ask(
    host,
    'Write a private diary entry by the protagonist about recent events: first person, 120-180 words, in their voice, with feelings about the people around them, a worry and a hope. Start with a short dated-style heading line like "Day 3, the Sunken Vault".',
    _context(host),
    temperature: 0.9,
    maxTokens: 2500,
  );

  /// Fills in who a character is: backstory, personality, wants and needs,
  /// consistent with everything the story has shown of them.
  Future<AiResult<PersonProfile>> profile(StoryHost host, Npc npc) async {
    final known = host.world.profileOf(npc);
    final said = [
      for (final e in host.log)
        if (e.speaker == npc.name || e.text.contains(npc.name.split(' ').first))
          e.text,
    ];
    final r = await _ask(
      host,
      'You write character profiles for an interactive story. Invent a believable inner life for ${npc.name} that fits the world and NEVER contradicts what the story has shown. Keep secrets intriguing. Reply ONLY JSON: {"backstory": "3-5 sentences: origins, a defining event, why they are here", "personality": "a few words", "traits": ["3-5 single words"], "goals": ["1-3 things they want"], "needs": ["1-2 deeper needs"], "secret": "something they hide", "age": "rough age or life stage", "occupation": "what they do"}',
      '${host.worldStyle}\nCHARACTER: ${npc.name}${npc.role.isEmpty ? '' : ', ${npc.role}'}${npc.gender.isEmpty ? '' : ', ${npc.gender}'}. ${npc.description}\nWHAT THEY THINK OF THE PROTAGONIST: ${host.world.bondFor(npc).describe(npc.name)}\nALREADY KNOWN: ${known.prompt()}\nWHAT THE STORY SHOWED OF THEM:\n${said.reversed.take(10).toList().reversed.map((t) => '- ${t.length > 300 ? t.substring(0, 300) : t}').join('\n')}\n\n${host.world.chronicle.prompt(focus: npc.name)}',
      category: 'character',
      maxTokens: 2500,
      temperature: 0.85,
      json: true,
    );
    final j = extractJsonObject(r.value) ?? const {};
    List<String> list(dynamic v) => v is List
        ? [for (final x in v) x.toString()]
        : (v == null || '$v'.isEmpty ? <String>[] : ['$v']);
    return AiResult(
      PersonProfile(
        backstory: (j['backstory'] ?? '').toString(),
        personality: (j['personality'] ?? '').toString(),
        traits: list(j['traits']),
        goals: list(j['goals']),
        needs: list(j['needs']),
        secret: (j['secret'] ?? '').toString(),
        age: (j['age'] ?? '').toString(),
        occupation: (j['occupation'] ?? '').toString(),
      ),
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// What a book, scroll, note or letter the protagonist carries actually says.
  Future<AiResult<ItemWriting>> readItem(
    StoryHost host,
    String item, {
    String description = '',
  }) async {
    final r = await _ask(
      host,
      'You write the contents of documents found in an interactive story. Write what "$item" says, in the voice of whoever wrote it, 80-300 words. Fit the world and the story so far, and include at least one detail that matters (a clue, a name, a warning, a secret), but never contradict established facts. Reply ONLY JSON: {"title": "its title or first line", "author": "who wrote it, or empty", "text": "the full text, with line breaks as \\n"}',
      '${_context(host)}\n\nITEM: $item${description.isEmpty ? '' : ' — $description'}',
      category: 'tools',
      maxTokens: 2500,
      temperature: 0.85,
      json: true,
    );
    final j = extractJsonObject(r.value);
    final text = (j?['text'] ?? r.value)
        .toString()
        .replaceAll(r'\n', '\n')
        .trim();
    return AiResult(
      ItemWriting(
        title: (j?['title'] ?? item).toString(),
        kind: writingKind(item),
        text: text,
        author: (j?['author'] ?? '').toString(),
      ),
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// Makes an item from the player's words ("a phone", "a red flower").
  Future<AiResult<Map<String, String>>> createItem(
    StoryHost host,
    String idea,
  ) async {
    final r = await _ask(
      host,
      'You create one item for the protagonist\'s inventory in an interactive story, from the player\'s idea. Fit it to the world (in a fantasy world a "phone" becomes a magical sending-stone, unless the world has phones). Reply ONLY JSON: {"name": "short item name", "description": "one or two vivid sentences", "kind": "weapon|armor|tool|food|potion|clothing|jewelry|document|key|trinket|tech|other", "text": "only if it has writing on it: what it says, else empty", "value": "rough worth in this world, or empty"}',
      '${host.worldStyle}\n${host.aiContext}\n\nPLAYER\'S IDEA: $idea',
      category: 'tools',
      maxTokens: 2000,
      temperature: 0.9,
      json: true,
    );
    final j = extractJsonObject(r.value) ?? const {};
    return AiResult(
      {
        for (final k in const ['name', 'description', 'kind', 'text', 'value'])
          k: (j[k] ?? '').toString().trim(),
      },
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// What things cost in this world and how its economy feels right now.
  Future<AiResult<(String, List<Map<String, String>>)>> economy(
    StoryHost host,
    String currency,
  ) async {
    final r = await _ask(
      host,
      'You describe the local economy of an interactive story for the player\'s wallet screen. Use the story\'s currency ($currency). Fit the world, the current place and recent events (a siege makes bread dear, a boom makes work easy). Reply ONLY JSON: {"note": "1-2 sentences on the local economy right now", "prices": [{"item": "a common thing to buy", "price": "e.g. 3 $currency"}]} with 10-14 everyday and adventuring items, cheap to expensive.',
      _context(host),
      temperature: 0.7,
      json: true,
    );
    final j = extractJsonObject(r.value) ?? const {};
    final prices = [
      for (final p in (j['prices'] as List? ?? const []))
        if (p is Map && p['item'] != null)
          {
            'item': p['item'].toString(),
            'price': (p['price'] ?? '').toString(),
          },
    ];
    return AiResult(
      ((j['note'] ?? '').toString(), prices),
      tokens: r.tokens,
      cost: r.cost,
    );
  }

  /// Where a quest or goal stands and what might move it forward.
  Future<AiResult<String>> questHint(StoryHost host, Quest q) => _ask(
    host,
    'Help the player with one quest or goal in their interactive story. In 3-5 short sentences: what is known so far, who or what seems connected, and two concrete ideas for what to try next. Use only what the protagonist could know; no spoilers, never invent major facts.',
    '${_context(host)}\n\nQUEST: ${q.title} [${q.status.name}]. ${q.description}\nSTEPS SO FAR: ${q.updates.map((u) => 'turn ${u.turn}: ${u.text}').join('; ')}',
    temperature: 0.6,
    maxTokens: 2500,
  );

  /// A one-sentence illustration brief for a dramatic moment.
  Future<AiResult<String>> momentPrompt(StoryHost host, String moment) => _ask(
    host,
    'Write ONE sentence (max 45 words) describing a dramatic illustration of the moment below, as a film still: subject, action, lighting, mood. No names of real artists, no text in the image.',
    '${host.aiContext}\n\nMOMENT: $moment',
    category: 'effects',
    temperature: 0.8,
    maxTokens: 2500,
  );
}

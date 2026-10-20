import '../../game/story.dart';
import '../../game/story_host.dart';
import '../../models/adventure.dart';
import '../narrator.dart';
import '../settings.dart';
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
  CharacterReply({required this.text, this.friendship = 0, this.romance = 0, this.status, this.romanceClosed, this.note = '', this.memory = '', this.tokens = 0, this.cost = 0});
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

/// AI features shared by D&D adventures and text adventures.
class StoryAi {
  StoryAi(this.settings);
  final SettingsController settings;

  String get _fast => settings.fastModel.isEmpty ? settings.textModel : settings.fastModel;

  String get _rating => settings.matureContent
      ? 'Mature themes are allowed (romance may be passionate but never explicit; no gratuitous gore).'
      : 'Keep it PG-13: romance can include flirting, confessions and kisses, nothing explicit.';

  Future<AiResult<String>> _ask(StoryHost host, String system, String user, {String category = 'tools', int maxTokens = 700, double temperature = 0.8, bool json = false}) async {
    final client = GatewayClient(apiKey: settings.apiKey, category: category, target: host.usageTotals);
    try {
      final text = await client.complete(model: _fast, temperature: temperature, maxTokens: maxTokens, json: json, messages: [ChatMessage('system', system), ChatMessage('user', user)]);
      return AiResult(text.trim(), tokens: client.spentTokens, cost: client.spentCost);
    } finally {
      client.close();
    }
  }

  String _context(StoryHost host) => '${host.aiContext}\n\nRECENT STORY:\n${recentStory(host.log)}';

  /// In-character reply to the protagonist, with relationship changes.
  Future<CharacterReply> reply(StoryHost host, Npc npc, String line) async {
    final bond = host.world.bondFor(npc);
    final all = host.world.chatWith(npc.id);
    final history = all.isNotEmpty && all.last.fromPlayer && all.last.text == line ? all.sublist(0, all.length - 1) : all;
    final past = history.length > 16 ? history.sublist(history.length - 16) : history;
    final transcript = [for (final l in past) '${l.fromPlayer ? host.playerName : npc.name}: ${l.text}'].join('\n');
    final system = '''
You role-play ${npc.name}${npc.role.isEmpty ? '' : ', ${npc.role}'} in an interactive story. ${host.worldStyle}
About ${npc.name}: ${npc.description.isEmpty ? 'decide a consistent personality from the story so far' : npc.description}${npc.notes.isEmpty ? '' : '\nWhat ${npc.name} remembers: ${npc.notes}'}
How ${npc.name} feels about ${host.playerName}: ${bond.describe(npc.name)}.
Stay in character. Reply in 1-4 sentences of natural speech (actions in *asterisks* are fine). Have your own goals, opinions and boundaries; you may refuse, tease, lie or change the subject.
Relationships evolve slowly and believably. Romance happens only if ${host.playerName} pursues it and it fits who ${npc.name} is; ${npc.name} can welcome it, be shy, or turn it down kindly (set "romance_closed": true only for a clear, lasting no). $_rating
Reply ONLY with JSON: {"reply": "what ${npc.name} says", "friendship_change": -10..10, "romance_change": -10..10, "status": "optional new relationship label like Friends, Partners, Rivals, or empty", "romance_closed": false, "note": "optional short thing ${npc.name} will remember about ${host.playerName}", "memory": "optional durable story fact revealed in this exchange, or empty"}''';
    final user = '${_context(host)}\n\nCONVERSATION SO FAR:\n${transcript.isEmpty ? '(none)' : transcript}\n${host.playerName}: $line';
    final r = await _ask(host, system, user, category: 'npc', maxTokens: 1500, temperature: settings.temperature, json: true);
    final j = extractJsonObject(r.value);
    if (j == null) return CharacterReply(text: readableNarration(r.value), tokens: r.tokens, cost: r.cost);
    int n(String k) => ((j[k] ?? 0) is num ? (j[k] ?? 0) as num : num.tryParse('${j[k]}') ?? 0).toInt();
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

  static String _unquote(String text) {
    final t = text.trim();
    for (final (o, c) in const [('"', '"'), ('“', '”')]) {
      if (t.length >= 2 && t.startsWith(o) && t.endsWith(c) && !t.substring(1, t.length - 1).contains(o)) return t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  /// Casts a fitting voice for every character who doesn't have one yet.
  /// Returns how many voices were assigned.
  Future<int> assignVoices(StoryHost host, Narrator narrator) async {
    if (!settings.useCloudVoice || !settings.useAiText || !settings.npcVoices) return 0;
    if (settings.useElevenLabs && narrator.elevenVoices.isEmpty) await narrator.loadElevenVoices();
    final narratorVoice = narrator.narratorVoice;
    final options = narrator.voiceChoices.where((o) => o.$1 != narratorVoice).toList();
    if (options.length < 2) return 0;
    final ids = {for (final o in options) o.$1};
    final cast = host.people.where((p) => !ids.contains(host.world.voices[p.id])).take(12).toList();
    if (cast.isEmpty) return 0;
    final r = await _ask(
      host,
      'You cast voice actors for characters in an audio drama. Pick the best-fitting voice for each character by gender, age, personality and accent. Vary voices so characters in the same scene sound different. Use only the voice ids given. Reply ONLY JSON: {"voices": {"<character name>": "<voice id>"}}',
      'VOICES:\n${options.map((o) => '- ${o.$1}: ${o.$2}').join('\n')}\n\nCHARACTERS:\n${cast.map((p) => '- ${p.name}${p.role.isEmpty ? '' : ' (${p.role})'}: ${p.description.isEmpty ? 'no description' : p.description}').join('\n')}\n\n${host.worldStyle}',
      category: 'voice',
      temperature: 0.4,
      maxTokens: 1500,
      json: true,
    );
    final picks = extractJsonObject(r.value)?['voices'];
    if (picks is! Map) return 0;
    var n = 0;
    for (final p in cast) {
      final v = (picks[p.name] ?? picks.entries.where((e) => e.key.toString().toLowerCase() == p.name.toLowerCase()).firstOrNull?.value)?.toString();
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
      maxTokens: 1500,
      json: true,
    );
    final j = extractJsonObject(r.value);
    final ideas = [for (final x in (j?['ideas'] as List? ?? const [])) x.toString()].where((s) => s.trim().isNotEmpty).take(3).toList();
    return AiResult(ideas.isEmpty ? [r.value] : ideas, tokens: r.tokens, cost: r.cost);
  }

  /// A diary entry written by the protagonist.
  Future<AiResult<String>> diary(StoryHost host) => _ask(
        host,
        'Write a private diary entry by the protagonist about recent events: first person, 120-180 words, in their voice, with feelings about the people around them, a worry and a hope. Start with a short dated-style heading line like "Day 3, the Sunken Vault".',
        _context(host),
        temperature: 0.9,
        maxTokens: 1500,
      );

  /// A one-sentence illustration brief for a dramatic moment.
  Future<AiResult<String>> momentPrompt(StoryHost host, String moment) => _ask(
        host,
        'Write ONE sentence (max 45 words) describing a dramatic illustration of the moment below, as a film still: subject, action, lighting, mood. No names of real artists, no text in the image.',
        '${host.aiContext}\n\nMOMENT: $moment',
        category: 'effects',
        temperature: 0.8,
        maxTokens: 1500,
      );
}

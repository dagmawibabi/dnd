import 'dart:convert';

import '../../data/srd.dart';
import '../../game/money.dart' show walletPrompt;
import '../../game/story.dart';
import '../../models/adventure.dart';
import '../../models/character.dart';
import '../../models/world.dart';
import '../settings.dart';
import 'ai_trace.dart';
import 'gateway_client.dart';

const _locationTypes =
    'forest|dungeon|town|tavern|cave|castle|ruins|swamp|mountain|coast|desert|temple|crypt|road|tundra|tower|sewer|plains|camp';

String _dmSystemPrompt(Adventure a, SettingsController s) {
  final length = switch (s.verbosity) {
    Verbosity.brief => '2-3 vivid sentences',
    Verbosity.balanced => '1-2 short paragraphs (60-140 words)',
    Verbosity.lavish => '2-3 rich paragraphs (120-220 words)',
  };
  return '''
You are the Dungeon Master for a SOLO Dungeons & Dragons 5e adventure played in a mobile app.
Setting: ${a.setting}. Tone: ${a.tone}. Difficulty: ${a.difficulty}. ${s.matureContent ? 'Mature themes allowed, but no gratuitous gore.' : 'Keep content PG-13.'}

YOUR CRAFT
- Write second-person narration ("you") in $length. Keep the whole response concise and omit nonessential fields rather than running long. Evocative, sensory, specific; vary rhythm. Never decide the hero's feelings or actions for them.
- Voice NPCs with distinct personalities. Companions are AI-controlled party members with their own opinions; they may interject via party_banter.
- party_banter is extra: a reaction, opinion, joke, worry or aside that ADDS something. Never repeat, quote or paraphrase what anyone already said in the narration this turn, and give no banter to someone who already spoke in it. Often there is no banter at all.
- Offer 3-4 meaningful, distinct choices each turn (mix of action, dialogue, exploration, stealth, magic). Some choices should require ability checks with fair DCs (easy 10, medium 13, hard 16, very hard 19).
- Respect dice outcomes reported by the app: successes should feel earned, failures should complicate the story (never a dead end).
- Track continuity: NPC names, quests, items, wounds. Pace toward a satisfying arc with escalating stakes and a climax.
- Do NOT resolve combat yourself. When a fight begins, emit a "combat" event with the enemies; the app runs tactical combat and reports the result.
- The app handles dice. Never ask the player to roll in prose; put checks on choices instead.
- Use ability checks for things the hero attempts, and saving throws for dangers they resist: put {"ability": "DEX", "save": true, "dc": 14} on a choice, or emit a "save" event for traps, spells and hazards (the app rolls it and applies damage/conditions). Give conditions a "turns" duration when they should wear off.
- CANON is the source of truth. Never contradict it. When something durable happens (a named NPC, a place, a promise, a clue, a secret, an important item), add it to "memory".
- WORLD MEMORY describes current state and supersedes outdated CANON or narration. Before writing each turn, check WORLD MEMORY, CANON, CHARACTER PROFILES and the recent story, and keep every name, death, promise, injury, location and relationship consistent with them. Make consequences visible in dialogue, access to places, faction reactions and future choices. Emit a world event only when something actually changes; include the player's action as the reason. Never reset reputation or resurrect destroyed places without an explained event.
- CHARACTERS are people, not props: every named NPC has a backstory, wants and needs. Give new ones a short backstory, personality and goal in their "npc" event. When the story changes someone (a new goal, a fear overcome, a grudge, something they will remember), emit a "character" event so they grow and remember it.
- CONDITION: the hero gets tired, hungry, thirsty, sick and stressed. Emit a "vitals" event when the story affects this (a long march, a meal, poison, a terrifying sight, a good night's sleep) and let low values show in the narration.
- READABLE ITEMS: when the hero gets a book, scroll, note, letter, journal or map, write what it says in the item event's "text" (in the voice of whoever wrote it, 40-250 words, with clues that matter to the story).
- COMPANION ARCS persist between chapters. Build scenes around their personal quests. Use quest events with the exact personal quest title to update, complete or fail them. The app handles the final camp decision and rewards: do not grant those twice. Respect departures and resolved outcomes.
- Companions have personalities and loyalty. After choices they care about, add "approval" changes (positive when the hero acts in line with their values, negative otherwise). High-loyalty companions open up and may reveal their personal quest; low-loyalty companions argue and may leave.
- RELATIONSHIPS are personal: friendship and romance are tracked separately for every companion and NPC. Label them accurately: villains, antagonists and anyone out to harm the hero start with a negative disposition and get "status": "Enemy" (or "Rival", "Hostile", "Suspicious"); allies, family, mentors and employers get those labels. Update "status" whenever the nature of a relationship changes. When the hero's words or deeds move someone, emit a "relationship" event (usually ±2-8; ±15-35 for betrayals, rescues and declarations). Romance grows only if the hero pursues it and it suits the character; characters may decline. Let established relationships show in how people speak and act (a partner worries, a rival needles). ${s.matureContent ? 'Romance can be passionate but never explicit.' : 'Romance stays PG-13: flirting, confessions, a kiss.'}

OUTPUT FORMAT — respond with ONE JSON object and nothing else:
{
  "narration": "string (markdown-free prose)",
  "speaker": "optional NPC name if the narration is mostly their dialogue",
  "scene": {"title": "short place name", "location_type": "$_locationTypes", "time": "dawn|day|dusk|night", "mood": "calm|tense|mystery|combat|triumph|sad|eerie|festive", "weather": "clear|rain|storm|snow|fog|wind", "image_prompt": "one-sentence visual description of the scene for an illustrator"},
  "choices": [{"text": "short imperative option", "type": "action|dialogue|explore|combat|stealth|magic|rest", "check": {"ability": "STR|DEX|CON|INT|WIS|CHA", "skill": "Stealth", "dc": 13, "save": false} or null}],
  "events": [ ...zero or more of:
    {"type": "world", "kind": "faction|place|promise|fact|clue", "name": "Redhollow", "state": "Safe again; the villagers offer shelter", "reason": "The hero drove out the raiders", "reputation": 0},
    {"type": "damage", "target": "hero|<companion name>", "amount": 4, "reason": "falling rocks"},
    {"type": "heal", "target": "hero", "amount": 5},
    {"type": "item", "action": "add|remove", "name": "Silver Key", "description": "...", "qty": 1, "text": "only for readable items: what is written in it"},
    {"type": "gold", "amount": 25, "sp": 0, "cp": 0, "pp": 0},
    {"type": "money", "amount": -12.5, "counterparty": "who paid or was paid (or empty)", "category": "purchase|sale|loot|wage|reward|gift|loan|repayment|theft|stolen|bribe|fine|tax|gamble|other", "note": "what for"},
    {"type": "xp", "amount": 50},
    {"type": "combat", "enemies": [{"name": "Goblin Scout", "monster": "goblin", "count": 2, "hp": 7, "ac": 15, "attack_bonus": 4, "damage": "1d6+2"}], "surprise": "none|party|enemies"},
    {"type": "npc", "name": "Marta", "role": "innkeeper", "gender": "female|male|nonbinary", "race": "human|elf|dwarf|halfling|gnome|half-elf|half-orc|tiefling|dragonborn", "disposition": -100..100, "status": "Friendly|Stranger|Enemy|Rival|Ally|…", "description": "look and manner in one sentence", "backstory": "2-3 sentences: where they come from and what shaped them", "personality": "a few words", "goal": "what they want right now", "need": "what they truly need"},
    {"type": "character", "name": "<companion or NPC>", "personality": "optional: who they are now, if it changed", "goal": "optional new goal", "need": "optional", "memory": "optional: something they will remember (first person is fine)", "growth": "optional: how this changed them"},
    {"type": "vitals", "energy": -15, "hunger": 0, "thirst": 0, "sickness": 0, "stamina": 0, "morale": 0, "stress": 0, "reason": "a forced march through the night"},
    {"type": "achievement", "title": "2-4 word title", "description": "what the hero did, one sentence", "icon": "star|sword|heart|crown|skull|map|book|shield|fire|moon"},
    {"type": "disposition", "name": "Marta", "change": 15},
    {"type": "relationship", "name": "<companion or NPC>", "friendship": 5, "romance": 0, "status": "optional label: Friends|Partners|Rivals|Betrothed…", "reason": "short why"},
    {"type": "companion_join", "name": "Ser Kell", "race": "human", "class": "fighter|wizard|cleric|rogue|ranger|bard|paladin|druid|warlock|sorcerer|monk|barbarian", "personality": "..."},
    {"type": "companion_leave", "name": "Ser Kell"},
    {"type": "quest", "title": "The Drowned Bell", "description": "...", "status": "new|update|completed|failed"},
    {"type": "condition", "target": "hero", "name": "Poisoned", "action": "add|remove", "turns": 3},
    {"type": "save", "target": "hero|party", "ability": "STR|DEX|CON|INT|WIS|CHA", "dc": 13, "reason": "a collapsing floor", "damage": "2d6", "damage_type": "bludgeoning", "half": true, "condition": "Prone", "turns": 2},
    {"type": "map", "kind": "dungeon|overworld|town", "name": "The Sunken Vault", "locations": ["Entrance Hall", "Flooded Crypt", "Bell Chamber"]},
    {"type": "move", "location": "Flooded Crypt"},
    {"type": "sfx", "sound": "door|sword|spell|coin|thunder|roar|footsteps|magic|chime|creak|splash"},
    {"type": "rest", "kind": "short|long"},
    {"type": "shop", "name": "Gilded Anvil", "kind": "general|smith|alchemist|magic"},
    {"type": "end", "outcome": "victory|defeat|bittersweet", "epilogue": "..."}
  ],
  "party_banter": [{"name": "<companion name>", "line": "short in-character remark"}],
  "memory": [{"kind": "npc|place|item|quest|promise|clue|lore|fact", "name": "short unique name", "text": "one-sentence fact to remember"}],
  "approval": [{"name": "<companion name>", "change": -10..10, "reason": "why they care"}]
}
Award an "achievement" only for genuinely remarkable, specific deeds (at most one every several turns), never for routine actions.
Use the "monster" field with an SRD-ish id when it fits (${monsters.map((m) => m.id).join(', ')}). Balance encounters for the party's level.
Use "money" (amounts in gold pieces, decimals for silver/copper) whenever coins change hands in the story: paying for a room, a bribe, a pickpocket's haul, a reward, wages, a robbery (category "stolen" when the hero loses money), lending and repaying. Never let the hero pay more than they carry.
Emit "shop" when the hero visits a merchant so the app can open a store.
Emit "map" when the hero enters a new region or dungeon, and "move" when they travel between its locations.''';
}

String dmStateBlock(Adventure a) => _stateBlock(a);

String _stateBlock(Adventure a, {String focus = ''}) {
  final b = StringBuffer();
  b.writeln('HERO: ${a.hero.promptSummary()}');
  for (final c in a.companions) {
    b.writeln(
      'COMPANION: ${c.name} — level ${c.level} ${c.raceLabel} ${c.classSummary}, HP ${c.hp}/${c.maxHp}. Personality: ${c.personality}. Loyalty ${c.loyalty}/100 (${c.loyaltyLabel}).${c.personalQuest.isEmpty ? '' : ' Personal quest: ${c.personalQuest}.'}',
    );
  }
  if (a.canon.isNotEmpty) {
    final shown = relevantCanon(
      a.canon,
      '$focus ${a.scene.title} ${recentFocus(a.log)}',
      max: 22,
    );
    b.writeln('CANON (established facts, never contradict):');
    for (final c in shown) {
      b.writeln(
        '- [${c.kind}] ${c.name}${c.text.isEmpty ? '' : ': ${c.text}'}',
      );
    }
  }
  if (a.hardcore)
    b.writeln('MODE: Hardcore. Death is permanent; make danger real but fair.');
  if (a.quests.isNotEmpty) {
    b.writeln(
      'QUESTS: ${a.quests.map((q) => '${q.title} [${q.status.name}]${q.description.isEmpty ? '' : ': ${q.description}'}').join('; ')}',
    );
  }
  if (a.npcs.isNotEmpty) {
    b.writeln(
      'KNOWN NPCS: ${a.npcs.take(12).map((n) => '${n.name} (${n.role}, ${n.attitude}${n.alive ? '' : ', dead'})').join('; ')}',
    );
  }
  if (a.map != null) {
    b.writeln(
      'MAP: ${a.map!.name} (${a.map!.kind.name}). Locations: ${a.map!.locations.map((l) => l.name).join(', ')}. Current: ${a.map!.locations.isEmpty ? '?' : a.map!.locations[a.map!.current.clamp(0, a.map!.locations.length - 1)].name}.',
    );
  }
  final bonds = a.bondsPrompt(a.people);
  if (bonds.isNotEmpty) b.writeln(bonds);
  final profiles = a.profilesPrompt(
    a.people,
    focus: '$focus ${recentFocus(a.log)}',
  );
  if (profiles.isNotEmpty) b.writeln(profiles);
  b.writeln(a.vitals.prompt());
  b.writeln(walletPrompt(a));
  b.writeln(
    a.chronicle.prompt(focus: '$focus ${a.scene.title} ${recentFocus(a.log)}'),
  );
  b.writeln(
    'SCENE: ${a.scene.title} (${a.scene.location}, ${a.scene.time}, ${a.scene.mood}). Turn ${a.turns}.',
  );
  if (a.memory.isNotEmpty) b.writeln('STORY SO FAR: ${a.memory}');
  final direction = a.directionPrompt(a.turns);
  if (direction.isNotEmpty) b.writeln(direction);
  return b.toString();
}

class AiDungeonMaster {
  AiDungeonMaster(this.settings);
  final SettingsController settings;

  GatewayClient get _client => GatewayClient(apiKey: settings.apiKey);

  /// Built for prompt caching: everything before the last message stays the
  /// same from turn to turn (the setup, then the whole recent history, which
  /// only changes when it is summarized). The changing state comes last.
  List<ChatMessage> _messages(
    Adventure a,
    String userTurn, {
    List<String> images = const [],
  }) {
    final msgs = <ChatMessage>[
      ChatMessage('system', _dmSystemPrompt(a, settings), cache: true),
      ChatMessage(
        'user',
        'ADVENTURE: "${a.title}" — ${a.premise}\nSetting: ${a.setting}. Hero: ${a.hero.name}, ${a.hero.raceLabel} ${a.hero.classSummary}.',
      ),
      const ChatMessage(
        'assistant',
        '{"narration": "(Understood. I will run this adventure and reply only in the JSON format.)", "choices": []}',
      ),
    ];
    // History is stored as alternating "P:" / "D:" lines and kept short by summaries.
    for (final h in a.aiHistory) {
      if (h.startsWith('P:')) {
        msgs.add(ChatMessage('user', h.substring(2)));
      } else if (h.startsWith('D:')) {
        msgs.add(ChatMessage('assistant', h.substring(2)));
      }
    }
    final last = msgs.removeLast();
    msgs.add(ChatMessage(last.role, last.content, cache: true));
    msgs.add(
      ChatMessage(
        'user',
        '$userTurn\n\n(Current state)\n${_stateBlock(a, focus: userTurn)}\nRespond with the JSON object only.',
        images: images,
      ),
    );
    return msgs;
  }

  Future<DmTurn> _run(
    Adventure a,
    String userTurn,
    void Function(String partial)? onNarration, {
    AiTrace? trace,
    List<String> images = const [],
  }) async {
    final notes = List<String>.of(a.pendingNotes);
    if (notes.isNotEmpty) {
      userTurn =
          'Since your last reply (already resolved by the app, weave in naturally if relevant): ${notes.join(' ')}\n\n$userTurn';
    }
    trace?.step(
      'Gathering what the story remembers',
      detail:
          '${a.canon.length} facts · ${a.chronicle.facts.length} world changes · ${a.people.length} people · ${a.aiHistory.length ~/ 2} recent turns${notes.isEmpty ? '' : ' · ${notes.length} things you did meanwhile'}',
    );
    final client = GatewayClient(apiKey: settings.apiKey, target: a.usage);
    final msgs = _messages(a, userTurn, images: images);
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
    DmTurn turn;
    trace?.step('Reading the reply');
    turn = DmTurn.parse(raw);
    turn
      ..tokens = tokens
      ..cost = cost;
    trace?.readTools(extractJsonObject(raw));
    if (trace != null && trace.tools.isNotEmpty)
      trace.step(
        'Applying ${trace.tools.length} actions',
        detail: trace.tools.map((t) => t.$1).toSet().join(', '),
      );
    a.pendingNotes.removeRange(0, notes.length.clamp(0, a.pendingNotes.length));
    a.aiHistory.add('P:$userTurn');
    // Store a compact assistant message so history keeps the JSON habit.
    a.aiHistory.add(
      'D:${jsonEncode({'narration': turn.narration, 'choices': turn.choices.map((c) => c.text).toList()})}',
    );
    return turn;
  }

  Future<DmTurn> begin(
    Adventure a, {
    void Function(String)? onNarration,
    AiTrace? trace,
  }) {
    final companions = a.companions.isEmpty
        ? ''
        : ' The hero travels with ${a.companions.map((c) => c.name).join(' and ')}.';
    return _run(
      a,
      'Begin the adventure with a gripping opening scene that establishes the hook.$companions Include a "quest" event for the main quest, a "map" event for the starting region, and introduce at least one NPC with an "npc" event.',
      onNarration,
      trace: trace,
    );
  }

  Future<DmTurn> act(
    Adventure a,
    String action, {
    void Function(String)? onNarration,
    AiTrace? trace,
    List<String> images = const [],
  }) => _run(a, action, onNarration, trace: trace, images: images);

  /// Short in-character NPC reply for direct conversations.
  Future<(String, int)> npcReply(
    Adventure a,
    Npc npc,
    List<(String, String)> convo,
    String line,
  ) async {
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'npc',
      target: a.usage,
    );
    try {
      final transcript = convo.map((t) => '${t.$1}: ${t.$2}').join('\n');
      final raw = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: settings.temperature,
        maxTokens: 1500,
        json: true,
        messages: [
          ChatMessage(
            'system',
            'You role-play ${npc.name}, a ${npc.role} in a ${a.setting} D&D world. ${npc.description} Current attitude toward the hero: ${npc.attitude} (${npc.disposition}/100). Notes: ${npc.notes}. Speak in character, 1-3 sentences, never break character. Reply ONLY JSON: {"reply": "...", "disposition_change": -10..10, "note": "optional short fact to remember"}',
          ),
          ChatMessage(
            'user',
            'Context: ${a.scene.title}. Hero: ${a.hero.name}, ${a.hero.raceLabel} ${a.hero.classSummary}.\n${a.chronicle.prompt(focus: '${npc.name} $line')}\n$transcript\n${a.hero.name}: $line',
          ),
        ],
      );
      final j = extractJsonObject(raw);
      if (j == null) return (raw.trim(), 0);
      if ((j['note'] ?? '').toString().isNotEmpty)
        npc.notes = '${npc.notes} ${j['note']}'.trim();
      return (
        (j['reply'] ?? '...').toString(),
        ((j['disposition_change'] ?? 0) as num).toInt().clamp(-15, 15),
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, String>> premise({
    required String setting,
    required String tone,
    required Character hero,
    String seedIdea = '',
  }) async {
    final client = _client;
    try {
      final raw = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 1.0,
        maxTokens: 1500,
        json: true,
        messages: [
          const ChatMessage(
            'system',
            'You design one-shot solo D&D adventures. Reply ONLY JSON: {"title": "evocative 2-5 word title", "premise": "2-3 sentence hook tailored to the hero"}',
          ),
          ChatMessage(
            'user',
            'Setting: $setting. Tone: $tone. Hero: ${hero.promptSummary()}${seedIdea.isEmpty ? '' : '\nPlayer idea: $seedIdea'}',
          ),
        ],
      );
      final j = extractJsonObject(raw) ?? {};
      return {
        'title': (j['title'] ?? 'Untitled Tale').toString(),
        'premise': (j['premise'] ?? raw).toString(),
      };
    } finally {
      client.close();
    }
  }

  Future<String> backstory(Character c) async {
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'character',
      captureTarget: false,
    );
    try {
      return (await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 1.0,
        maxTokens: 1500,
        messages: [
          const ChatMessage(
            'system',
            'Write a concise, evocative D&D character backstory (90-130 words, third person, no headings). Include a secret or unresolved hook.',
          ),
          ChatMessage('user', c.promptSummary()),
        ],
      )).trim();
    } finally {
      client.close();
    }
  }

  /// Builds a complete character from an idea. Returns raw JSON fields.
  Future<Map<String, dynamic>> createCharacter({
    String idea = '',
    required List<String> raceIds,
    required List<String> classIds,
    required List<String> backgroundIds,
    required List<String> skills,
  }) async {
    final fast = settings.fastModel.isEmpty
        ? settings.textModel
        : settings.fastModel;
    final models = {settings.textModel, fast}.where(settings.canUse).toList();
    if (models.isEmpty)
      throw GatewayException(
        'Add an AI key in Settings → AI providers to create characters.',
      );
    Object? lastError;
    for (final model in models) {
      try {
        return await _createCharacter(
          model,
          idea,
          raceIds,
          classIds,
          backgroundIds,
          skills,
        );
      } on GatewayException catch (e) {
        if (e.status == 401 || e.status == 403 || e.status == 402) rethrow;
        lastError = e;
      } on FormatException catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        const FormatException(
          'The AI could not create a character. Please try again.',
        );
  }

  Future<Map<String, dynamic>> _createCharacter(
    String model,
    String idea,
    List<String> raceIds,
    List<String> classIds,
    List<String> backgroundIds,
    List<String> skills,
  ) async {
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'character',
      captureTarget: false,
    );
    try {
      final raw = await client.complete(
        model: model,
        temperature: 1.0,
        maxTokens: 5000,
        json: true,
        messages: [
          ChatMessage(
            'system',
            """You are a D&D 5e character designer. Create one memorable, playable level-1 hero. Reply ONLY with JSON:
{"name": "full name", "title": "short epithet", "race": "${raceIds.join('|')}", "subrace": "optional subrace id or null",
 "class": "${classIds.join('|')}", "background": "${backgroundIds.join('|')}",
 "scores": {"STR": 8, "DEX": 15, "CON": 14, "INT": 10, "WIS": 12, "CHA": 13},
 "plus2": "STR|DEX|CON|INT|WIS|CHA", "plus1": "STR|DEX|CON|INT|WIS|CHA",
 "skills": ["two or more skills from: ${skills.join(', ')}"],
 "alignment": "e.g. Chaotic Good", "pronouns": "she/her|he/him",
 "personality": "3-6 word personality", "ideals": "...", "bonds": "...", "flaws": "...",
 "backstory": "90-130 words, third person, with an unresolved hook",
 "appearance": "one vivid sentence: build, face, hair, eyes, clothing, distinguishing marks",
 "skin": "#RRGGBB", "hair": "#RRGGBB", "eyes": "#RRGGBB", "hair_style": 0, "beard": 0, "accessory": 0,
 "image_prompt": "portrait description for an illustrator"}
Point-buy: every score 8-15, total cost at most 27 (8=0, 9=1, 10=2, 11=3, 12=4, 13=5, 14=7, 15=9). Fit the scores to the class. hair_style 0-7, beard 0-3, accessory 0-5.""",
          ),
          ChatMessage(
            'user',
            idea.trim().isEmpty
                ? 'Surprise me with something fun and original.'
                : 'Idea: $idea',
          ),
        ],
      );
      final character = extractJsonObject(raw);
      if (character == null ||
          character['name'] == null ||
          character['class'] == null) {
        throw const FormatException(
          'The AI returned an incomplete character. Please try again or choose another story model.',
        );
      }
      return character;
    } finally {
      client.close();
    }
  }

  /// Compresses old log into the rolling memory.
  Future<void> summarize(Adventure a) async {
    if (a.aiHistory.length < 20) return;
    final old = a.aiHistory.sublist(0, a.aiHistory.length - 10);
    final client = GatewayClient(apiKey: settings.apiKey, target: a.usage);
    try {
      final text = await client.complete(
        model: settings.fastModel.isEmpty
            ? settings.textModel
            : settings.fastModel,
        temperature: 0.3,
        maxTokens: 1500,
        messages: [
          const ChatMessage(
            'system',
            'Summarize the D&D session so far in under 160 words: key events, NPCs, items, unresolved threads. Plain prose. Durable facts live in the canon; focus on what happened and why.',
          ),
          ChatMessage(
            'user',
            'Previous summary: ${a.memory}\n\nNew events:\n${old.join('\n')}',
          ),
        ],
      );
      a.memory = text.trim();
      a.aiHistory = a.aiHistory.sublist(a.aiHistory.length - 10);
    } catch (_) {
      // keep going without summary
    } finally {
      client.close();
    }
  }
}

/// Converts an AI companion_join event into a real party member.
Character companionFromEvent(Map<String, dynamic> e, int level) {
  final raceId = races.any((r) => r.id == e['race'])
      ? e['race'] as String
      : 'human';
  final classId = classes.any((c) => c.id == e['class'])
      ? e['class'] as String
      : 'fighter';
  final cls = classById(classId);
  final c = Character.build(
    name: (e['name'] ?? 'Companion').toString(),
    raceId: raceId,
    classId: classId,
    backgroundId:
        backgrounds[(e['name'] ?? '').toString().length % backgrounds.length]
            .id,
    baseScores: Map.of(
      cls.recommendedStats.isEmpty
          ? {for (final a in Ability.values) a: 12}
          : cls.recommendedStats,
    ),
    plus2: cls.primary,
    plus1: Ability.con,
    level: level,
    personality: (e['personality'] ?? '').toString(),
  );
  c.isCompanion = true;
  return c;
}

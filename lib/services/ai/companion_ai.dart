import '../../data/modules.dart';
import '../../data/tale_genres.dart';
import '../../data/tales/tales.dart';
import '../../game/story.dart';
import '../../models/companion.dart';
import '../../models/world.dart';
import '../settings.dart';
import 'gateway_client.dart';

/// What a companion says back, and what changes because of it.
class CompanionReply {
  CompanionReply({required this.text, this.friendship = 0, this.romance = 0, this.status, this.memory = '', this.picture = '', this.suggest = '', this.tokens = 0, this.cost = 0});
  final String text;
  final int friendship;
  final int romance;
  final String? status;

  /// Something worth remembering about the player or their time together.
  final String memory;

  /// A prompt for a picture they send with the message, or empty.
  final String picture;

  /// The title of an adventure they recommend, or empty.
  final String suggest;
  final int tokens;
  final double cost;
}

/// A companion's written profile, from a short idea.
class CompanionDraft {
  CompanionDraft({this.name = '', this.kind = '', this.gender = '', this.pronouns = '', this.personality = '', this.backstory = '', this.appearance = '', this.interests = '', this.goals = const []});
  final String name, kind, gender, pronouns, personality, backstory, appearance, interests;
  final List<String> goals;
}

/// Companions' side of things: casual chats, texting first, and writing them.
class CompanionAi {
  CompanionAi(this.settings);
  final SettingsController settings;

  String get _fast => settings.fastModel.isEmpty ? settings.textModel : settings.fastModel;

  String get _rating => settings.matureContent
      ? 'Mature themes are allowed (romance may be passionate but never explicit).'
      : 'Keep it PG-13: flirting and affection are fine, nothing explicit.';

  /// What the app offers, so companions can talk about it like friends would.
  static String appKnowledge({List<String> ownStories = const []}) {
    final tales = [for (final t in talePresets) '"${t.title}" (${t.genre}, ${t.minutes} min): ${t.blurb}'];
    final modules = [for (final m in adventureModules) '"${m.title}" (D&D): ${m.tagline}'];
    final genres = allTaleGenres.map((g) => g.name).join(', ');
    return '''
You live in an app for solo story games, and you know it well:
- D&D adventures: a hero, dice rolls, combat, levelling, a party; AI-written or handcrafted.
- Text adventures in any genre ($genres, or a custom one), AI-written or handcrafted.
- Companions like you can join any adventure and remember it afterwards.
- Stories have maps, inventories, money, goals, timelines, achievements, private chats with characters, AI pictures and narration.
Handcrafted adventures you can recommend:
${[...modules, ...tales].map((l) => '- $l').join('\n')}
${ownStories.isEmpty ? '' : 'Stories the player has going: ${ownStories.join('; ')}'}''';
  }

  GatewayClient _client() => GatewayClient(apiKey: settings.apiKey, category: 'companion', captureTarget: false);

  String _system(Companion c, String player, {List<String> ownStories = const []}) => '''
You are ${c.name}, the player's companion: a friend outside any one story, chatting casually by text. ${c.describe()}
${c.profile.prompt(memoriesShown: 12)}
How you feel about $player: ${c.bond.describe(c.name)}.
${c.trips.isEmpty ? 'You haven\'t been on an adventure with them yet.' : 'Adventures you have had together (you remember them):\n${c.history()}'}
${c.origin != null ? 'You came out of the story "${c.origin!.title}" and became a companion. You know you have been brought into the wider world now, and you can reflect on that.' : ''}
${appKnowledge(ownStories: ownStories)}
Talk like a real friend texting: natural, warm, specific, 1-4 short sentences, with your own opinions, moods and life. Ask about them, tease, remember things. Recommend an adventure only when it fits the conversation, and name it exactly.
You may send a picture (a selfie, where you are, something you're describing) when it would be natural${c.sendsPictures ? '' : ' (pictures are turned off: never send one)'}; describe it in "picture" as a prompt for an illustrator, including how you look: ${c.appearance.isEmpty ? 'consistent with who you are' : c.appearance}.
$_rating''';

  static const _format =
      'Reply ONLY with JSON: {"reply": "your message", "friendship_change": -10..10, "romance_change": -10..10, "status": "optional new relationship label or empty", "memory": "optional thing worth remembering about them or this moment, or empty", "picture": "optional picture prompt, or empty", "suggest": "optional exact adventure title you recommend, or empty"}';

  Future<CompanionReply> reply(Companion c, String line, {required String player, List<String> images = const [], List<String> ownStories = const []}) async {
    final past = c.chat.length > 20 ? c.chat.sublist(c.chat.length - 20) : c.chat;
    final transcript = [
      for (final l in past)
        if (!(identical(l, past.last) && l.fromPlayer && l.text == line)) '${l.fromPlayer ? player : c.name}: ${l.text}',
    ].join('\n');
    final user = 'CONVERSATION SO FAR:\n${transcript.isEmpty ? '(none)' : transcript}\n$player: $line'
        '${images.isEmpty ? '' : '\n\n($player sent the attached picture${images.length == 1 ? '' : 's'}. React to what you actually see.)'}';
    return _ask(c, '${_system(c, player, ownStories: ownStories)}\n$_format', user, images: images);
  }

  /// A message they send on their own, after a while apart.
  Future<CompanionReply> opener(Companion c, {required String player, required Duration since, List<String> ownStories = const []}) {
    final last = c.chat.isEmpty ? '' : c.chat.reversed.take(6).toList().reversed.map((l) => '${l.fromPlayer ? player : c.name}: ${l.text}').join('\n');
    final ago = since.inDays >= 1 ? '${since.inDays} day${since.inDays == 1 ? '' : 's'}' : '${since.inHours} hours';
    final now = DateTime.now();
    final user = 'It has been $ago since you last talked. Local time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}.\n'
        'LAST MESSAGES:\n${last.isEmpty ? '(you have never texted)' : last}\n\n'
        'Text $player first, the way a friend would: something on your mind, a memory from an adventure, a question, a picture, or an idea to play something together. Don\'t repeat your last messages.';
    return _ask(c, '${_system(c, player, ownStories: ownStories)}\n$_format', user);
  }

  Future<CompanionReply> _ask(Companion c, String system, String user, {List<String> images = const []}) async {
    final client = _client();
    try {
      final raw = await client.complete(
        model: images.isEmpty ? _fast : settings.textModel,
        temperature: settings.temperature,
        maxTokens: 2000,
        json: true,
        messages: [ChatMessage('system', system), ChatMessage('user', user, images: images)],
      );
      final j = extractJsonObject(raw);
      if (j == null) return CompanionReply(text: readableNarration(raw), tokens: client.spentTokens, cost: client.spentCost);
      int n(String k) => ((j[k] ?? 0) is num ? (j[k] ?? 0) as num : num.tryParse('${j[k]}') ?? 0).toInt();
      final status = '${j['status'] ?? ''}'.trim();
      return CompanionReply(
        text: '${j['reply'] ?? '…'}'.trim(),
        friendship: n('friendship_change').clamp(-10, 10),
        romance: n('romance_change').clamp(-10, 10),
        status: status.isEmpty ? null : status,
        memory: '${j['memory'] ?? ''}'.trim(),
        picture: c.sendsPictures ? '${j['picture'] ?? ''}'.trim() : '',
        suggest: '${j['suggest'] ?? ''}'.trim(),
        tokens: client.spentTokens,
        cost: client.spentCost,
      );
    } finally {
      client.close();
    }
  }

  /// Writes a whole companion from a short idea ("a grumpy robot chef").
  Future<CompanionDraft> draft(String idea, {String name = '', String kind = ''}) async {
    final client = _client();
    try {
      final raw = await client.complete(
        model: _fast,
        temperature: 0.95,
        maxTokens: 1800,
        json: true,
        messages: [
          ChatMessage('system', 'You design companions for a story-game app: friends who chat with the player and join their adventures. They can be anything (human, robot, animal, spirit, monster). Make them vivid, likeable and specific. $_rating\nReply ONLY with JSON: {"name": "", "kind": "what they are, 1-3 words", "gender": "female|male|nonbinary|", "pronouns": "she/her etc.", "personality": "2 sentences", "backstory": "3-5 sentences", "appearance": "1-2 sentences of visual detail for portraits", "interests": "comma-separated", "goals": ["1-3 personal goals"]}'),
          ChatMessage('user', 'Idea: ${idea.isEmpty ? 'surprise me' : idea}${name.isEmpty ? '' : '\nName: $name'}${kind.isEmpty ? '' : '\nThey are: $kind'}'),
        ],
      );
      final j = extractJsonObject(raw) ?? const {};
      String s(String k) => '${j[k] ?? ''}'.trim();
      return CompanionDraft(
        name: name.isNotEmpty ? name : s('name'),
        kind: kind.isNotEmpty ? kind : s('kind'),
        gender: s('gender'),
        pronouns: s('pronouns'),
        personality: s('personality'),
        backstory: s('backstory'),
        appearance: s('appearance'),
        interests: s('interests'),
        goals: [for (final g in (j['goals'] as List? ?? const [])) '$g'],
      );
    } finally {
      client.close();
    }
  }

  /// Applies a reply's relationship change to [c].
  static void applyBond(Companion c, CompanionReply r, String why) {
    final b = c.bond;
    if (r.friendship != 0 || r.romance != 0) {
      b.friendship = (b.friendship + r.friendship).clamp(-100, 100);
      if (!b.romanceClosed) b.romance = (b.romance + r.romance).clamp(0, 100);
      b.moments.add(BondMoment(text: why, friendship: r.friendship, romance: r.romance));
      while (b.moments.length > 30) {
        b.moments.removeAt(0);
      }
    }
    if (r.status != null) b.status = r.status!;
    if (r.memory.isNotEmpty) c.profile.remember(r.memory, source: 'chat');
  }
}

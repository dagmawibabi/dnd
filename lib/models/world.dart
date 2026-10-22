import 'adventure.dart';
import 'character.dart' show Character, newId;
import 'chronicle.dart';

/// What the story feed needs from a D&D adventure or a text adventure.
abstract interface class StoryRecord {
  String get id;
  Npc? personNamed(String? name);
  Character? companionNamed(String? name);
  String? get sceneImagePath;
  Map<String, String> get sceneImages;
  Map<String, double> get mediaCosts;
}

/// A notable moment in a relationship ("+10 romance: you kissed her").
class BondMoment {
  BondMoment({required this.text, this.friendship = 0, this.romance = 0, this.turn = 0, DateTime? at}) : at = at ?? DateTime.now();
  final String text;
  final int friendship;
  final int romance;
  final int turn;
  final DateTime at;

  Map<String, dynamic> toJson() => {'t': text, 'f': friendship, 'r': romance, 'n': turn, 'at': at.millisecondsSinceEpoch};
  factory BondMoment.fromJson(Map<String, dynamic> j) => BondMoment(
        text: j['t'] ?? '',
        friendship: j['f'] ?? 0,
        romance: j['r'] ?? 0,
        turn: j['n'] ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// How a character feels about the protagonist: friendship and romance are
/// tracked separately, so a rival can still be attracted to you.
class Bond {
  Bond({this.friendship = 0, this.romance = 0, this.status = '', this.romanceClosed = false, List<BondMoment>? moments}) : moments = moments ?? [];

  /// -100 (enemy) .. 100 (best friend)
  int friendship;

  /// 0 (none) .. 100 (deeply in love)
  int romance;

  /// A label set by the story ("Partners", "Betrothed", "Rivals", "Ex"). Empty uses the derived labels.
  String status;

  /// They turned romance down; the storyteller shouldn't push it.
  bool romanceClosed;
  List<BondMoment> moments;

  String get friendshipLabel => friendship >= 80
      ? 'Best friend'
      : friendship >= 50
          ? 'Close friend'
          : friendship >= 20
              ? 'Friend'
              : friendship >= 8
                  ? 'Friendly'
                  : friendship > -8
                      ? (moments.isEmpty ? 'Stranger' : 'Acquaintance')
                      : friendship > -25
                          ? 'Uneasy'
                          : friendship > -45
                              ? 'Wary'
                              : friendship > -65
                                  ? 'Hostile'
                                  : 'Enemy';

  /// Whether the label says they're against you (for colors and icons).
  bool get isHostile {
    final s = status.toLowerCase();
    if (const ['enemy', 'rival', 'hostile', 'nemesis', 'foe', 'suspicious', 'wary', 'betray', 'hunted', 'traitor', 'antagonist'].any(s.contains)) return true;
    return status.isEmpty && friendship <= -25;
  }

  String get romanceLabel => romanceClosed
      ? 'Not interested'
      : romance >= 90
          ? 'In love'
          : romance >= 70
              ? 'Smitten'
              : romance >= 45
                  ? 'Courting'
                  : romance >= 20
                      ? 'Flirting'
                      : romance > 0
                          ? 'Curious'
                          : 'None';

  /// The single label shown on cards.
  String get label {
    if (status.isNotEmpty) return status;
    if (romance >= 20 && !romanceClosed) return romanceLabel;
    return friendshipLabel;
  }

  bool get isRomantic => romance >= 20 && !romanceClosed;

  /// One line for AI prompts.
  String describe(String name) => '$name — friendship $friendship/100 ($friendshipLabel)'
      '${romance > 0 || romanceClosed ? ', romance $romance/100 ($romanceLabel)' : ''}'
      '${status.isNotEmpty ? ', status: $status' : ''}'
      '${moments.isEmpty ? '' : '. Recently: ${moments.reversed.take(2).map((m) => m.text).join('; ')}'}';

  Map<String, dynamic> toJson() => {
        'f': friendship,
        'r': romance,
        's': status,
        'rc': romanceClosed,
        'm': moments.map((m) => m.toJson()).toList(),
      };
  factory Bond.fromJson(Map<String, dynamic> j) => Bond(
        friendship: j['f'] ?? 0,
        romance: j['r'] ?? 0,
        status: j['s'] ?? '',
        romanceClosed: j['rc'] ?? false,
        moments: [for (final m in (j['m'] as List? ?? const [])) BondMoment.fromJson(Map<String, dynamic>.from(m))],
      );
}

/// One line of a private conversation with a character.
class ChatLine {
  ChatLine({required this.fromPlayer, required this.text, DateTime? at, this.tokens = 0, this.cost = 0, this.opener = '', this.images = const [], this.suggest = ''}) : at = at ?? DateTime.now();
  final bool fromPlayer;

  /// Pictures sent with the message (file paths).
  final List<String> images;

  /// Why the character started this conversation themselves, or empty.
  final String opener;

  /// An adventure they recommend in this message, or empty.
  final String suggest;
  final String text;
  final DateTime at;
  final int tokens;
  final double cost;

  Map<String, dynamic> toJson() => {'p': fromPlayer, 't': text, 'at': at.millisecondsSinceEpoch, if (tokens > 0) 'tok': tokens, if (cost > 0) 'usd': cost, if (opener.isNotEmpty) 'o': opener, if (images.isNotEmpty) 'img': images, if (suggest.isNotEmpty) 'sug': suggest};
  factory ChatLine.fromJson(Map<String, dynamic> j) => ChatLine(
        fromPlayer: j['p'] ?? false,
        text: j['t'] ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
        tokens: j['tok'] ?? 0,
        cost: ((j['usd'] ?? 0) as num).toDouble(),
        opener: j['o'] ?? '',
        images: List<String>.from(j['img'] ?? const []),
        suggest: j['sug'] ?? '',
      );
}

/// A generated image or video kept in the story's gallery.
class MediaItem {
  MediaItem({String? id, required this.path, this.video = false, this.kind = 'scene', this.caption = '', this.turn = 0, this.cost = 0, DateTime? at})
      : id = id ?? newId(),
        at = at ?? DateTime.now();
  final String id;
  final String path;
  final bool video;

  /// scene | portrait | effect | map | cover
  final String kind;
  final String caption;
  final int turn;
  final double cost;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 'p': path, if (video) 'v': true, 'k': kind, 'c': caption, 'n': turn, if (cost > 0) 'usd': cost, 'at': at.millisecondsSinceEpoch};
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'],
        path: j['p'] ?? '',
        video: j['v'] ?? false,
        kind: j['k'] ?? 'scene',
        caption: j['c'] ?? '',
        turn: j['n'] ?? 0,
        cost: ((j['usd'] ?? 0) as num).toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// Something a character remembers: from the story, a conversation, or added
/// by the player.
class CharacterMemory {
  CharacterMemory({String? id, required this.text, this.turn = 0, this.source = 'story', this.pinned = false, DateTime? at})
      : id = id ?? newId(),
        at = at ?? DateTime.now();
  final String id;
  String text;
  final int turn;

  /// story | chat | player
  final String source;
  bool pinned;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 't': text, 'n': turn, 's': source, if (pinned) 'p': true, 'at': at.millisecondsSinceEpoch};
  factory CharacterMemory.fromJson(Map<String, dynamic> j) => CharacterMemory(
        id: j['id'],
        text: j['t'] ?? '',
        turn: j['n'] ?? 0,
        source: j['s'] ?? 'story',
        pinned: j['p'] ?? false,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// A character's inner life: where they come from, who they are now, what
/// they want and need, what they remember, and how the story changed them.
class PersonProfile {
  PersonProfile({this.backstory = '', this.personality = '', List<String>? traits, List<String>? goals, List<String>? needs, List<CharacterMemory>? memories, List<String>? growth, this.secret = '', this.age = '', this.occupation = ''})
      : traits = traits ?? [],
        goals = goals ?? [],
        needs = needs ?? [],
        memories = memories ?? [],
        growth = growth ?? [];
  String backstory;

  /// Who they are right now (it changes with the story).
  String personality;
  List<String> traits;
  List<String> goals;
  List<String> needs;
  List<CharacterMemory> memories;

  /// How they've changed ("Turn 14: learned to trust you after the bridge").
  List<String> growth;

  /// Something they hide (known to the storyteller, shown only once revealed).
  String secret;
  String age;
  String occupation;

  bool get isEmpty => backstory.isEmpty && personality.isEmpty && traits.isEmpty && goals.isEmpty && needs.isEmpty && memories.isEmpty;

  void remember(String text, {int turn = 0, String source = 'story'}) {
    final t = text.trim();
    if (t.isEmpty || memories.any((m) => m.text.toLowerCase() == t.toLowerCase())) return;
    memories.add(CharacterMemory(text: t, turn: turn, source: source));
    // Keep what matters: pinned memories stay, the oldest others fade.
    while (memories.length > 40) {
      final i = memories.indexWhere((m) => !m.pinned);
      if (i < 0) break;
      memories.removeAt(i);
    }
  }

  /// For AI prompts: a compact portrait of who they are and what they recall.
  String prompt({int memoriesShown = 8}) {
    final recent = [...memories.where((m) => m.pinned), ...memories.reversed.where((m) => !m.pinned)].take(memoriesShown);
    return [
      if (backstory.isNotEmpty) 'Backstory: $backstory',
      if (personality.isNotEmpty) 'Personality now: $personality',
      if (traits.isNotEmpty) 'Traits: ${traits.join(', ')}',
      if (goals.isNotEmpty) 'Goals: ${goals.join('; ')}',
      if (needs.isNotEmpty) 'Needs: ${needs.join('; ')}',
      if (secret.isNotEmpty) 'Secret (reveal only if earned): $secret',
      if (growth.isNotEmpty) 'How they have changed: ${growth.reversed.take(3).join(' ')}',
      if (recent.isNotEmpty) 'Their memories: ${recent.map((m) => m.text).join(' | ')}',
    ].join('\n');
  }

  Map<String, dynamic> toJson() => {
        if (backstory.isNotEmpty) 'b': backstory,
        if (personality.isNotEmpty) 'p': personality,
        if (traits.isNotEmpty) 'tr': traits,
        if (goals.isNotEmpty) 'g': goals,
        if (needs.isNotEmpty) 'n': needs,
        if (memories.isNotEmpty) 'm': memories.map((m) => m.toJson()).toList(),
        if (growth.isNotEmpty) 'gr': growth,
        if (secret.isNotEmpty) 's': secret,
        if (age.isNotEmpty) 'age': age,
        if (occupation.isNotEmpty) 'job': occupation,
      };
  factory PersonProfile.fromJson(Map<String, dynamic> j) => PersonProfile(
        backstory: j['b'] ?? '',
        personality: j['p'] ?? '',
        traits: List<String>.from(j['tr'] ?? const []),
        goals: List<String>.from(j['g'] ?? const []),
        needs: List<String>.from(j['n'] ?? const []),
        memories: [for (final m in (j['m'] as List? ?? const [])) CharacterMemory.fromJson(Map<String, dynamic>.from(m))],
        growth: List<String>.from(j['gr'] ?? const []),
        secret: j['s'] ?? '',
        age: j['age'] ?? '',
        occupation: j['job'] ?? '',
      );
}

/// A result from the AI tools (recap, ideas, diary, an answer), kept so it
/// can be read again later.
class AiNote {
  AiNote({String? id, required this.kind, required this.title, this.question = '', this.text = '', List<String>? ideas, this.turn = 0, this.tokens = 0, this.cost = 0, this.pinned = false, DateTime? at})
      : id = id ?? newId(),
        ideas = ideas ?? [],
        at = at ?? DateTime.now();
  final String id;

  /// recap | ideas | diary | lore | insight
  final String kind;
  final String title;
  final String question;
  final String text;
  final List<String> ideas;
  final int turn;
  final int tokens;
  final double cost;
  bool pinned;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'ti': title, if (question.isNotEmpty) 'q': question, if (text.isNotEmpty) 't': text, if (ideas.isNotEmpty) 'i': ideas, 'n': turn, if (tokens > 0) 'tok': tokens, if (cost > 0) 'usd': cost, if (pinned) 'p': true, 'at': at.millisecondsSinceEpoch};
  factory AiNote.fromJson(Map<String, dynamic> j) => AiNote(
        id: j['id'],
        kind: j['k'] ?? 'insight',
        title: j['ti'] ?? '',
        question: j['q'] ?? '',
        text: j['t'] ?? '',
        ideas: List<String>.from(j['i'] ?? const []),
        turn: j['n'] ?? 0,
        tokens: j['tok'] ?? 0,
        cost: ((j['usd'] ?? 0) as num).toDouble(),
        pinned: j['p'] ?? false,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// What is written in a book, scroll, note or letter the player carries.
class ItemWriting {
  ItemWriting({required this.title, this.kind = 'note', required this.text, this.author = ''});
  final String title;

  /// book | scroll | note | letter | journal | map | inscription
  final String kind;
  String text;
  final String author;

  Map<String, dynamic> toJson() => {'ti': title, 'k': kind, 't': text, if (author.isNotEmpty) 'a': author};
  factory ItemWriting.fromJson(Map<String, dynamic> j) => ItemWriting(title: j['ti'] ?? '', kind: j['k'] ?? 'note', text: j['t'] ?? '', author: j['a'] ?? '');
}

/// Items that are meant to be read.
bool isReadableItem(String name) => RegExp(r'\b(book|tome|scroll|note|letter|journal|diary|ledger|map|page|parchment|manuscript|codex|grimoire|missive|notice|poster|newspaper|report|log|file|dossier|record|message|card|inscription|tablet|recipe|manifest|chart)s?\b', caseSensitive: false).hasMatch(name);

/// How the protagonist is holding up beyond health (each 0-100, higher is better).
class Vitals {
  Vitals({this.energy = 90, this.fullness = 85, this.hydration = 85, this.wellness = 100, this.stamina = 100, this.morale = 70, this.calm = 75});

  /// Rested (100) vs exhausted (0).
  int energy;

  /// Fed (100) vs starving (0).
  int fullness;
  int hydration;

  /// Healthy (100) vs gravely sick or poisoned (0).
  int wellness;

  /// Ready for exertion (100) vs winded (0).
  int stamina;

  /// Spirits: hopeful (100) vs despairing (0).
  int morale;

  /// Composure: calm (100) vs panicked (0).
  int calm;

  static const keys = ['energy', 'fullness', 'hydration', 'wellness', 'stamina', 'morale', 'calm'];

  int get(String k) => switch (k) { 'energy' => energy, 'fullness' => fullness, 'hydration' => hydration, 'wellness' => wellness, 'stamina' => stamina, 'morale' => morale, _ => calm };

  void set(String k, int v) {
    final x = v.clamp(0, 100);
    switch (k) {
      case 'energy':
        energy = x;
      case 'fullness':
        fullness = x;
      case 'hydration':
        hydration = x;
      case 'wellness':
        wellness = x;
      case 'stamina':
        stamina = x;
      case 'morale':
        morale = x;
      default:
        calm = x;
    }
  }

  /// Applies changes the story reports, e.g. {"energy": -10, "hunger": +20}.
  /// Accepts the opposite words too (tiredness, hunger, thirst, sickness, stress).
  List<String> apply(Map<String, dynamic> changes) {
    final out = <String>[];
    for (final e in changes.entries) {
      final raw = e.value is num ? (e.value as num).toInt() : int.tryParse('${e.value}') ?? 0;
      if (raw == 0) continue;
      final (key, sign) = switch (e.key.toLowerCase()) {
        'energy' || 'rest' => ('energy', 1),
        'tiredness' || 'fatigue' || 'exhaustion' => ('energy', -1),
        'fullness' || 'food' || 'satiety' => ('fullness', 1),
        'hunger' => ('fullness', -1),
        'hydration' || 'water' => ('hydration', 1),
        'thirst' => ('hydration', -1),
        'wellness' || 'health' => ('wellness', 1),
        'sickness' || 'illness' || 'poison' || 'infection' => ('wellness', -1),
        'stamina' => ('stamina', 1),
        'morale' || 'hope' || 'spirits' => ('morale', 1),
        'calm' || 'composure' => ('calm', 1),
        'stress' || 'fear' || 'panic' => ('calm', -1),
        _ => ('', 0),
      };
      if (key.isEmpty) continue;
      final delta = (raw * sign).clamp(-60, 60);
      final before = get(key);
      set(key, before + delta);
      if (get(key) != before) out.add('${labelOf(key)} ${delta > 0 ? '+' : ''}$delta');
    }
    return out;
  }

  /// Time passing: a little hungrier, thirstier and more tired each turn.
  void tick() {
    fullness = (fullness - 2).clamp(0, 100);
    hydration = (hydration - 3).clamp(0, 100);
    energy = (energy - 2).clamp(0, 100);
    stamina = (stamina + 6).clamp(0, 100);
  }

  /// A full night's sleep.
  void rest({bool food = true}) {
    energy = 100;
    stamina = 100;
    calm = (calm + 15).clamp(0, 100);
    if (food) {
      fullness = (fullness + 40).clamp(0, 100);
      hydration = (hydration + 50).clamp(0, 100);
    }
  }

  static String labelOf(String k) => switch (k) { 'energy' => 'Energy', 'fullness' => 'Fullness', 'hydration' => 'Hydration', 'wellness' => 'Wellness', 'stamina' => 'Stamina', 'morale' => 'Morale', _ => 'Composure' };

  /// The words a person would use for a value ("Exhausted", "Peckish"…).
  static String describe(String k, int v) {
    String pick(List<String> words) => words[(v / 100 * (words.length - 1)).round().clamp(0, words.length - 1)];
    return switch (k) {
      'energy' => pick(['Exhausted', 'Drained', 'Tired', 'Alert', 'Well rested']),
      'fullness' => pick(['Starving', 'Hungry', 'Peckish', 'Satisfied', 'Well fed']),
      'hydration' => pick(['Parched', 'Thirsty', 'Dry-mouthed', 'Fine', 'Hydrated']),
      'wellness' => pick(['Gravely ill', 'Sick', 'Unwell', 'Mostly fine', 'Healthy']),
      'stamina' => pick(['Spent', 'Winded', 'Steady', 'Strong', 'Fresh']),
      'morale' => pick(['Despairing', 'Low', 'Wavering', 'Hopeful', 'Inspired']),
      _ => pick(['Panicked', 'Shaken', 'Uneasy', 'Collected', 'Calm']),
    };
  }

  /// Short status for AI prompts, only what matters.
  String prompt() {
    final notes = [for (final k in keys) if (get(k) < 45) '${describe(k, get(k)).toLowerCase()} (${labelOf(k).toLowerCase()} ${get(k)}/100)'];
    return notes.isEmpty ? 'CONDITION: fine (rested, fed, healthy).' : 'CONDITION: ${notes.join(', ')}. Let this show in the story and in what the protagonist can do.';
  }

  Map<String, dynamic> toJson() => {for (final k in keys) k: get(k)};
  factory Vitals.fromJson(Map<String, dynamic> j) {
    final v = Vitals();
    for (final k in keys) {
      if (j[k] is num) v.set(k, (j[k] as num).toInt());
    }
    return v;
  }
}

/// One movement of money: in (positive) or out (negative).
class MoneyMove {
  MoneyMove({String? id, required this.amount, this.category = 'other', this.counterparty = '', this.note = '', this.turn = 0, this.account = 'cash', DateTime? at})
      : id = id ?? newId(),
        at = at ?? DateTime.now();
  final String id;
  final double amount;

  /// loot | purchase | sale | wage | reward | gift | loan | repayment | theft |
  /// stolen | bribe | fine | tax | gamble | deposit | withdrawal | transfer | other
  final String category;
  final String counterparty;
  final String note;
  final int turn;

  /// cash (in hand) or bank (the card).
  final String account;
  final DateTime at;

  bool get income => amount > 0;

  Map<String, dynamic> toJson() => {'id': id, 'a': amount, 'c': category, if (counterparty.isNotEmpty) 'who': counterparty, if (note.isNotEmpty) 'n': note, 't': turn, if (account != 'cash') 'acc': account, 'at': at.millisecondsSinceEpoch};
  factory MoneyMove.fromJson(Map<String, dynamic> j) => MoneyMove(
        id: j['id'],
        amount: ((j['a'] ?? 0) as num).toDouble(),
        category: j['c'] ?? 'other',
        counterparty: j['who'] ?? '',
        note: j['n'] ?? '',
        turn: j['t'] ?? 0,
        account: j['acc'] ?? 'cash',
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
      );
}

/// Money in a story: cash in hand (text adventures; D&D uses the hero's
/// coins), savings on a card, every transaction, debts, and local prices.
class Wallet {
  Wallet({this.cash = 0, this.bank = 0, this.currency = '', List<MoneyMove>? ledger, Map<String, double>? owed, List<Map<String, String>>? prices, this.economy = '', this.tracked, Map<String, int>? due, Map<String, double>? rates, this.bankRate = 0, this.interestTurn})
      : ledger = ledger ?? [],
        owed = owed ?? {},
        prices = prices ?? [],
        due = due ?? {},
        rates = rates ?? {};

  /// Cash in a text adventure.
  double cash;

  /// Savings held on the card / in the bank.
  double bank;

  /// The money's name in this world ("credits", "caps"); empty = the default.
  String currency;
  List<MoneyMove> ledger;

  /// Person name -> how much they owe you (negative: you owe them).
  Map<String, double> owed;

  /// What things cost here: {item, price}.
  List<Map<String, String>> prices;

  /// A line on the local economy (scarce, booming, taxed…).
  String economy;

  /// Cash plus card as the ledger last left it (null: not counted yet). When
  /// the real total differs, something moved money without a record, and an
  /// adjustment keeps the history adding up.
  double? tracked;

  /// Person name -> the turn a debt is due.
  Map<String, int> due;

  /// Person name -> interest on the debt, percent per 10 turns.
  Map<String, double> rates;

  /// Interest the card pays on savings, percent per 10 turns.
  double bankRate;

  /// The turn interest was last worked out (null: not started).
  int? interestTurn;

  /// Moves between the wallet and the card: no money is made or lost.
  static const transfers = {'deposit', 'withdrawal'};

  /// Borrowing and lending: money that has to come back, not earnings.
  static const credit = {'loan', 'repayment'};

  void record(MoneyMove m) {
    ledger.add(m);
    if (tracked != null && !transfers.contains(m.category)) tracked = tracked! + m.amount;
    if (ledger.length > 500) ledger.removeAt(0);
  }

  bool _counts(MoneyMove m) => !transfers.contains(m.category) && !credit.contains(m.category);

  /// Money earned (found, paid, won, received), not counting loans.
  double get income => ledger.where((m) => m.amount > 0 && _counts(m)).fold(0, (n, m) => n + m.amount);

  /// Money spent or lost, not counting lending or paying debts back.
  double get spent => ledger.where((m) => m.amount < 0 && _counts(m)).fold(0, (n, m) => n - m.amount);

  /// What others owe the player.
  double get receivable => owed.values.where((v) => v > 0).fold(0, (n, v) => n + v);

  /// What the player owes others.
  double get payable => owed.values.where((v) => v < 0).fold(0, (n, v) => n - v);

  Map<String, dynamic> toJson() => {
        if (cash != 0) 'cash': cash,
        if (bank != 0) 'bank': bank,
        if (currency.isNotEmpty) 'cur': currency,
        if (ledger.isNotEmpty) 'ledger': ledger.map((m) => m.toJson()).toList(),
        if (owed.isNotEmpty) 'owed': owed,
        if (prices.isNotEmpty) 'prices': prices,
        if (economy.isNotEmpty) 'eco': economy,
        if (tracked != null) 'trk': tracked,
        if (due.isNotEmpty) 'due': due,
        if (rates.isNotEmpty) 'rates': rates,
        if (bankRate != 0) 'bankRate': bankRate,
        if (interestTurn != null) 'intT': interestTurn,
      };
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        cash: ((j['cash'] ?? 0) as num).toDouble(),
        bank: ((j['bank'] ?? 0) as num).toDouble(),
        currency: j['cur'] ?? '',
        ledger: [for (final m in (j['ledger'] as List? ?? const [])) MoneyMove.fromJson(Map<String, dynamic>.from(m))],
        owed: {for (final e in (j['owed'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
        prices: [for (final p in (j['prices'] as List? ?? const [])) Map<String, String>.from(p)],
        economy: j['eco'] ?? '',
        tracked: (j['trk'] as num?)?.toDouble(),
        due: {for (final e in (j['due'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt()},
        rates: {for (final e in (j['rates'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
        bankRate: ((j['bankRate'] ?? 0) as num).toDouble(),
        interestTurn: (j['intT'] as num?)?.toInt(),
      );
}

/// A note the player writes for themselves.
class StoryNote {
  StoryNote({String? id, this.title = '', this.body = '', this.pinned = false, DateTime? created, DateTime? updated})
      : id = id ?? newId(),
        created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now();
  final String id;
  String title;
  String body;
  bool pinned;
  final DateTime created;
  DateTime updated;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
  String get heading {
    if (title.trim().isNotEmpty) return title.trim();
    final first = body.trim().split('\n').first.trim();
    return first.isEmpty ? 'Untitled note' : first;
  }

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'b': body, if (pinned) 'p': true, 'c': created.millisecondsSinceEpoch, 'u': updated.millisecondsSinceEpoch};
  factory StoryNote.fromJson(Map<String, dynamic> j) => StoryNote(
        id: j['id'],
        title: j['t'] ?? '',
        body: j['b'] ?? '',
        pinned: j['p'] ?? false,
        created: DateTime.fromMillisecondsSinceEpoch(j['c'] ?? 0),
        updated: DateTime.fromMillisecondsSinceEpoch(j['u'] ?? 0),
      );
}

/// State every story keeps, whether it is a D&D adventure or a text adventure:
/// relationships, private chats, generated media and character voices.
mixin WorldData {
  Chronicle chronicle = Chronicle();
  Map<String, Bond> bonds = {};
  Map<String, List<ChatLine>> chats = {};
  List<MediaItem> gallery = [];

  /// Person id -> voice name for AI voices.
  Map<String, String> voices = {};

  /// Media path -> cost of generating it (for per-image labels).
  Map<String, double> mediaCosts = {};

  /// The player's own notes.
  List<StoryNote> notes = [];

  /// Seconds spent with this story open.
  int playSeconds = 0;

  /// People who started a conversation the player hasn't opened yet.
  Set<String> unreadChats = {};

  /// Topics characters have already come to the player about (topic -> turn).
  Map<String, int> approachTopics = {};

  /// Turn of the last time someone started a conversation (-1 never).
  int lastApproachTurn = -1;

  /// Chapters whose "What changed" screen has been shown.
  Set<String> seenRecaps = {};

  /// Inner lives of characters, by person id.
  Map<String, PersonProfile> profiles = {};

  /// Results from the AI tools, newest last.
  List<AiNote> aiNotes = [];

  /// The text of readable items, by lowercase item name.
  Map<String, ItemWriting> writings = {};

  /// Pictures of items, by lowercase item name.
  Map<String, String> itemImages = {};

  /// Descriptions of items made or found, by lowercase item name.
  Map<String, String> itemNotes = {};

  /// Body and mind beyond hit points.
  Vitals vitals = Vitals();

  /// How the storyteller narrates ("Grim and gritty", or the player's own words). Empty = default.
  String narratorTone = '';

  /// World details the player wrote when creating the story (their own setting).
  String worldNotes = '';

  /// The player asked to wrap the story up (turn they asked, or -1).
  int wrapUpTurn = -1;

  /// Cash (text adventures), savings, transactions, debts and prices.
  Wallet wallet = Wallet();

  /// Saved narration for replays: log index -> audio files (from imports).
  Map<String, List<String>> replayAudio = {};

  /// Achievements the storyteller awarded in this story (titles).
  List<String> storyAwards = [];

  PersonProfile profileOf(Npc person) => profiles.putIfAbsent(person.id, () => PersonProfile());

  void addAiNote(AiNote n) {
    aiNotes.add(n);
    while (aiNotes.length > 120) {
      final i = aiNotes.indexWhere((x) => !x.pinned);
      if (i < 0) break;
      aiNotes.removeAt(i);
    }
  }

  Bond bondFor(Npc person) => bonds.putIfAbsent(person.id, () => Bond(friendship: person.disposition.clamp(-100, 100)));

  List<ChatLine> chatWith(String personId) => chats.putIfAbsent(personId, () => []);

  void addMedia(MediaItem m) {
    gallery.removeWhere((g) => g.path == m.path);
    gallery.add(m);
    if (m.cost > 0) mediaCosts[m.path] = m.cost;
    if (gallery.length > 300) gallery.removeAt(0);
  }

  Map<String, dynamic> worldToJson() => {
        'chronicle': chronicle.toJson(),
        'bonds': bonds.map((k, v) => MapEntry(k, v.toJson())),
        'chats': chats.map((k, v) => MapEntry(k, v.map((l) => l.toJson()).toList())),
        'gallery': gallery.map((m) => m.toJson()).toList(),
        'voices': voices,
        'mediaCosts': mediaCosts,
        'playerNotes': notes.where((n) => !n.isEmpty).map((n) => n.toJson()).toList(),
        'play': playSeconds,
        if (unreadChats.isNotEmpty) 'unread': unreadChats.toList(),
        if (approachTopics.isNotEmpty) 'approaches': approachTopics,
        'approachTurn': lastApproachTurn,
        if (seenRecaps.isNotEmpty) 'seenRecaps': seenRecaps.toList(),
        if (profiles.isNotEmpty) 'profiles': profiles.map((k, v) => MapEntry(k, v.toJson())),
        if (aiNotes.isNotEmpty) 'aiNotes': aiNotes.map((n) => n.toJson()).toList(),
        if (writings.isNotEmpty) 'writings': writings.map((k, v) => MapEntry(k, v.toJson())),
        if (itemImages.isNotEmpty) 'itemImages': itemImages,
        if (itemNotes.isNotEmpty) 'itemNotes': itemNotes,
        'vitals': vitals.toJson(),
        if (narratorTone.isNotEmpty) 'tone': narratorTone,
        if (worldNotes.isNotEmpty) 'worldNotes': worldNotes,
        if (wrapUpTurn >= 0) 'wrapUp': wrapUpTurn,
        if (storyAwards.isNotEmpty) 'awards': storyAwards,
        if (replayAudio.isNotEmpty) 'replayAudio': replayAudio,
        'wallet': wallet.toJson(),
      };

  void worldFromJson(Map<String, dynamic> j) {
    chronicle = Chronicle.fromJson(Map<String, dynamic>.from(j['chronicle'] ?? {}));
    bonds = {for (final e in (j['bonds'] as Map? ?? const {}).entries) e.key as String: Bond.fromJson(Map<String, dynamic>.from(e.value))};
    chats = {
      for (final e in (j['chats'] as Map? ?? const {}).entries)
        e.key as String: [for (final l in (e.value as List)) ChatLine.fromJson(Map<String, dynamic>.from(l))],
    };
    gallery = [for (final m in (j['gallery'] as List? ?? const [])) MediaItem.fromJson(Map<String, dynamic>.from(m))];
    voices = Map<String, String>.from(j['voices'] ?? const {});
    mediaCosts = {for (final e in (j['mediaCosts'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toDouble()};
    notes = [for (final n in (j['playerNotes'] as List? ?? const [])) StoryNote.fromJson(Map<String, dynamic>.from(n))];
    playSeconds = (j['play'] as num?)?.toInt() ?? 0;
    unreadChats = {for (final id in (j['unread'] as List? ?? const [])) id as String};
    approachTopics = {for (final e in (j['approaches'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt()};
    lastApproachTurn = (j['approachTurn'] as num?)?.toInt() ?? -1;
    seenRecaps = {for (final id in (j['seenRecaps'] as List? ?? const [])) id as String};
    profiles = {for (final e in (j['profiles'] as Map? ?? const {}).entries) e.key as String: PersonProfile.fromJson(Map<String, dynamic>.from(e.value))};
    aiNotes = [for (final n in (j['aiNotes'] as List? ?? const [])) AiNote.fromJson(Map<String, dynamic>.from(n))];
    writings = {for (final e in (j['writings'] as Map? ?? const {}).entries) e.key as String: ItemWriting.fromJson(Map<String, dynamic>.from(e.value))};
    itemImages = Map<String, String>.from(j['itemImages'] ?? const {});
    itemNotes = Map<String, String>.from(j['itemNotes'] ?? const {});
    vitals = j['vitals'] is Map ? Vitals.fromJson(Map<String, dynamic>.from(j['vitals'])) : Vitals();
    narratorTone = j['tone'] ?? '';
    worldNotes = j['worldNotes'] ?? '';
    wrapUpTurn = (j['wrapUp'] as num?)?.toInt() ?? -1;
    storyAwards = List<String>.from(j['awards'] ?? const []);
    replayAudio = {for (final e in (j['replayAudio'] as Map? ?? const {}).entries) e.key as String: List<String>.from(e.value as List)};
    wallet = j['wallet'] is Map ? Wallet.fromJson(Map<String, dynamic>.from(j['wallet'])) : Wallet();
  }

  /// Every character's profile for AI prompts (only those with one).
  String profilesPrompt(Iterable<Npc> people, {String focus = '', int max = 6}) {
    final f = focus.toLowerCase();
    final list = [
      for (final p in people)
        if (profiles[p.id] case final pr? when !pr.isEmpty) (p, pr),
    ];
    // Characters in the scene first.
    list.sort((a, b) => (f.contains(b.$1.name.split(' ').first.toLowerCase()) ? 1 : 0).compareTo(f.contains(a.$1.name.split(' ').first.toLowerCase()) ? 1 : 0));
    final lines = [for (final (p, pr) in list.take(max)) '${p.name}:\n${pr.prompt(memoriesShown: 4).split('\n').map((l) => '  $l').join('\n')}'];
    return lines.isEmpty ? '' : 'CHARACTER PROFILES (who they are; keep them consistent and let them grow):\n${lines.join('\n')}';
  }

  /// Instructions that follow the player's narrator tone and wrap-up request.
  String directionPrompt(int turn) => [
        if (worldNotes.isNotEmpty) 'THE WORLD (the player designed it; honor every detail): $worldNotes',
        if (narratorTone.isNotEmpty) 'NARRATOR VOICE (the player chose this; keep to it): $narratorTone.',
        if (wrapUpTurn >= 0) 'THE PLAYER WANTS TO FINISH SOON (asked ${turn - wrapUpTurn} turns ago): steer every thread toward a satisfying climax and ending within ${(3 - (turn - wrapUpTurn)).clamp(1, 3)} more turns. Resolve the main quest, give companions a closing beat, then end the story (end event / ending). Do not open new threads.',
      ].join('\n');

  /// Relationships for the AI, strongest first.
  String bondsPrompt(Iterable<Npc> people) {
    final lines = [
      for (final p in people)
        if (bonds[p.id] case final b? when b.friendship != 0 || b.romance != 0 || b.status.isNotEmpty || b.romanceClosed) b.describe(p.name),
    ];
    return lines.isEmpty ? '' : 'RELATIONSHIPS (how they feel about the protagonist; keep this consistent):\n- ${lines.join('\n- ')}';
  }
}

/// Applies a relationship change from the story or a conversation and records it.
/// Returns a one-line summary for the log, or null if nothing changed.
String? applyBondChange(WorldData w, Npc person, {int friendship = 0, int romance = 0, String reason = '', String? status, bool? romanceClosed, int turn = 0}) {
  final b = w.bondFor(person);
  final f = friendship.clamp(-35, 35), r = romance.clamp(-25, 25);
  if (f == 0 && r == 0 && (status == null || status == b.status) && (romanceClosed == null || romanceClosed == b.romanceClosed)) return null;
  b.friendship = (b.friendship + f).clamp(-100, 100);
  if (romanceClosed != null) b.romanceClosed = romanceClosed;
  if (!b.romanceClosed) b.romance = (b.romance + r).clamp(0, 100);
  if (status != null) b.status = status.trim();
  person.disposition = b.friendship;
  final parts = [
    if (f != 0) '${f > 0 ? '+' : ''}$f friendship',
    if (r != 0 && !b.romanceClosed) '${r > 0 ? '+' : ''}$r romance',
    if (status != null && status.trim().isNotEmpty) status.trim(),
  ];
  b.moments.add(BondMoment(text: reason.isEmpty ? parts.join(', ') : reason, friendship: f, romance: r, turn: turn));
  return '${person.name}: ${parts.join(', ')}${reason.isEmpty ? '' : ' — $reason'}';
}


/// A starting friendship for how someone stands toward the protagonist.
int? stanceFriendship(String? stance) => switch ((stance ?? '').trim().toLowerCase()) {
      'enemy' || 'nemesis' || 'villain' => -75,
      'hostile' => -50,
      'rival' => -35,
      'wary' || 'suspicious' => -20,
      'neutral' || 'stranger' => 0,
      'friendly' => 15,
      'ally' || 'friend' => 35,
      'family' || 'devoted' => 55,
      _ => null,
    };

/// The label for a stance, when it should be shown from the start.
String? stanceLabel(String? stance) => switch ((stance ?? '').trim().toLowerCase()) {
      'enemy' || 'nemesis' || 'villain' => 'Enemy',
      'hostile' => 'Hostile',
      'rival' => 'Rival',
      'ally' => 'Ally',
      'family' => 'Family',
      _ => null,
    };

/// The memory worth sending this turn: pinned facts, facts about whatever was
/// just mentioned, then the most recent — instead of everything ever recorded.
List<CanonEntry> relevantCanon(List<CanonEntry> canon, String focus, {int max = 20}) {
  final text = focus.toLowerCase();
  bool mentioned(CanonEntry c) {
    final name = c.name.toLowerCase().trim();
    if (name.isEmpty) return false;
    if (text.contains(name)) return true;
    final first = name.split(RegExp(r'\s+')).first;
    return first.length >= 4 && text.contains(first);
  }

  final out = <CanonEntry>[];
  void add(Iterable<CanonEntry> xs) {
    for (final c in xs) {
      if (out.length >= max) return;
      if (!out.contains(c)) out.add(c);
    }
  }

  final recent = canon.toList()..sort((a, b) => b.turn.compareTo(a.turn));
  add(canon.where((c) => c.pinned));
  add(recent.where(mentioned));
  add(recent);
  return out;
}

/// The last few lines of a story, for deciding what memory is relevant.
String recentFocus(List<LogEntry> log, {int entries = 8}) =>
    log.reversed.take(entries).map((e) => '${e.speaker ?? ''} ${e.text}').join(' ');

/// The latest AI scene picture of a place like [s] (same kind of place, day or
/// night), so a story only pays for art when it reaches a new environment.
String? reusableSceneArt(List<LogEntry> log, Map<String, String> sceneImages, SceneInfo s) {
  final env = s.environment;
  for (final e in log.reversed) {
    final raw = e.meta['scene'];
    if (raw is! Map || e.text == s.title) continue;
    final path = sceneImages[e.text];
    if (path == null) continue;
    if (SceneInfo.fromJson(Map<String, dynamic>.from(raw)).environment == env) return path;
  }
  return null;
}

/// The newest painted scene of a story, used as a style reference for new art.
String? latestScenePicture(List<MediaItem> gallery) => gallery.reversed.where((m) => !m.video && (m.kind == 'scene' || m.kind == 'effect')).firstOrNull?.path;

/// What sort of writing an item is, from its name.
String writingKind(String name) {
  final n = name.toLowerCase();
  for (final k in const ['letter', 'scroll', 'journal', 'diary', 'map', 'book', 'tome', 'ledger', 'log', 'file', 'report', 'note']) {
    if (n.contains(k)) return switch (k) { 'diary' => 'journal', 'tome' || 'ledger' => 'book', 'log' || 'file' || 'report' => 'record', _ => k };
  }
  return 'note';
}

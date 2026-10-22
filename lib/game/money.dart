import 'dart:math' as math;

import '../data/inventory_rules.dart';
import '../data/tale_genres.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import '../models/tale.dart';
import '../models/world.dart';
import 'story_host.dart';

/// The money's name and symbol in a story ('gp', 'credits'…).
(String name, String symbol) currencyOf(StoryRecord r) {
  final w = r as WorldData;
  if (w.wallet.currency.isNotEmpty)
    return (w.wallet.currency, w.wallet.currency);
  if (r is Adventure) return ('gold', 'gp');
  return switch (genreById((r as Tale).genre).id) {
    'scifi' => ('credits', '\$'),
    'cyberpunk' => ('eddies', '€\$'),
    'postapoc' => ('caps', 'caps'),
    'western' || 'noir' || 'comedy' || 'horror' => ('dollars', '\$'),
    'pirate' => ('doubloons', 'dbl'),
    'fantasy' => ('gold', 'gp'),
    _ => ('coins', 'c'),
  };
}

/// "12 gp", "\$40", "350 credits".
String money(StoryRecord r, num amount, {bool sign = false}) {
  final (name, sym) = currencyOf(r);
  final a = amount.abs();
  final n = a == a.roundToDouble()
      ? a.toStringAsFixed(0)
      : a
            .toStringAsFixed(r is Adventure ? 2 : 2)
            .replaceFirst(RegExp(r'0$'), '');
  final s = sign ? (amount < 0 ? '−' : '+') : (amount < 0 ? '−' : '');
  if (sym == '\$' || sym == '€\$') return '$s$sym$n';
  return '$s$n ${sym == name ? name : sym}';
}

/// Cash in hand: the hero's whole purse in gold (D&D) or the wallet.
double cashOf(StoryRecord r) =>
    r is Adventure ? r.hero.wealthGp : (r as WorldData).wallet.cash;

/// Cash plus what's on the card.
double totalOf(StoryRecord r) => cashOf(r) + (r as WorldData).wallet.bank;

int _turnOf(StoryRecord r) => r is Adventure ? r.turns : (r as Tale).turns;

double _round(double v) => double.parse(v.toStringAsFixed(2));

/// Adds (or takes, if negative) cash. D&D coins are re-counted into gp/sp/cp.
/// Returns false when there isn't enough.
bool changeCash(StoryRecord r, double amount) {
  if (cashOf(r) + amount < -0.001) return false;
  if (r is Adventure) {
    final h = r.hero;
    final cp = ((h.wealthGp + amount) * 100).round();
    h.platinum = 0;
    h.gold = cp ~/ 100;
    h.silver = (cp % 100) ~/ 10;
    h.copper = cp % 10;
  } else {
    final w = (r as WorldData).wallet;
    w.cash = double.parse((w.cash + amount).toStringAsFixed(2));
  }
  return true;
}

/// Records a transaction that already happened (the story moved the coins).
void logMoney(
  StoryHost host,
  double amount, {
  String category = 'other',
  String who = '',
  String note = '',
  String account = 'cash',
}) {
  if (amount == 0) return;
  final w = host.world.wallet;
  // The first record sets the count; the coins have already moved.
  w.tracked ??= totalOf(host.record) - (Wallet.transfers.contains(category) ? 0 : amount);
  w.record(
    MoneyMove(
      amount: amount,
      category: category,
      counterparty: who,
      note: note,
      turn: host.turns,
      account: account,
    ),
  );
}

/// Moves money and records it. Returns an error message, or null.
String? spend(
  StoryHost host,
  double amount, {
  required String category,
  String who = '',
  String note = '',
  bool tellStory = true,
}) {
  if (amount == 0) return null;
  if (!changeCash(host.record, amount))
    return 'Not enough cash: you have ${money(host.record, cashOf(host.record))}.';
  logMoney(host, amount, category: category, who: who, note: note);
  if (tellStory) {
    final m = money(host.record, amount.abs());
    host.note(
      amount < 0
          ? 'The player paid $m${who.isEmpty ? '' : ' to $who'} ($category${note.isEmpty ? '' : ': $note'}).'
          : 'The player received $m${who.isEmpty ? '' : ' from $who'} ($category${note.isEmpty ? '' : ': $note'}).',
    );
  }
  return null;
}

/// Puts cash on the card (positive) or takes it back out (negative).
String? bankTransfer(StoryHost host, double toBank) {
  final w = host.world.wallet;
  if (toBank < 0 && w.bank + toBank < -0.001)
    return 'Only ${money(host.record, w.bank)} on the card.';
  if (!changeCash(host.record, -toBank))
    return 'Not enough cash: you have ${money(host.record, cashOf(host.record))}.';
  w.bank = double.parse((w.bank + toBank).toStringAsFixed(2));
  logMoney(
    host,
    -toBank,
    category: toBank > 0 ? 'deposit' : 'withdrawal',
    note: toBank > 0 ? 'To the card' : 'From the card',
  );
  return null;
}

/// Pays from the card instead of cash. Returns an error message, or null.
String? payByCard(StoryHost host, double amount, {required String category, String who = '', String note = ''}) {
  final w = host.world.wallet;
  if (amount <= 0) return 'Enter an amount.';
  if (w.bank + 0.001 < amount) return 'Only ${money(host.record, w.bank)} on the card.';
  w.bank = _round(w.bank - amount);
  logMoney(host, -amount, category: category, who: who, note: note, account: 'bank');
  return null;
}

/// Gives money to someone in the story: a gift, a payment or a loan.
/// A loan can carry interest ([rate], percent per 10 turns) and a due turn.
String? giveMoney(
  StoryHost host,
  Npc to,
  double amount, {
  required String kind,
  String note = '',
  bool byCard = false,
  int? dueIn,
  double rate = 0,
}) {
  if (amount <= 0) return 'Enter an amount.';
  final err = byCard
      ? payByCard(host, amount, category: kind, who: to.name, note: note)
      : spend(
          host,
          -amount,
          category: kind,
          who: to.name,
          note: note,
          tellStory: false,
        );
  if (err != null) return err;
  final w = host.world.wallet;
  if (kind == 'loan') {
    w.owed[to.name] = (w.owed[to.name] ?? 0) + amount;
    if (dueIn != null && dueIn > 0) w.due[to.name] = host.turns + dueIn;
    if (rate > 0) w.rates[to.name] = rate;
  }
  if (kind == 'repayment') w.owed[to.name] = (w.owed[to.name] ?? 0) + amount;
  _settleDebt(w, to.name);
  final m = money(host.record, amount);
  final terms = kind == 'loan' && (dueIn != null || rate > 0)
      ? ' Terms:${rate > 0 ? ' ${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1)}% interest every 10 turns' : ''}${dueIn != null && dueIn > 0 ? ', due in $dueIn turns' : ''}.'
      : '';
  host.note('${switch (kind) {
    'loan' =>
      'The player lent $m to ${to.name}${note.isEmpty ? '' : ' ($note)'}. ${to.name} owes it back.',
    'repayment' =>
      'The player paid back $m to ${to.name}${note.isEmpty ? '' : ' ($note)'}.',
    'bribe' =>
      'The player slipped ${to.name} a bribe of $m${note.isEmpty ? '' : ' ($note)'}.',
    'purchase' =>
      'The player paid ${to.name} $m${note.isEmpty ? '' : ' for $note'}.',
    _ =>
      'The player gave ${to.name} $m as a gift${note.isEmpty ? '' : ' ($note)'}.',
  }}${byCard ? ' (paid by card)' : ''}$terms');
  return null;
}

/// Clears a debt's terms once it's paid off.
void _settleDebt(Wallet w, String who) {
  if ((w.owed[who] ?? 0).abs() < 0.01) {
    w.owed.remove(who);
    w.due.remove(who);
    w.rates.remove(who);
  }
}

/// Records money the player says moved (a correction, or something the story
/// missed). [account] is 'cash' or 'bank'. Returns an error message, or null.
String? recordManual(StoryHost host, double amount, {required String category, String who = '', String note = '', String account = 'cash'}) {
  if (amount == 0) return 'Enter an amount.';
  final w = host.world.wallet;
  if (account == 'bank') {
    if (w.bank + amount < -0.001) return 'Only ${money(host.record, w.bank)} on the card.';
    w.bank = _round(w.bank + amount);
  } else if (!changeCash(host.record, amount)) {
    return 'Not enough cash: you have ${money(host.record, cashOf(host.record))}.';
  }
  logMoney(host, amount, category: category, who: who, note: note.isEmpty ? 'Added by you' : note, account: account);
  if (who.isNotEmpty && Wallet.credit.contains(category)) {
    w.owed[who] = (w.owed[who] ?? 0) - amount;
    _settleDebt(w, who);
  }
  return null;
}

/// Undoes [m] with an opposite entry, so the history stays complete.
/// Returns an error message, or null.
String? reverseMove(StoryHost host, MoneyMove m) {
  final w = host.world.wallet;
  if (w.ledger.any((x) => x.category == 'reversal' && x.note.endsWith('#${m.id}'))) return 'Already reversed.';
  // A deposit was logged as cash leaving (and a withdrawal as cash arriving),
  // so moving that amount the other way undoes either.
  if (Wallet.transfers.contains(m.category)) return bankTransfer(host, m.amount);
  final back = -m.amount;
  if (m.account == 'bank') {
    if (w.bank + back < -0.001) return 'Only ${money(host.record, w.bank)} on the card.';
    w.bank = _round(w.bank + back);
  } else if (!changeCash(host.record, back)) {
    return 'Not enough cash to undo this.';
  }
  logMoney(host, back, category: 'reversal', who: m.counterparty, note: 'Undid ${m.category}${m.note.isEmpty ? '' : ': ${m.note}'} #${m.id}', account: m.account);
  if (m.counterparty.isNotEmpty && Wallet.credit.contains(m.category)) {
    w.owed[m.counterparty] = (w.owed[m.counterparty] ?? 0) + m.amount;
    _settleDebt(w, m.counterparty);
  }
  return null;
}

/// Keeps the history adding up: when the real total differs from what the
/// ledger knows (coins changed without a record), records the difference.
/// Returns it (0 when everything matched).
double reconcile(StoryHost host) {
  final w = host.world.wallet;
  final total = totalOf(host.record);
  final known = w.tracked;
  w.tracked = total;
  if (known == null) return 0;
  final diff = _round(total - known);
  if (diff.abs() < 0.01) return 0;
  w.ledger.add(MoneyMove(amount: diff, category: 'adjustment', note: 'Changed outside the story', turn: host.turns));
  if (w.ledger.length > 500) w.ledger.removeAt(0);
  return diff;
}

/// Works out interest every 10 turns: savings on the card, and debts with a
/// rate (what you owe grows, and so does what you're owed). Returns lines
/// describing what changed.
List<String> accrueInterest(StoryHost host) {
  final w = host.world.wallet;
  final now = host.turns;
  final since = w.interestTurn;
  if (since == null || since > now) {
    w.interestTurn = now;
    return const [];
  }
  final periods = (now - since) ~/ 10;
  if (periods <= 0) return const [];
  w.interestTurn = since + periods * 10;
  final out = <String>[];
  if (w.bankRate > 0 && w.bank > 0) {
    final gain = _round(w.bank * (math.pow(1 + w.bankRate / 100, periods) - 1));
    if (gain >= 0.01) {
      w.bank = _round(w.bank + gain);
      logMoney(host, gain, category: 'interest', note: 'Savings interest', account: 'bank');
      out.add('The card paid ${money(host.record, gain)} interest.');
    }
  }
  for (final e in w.rates.entries.toList()) {
    final owed = w.owed[e.key];
    if (owed == null || e.value <= 0) continue;
    final grown = _round(owed * math.pow(1 + e.value / 100, periods));
    if ((grown - owed).abs() < 0.01) continue;
    w.owed[e.key] = grown;
    out.add(owed > 0 ? '${e.key} now owes you ${money(host.record, grown)} with interest.' : 'Your debt to ${e.key} grew to ${money(host.record, -grown)} with interest.');
  }
  return out;
}

/// Interest, then a balance check. Called on save.
void settleMoney(StoryHost host) {
  for (final line in accrueInterest(host)) {
    host.note(line);
  }
  reconcile(host);
}

/// Money in and out with each person, and what's owed: name -> (in, out, owed).
Map<String, (double, double, double)> moneyByPerson(Wallet w) {
  final out = <String, (double, double, double)>{};
  for (final m in w.ledger) {
    if (m.counterparty.isEmpty || m.category == 'adjustment') continue;
    final (i, o, d) = out[m.counterparty] ?? (0.0, 0.0, 0.0);
    out[m.counterparty] = m.amount > 0 ? (i + m.amount, o, d) : (i, o - m.amount, d);
  }
  for (final e in w.owed.entries) {
    final (i, o, _) = out[e.key] ?? (0.0, 0.0, 0.0);
    out[e.key] = (i, o, e.value);
  }
  return out;
}

/// The whole history as a spreadsheet (CSV), oldest first.
String ledgerCsv(StoryRecord r) {
  final w = (r as WorldData).wallet;
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final rows = <String>['Date,Turn,Account,Category,Who,Note,Amount,Currency'];
  final cur = currencyOf(r).$1;
  for (final m in w.ledger) {
    rows.add([m.at.toIso8601String(), m.turn, m.account, q(m.category), q(m.counterparty), q(m.note), m.amount.toStringAsFixed(2), q(cur)].join(','));
  }
  return rows.join('\n');
}

/// Applies a money event from the storyteller: {amount, counterparty, category, note}.
/// Returns a short line for the log, or null.
String? applyMoneyEvent(StoryHost host, Map<String, dynamic> e) {
  final raw = e['amount'];
  final amount = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  if (amount == 0) return null;
  final who = (e['counterparty'] ?? e['who'] ?? '').toString();
  final category = (e['category'] ?? (amount > 0 ? 'loot' : 'purchase'))
      .toString();
  final note = (e['note'] ?? e['reason'] ?? '').toString();
  // The storyteller can't overdraw the player: take what there is.
  final applied = amount < 0
      ? -(amount.abs().clamp(0, cashOf(host.record)))
      : amount;
  if (applied == 0) return null;
  changeCash(host.record, applied.toDouble());
  logMoney(host, applied.toDouble(), category: category, who: who, note: note);
  final w = host.world.wallet;
  if (who.isNotEmpty && (category == 'loan' || category == 'repayment')) {
    // A loan to you, or someone paying back what they owed.
    w.owed[who] = (w.owed[who] ?? 0) - applied;
    if ((w.owed[who] ?? 0).abs() < 0.01) w.owed.remove(who);
  }
  _settleDebt(w, who);
  return '${money(host.record, applied, sign: true)}${who.isEmpty ? '' : ' · $who'}${note.isEmpty ? '' : ' · $note'}';
}

/// Wallet lines for the storyteller's state.
String walletPrompt(StoryRecord r) {
  final w = (r as WorldData).wallet;
  final (name, _) = currencyOf(r);
  final turn = _turnOf(r);
  String terms(String who) {
    final due = w.due[who];
    final rate = w.rates[who];
    return [
      if (rate != null) '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1)}% interest per 10 turns',
      if (due != null) due < turn ? 'OVERDUE since turn $due' : 'due by turn $due',
    ].join(', ');
  }
  final debts = w.owed.entries
      .map((e) {
        final t = terms(e.key);
        return '${e.value > 0 ? '${e.key} owes the player ${money(r, e.value)}' : 'the player owes ${e.key} ${money(r, -e.value)}'}${t.isEmpty ? '' : ' ($t)'}';
      })
      .join('; ');
  return 'MONEY ($name): cash ${money(r, cashOf(r))}${w.bank > 0 ? ', savings ${money(r, w.bank)} (not in hand)' : ''}${debts.isEmpty ? '' : '. Debts: $debts'}. '
      'Money is real: use the money event/field whenever coins change hands (found, earned, paid, stolen, lost, lent). Never let the player spend more than they carry.';
}

/// Rough market prices from the SRD, for D&D stories without an AI list.
List<Map<String, String>> defaultPrices(StoryRecord r) {
  if (r is! Adventure) return const [];
  return const [
    {'item': 'Ale (mug)', 'price': '4 cp'},
    {'item': 'Inn room (night)', 'price': '5 sp'},
    {'item': 'Hot meal', 'price': '3 sp'},
    {'item': 'Rations (1 day)', 'price': '5 sp'},
    {'item': 'Torch', 'price': '1 cp'},
    {'item': 'Rope, 50 ft', 'price': '1 gp'},
    {'item': 'Potion of healing', 'price': '50 gp'},
    {'item': 'Longsword', 'price': '15 gp'},
    {'item': 'Riding horse', 'price': '75 gp'},
    {'item': 'Skilled hireling (day)', 'price': '2 gp'},
  ];
}

/// The value of what the player carries (D&D items with a price).
double carriedValue(StoryRecord r) {
  if (r is! Adventure) return 0;
  return r.hero.inventory.fold<double>(
    0,
    (n, i) => n + (i.def?.value ?? 0) * i.qty,
  );
}

/// The carrying weight of coins (keeps the inventory rules in one place).
double coinWeightOf(Character c) => c.coinWeight;

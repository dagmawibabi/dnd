import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../game/adventure_controller.dart';
import '../../../game/money.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../models/world.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/error_card.dart';
import '../../widgets/portrait.dart';

Future<void> openFinance(BuildContext context, StoryHost host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FinanceScreen(host: host)));

const _categoryIcons = {
  'loot': Icons.diamond_outlined,
  'purchase': Icons.shopping_bag_outlined,
  'sale': Icons.sell_outlined,
  'wage': Icons.work_outline,
  'reward': Icons.emoji_events_outlined,
  'gift': Icons.card_giftcard_outlined,
  'loan': Icons.handshake_outlined,
  'repayment': Icons.assignment_turned_in_outlined,
  'theft': Icons.back_hand_outlined,
  'stolen': Icons.report_outlined,
  'bribe': Icons.visibility_off_outlined,
  'fine': Icons.gavel_outlined,
  'tax': Icons.account_balance_outlined,
  'gamble': Icons.casino_outlined,
  'deposit': Icons.south_east,
  'withdrawal': Icons.north_west,
  'interest': Icons.trending_up,
  'adjustment': Icons.tune,
  'reversal': Icons.undo,
  'rent': Icons.home_outlined,
  'food': Icons.restaurant_outlined,
  'travel': Icons.directions_walk,
};

/// Categories the player can pick when recording money by hand.
const _manualCategories = ['loot', 'wage', 'reward', 'gift', 'sale', 'purchase', 'food', 'rent', 'travel', 'fine', 'tax', 'gamble', 'stolen', 'loan', 'repayment', 'other'];

IconData moneyIcon(String category) => _categoryIcons[category] ?? Icons.payments_outlined;

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The story's money: wallet, card, transfers, earning in the story, debts,
/// spending stats, local prices and the full history.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, required this.host});
  final StoryHost host;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  String _filter = 'all';
  String _category = '';
  final _search = TextEditingController();
  bool _pricing = false;

  StoryHost get host => widget.host;
  StoryRecord get r => host.record;

  @override
  void initState() {
    super.initState();
    // Interest due, and anything that moved money without a record.
    final before = host.world.wallet.ledger.length;
    settleMoney(host);
    if (host.world.wallet.ledger.length != before) host.save();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final done = await showAppSheet<bool>(context, builder: (_) => _RecordSheet(host: host));
    if (done == true && mounted) _changed();
  }

  Future<void> _export() async {
    final csv = ledgerCsv(r);
    final name = '${host.storyTitle.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim()} money.csv';
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(Uint8List.fromList(utf8.encode(csv)), mimeType: 'text/csv', name: name)], fileNameOverrides: [name], subject: name));
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) showToast(context, 'Copied the history as CSV');
    }
  }

  Future<void> _savingsRate() async {
    final w = host.world.wallet;
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Savings interest'),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('What the card pays on savings, every 10 turns.', style: T.small())),
          for (final rate in const [0.0, 0.5, 1.0, 2.0, 5.0])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, rate),
              child: Row(children: [
                Icon(w.bankRate == rate ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: AppColors.accent),
                const SizedBox(width: 12),
                Text(rate == 0 ? 'None' : '${_pct(rate)} per 10 turns', style: T.body()),
              ]),
            ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    w.bankRate = v;
    w.interestTurn ??= host.turns;
    host.save();
    setState(() {});
  }

  Future<void> _terms(String who) async {
    final done = await showAppSheet<bool>(context, builder: (_) => _TermsSheet(host: host, who: who));
    if (done == true && mounted) _changed();
  }

  void _details(MoneyMove m) => showAppSheet(context, builder: (_) => _MoveSheet(host: host, move: m, onChanged: _changed));

  void _changed() {
    host.save();
    host.refresh();
    context.read<AudioService>().play('coin');
  }

  Future<void> _bank(bool deposit) async {
    final max = deposit ? cashOf(r) : host.world.wallet.bank;
    final amount = await _askAmount(context, title: deposit ? 'Put on the card' : 'Take from the card', max: max, record: r);
    if (amount == null || !mounted) return;
    final err = bankTransfer(host, deposit ? amount : -amount);
    if (err != null) {
      showToast(context, err, icon: Icons.error_outline);
      return;
    }
    _changed();
  }

  Future<void> _send({Npc? to}) async {
    final done = await showAppSheet<bool>(context, builder: (_) => _SendSheet(host: host, to: to));
    if (done == true && mounted) _changed();
  }

  Future<void> _request() async {
    final who = await _pickPerson(context, host, title: 'Ask who for money?');
    if (who == null || !mounted) return;
    final amount = await _askAmount(context, title: 'How much do you ask ${who.name.split(' ').first} for?', record: r, reason: true);
    if (amount == null || !mounted) return;
    Navigator.pop(context);
    host.act('I ask ${who.name} for ${money(r, amount)}${_lastReason.isEmpty ? '' : ': $_lastReason'}.');
  }

  void _storyAction(String text) {
    Navigator.pop(context);
    host.act(text);
  }

  Future<void> _personAction(String verb, String Function(Npc) text) async {
    final who = await _pickPerson(context, host, title: verb);
    if (who == null || !mounted) return;
    _storyAction(text(who));
  }

  Future<void> _prices() async {
    setState(() => _pricing = true);
    try {
      final res = await StoryAi(host.settings).economy(host, currencyOf(r).$1);
      host.world.wallet
        ..economy = res.value.$1
        ..prices = res.value.$2;
      host.save();
    } catch (e) {
      if (mounted) showIssueSheet(context, '$e', label: 'Prices');
    } finally {
      if (mounted) setState(() => _pricing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final w = host.world.wallet;
        final cash = cashOf(r);
        final ai = host.isAi && context.watch<SettingsController>().useAiText;
        final q = _search.text.trim().toLowerCase();
        final moves = w.ledger.reversed.where((m) => switch (_filter) { 'in' => m.amount > 0 && !Wallet.transfers.contains(m.category), 'out' => m.amount < 0 && !Wallet.transfers.contains(m.category), 'card' => m.account == 'bank' || Wallet.transfers.contains(m.category), _ => true })
            .where((m) => _category.isEmpty || m.category == _category)
            .where((m) => q.isEmpty || '${m.category} ${m.counterparty} ${m.note}'.toLowerCase().contains(q))
            .toList();
        bool counts(MoneyMove m) => !Wallet.transfers.contains(m.category) && !Wallet.credit.contains(m.category);
        final byCat = <String, double>{};
        final bySource = <String, double>{};
        for (final m in w.ledger.where(counts)) {
          if (m.amount < 0) {
            byCat[m.category] = (byCat[m.category] ?? 0) - m.amount;
          } else {
            bySource[m.category] = (bySource[m.category] ?? 0) + m.amount;
          }
        }
        final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final sources = bySource.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final people = moneyByPerson(w).entries.toList()..sort((a, b) => (b.value.$1 + b.value.$2 + b.value.$3.abs()).compareTo(a.value.$1 + a.value.$2 + a.value.$3.abs()));
        final present = {for (final m in w.ledger) m.category}.toList()..sort();
        final prices = w.prices.isNotEmpty ? w.prices : defaultPrices(r);
        final (name, _) = currencyOf(r);
        Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
              child: Opacity(
                opacity: onTap == null ? 0.4 : 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: Icon(icon, size: 20)),
                      const SizedBox(height: 6),
                      Text(label, style: T.caption(color: AppColors.text)),
                    ]),
                  ),
                ),
              ),
            );
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wallet & money', style: T.h3()),
              Text('${host.storyTitle} · ${_cap(name)}', style: T.caption(), overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              IconButton(tooltip: 'Record money by hand', icon: const Icon(Icons.edit_note), onPressed: _record),
              IconButton(tooltip: 'Export the history (CSV)', icon: const Icon(Icons.ios_share), onPressed: w.ledger.isEmpty ? null : _export),
            ],
          ),
          body: ContentWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              SizedBox(
                height: 196,
                child: PageView(controller: PageController(viewportFraction: 0.92), padEnds: false, children: [
                  _MoneyCard(title: 'Wallet', subtitle: r is Adventure ? _purse(r as Adventure) : 'Cash in hand', amount: money(r, cash), colors: const [Color(0xFF3A2C12), Color(0xFF1A140A)], accent: const Color(0xFFE0B354), icon: Icons.account_balance_wallet_outlined, footer: host.playerName == 'you' ? 'Yours' : host.playerName),
                  GestureDetector(
                    onTap: _savingsRate,
                    child: _MoneyCard(title: 'Card', subtitle: '•••• ${(host.storyId.hashCode.abs() % 9000 + 1000)}', amount: money(r, w.bank), colors: const [Color(0xFF1E2A4A), Color(0xFF0D1220)], accent: const Color(0xFF93C5FD), icon: Icons.credit_card, footer: w.bankRate > 0 ? 'Savings · ${_pct(w.bankRate)} interest per 10 turns' : 'Savings · safe from thieves · tap for interest', chip: true),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                action(Icons.send_outlined, 'Send', host.people.isEmpty ? null : () => _send()),
                action(Icons.call_received, 'Request', ai && host.people.isNotEmpty && !host.busy ? _request : null),
                action(Icons.south_east, 'Deposit', cash > 0 ? () => _bank(true) : null),
                action(Icons.north_west, 'Withdraw', w.bank > 0 ? () => _bank(false) : null),
              ]),
              if (ai && !host.busy) ...[
                const SectionLabel('Make or lose money in the story'),
                CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
                  ActionChip(avatar: const Icon(Icons.search, size: 16), label: const Text('Look for valuables'), onPressed: () => _storyAction('I search the area for coins or anything worth money.')),
                  ActionChip(avatar: const Icon(Icons.work_outline, size: 16), label: const Text('Find paid work'), onPressed: () => _storyAction('I look for some paid work nearby.')),
                  ActionChip(avatar: const Icon(Icons.sell_outlined, size: 16), label: const Text('Sell something'), onPressed: () => _storyAction('I look for someone who will buy something I carry, and haggle for a good price.')),
                  ActionChip(avatar: const Icon(Icons.back_hand_outlined, size: 16), label: const Text('Pickpocket…'), onPressed: host.people.isEmpty ? null : () => _personAction('Pick whose pocket?', (n) => 'I try to quietly pick ${n.name}\'s pocket.')),
                  ActionChip(avatar: const Icon(Icons.dangerous_outlined, size: 16), label: const Text('Rob…'), onPressed: host.people.isEmpty ? null : () => _personAction('Rob whom?', (n) => 'I try to rob ${n.name}.')),
                  ActionChip(avatar: const Icon(Icons.casino_outlined, size: 16), label: const Text('Gamble'), onPressed: () async {
                    final a = await _askAmount(context, title: 'How much do you stake?', max: cash, record: r);
                    if (a != null && context.mounted) _storyAction('I find a game of chance and stake ${money(r, a)}.');
                  }),
                ])),
                const SizedBox(height: 4),
                Text('These play out in the story: the storyteller decides what happens and moves the money.', style: T.caption()),
              ],
              if (w.owed.isNotEmpty) ...[
                const SectionLabel('Debts'),
                RowGroup(children: [
                  for (final e in w.owed.entries)
                    ListRow(
                      leading: Icon(e.value > 0 ? Icons.call_received : Icons.call_made, size: 20, color: (w.due[e.key] ?? 1 << 30) < host.turns ? AppColors.danger : (e.value > 0 ? AppColors.success : AppColors.warning)),
                      title: e.value > 0 ? '${e.key} owes you' : 'You owe ${e.key}',
                      subtitle: [
                        money(r, e.value.abs()),
                        if (w.rates[e.key] case final rate?) '${_pct(rate)} per 10 turns',
                        if (w.due[e.key] case final due?) due < host.turns ? 'overdue since turn $due' : 'due turn $due',
                      ].join(' · '),
                      onTap: () => _terms(e.key),
                      trailing: e.value < 0
                          ? TextButton(onPressed: () => _send(to: host.people.where((p) => p.name == e.key).firstOrNull), child: const Text('Pay back'))
                          : (ai && !host.busy ? TextButton(onPressed: () => _storyAction('I remind ${e.key} that they owe me ${money(r, e.value)} and ask for it back.'), child: const Text('Ask for it')) : null),
                    ),
                ]),
              ],
              const SectionLabel('This story'),
              Row(children: [
                Expanded(child: StatTile(label: 'Earned', value: money(r, w.income))),
                const SizedBox(width: 8),
                Expanded(child: StatTile(label: 'Spent', value: money(r, w.spent))),
                const SizedBox(width: 8),
                Expanded(child: StatTile(label: 'Net worth', value: money(r, cash + w.bank + carriedValue(r) + w.receivable - w.payable))),
              ]),
              if (w.receivable > 0 || w.payable > 0 || carriedValue(r) > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: StatTile(label: 'Owed to you', value: money(r, w.receivable))),
                  const SizedBox(width: 8),
                  Expanded(child: StatTile(label: 'You owe', value: money(r, w.payable))),
                  const SizedBox(width: 8),
                  Expanded(child: StatTile(label: 'Gear value', value: money(r, carriedValue(r)))),
                ]),
              ],
              if (w.ledger.length >= 2) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Money over time', style: T.caption()),
                    const SizedBox(height: 8),
                    SizedBox(height: 90, child: CustomPaint(size: Size.infinite, painter: _TrendPainter(_series(w, cash + w.bank)))),
                  ]),
                ),
              ],
              if (people.isNotEmpty) ...[
                const SectionLabel('Money with people'),
                RowGroup(children: [
                  for (final e in people.take(8))
                    ListRow(
                      leading: () {
                        final p = host.people.where((p) => p.name == e.key).firstOrNull;
                        return p == null ? const Icon(Icons.person_outline, size: 20) : NpcPortrait(npc: p, size: 32);
                      }(),
                      title: e.key,
                      subtitle: [
                        if (e.value.$1 > 0) 'got ${money(r, e.value.$1)}',
                        if (e.value.$2 > 0) 'gave ${money(r, e.value.$2)}',
                        if (e.value.$3 > 0) 'owes you ${money(r, e.value.$3)}',
                        if (e.value.$3 < 0) 'you owe ${money(r, -e.value.$3)}',
                      ].join(' · '),
                      trailing: host.people.any((p) => p.name == e.key && p.alive) ? IconButton(tooltip: 'Send money', icon: const Icon(Icons.send_outlined, size: 18), onPressed: () => _send(to: host.people.firstWhere((p) => p.name == e.key))) : null,
                    ),
                ]),
              ],
              if (sources.isNotEmpty) ...[
                const SectionLabel('Where it came from'),
                for (final e in sources.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(moneyIcon(e.key), size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      SizedBox(width: 92, child: Text(_cap(e.key), style: T.small(color: AppColors.text))),
                      Expanded(child: Bar(value: (e.value * 100).round(), max: (sources.first.value * 100).round().clamp(1, 1 << 30), color: AppColors.success)),
                      const SizedBox(width: 8),
                      Text(money(r, e.value), style: T.caption()),
                    ]),
                  ),
              ],
              if (cats.isNotEmpty) ...[
                const SectionLabel('Where it went'),
                for (final e in cats.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(moneyIcon(e.key), size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      SizedBox(width: 92, child: Text(_cap(e.key), style: T.small(color: AppColors.text))),
                      Expanded(child: Bar(value: (e.value * 100).round(), max: (cats.first.value * 100).round().clamp(1, 1 << 30), color: AppColors.warning)),
                      const SizedBox(width: 8),
                      Text(money(r, e.value), style: T.caption()),
                    ]),
                  ),
              ],
              SectionLabel('Economy', trailing: ai
                  ? GestureDetector(onTap: _pricing ? null : _prices, child: Text(_pricing ? 'Checking…' : (w.prices.isEmpty ? 'Check local prices' : 'Update'), style: T.caption(color: AppColors.textMuted)))
                  : null),
              if (w.economy.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(w.economy, style: T.small(color: AppColors.text))),
              if (prices.isEmpty) Text(ai ? 'Tap "Check local prices" to see what things cost here.' : 'Prices appear as the story mentions them.', style: T.small()),
              if (prices.isNotEmpty)
                RowGroup(children: [
                  for (final p in prices)
                    ListRow(
                      title: p['item'] ?? '',
                      subtitle: ai && !host.busy ? 'Tap to buy it in the story' : null,
                      trailing: Text(p['price'] ?? '', style: T.small(color: AppColors.text)),
                      onTap: ai && !host.busy ? () => _storyAction('I buy ${p['item']} (about ${p['price']}).') : null,
                    ),
                ]),
              SectionLabel('History · ${w.ledger.length}'),
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final (id, label) in const [('all', 'All'), ('in', 'Money in'), ('out', 'Money out'), ('card', 'Card')])
                    Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
                ]),
              ),
              if (w.ledger.length > 6) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  style: T.body(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Search people, notes, categories', suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_search.clear))),
                ),
                if (present.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final c in present)
                        Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(avatar: Icon(moneyIcon(c), size: 14), label: Text(_cap(c)), selected: _category == c, onSelected: (v) => setState(() => _category = v ? c : ''))),
                    ]),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              if (moves.isEmpty) EmptyState(icon: Icons.receipt_long_outlined, title: w.ledger.isEmpty ? 'No transactions yet' : 'Nothing matches', message: 'Everything you earn, spend, find, lose, lend or borrow appears here.'),
              if (moves.isNotEmpty)
                RowGroup(children: [
                  for (final m in moves.take(150))
                    ListRow(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: (m.amount >= 0 ? AppColors.success : AppColors.danger).withValues(alpha: 0.12)),
                        child: Icon(moneyIcon(m.category), size: 18, color: m.amount >= 0 ? AppColors.success : AppColors.danger),
                      ),
                      title: [_cap(m.category), if (m.counterparty.isNotEmpty) m.counterparty].join(' · '),
                      subtitle: [if (m.note.isNotEmpty) m.note.replaceAll(RegExp(r' #\S+$'), ''), if (m.account == 'bank') 'card', 'Turn ${m.turn}'].join(' · '),
                      onTap: () => _details(m),
                      trailing: Text(money(r, m.amount, sign: true), style: T.small(color: m.amount >= 0 ? AppColors.success : AppColors.text).copyWith(fontWeight: FontWeight.w600)),
                    ),
                ]),
            ]),
          ),
        );
      },
    );
  }

  /// Balance after each transaction, oldest first, ending at [now].
  List<double> _series(Wallet w, double now) {
    final out = <double>[now];
    var v = now;
    for (final m in w.ledger.reversed) {
      if (m.category == 'deposit' || m.category == 'withdrawal') continue;
      v -= m.amount;
      out.add(v);
    }
    return out.reversed.toList();
  }

  String _purse(Adventure a) {
    final h = a.hero;
    return [if (h.platinum > 0) '${h.platinum} pp', '${h.gold} gp', if (h.silver > 0) '${h.silver} sp', if (h.copper > 0) '${h.copper} cp'].join(' · ');
  }
}

String _lastReason = '';

String _pct(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%';

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.title, required this.subtitle, required this.amount, required this.colors, required this.accent, required this.icon, required this.footer, this.chip = false});
  final String title;
  final String subtitle;
  final String amount;
  final List<Color> colors;
  final Color accent;
  final IconData icon;
  final String footer;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 24, spreadRadius: -4)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: T.overline(color: accent).copyWith(letterSpacing: 2)),
            const Spacer(),
            if (chip)
              Container(
                width: 34,
                height: 26,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: const LinearGradient(colors: [Color(0xFFE6C77A), Color(0xFFB8913E)])),
              ),
          ]),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(amount, style: T.number(34, color: Colors.white))),
          const SizedBox(height: 4),
          Text(subtitle, style: T.small(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Text(footer, style: T.caption(color: Colors.white54)),
        ]),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = (hi - lo).abs() < 0.001 ? 1.0 : hi - lo;
    Offset pt(int i) => Offset(i / (values.length - 1) * size.width, size.height - (values[i] - lo) / span * (size.height - 6) - 3);
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55E0B354), Color(0x00E0B354)]).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFE0B354)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawCircle(pt(values.length - 1), 3.5, Paint()..color = const Color(0xFFE0B354));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}

/// Picks someone from the story.
Future<Npc?> _pickPerson(BuildContext context, StoryHost host, {required String title}) => showAppSheet<Npc>(context, builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.7,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SheetTitle(title),
        RowGroup(children: [
          for (final p in host.people.where((p) => p.alive))
            ListRow(leading: NpcPortrait(npc: p, size: 36), title: p.name, subtitle: [if (p.role.isNotEmpty) p.role, host.world.bondFor(p).label].join(' · '), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ]),
    ));

/// Asks for an amount (and optionally a reason, kept in [_lastReason]).
Future<double?> _askAmount(BuildContext context, {required String title, double? max, required StoryRecord record, bool reason = false}) {
  final amount = TextEditingController();
  final why = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.body(),
            decoration: InputDecoration(labelText: 'Amount (${currencyOf(record).$1})', helperText: max == null ? null : 'Up to ${money(record, max)}'),
          ),
          if (reason) ...[
            const SizedBox(height: 10),
            TextField(controller: why, style: T.body(), decoration: const InputDecoration(labelText: 'Why (optional)')),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final v = double.tryParse(amount.text.trim().replaceAll(',', '.'));
            if (v == null || v <= 0) return;
            if (max != null && v > max + 0.001) {
              showToast(ctx, 'That\'s more than ${money(record, max)}', icon: Icons.error_outline);
              return;
            }
            _lastReason = why.text.trim();
            Navigator.pop(ctx, v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Give, pay, lend, repay or bribe someone in the story.
class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.host, this.to});
  final StoryHost host;
  final Npc? to;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late Npc? _to = widget.to;
  String _kind = 'gift';
  bool _card = false;
  int? _dueIn;
  double _rate = 0;
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final owed = _to == null ? null : widget.host.world.wallet.owed[_to!.name];
    if (owed != null && owed < 0) {
      _kind = 'repayment';
      _amount.text = (-owed).toStringAsFixed(owed == owed.roundToDouble() ? 0 : 2);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _send() {
    final host = widget.host;
    final to = _to;
    final v = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (to == null || v == null || v <= 0) {
      showToast(context, 'Choose someone and an amount', icon: Icons.info_outline);
      return;
    }
    final err = giveMoney(host, to, v, kind: _kind, note: _note.text.trim(), byCard: _card, dueIn: _kind == 'loan' ? _dueIn : null, rate: _kind == 'loan' ? _rate : 0);
    if (err != null) {
      showToast(context, err, icon: Icons.error_outline);
      return;
    }
    // Generosity is noticed; a bribe less so.
    if (_kind == 'gift') applyBondChange(host.world, to, friendship: (v / math.max(1, cashOf(host.record) + v) * 20).round().clamp(1, 8), reason: 'You gave them ${money(host.record, v)}', turn: host.turns);
    if (host is AdventureController) host.refresh();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final r = host.record;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle('Send money', subtitle: 'You have ${money(r, cashOf(r))} in hand${host.world.wallet.bank > 0 ? ' and ${money(r, host.world.wallet.bank)} on the card' : ''}. The storyteller hears about it.'),
          SizedBox(
            height: 86,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in host.people.where((p) => p.alive))
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _to = p),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _to?.id == p.id ? AppColors.accent : Colors.transparent, width: 2)),
                        child: NpcPortrait(npc: p, size: 48),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(width: 60, child: Text(p.name.split(' ').first, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: _to?.id == p.id ? AppColors.text : AppColors.textMuted))),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, label) in const [('gift', 'Gift'), ('purchase', 'Payment'), ('loan', 'Loan'), ('repayment', 'Pay back'), ('bribe', 'Bribe')])
              ChoiceChip(avatar: Icon(moneyIcon(id), size: 16), label: Text(label), selected: _kind == id, onSelected: (_) => setState(() => _kind = id)),
          ])),
          const SizedBox(height: 12),
          TextField(controller: _amount, autofocus: widget.to != null, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: T.h2(), decoration: InputDecoration(labelText: 'Amount (${currencyOf(r).$1})')),
          const SizedBox(height: 10),
          TextField(controller: _note, style: T.body(), decoration: InputDecoration(labelText: switch (_kind) { 'purchase' => 'What for', 'loan' => 'What it\'s for (optional)', _ => 'A note (optional)' })),
          if (_kind == 'loan') ...[
            const SizedBox(height: 12),
            Text('Due', style: T.caption()),
            const SizedBox(height: 6),
            CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, label) in const [(null, 'Whenever'), (10, 'In 10 turns'), (25, 'In 25 turns'), (50, 'In 50 turns')])
                ChoiceChip(label: Text(label), selected: _dueIn == v, onSelected: (_) => setState(() => _dueIn = v)),
            ])),
            const SizedBox(height: 10),
            Text('Interest', style: T.caption()),
            const SizedBox(height: 6),
            CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final v in const [0.0, 2.0, 5.0, 10.0])
                ChoiceChip(label: Text(v == 0 ? 'None' : '${_pct(v)} / 10 turns'), selected: _rate == v, onSelected: (_) => setState(() => _rate = v)),
            ])),
          ],
          if (host.world.wallet.bank > 0) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.account_balance_wallet_outlined, size: 18), label: Text('Cash')),
                ButtonSegment(value: true, icon: Icon(Icons.credit_card, size: 18), label: Text('Card')),
              ],
              selected: {_card},
              onSelectionChanged: (v) => setState(() => _card = v.first),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(label: _to == null ? 'Choose someone' : 'Send to ${_to!.name.split(' ').first}', icon: Icons.send, onPressed: _send),
        ]),
      ),
    );
  }
}

/// Records money by hand: a correction, or something the story didn't track.
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.host});
  final StoryHost host;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  bool _in = true;
  String _category = 'loot';
  String _account = 'cash';
  final _amount = TextEditingController();
  final _who = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _who.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) {
      showToast(context, 'Enter an amount', icon: Icons.info_outline);
      return;
    }
    final err = recordManual(widget.host, _in ? v : -v, category: _category, who: _who.text.trim(), note: _note.text.trim(), account: _account);
    if (err != null) {
      showToast(context, err, icon: Icons.error_outline);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.host.record;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Record money', subtitle: 'For anything the story didn\'t count. It changes your balance and shows in the history.'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: true, label: Text('Money in')), ButtonSegment(value: false, label: Text('Money out'))],
            selected: {_in},
            onSelectionChanged: (v) => setState(() => _in = v.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: T.h2(), decoration: InputDecoration(labelText: 'Amount (${currencyOf(r).$1})')),
          const SizedBox(height: 12),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in _manualCategories)
              ChoiceChip(avatar: Icon(moneyIcon(c), size: 14), label: Text(_cap(c)), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
          ])),
          const SizedBox(height: 12),
          TextField(controller: _who, style: T.body(), decoration: const InputDecoration(labelText: 'Who (optional)')),
          const SizedBox(height: 10),
          TextField(controller: _note, style: T.body(), decoration: const InputDecoration(labelText: 'Note (optional)')),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'cash', icon: Icon(Icons.account_balance_wallet_outlined, size: 18), label: Text('Wallet')),
              ButtonSegment(value: 'bank', icon: Icon(Icons.credit_card, size: 18), label: Text('Card')),
            ],
            selected: {_account},
            onSelectionChanged: (v) => setState(() => _account = v.first),
          ),
          const SizedBox(height: 16),
          AppButton(label: 'Record', icon: Icons.check, onPressed: _save),
        ]),
      ),
    );
  }
}

/// A debt's terms: interest, due date, or writing it off.
class _TermsSheet extends StatefulWidget {
  const _TermsSheet({required this.host, required this.who});
  final StoryHost host;
  final String who;

  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  late final _w = widget.host.world.wallet;
  late double _rate = _w.rates[widget.who] ?? 0;
  late int? _dueIn = _w.due[widget.who] == null ? null : (_w.due[widget.who]! - widget.host.turns);

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final r = host.record;
    final owed = _w.owed[widget.who] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(owed > 0 ? '${widget.who} owes you ${money(r, owed)}' : 'You owe ${widget.who} ${money(r, -owed)}', subtitle: 'The storyteller keeps track of these terms.'),
        Text('Interest every 10 turns', style: T.caption()),
        const SizedBox(height: 6),
        CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in const [0.0, 2.0, 5.0, 10.0]) ChoiceChip(label: Text(v == 0 ? 'None' : _pct(v)), selected: _rate == v, onSelected: (_) => setState(() => _rate = v)),
        ])),
        const SizedBox(height: 12),
        Text('Due', style: T.caption()),
        const SizedBox(height: 6),
        CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, label) in const [(null, 'Whenever'), (10, 'In 10 turns'), (25, 'In 25 turns'), (50, 'In 50 turns')])
            ChoiceChip(label: Text(label), selected: _dueIn == v, onSelected: (_) => setState(() => _dueIn = v)),
        ])),
        const SizedBox(height: 16),
        AppButton(
          label: 'Save terms',
          onPressed: () {
            if (_rate > 0) {
              _w.rates[widget.who] = _rate;
            } else {
              _w.rates.remove(widget.who);
            }
            if (_dueIn != null) {
              _w.due[widget.who] = host.turns + _dueIn!;
            } else {
              _w.due.remove(widget.who);
            }
            _w.interestTurn ??= host.turns;
            host.note('New terms for the debt between the player and ${widget.who}: ${_rate > 0 ? '${_pct(_rate)} interest every 10 turns' : 'no interest'}${_dueIn != null ? ', due in $_dueIn turns' : ''}.');
            Navigator.pop(context, true);
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          label: owed > 0 ? 'Forgive the debt' : 'Write it off',
          kind: ButtonKind.secondary,
          onPressed: () async {
            final ok = await confirm(context, title: owed > 0 ? 'Forgive ${widget.who}?' : 'Write off this debt?', message: owed > 0 ? '${widget.who} won\'t owe you anything any more. They\'ll hear about it.' : 'It disappears from your books. ${widget.who} may not see it that way.', action: owed > 0 ? 'Forgive' : 'Write off', danger: owed < 0);
            if (!ok || !context.mounted) return;
            _w.owed.remove(widget.who);
            _w.due.remove(widget.who);
            _w.rates.remove(widget.who);
            host.note(owed > 0 ? 'The player forgave ${widget.who}\'s debt of ${money(r, owed)}.' : 'The player considers their debt of ${money(r, -owed)} to ${widget.who} gone, though ${widget.who} may disagree.');
            Navigator.pop(context, true);
          },
        ),
      ]),
    );
  }
}

/// One transaction in full, with a way to undo it.
class _MoveSheet extends StatelessWidget {
  const _MoveSheet({required this.host, required this.move, required this.onChanged});
  final StoryHost host;
  final MoneyMove move;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final r = host.record;
    final m = move;
    final w = host.world.wallet;
    // The balance (cash and card) right after this move.
    var after = totalOf(r);
    for (final x in w.ledger.reversed) {
      if (identical(x, m)) break;
      if (!Wallet.transfers.contains(x.category)) after -= x.amount;
    }
    final reversed = w.ledger.any((x) => x.category == 'reversal' && x.note.endsWith('#${m.id}'));
    final canUndo = !reversed && m.category != 'reversal' && m.category != 'adjustment';
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: T.small())),
            Expanded(child: Text(v, style: T.body())),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Icon(moneyIcon(m.category), size: 30, color: m.amount >= 0 ? AppColors.success : AppColors.danger)),
        const SizedBox(height: 8),
        Center(child: Text(money(r, m.amount, sign: true), style: T.number(32, color: m.amount >= 0 ? AppColors.success : AppColors.text))),
        Center(child: Text(_cap(m.category), style: T.small())),
        const SizedBox(height: 18),
        if (m.counterparty.isNotEmpty) row('With', m.counterparty),
        if (m.note.isNotEmpty) row('Note', m.note.replaceAll(RegExp(r' #\S+$'), '')),
        row('Paid with', m.account == 'bank' ? 'Card' : 'Cash'),
        row('When', 'Turn ${m.turn} · ${m.at.day}/${m.at.month}/${m.at.year} ${m.at.hour}:${m.at.minute.toString().padLeft(2, '0')}'),
        if (!Wallet.transfers.contains(m.category)) row('Balance after', money(r, after)),
        if (Wallet.credit.contains(m.category)) row('Counts as', 'Credit: money that has to come back, not earnings'),
        if (reversed) row('Status', 'Undone'),
        if (canUndo) ...[
          const SizedBox(height: 8),
          AppButton(
            label: 'Undo this',
            icon: Icons.undo,
            kind: ButtonKind.secondary,
            onPressed: () async {
              final ok = await confirm(context, title: 'Undo this transaction?', message: 'An opposite entry is added, so the history stays complete. The story isn\'t rewound.', action: 'Undo', danger: false);
              if (!ok || !context.mounted) return;
              final err = reverseMove(host, m);
              if (err != null) {
                showToast(context, err, icon: Icons.error_outline);
                return;
              }
              onChanged();
              Navigator.pop(context);
            },
          ),
        ],
      ]),
    );
  }
}

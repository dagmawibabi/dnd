import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/ai/gateway_client.dart';
import '../../../services/ai/model_catalog.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';

enum _Sort { recommended, cheapest, newest, context, name }

/// Browse text, image, video or voice models from both routers.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key, required this.current, this.kind = ModelKind.text, this.images = false, required this.title});
  final String current;
  final ModelKind kind;

  /// Legacy flag: same as kind: image.
  final bool images;
  final String title;

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String _q = '';
  String? _provider;
  AiRouter? _router;
  bool _free = false;
  bool _reasoning = false;
  bool _vision = false;
  _Sort _sort = _Sort.recommended;

  ModelKind get _kind => widget.images ? ModelKind.image : widget.kind;

  static const _favored = ['anthropic', 'openai', 'google', 'xai', 'spacexai', 'x-ai', 'mistral', 'mistralai', 'deepseek', 'meta', 'meta-llama', 'moonshotai', 'alibaba', 'qwen', 'bytedance', 'bfl', 'black-forest-labs'];
  static const _sortLabels = {_Sort.recommended: 'Recommended', _Sort.cheapest: 'Cheapest', _Sort.newest: 'Newest', _Sort.context: 'Context', _Sort.name: 'Name'};

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsController>();
    // Start on the router you have a key for.
    if (s.hasOpenRouterKey && !s.hasVercelKey) _router = AiRouter.openRouter;
    if (s.hasVercelKey && !s.hasOpenRouterKey) _router = AiRouter.vercel;
    if (AiRoute.isLmStudio(widget.current) || (s.hasLmStudio && !s.hasVercelKey && !s.hasOpenRouterKey)) _router = AiRouter.lmStudio;
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ModelCatalog>().ensureLoaded());
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController(text: widget.current);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model ID'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, style: T.body(), decoration: const InputDecoration(hintText: 'provider/model or or:provider/model')),
          const SizedBox(height: 8),
          Text('Prefix with "or:" to use OpenRouter, or "lm:" for an LM Studio model.', style: T.caption()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Use')),
        ],
      ),
    );
    if (id != null && id.isNotEmpty && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<ModelCatalog>();
    final settings = context.watch<SettingsController>();
    final all = cat.ofKind(_kind).where((m) => !m.isVariant).toList();
    final counts = {for (final r in AiRouter.values) r: all.where((m) => m.router == r).length};
    final providers = all.where((m) => _router == null || m.router == _router).map((m) => m.provider).toSet().toList()..sort();
    final list = all.where((m) {
      if (_router != null && m.router != _router) return false;
      if (_provider != null && m.provider != _provider) return false;
      if (_free && !m.isFree) return false;
      if (_reasoning && !m.reasoning) return false;
      if (_vision && !m.inputModalities.contains('image')) return false;
      final q = _q.toLowerCase();
      return q.isEmpty || m.id.toLowerCase().contains(q) || m.name.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.recommended:
        int rank(ModelInfo m) {
          final i = _favored.indexOf(m.provider);
          return i < 0 ? 99 : i;
        }
        list.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
      case _Sort.cheapest:
        list.sort((a, b) {
          final c = a.sortPrice.compareTo(b.sortPrice);
          return c != 0 ? c : (b.releaseDate ?? '').compareTo(a.releaseDate ?? '');
        });
      case _Sort.newest:
        list.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
      case _Sort.context:
        list.sort((a, b) => (b.contextWindow ?? 0).compareTo(a.contextWindow ?? 0));
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    final missingKey = _router != null && !switch (_router!) { AiRouter.openRouter => settings.hasOpenRouterKey, AiRouter.lmStudio => settings.hasLmStudio, AiRouter.vercel => settings.hasVercelKey };
    final showLocal = _kind == ModelKind.text && (settings.hasLmStudio || counts[AiRouter.lmStudio]! > 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(tooltip: 'Enter ID', icon: const Icon(Icons.edit_outlined), onPressed: _manual),
          IconButton(
            tooltip: 'Refresh',
            onPressed: cat.loading ? null : cat.refresh,
            icon: cat.loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ContentWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<AiRouter?>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: null, label: Text(showLocal ? 'All' : 'All · ${all.length}', maxLines: 1)),
                ButtonSegment(value: AiRouter.vercel, label: Text(showLocal ? 'Vercel' : 'Vercel · ${counts[AiRouter.vercel]}', maxLines: 1)),
                ButtonSegment(value: AiRouter.openRouter, label: Text(showLocal ? 'OpenRouter' : 'OpenRouter · ${counts[AiRouter.openRouter]}', maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
                if (showLocal) ButtonSegment(value: AiRouter.lmStudio, label: Text('Local · ${counts[AiRouter.lmStudio]}', maxLines: 1)),
              ],
              selected: {_router},
              onSelectionChanged: (v) => setState(() {
                _router = v.first;
                _provider = null;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              style: T.body(),
              decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search, size: 20)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FilterChip(avatar: const Icon(Icons.money_off, size: 15), label: const Text('Free'), selected: _free, onSelected: (v) => setState(() => _free = v)),
              const SizedBox(width: 6),
              _menuChip<_Sort>(Icons.sort, _sortLabels[_sort]!, _Sort.values.map((s) => (s, _sortLabels[s]!)).toList(), (s) => setState(() => _sort = s)),
              const SizedBox(width: 6),
              _menuChip<String>(Icons.business_outlined, _provider ?? 'All providers', [('', 'All providers'), ...providers.map((p) => (p, p))], (p) => setState(() => _provider = p.isEmpty ? null : p)),
              if (_kind == ModelKind.text) ...[
                const SizedBox(width: 6),
                FilterChip(label: const Text('Reasoning'), selected: _reasoning, onSelected: (v) => setState(() => _reasoning = v)),
                const SizedBox(width: 6),
                FilterChip(label: const Text('Vision'), selected: _vision, onSelected: (v) => setState(() => _vision = v)),
              ],
            ]),
          ),
          if (missingKey)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(_router == AiRouter.lmStudio ? 'Connect LM Studio in Settings → AI providers to use local models.' : 'Add your ${_router == AiRouter.openRouter ? 'OpenRouter' : 'Vercel AI Gateway'} key in Settings → AI providers to use these models.', style: T.small(color: AppColors.warning)),
            ),
          if (_router == AiRouter.lmStudio && cat.localError != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Text(cat.localError!, style: T.small(color: AppColors.danger))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(children: [
              Text('${list.length} models', style: T.caption()),
              const Spacer(),
              Text(switch (_kind) { ModelKind.video => 'Price per second of video', ModelKind.speech => 'Price per 1K characters', ModelKind.image => 'Price per image', ModelKind.text => 'Input / output per 1M tokens' }, style: T.caption()),
            ]),
          ),
          if (cat.error != null && all.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Couldn\'t load models: ${cat.error}', style: T.small(color: AppColors.danger))),
          if (!cat.loading && all.isEmpty && cat.error == null)
            Padding(padding: const EdgeInsets.all(20), child: Text('No ${_kind.name} models found. Pull to refresh, or enter a model ID.', style: T.small())),
          Expanded(
            child: cat.loading && all.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : RefreshIndicator(
                    onRefresh: cat.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _ModelTile(model: list[i], selected: list[i].id == widget.current, kind: _kind, onTap: () => Navigator.pop(context, list[i].id)),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _menuChip<V>(IconData icon, String label, List<(V, String)> items, ValueChanged<V> onSelect) {
    return PopupMenuButton<V>(
      onSelected: onSelect,
      itemBuilder: (_) => [for (final i in items) PopupMenuItem(value: i.$1, child: Text(i.$2))],
      child: Chip(avatar: Icon(icon, size: 15, color: AppColors.textMuted), label: Text(label)),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.selected, required this.onTap, required this.kind});
  final ModelInfo model;
  final bool selected;
  final ModelKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final or = m.router == AiRouter.openRouter;
    final local = m.router == AiRouter.lmStudio;
    return SelectCard(
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: T.h3()),
          const SizedBox(height: 2),
          Text(m.bareId, style: T.caption()),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Tag(local ? 'LM Studio' : (or ? 'OpenRouter' : 'Vercel'), color: local ? AppColors.success : (or ? const Color(0xFF60A5FA) : AppColors.textMuted)),
            if (m.isFree) const Tag('Free', icon: Icons.money_off, color: AppColors.success, filled: true) else Tag(kind == ModelKind.text && !m.canMakeImages ? '${m.priceLabel} / 1M' : m.priceLabel, icon: Icons.payments_outlined),
            if (m.contextWindow != null && kind == ModelKind.text) Tag('${m.contextLabel} context'),
            if (m.reasoning && kind == ModelKind.text) const Tag('Reasoning', color: AppColors.accent, filled: true),
            if (m.inputModalities.contains('image') && kind == ModelKind.text) const Tag('Vision'),
            if (m.multimodalImage) const Tag('Text + image'),
            if (m.durations.isNotEmpty) Tag('${m.durations.first}–${m.durations.last}s', icon: Icons.timer_outlined),
            if (m.resolutions.isNotEmpty) Tag(m.resolutions.take(3).join(' · ')),
            if (m.voices.isNotEmpty) Tag('${m.voices.length} voices', icon: Icons.record_voice_over_outlined),
            if (m.openWeights) const Tag('Open weights'),
            if (m.releaseDate != null) Tag(m.releaseDate!),
          ]),
          if (m.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small()),
          ],
        ]),
      ),
    );
  }
}

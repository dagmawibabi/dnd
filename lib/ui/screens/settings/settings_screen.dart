import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/ai/elevenlabs.dart';
import '../../../services/ai/gateway_client.dart';
import '../../../services/ai/model_catalog.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/db/database.dart';
import '../../../services/export.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/usage.dart';
import '../../../theme/ui.dart';
import '../achievements_screen.dart';
import '../adventure/adventure_extras.dart';
import 'model_picker.dart';
import '../story/story_tools.dart' show ReadingControls;

String _modelSub(ModelCatalog cat, String id) {
  final info = cat.byId(id);
  final router = AiRoute.isOpenRouter(id) ? 'OpenRouter' : 'Vercel';
  if (info == null) return '${AiRoute.bare(id)} · $router';
  final price = info.isFree ? 'Free' : (info.type == 'language' && !info.canMakeImages ? '${info.priceLabel} per 1M' : info.priceLabel);
  return '${info.name} · $router · $price';
}

Future<void> _pickModel(BuildContext context, {required ModelKind kind, required String title, required String current, required void Function(SettingsController s, String id) apply}) async {
  final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ModelPickerScreen(current: current, kind: kind, title: title)));
  if (id == null || !context.mounted) return;
  context.read<SettingsController>().update((s) => apply(s, id));
}

void _push(BuildContext context, String title, WidgetBuilder body) {
  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => Scaffold(appBar: AppBar(title: Text(title)), body: ContentWidth(child: body(ctx)))));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalog>();
    final usage = context.watch<UsageTracker>();
    final audio = context.read<AudioService>();
    Widget hub(IconData icon, String title, String subtitle, WidgetBuilder page, {bool on = true}) => ListRow(
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: on ? AppColors.accentSoft : AppColors.surface2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: on ? AppColors.accent : AppColors.textMuted),
          ),
          title: title,
          subtitle: subtitle,
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          onTap: () => _push(context, title, page),
        );
    final keys = [if (s.hasVercelKey) 'Vercel', if (s.hasOpenRouterKey) 'OpenRouter'];
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        const SectionLabel('AI'),
        RowGroup(children: [
          hub(Icons.key_outlined, 'AI providers', keys.isEmpty ? 'Not connected — everything runs offline' : 'Connected: ${keys.join(' + ')}', (_) => const _ProvidersPage(), on: keys.isNotEmpty),
          hub(Icons.auto_stories_outlined, 'Text & story', s.useAiText ? _modelSub(cat, s.textModel) : 'Offline storyteller', (_) => const _TextPage(), on: s.useAiText),
          hub(Icons.image_outlined, 'Images', s.useAiImages ? '${_modelSub(cat, s.imageModel)}${s.aiEffects ? ' · effects on' : ''}' : 'Drawn on device', (_) => const _ImagesPage(), on: s.useAiImages),
          hub(Icons.movie_outlined, 'Video', s.useAiVideo ? '${_modelSub(cat, s.videoModel)} · ${s.videoDuration}s ${s.videoResolution}' : 'Off', (_) => const _VideoPage(), on: s.useAiVideo),
          hub(Icons.record_voice_over_outlined, 'Voice', !s.ttsEnabled ? 'Off' : (s.useElevenLabs ? 'ElevenLabs · ${s.elevenVoiceName.isEmpty ? 'default voice' : s.elevenVoiceName}' : s.useAiVoice ? 'AI voices · ${_modelSub(cat, s.speechModel)}' : 'Device voice'), (_) => const _VoicePage(), on: s.ttsEnabled),
          hub(Icons.toll_outlined, 'Usage & limits', '${fmtCost(usage.total.cost)} all time · ${fmtCost(usage.today.cost)} today', (_) => const _UsagePage(), on: s.showUsage || s.showAnyItemCost),
        ]),
        const SectionLabel('Play'),
        RowGroup(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Home screen opens to', style: T.body()),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'dnd', label: Text('D&D'), icon: Icon(Icons.shield_outlined, size: 16)),
                  ButtonSegment(value: 'tales', label: Text('Text adventures', maxLines: 1), icon: Icon(Icons.menu_book_outlined, size: 16)),
                ],
                selected: {s.homeMode},
                onSelectionChanged: (v) => s.update((s) => s.homeMode = v.first),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Text adventure layout', style: T.body()),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Book'), icon: Icon(Icons.chrome_reader_mode_outlined, size: 16)),
                  ButtonSegment(value: true, label: Text('Terminal'), icon: Icon(Icons.terminal, size: 16)),
                ],
                selected: {s.taleTerminal},
                onSelectionChanged: (v) => s.update((s) => s.taleTerminal = v.first),
              ),
              const SizedBox(height: 6),
              Text('Used for new stories. Any story can switch layouts from its menu.', style: T.caption()),
            ]),
          ),
        ]),
        const SectionLabel('D&D adventures'),
        RowGroup(children: [
          _SwitchRow(title: 'Hardcore by default', subtitle: 'Permadeath, no rewind, riskier rests', value: s.defaultHardcore, onChanged: (v) => s.update((s) => s.defaultHardcore = v)),
          _SwitchRow(title: 'Show DCs', subtitle: 'Reveal difficulty numbers on checks', value: s.defaultShowDcs, onChanged: (v) => s.update((s) => s.defaultShowDcs = v)),
        ]),
        const SectionLabel('Sound'),
        RowGroup(children: [
          _SwitchRow(title: 'Sound effects', value: s.sfxEnabled, onChanged: (v) => s.update((s) => s.sfxEnabled = v), preview: () => audio.play('success')),
          _SliderRow(title: 'Effects volume', value: s.sfxVolume, min: 0, max: 1, label: '${(s.sfxVolume * 100).round()}%', onChanged: (v) => s.update((s) => s.sfxVolume = v)),
          _SwitchRow(title: 'Music', subtitle: 'Generated on device, follows the scene', value: s.musicEnabled, onChanged: (v) => s.update((s) => s.musicEnabled = v)),
          _SliderRow(title: 'Music volume', value: s.musicVolume, min: 0, max: 1, label: '${(s.musicVolume * 100).round()}%', onChanged: (v) => s.update((s) => s.musicVolume = v)),
          _SwitchRow(title: 'Ambient sound', subtitle: 'Rain, wind, taverns and caves that follow the weather and the place', value: s.ambienceEnabled, onChanged: (v) => s.update((s) => s.ambienceEnabled = v), preview: () {
            audio.ambience('rain');
            Future.delayed(const Duration(seconds: 4), audio.stopAmbience);
          }),
          _SliderRow(title: 'Ambience volume', value: s.ambienceVolume, min: 0, max: 1, label: '${(s.ambienceVolume * 100).round()}%', onChanged: (v) => s.update((s) => s.ambienceVolume = v)),
        ]),
        const SectionLabel('Reading'),
        RowGroup(children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 10), child: ReadingControls(preview: false)),
          _SwitchRow(title: 'Typewriter effect', value: s.typewriter, onChanged: (v) => s.update((s) => s.typewriter = v)),
          _SliderRow(title: 'Text speed', value: s.typeSpeed, min: 0.5, max: 4, label: '${s.typeSpeed.toStringAsFixed(1)}×', onChanged: (v) => s.update((s) => s.typeSpeed = v)),
          _SwitchRow(title: 'Haptics', value: s.haptics, onChanged: (v) => s.update((s) => s.haptics = v)),
        ]),
        const SectionLabel('Accessibility'),
        RowGroup(children: [
          _SliderRow(title: 'Text size', value: s.textScale, min: 0.85, max: 1.5, label: '${(s.textScale * 100).round()}%', onChanged: (v) => s.update((s) => s.textScale = (v * 20).round() / 20)),
          _SwitchRow(title: 'High contrast', subtitle: 'Brighter secondary text and borders', value: s.highContrast, onChanged: (v) => s.update((s) => s.highContrast = v)),
          _SwitchRow(title: 'Reduce motion', subtitle: 'Fewer animations, no dice tumbling, videos paused', value: s.reducedMotion, onChanged: (v) => s.update((s) => s.reducedMotion = v)),
        ]),
        const SectionLabel('Progress'),
        RowGroup(children: [
          ListRow(
            leading: const Icon(Icons.emoji_events_outlined, size: 20),
            title: 'Achievements & stats',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AchievementsScreen())),
          ),
        ]),
        const SectionLabel('Data'),
        RowGroup(children: [
          ListRow(leading: const Icon(Icons.upload_file_outlined, size: 20), title: 'Export backup', subtitle: 'Heroes, adventures, stories, campaigns and achievements', onTap: () => exportBackup(context)),
          ListRow(leading: const Icon(Icons.download_outlined, size: 20), title: 'Import backup', subtitle: 'Merge a DnD backup file into this device', onTap: () => importBackup(context)),
          ListRow(title: 'Show onboarding again', onTap: () => s.update((s) => s.onboarded = false)),
          ListRow(
            title: 'Erase all data',
            danger: true,
            onTap: () async {
              if (await confirm(context, title: 'Erase all data?', message: 'All characters, adventures and settings will be permanently deleted.', action: 'Erase')) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (AppDatabase.isOpen) await AppDatabase.instance.clearAll();
                if (context.mounted) showToast(context, 'Data erased. Restart the app.');
              }
            },
          ),
        ]),
        const SizedBox(height: 24),
        const SectionLabel('About'),
        RowGroup(children: [
          ListRow(
            leading: ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset('assets/icon/icon.png', width: 28, height: 28, errorBuilder: (_, _, _) => const Icon(Icons.casino_outlined))),
            title: 'DnD',
            subtitle: 'Version 1.0 · solo D&D and text adventures',
          ),
          ListRow(
            leading: const Icon(Icons.description_outlined, size: 20),
            title: 'Open-source licenses',
            onTap: () => showLicensePage(context: context, applicationName: 'DnD', applicationVersion: '1.0', applicationLegalese: 'Rules content: 5e SRD (CC-BY-4.0). Model data: Vercel AI Gateway, OpenRouter, models.dev. Fonts: Inter and JetBrains Mono (OFL).'),
          ),
        ]),
        const SizedBox(height: 16),
        Center(child: Text('Rules content: 5e SRD (CC-BY-4.0)\nModel data: Vercel AI Gateway, OpenRouter, models.dev', textAlign: TextAlign.center, style: T.caption())),
      ],
    );
    final body = ContentWidth(child: list);
    if (embedded) return SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const ContentWidth(child: PageHeader(title: 'Settings')), Expanded(child: body)]));
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: body);
  }
}

// ------------------------------------------------------------- providers

class _ProvidersPage extends StatelessWidget {
  const _ProvidersPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    String masked(String k) => k.length > 8 ? '••••${k.substring(k.length - 4)}' : '••••';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      Text('Use either router or both. Every model setting remembers which router it comes from, so you can mix them, for example a free OpenRouter story model with Vercel images.', style: T.small()),
      const SectionLabel('Routers'),
      RowGroup(children: [
        ListRow(
          leading: const Icon(Icons.change_history, size: 20),
          title: 'Vercel AI Gateway',
          subtitle: s.hasVercelKey ? 'Connected · ${masked(s.apiKey)}' : 'Not set · vercel.com → AI Gateway → API Keys',
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          onTap: () => showAppSheet(context, builder: (_) => const _KeySheet(router: AiRouter.vercel)),
        ),
        ListRow(
          leading: const Icon(Icons.hub_outlined, size: 20),
          title: 'OpenRouter',
          subtitle: s.hasOpenRouterKey ? 'Connected · ${masked(s.openRouterKey)}' : 'Not set · openrouter.ai → Keys (many free models)',
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          onTap: () => showAppSheet(context, builder: (_) => const _KeySheet(router: AiRouter.openRouter)),
        ),
      ]),
      if (s.hasApiKey) ...[
        const SectionLabel('Models in use'),
        RowGroup(children: [
          for (final (label, id) in [('Story', s.textModel), ('Fast', s.fastModel), ('Images', s.imageModel), ('Video', s.videoModel), ('Voice', s.speechModel)])
            ListRow(
              title: label,
              subtitle: AiRoute.bare(id),
              trailing: s.canUse(id) ? Tag(AiRoute.routerName(id).split(' ').first, color: AppColors.success) : const Tag('No key', color: AppColors.warning),
            ),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('A model whose router has no key won\'t run; pick another in its section.', style: T.caption())),
      ],
      const SectionLabel('Model list'),
      Consumer<ModelCatalog>(
        builder: (context, cat, _) => RowGroup(children: [
          ListRow(
            leading: cat.loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 20),
            title: 'Refresh models and prices',
            subtitle: '${cat.models.length} models${cat.fetchedAt == null ? '' : ' · updated ${cat.fetchedAt!.toLocal().toString().substring(0, 16)}'}${cat.error == null ? '' : ' · ${cat.error}'}',
            onTap: cat.loading ? null : cat.refresh,
          ),
        ]),
      ),
    ]);
  }
}

class _KeySheet extends StatefulWidget {
  const _KeySheet({required this.router});
  final AiRouter router;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late final _ctrl = TextEditingController(text: _or ? context.read<SettingsController>().openRouterKey : context.read<SettingsController>().apiKey);
  bool _obscure = true;
  bool _testing = false;
  bool? _ok;

  bool get _or => widget.router == AiRouter.openRouter;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _ok = null;
    });
    final key = _ctrl.text.trim();
    final s = context.read<SettingsController>();
    final c = GatewayClient(apiKey: _or ? '' : key, openRouterKey: _or ? key : null, captureTarget: false);
    final ok = await c.verifyKey(_or ? '${AiRoute.prefix}openai/gpt-4o-mini' : (AiRoute.isOpenRouter(s.fastModel) ? 'openai/gpt-5-mini' : s.fastModel));
    c.close();
    if (mounted) {
      setState(() {
        _testing = false;
        _ok = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsController>();
    final has = _or ? s.hasOpenRouterKey : s.hasVercelKey;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(_or ? 'OpenRouter key' : 'AI Gateway key', subtitle: _or ? 'Create a key at openrouter.ai → Keys. Stored only on this device.' : 'Create a key in Vercel → AI Gateway → API Keys. Stored only on this device.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              autofocus: true,
              style: T.body(),
              onChanged: (_) => setState(() => _ok = null),
              decoration: InputDecoration(
                hintText: _or ? 'sk-or-…' : 'vck_…',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_ok != null) Icon(_ok! ? Icons.check_circle : Icons.error_outline, size: 20, color: _ok! ? AppColors.success : AppColors.danger),
                  IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _obscure = !_obscure)),
                ]),
              ),
            ),
            if (_ok == false) Padding(padding: const EdgeInsets.only(top: 8), child: Text('The key was rejected.', style: T.small(color: AppColors.danger))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: AppButton(label: 'Test', kind: ButtonKind.secondary, busy: _testing, onPressed: _ctrl.text.trim().isEmpty ? null : _test)),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Save',
                  onPressed: () {
                    final cat = context.read<ModelCatalog>();
                    s.update((s) {
                      if (_or) {
                        s.openRouterKey = _ctrl.text.trim();
                        if (!s.hasVercelKey && s.hasOpenRouterKey) adoptOpenRouterModels(s, cat);
                      } else {
                        s.apiKey = _ctrl.text.trim();
                      }
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
            ]),
            if (has) ...[
              const SizedBox(height: 8),
              AppButton(
                label: 'Remove key',
                kind: ButtonKind.ghost,
                onPressed: () {
                  s.update((s) => _or ? s.openRouterKey = '' : s.apiKey = '');
                  Navigator.pop(context);
                },
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ text

class _TextPage extends StatelessWidget {
  const _TextPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalog>();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      if (!s.hasApiKey) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Add a key in AI providers to use AI writing. Until then the offline storyteller runs everything.', style: T.small(color: AppColors.warning))),
      const SectionLabel('Models'),
      RowGroup(children: [
        _SwitchRow(title: 'AI storyteller', subtitle: 'The AI runs D&D adventures and AI text adventures', value: s.aiText, onChanged: s.hasApiKey ? (v) => s.update((s) => s.aiText = v) : null),
        ListRow(leading: const Icon(Icons.auto_stories_outlined, size: 20), title: 'Story model', subtitle: _modelSub(cat, s.textModel), onTap: () => _pickModel(context, kind: ModelKind.text, title: 'Story model', current: s.textModel, apply: (s, id) => s.textModel = id)),
        ListRow(leading: const Icon(Icons.bolt_outlined, size: 20), title: 'Fast model', subtitle: 'Chats, recaps, ideas, summaries · ${_modelSub(cat, s.fastModel)}', onTap: () => _pickModel(context, kind: ModelKind.text, title: 'Fast model', current: s.fastModel, apply: (s, id) => s.fastModel = id)),
      ]),
      const SectionLabel('Writing'),
      RowGroup(children: [
        _SliderRow(title: 'Creativity', value: s.temperature, min: 0, max: 1.5, label: s.temperature.toStringAsFixed(2), onChanged: (v) => s.update((s) => s.temperature = v)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(child: Text('Narration length', style: T.body())),
            SegmentedButton<Verbosity>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Verbosity.brief, label: Text('Short')),
                ButtonSegment(value: Verbosity.balanced, label: Text('Medium')),
                ButtonSegment(value: Verbosity.lavish, label: Text('Long')),
              ],
              selected: {s.verbosity},
              onSelectionChanged: (v) => s.update((s) => s.verbosity = v.first),
            ),
          ]),
        ),
        _SwitchRow(title: 'Stream responses', subtitle: 'Words appear as they are written', value: s.streaming, onChanged: (v) => s.update((s) => s.streaming = v)),
        _SwitchRow(title: 'Mature themes', subtitle: 'Darker stories and more passionate romance; never explicit or gratuitous', value: s.matureContent, onChanged: (v) => s.update((s) => s.matureContent = v)),
      ]),
      const SectionLabel('What the AI writes'),
      RowGroup(children: [
        _SwitchRow(title: 'Character chats', subtitle: 'Talk to anyone; relationships change with what you say', value: s.aiNpcChat, onChanged: (v) => s.update((s) => s.aiNpcChat = v)),
        _SwitchRow(title: '"Previously on…" recaps', subtitle: 'When you return to a story after a few hours', value: s.aiRecaps, onChanged: (v) => s.update((s) => s.aiRecaps = v)),
        _SwitchRow(title: 'Story summaries', subtitle: 'Compress long stories so the AI remembers them', value: s.aiSummaries, onChanged: (v) => s.update((s) => s.aiSummaries = v)),
        _SwitchRow(title: 'Character creation', subtitle: 'AI-built heroes and backstories', value: s.aiCreator, onChanged: (v) => s.update((s) => s.aiCreator = v)),
        _SwitchRow(title: 'Adventure ideas', subtitle: 'Titles and premises for new stories', value: s.aiPremises, onChanged: (v) => s.update((s) => s.aiPremises = v)),
      ]),
      Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Anything turned off falls back to the on-device storyteller.', style: T.caption())),
    ]);
  }
}

// ---------------------------------------------------------------- images

const _momentLabels = {
  'crit': 'Critical hits',
  'spell': 'Big spells',
  'boss': 'Boss fights',
  'levelup': 'Level ups',
  'victory': 'Victories & endings',
  'defeat': 'Defeats',
  'romance': 'Romantic moments',
  'moment': 'Dramatic story beats',
};

class _ImagesPage extends StatelessWidget {
  const _ImagesPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalog>();
    final on = s.imageMode == ImageMode.ai;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      const SectionLabel('AI images'),
      RowGroup(children: [
        _SwitchRow(title: 'Generate AI images', subtitle: 'Off: everything is painted on device for free', value: on, onChanged: s.hasApiKey ? (v) => s.update((s) => s.imageMode = v ? ImageMode.ai : ImageMode.procedural) : null),
        ListRow(leading: const Icon(Icons.palette_outlined, size: 20), title: 'Image model', subtitle: _modelSub(cat, s.imageModel), onTap: () => _pickModel(context, kind: ModelKind.image, title: 'Image model', current: s.imageModel, apply: (s, id) => s.imageModel = id)),
        _SwitchRow(title: 'Generate automatically', subtitle: 'Off: only when you tap a paint button', value: s.aiAutoImages, onChanged: (v) => s.update((s) => s.aiAutoImages = v)),
      ]),
      const SectionLabel('What to paint'),
      RowGroup(children: [
        _SwitchRow(title: 'Hero portraits', subtitle: 'Your hero in creation and adventures', value: s.aiPortraits, onChanged: on ? (v) => s.update((s) => s.aiPortraits = v) : null),
        _SwitchRow(title: 'Character portraits', subtitle: 'People you meet, in both modes', value: s.aiNpcPortraits, onChanged: on ? (v) => s.update((s) => s.aiNpcPortraits = v) : null),
        _SwitchRow(title: 'Companion portraits', subtitle: 'When someone joins your party', value: s.aiCompanionPortraits, onChanged: on ? (v) => s.update((s) => s.aiCompanionPortraits = v) : null),
        _SwitchRow(title: 'Scene art', subtitle: 'When the story moves somewhere new', value: s.aiScenes, onChanged: on ? (v) => s.update((s) => s.aiScenes = v) : null),
        _SwitchRow(title: 'Map art', subtitle: 'An illustrated map of the region', value: s.aiMaps, onChanged: on ? (v) => s.update((s) => s.aiMaps = v) : null),
      ]),
      const SectionLabel('Special effects'),
      RowGroup(children: [
        _SwitchRow(title: 'Special-effect images', subtitle: 'Cinematic art for big moments, shown in the story', value: s.aiEffects, onChanged: on ? (v) => s.update((s) => s.aiEffects = v) : null),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _momentLabels.entries)
              FilterChip(
                label: Text(e.value),
                selected: s.effectMoments.contains(e.key),
                onSelected: s.aiEffects || s.videoEffects
                    ? (v) => s.update((s) => v ? s.effectMoments.add(e.key) : s.effectMoments.remove(e.key))
                    : null,
              ),
          ]),
        ),
      ]),
      Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Effects are limited to one every couple of turns. Every image lands in the story\'s Gallery, where you can save it to your phone.', style: T.caption())),
    ]);
  }
}

// ----------------------------------------------------------------- video

class _VideoPage extends StatelessWidget {
  const _VideoPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalog>();
    final info = cat.byId(s.videoModel);
    final perClip = info?.videoPrice == null ? null : info!.videoPrice! * s.videoDuration;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      Padding(padding: const EdgeInsets.only(top: 8), child: Text('Short AI clips instead of still images. Videos take a minute or two and cost more than images; cheap models at 480p cost a few cents per clip.', style: T.small())),
      const SectionLabel('Video'),
      RowGroup(children: [
        _SwitchRow(title: 'Generate videos', value: s.videoEnabled, onChanged: s.hasApiKey ? (v) => s.update((s) => s.videoEnabled = v) : null),
        ListRow(leading: const Icon(Icons.movie_creation_outlined, size: 20), title: 'Video model', subtitle: _modelSub(cat, s.videoModel), onTap: () => _pickModel(context, kind: ModelKind.video, title: 'Video model', current: s.videoModel, apply: (s, id) => s.videoModel = id)),
        _SwitchRow(title: 'Film new scenes', subtitle: 'A clip instead of scene art when the story moves', value: s.videoScenes, onChanged: s.videoEnabled ? (v) => s.update((s) => s.videoScenes = v) : null),
        _SwitchRow(title: 'Film special moments', subtitle: 'Clips for the moments chosen under Images', value: s.videoEffects, onChanged: s.videoEnabled ? (v) => s.update((s) => s.videoEffects = v) : null),
      ]),
      const SectionLabel('Clip'),
      RowGroup(children: [
        _SliderRow(title: 'Length', value: s.videoDuration.toDouble(), min: 2, max: 10, label: '${s.videoDuration}s', onChanged: (v) => s.update((s) => s.videoDuration = v.round())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(child: Text('Resolution', style: T.body())),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: '480p', label: Text('480p')), ButtonSegment(value: '720p', label: Text('720p')), ButtonSegment(value: '1080p', label: Text('1080p'))],
              selected: {s.videoResolution},
              onSelectionChanged: (v) => s.update((s) => s.videoResolution = v.first),
            ),
          ]),
        ),
        _SwitchRow(title: 'Generate sound', subtitle: 'Some models add audio; usually costs more', value: s.videoAudio, onChanged: (v) => s.update((s) => s.videoAudio = v)),
      ]),
      if (perClip != null) Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 0), child: Text('About ${fmtCost(perClip)} per ${s.videoDuration}s clip at the cheapest resolution.', style: T.caption())),
      if (info != null && info.durations.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: Text('${info.name} supports ${info.durations.join(', ')} second clips; the closest is used.', style: T.caption())),
    ]);
  }
}

// ----------------------------------------------------------------- voice

class _VoicePage extends StatelessWidget {
  const _VoicePage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final cat = context.watch<ModelCatalog>();
    final narrator = context.read<Narrator>();
    final voices = cat.voicesFor(s.speechModel);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      const SectionLabel('Read aloud'),
      RowGroup(children: [
        _SwitchRow(
          title: 'Read the story aloud',
          subtitle: 'Narration and dialogue as they appear. Long-press any passage to hear it.',
          value: s.ttsEnabled,
          onChanged: (v) {
            s.update((s) => s.ttsEnabled = v);
            if (!v) narrator.stop();
          },
          preview: () => narrator.speakNow('The torches gutter as the iron door groans open. Something stirs in the dark.'),
        ),
        _SwitchRow(title: 'Distinct character voices', subtitle: 'Everyone sounds different from the narrator', value: s.npcVoices, onChanged: (v) => s.update((s) => s.npcVoices = v)),
        _SwitchRow(title: 'Speak chat replies', subtitle: 'Characters answer out loud in conversations', value: s.speakChatReplies, onChanged: (v) => s.update((s) => s.speakChatReplies = v)),
      ]),
      const SectionLabel('Voice engine'),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'device', label: Text('Device'), icon: Icon(Icons.phone_android, size: 16)),
            ButtonSegment(value: 'ai', label: Text('AI router'), icon: Icon(Icons.graphic_eq, size: 16)),
            ButtonSegment(value: 'elevenlabs', label: Text('ElevenLabs', maxLines: 1)),
          ],
          selected: {s.voiceEngine},
          onSelectionChanged: (v) => s.update((s) => s.voiceEngine = v.first),
        ),
      ),
      if (s.voiceEngine == 'elevenlabs') const _ElevenLabsSection() else if (s.voiceEngine == 'ai') ...[
        RowGroup(children: [
          ListRow(leading: const Icon(Icons.graphic_eq, size: 20), title: 'Voice model', subtitle: _modelSub(cat, s.speechModel), onTap: () => _pickModel(context, kind: ModelKind.speech, title: 'Voice model', current: s.speechModel, apply: (s, id) => s
            ..speechModel = id
            ..aiVoice = '')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Narrator voice', style: T.body()),
              const SizedBox(height: 8),
              if (voices.isEmpty) Text('This model doesn\'t list its voices; its default is used.', style: T.caption()),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final v in voices)
                  ChoiceChip(
                    label: Text(v),
                    selected: (s.aiVoice.isEmpty ? voices.first : s.aiVoice) == v,
                    onSelected: (_) {
                      s.update((s) => s.aiVoice = v);
                      narrator.speakNow('Welcome back, adventurer.');
                    },
                  ),
              ]),
            ]),
          ),
          ListRow(
            leading: const Icon(Icons.theater_comedy_outlined, size: 20),
            title: 'Narrator delivery',
            subtitle: s.voiceStyle,
            onTap: () async {
              final ctrl = TextEditingController(text: s.voiceStyle);
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('How should the narrator sound?'),
                  content: TextField(controller: ctrl, autofocus: true, maxLines: 3, style: T.body()),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save'))],
                ),
              );
              if (v != null && v.isNotEmpty) s.update((s) => s.voiceStyle = v);
            },
          ),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('AI voices are cached on the device, so replaying a line is free. Pick a voice for any character from their profile in People. If an AI voice fails, the device voice takes over.', style: T.caption())),
        if (narrator.lastError != null) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Last AI voice error: ${narrator.lastError}', style: T.caption(color: AppColors.warning))),
      ] else
        RowGroup(children: [
          _SliderRow(title: 'Speed', value: s.ttsRate, min: 0.2, max: 1.0, label: '${(s.ttsRate * 2).toStringAsFixed(1)}×', onChanged: (v) => s.update((s) => s.ttsRate = v)),
          _SliderRow(title: 'Pitch', value: s.ttsPitch, min: 0.5, max: 2.0, label: s.ttsPitch.toStringAsFixed(1), onChanged: (v) => s.update((s) => s.ttsPitch = v)),
          ListRow(
            leading: const Icon(Icons.record_voice_over_outlined, size: 20),
            title: 'Device voice',
            subtitle: s.ttsVoice.isEmpty ? 'System default' : s.ttsVoice,
            onTap: () => showAppSheet(context, builder: (_) => const _DeviceVoicePicker()),
          ),
        ]),
    ]);
  }
}

class _DeviceVoicePicker extends StatefulWidget {
  const _DeviceVoicePicker();

  @override
  State<_DeviceVoicePicker> createState() => _DeviceVoicePickerState();
}

class _DeviceVoicePickerState extends State<_DeviceVoicePicker> {
  late final Future<List<Map<String, String>>> _voices = context.read<Narrator>().loadVoices();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        const SheetTitle('Device voice', subtitle: 'Voices installed on this device'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search voices or languages', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _filter = v.toLowerCase())),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, String>>>(
            future: _voices,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              final list = snap.data!.where((v) => _filter.isEmpty || '${v['name']} ${v['locale']}'.toLowerCase().contains(_filter)).toList();
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                RowGroup(children: [
                  ListRow(
                    title: 'System default',
                    trailing: s.ttsVoice.isEmpty ? const Icon(Icons.check, size: 18, color: AppColors.accent) : null,
                    onTap: () => s.update((s) => s.ttsVoice = ''),
                  ),
                  for (final v in list.take(200))
                    ListRow(
                      title: v['name'] ?? '',
                      subtitle: v['locale'],
                      trailing: s.ttsVoice == v['name'] ? const Icon(Icons.check, size: 18, color: AppColors.accent) : null,
                      onTap: () {
                        s.update((s) => s.ttsVoice = v['name'] ?? '');
                        context.read<Narrator>().speakNow('Hello, adventurer.');
                      },
                    ),
                ]),
                if (list.isEmpty) const EmptyState(icon: Icons.voice_over_off_outlined, title: 'No voices found', message: 'Install voices in your device\'s text-to-speech settings.'),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------------------- usage

class _UsagePage extends StatelessWidget {
  const _UsagePage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final usage = context.watch<UsageTracker>();
    String limit(num v, {bool money = false}) => v == 0 ? 'No limit' : (money ? fmtCost(v.toDouble()) : fmtTokens(v));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      const SectionLabel('Show costs'),
      RowGroup(children: [
        _SwitchRow(title: 'Cost chip', subtitle: 'Live tokens and spend in every story\'s top bar', value: s.showUsage, onChanged: (v) => s.update((s) => s.showUsage = v)),
        _SwitchRow(title: 'Per message', subtitle: 'Tokens and price under each AI passage and chat reply', value: s.costPerMessage, onChanged: (v) => s.update((s) => s.costPerMessage = v)),
        _SwitchRow(title: 'Per image', subtitle: 'Price on scene art and special effects', value: s.costPerImage, onChanged: (v) => s.update((s) => s.costPerImage = v)),
        _SwitchRow(title: 'Per video', subtitle: 'Price on generated clips', value: s.costPerVideo, onChanged: (v) => s.update((s) => s.costPerVideo = v)),
      ]),
      const SectionLabel('Limits'),
      RowGroup(children: [
        ListRow(
          leading: const Icon(Icons.tune, size: 20),
          title: 'Token, cost and media limits',
          subtitle: 'Daily ${limit(s.dailyCostLimit, money: true)} · per story ${limit(s.adventureCostLimit, money: true)} · images ${s.adventureImageLimit == 0 ? '∞' : s.adventureImageLimit} · videos ${s.adventureVideoLimit == 0 ? '∞' : s.adventureVideoLimit}',
          onTap: () => showAppSheet(context, builder: (_) => const _UsageLimitsSheet()),
        ),
      ]),
      const SectionLabel('Spending'),
      RowGroup(children: [
        ListRow(
          leading: const Icon(Icons.insights_outlined, size: 20),
          title: 'Usage & insights',
          subtitle: '${fmtCost(usage.total.cost)} all time · ${fmtCost(usage.today.cost)} today · ${usage.total.detail}',
          onTap: () => showUsageSheet(context),
        ),
      ]),
      if (usage.byCategory.isNotEmpty) ...[
        const SectionLabel('By feature'),
        RowGroup(children: [
          for (final e in (usage.byCategory.entries.toList()..sort((a, b) => b.value.cost.compareTo(a.value.cost))))
            ListRow(leading: Icon(usageCategoryIcon(e.key), size: 18), title: usageCategoryLabel(e.key), subtitle: e.value.detail, trailing: Text(fmtCost(e.value.cost), style: T.small())),
        ]),
      ],
      if (usage.byModel.isNotEmpty) ...[
        const SectionLabel('By model'),
        RowGroup(children: [
          for (final e in (usage.byModel.entries.toList()..sort((a, b) => b.value.cost.compareTo(a.value.cost))).take(8))
            ListRow(title: AiRoute.bare(e.key), subtitle: '${AiRoute.routerName(e.key)} · ${e.value.detail}', trailing: Text(fmtCost(e.value.cost), style: T.small())),
        ]),
      ],
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('BY STORY', style: T.overline())),
      const AdventureUsageList(limit: 8),
    ]);
  }
}

class _UsageLimitsSheet extends StatefulWidget {
  const _UsageLimitsSheet();
  @override
  State<_UsageLimitsSheet> createState() => _UsageLimitsSheetState();
}

class _UsageLimitsSheetState extends State<_UsageLimitsSheet> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _fields;
  static const _labels = ['Daily token limit', 'Daily cost limit (USD)', 'Token limit per story', 'Cost limit per story (USD)', 'Max AI images per story', 'Max AI videos per story'];
  static const _money = [false, true, false, true, false, false];

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsController>();
    _fields = [s.dailyTokenLimit, s.dailyCostLimit, s.adventureTokenLimit, s.adventureCostLimit, s.adventureImageLimit, s.adventureVideoLimit].map((v) => TextEditingController(text: '$v')).toList();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Usage limits'),
          Text('Use 0 for unlimited. Daily limits reset at local midnight. Story limits apply separately to each D&D adventure and text adventure.', style: T.small()),
          const SizedBox(height: 12),
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                controller: _fields[i],
                decoration: InputDecoration(labelText: _labels[i]),
                keyboardType: TextInputType.numberWithOptions(decimal: _money[i]),
                validator: (value) {
                  final n = num.tryParse(value?.trim() ?? '');
                  if (n == null || !n.isFinite || n < 0 || (!_money[i] && n != n.roundToDouble())) return 'Enter a non-negative ${_money[i] ? 'amount' : 'whole number'}.';
                  return null;
                },
              ),
            ),
          Text('Requests reserve estimated input and maximum output before starting, including simultaneous image and video requests. Costs depend on model pricing; your provider bill may differ. Unknown-price models are blocked while a cost limit is on.', style: T.caption()),
          const SizedBox(height: 16),
          AppButton(
            label: 'Save limits',
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              num v(int i) => num.parse(_fields[i].text.trim());
              context.read<SettingsController>().update((s) {
                s.dailyTokenLimit = v(0).toInt();
                s.dailyCostLimit = v(1).toDouble();
                s.adventureTokenLimit = v(2).toInt();
                s.adventureCostLimit = v(3).toDouble();
                s.adventureImageLimit = v(4).toInt();
                s.adventureVideoLimit = v(5).toInt();
              });
              Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------- rows

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, this.subtitle, required this.value, required this.onChanged, this.preview});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? preview;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: title,
      subtitle: subtitle,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (preview != null) IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: preview),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.title, required this.value, required this.min, required this.max, required this.label, required this.onChanged});
  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: [
        SizedBox(width: 120, child: Text(title, style: T.body())),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 44, child: Text(label, textAlign: TextAlign.right, style: T.caption(color: AppColors.textMuted))),
      ]),
    );
  }
}

// ------------------------------------------------------------- elevenlabs

class _ElevenLabsSection extends StatefulWidget {
  const _ElevenLabsSection();

  @override
  State<_ElevenLabsSection> createState() => _ElevenLabsSectionState();
}

class _ElevenLabsSectionState extends State<_ElevenLabsSection> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<Narrator>().loadElevenVoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final narrator = context.watch<Narrator>();
    final masked = s.elevenLabsKey.length > 8 ? '••••${s.elevenLabsKey.substring(s.elevenLabsKey.length - 4)}' : '••••';
    final voices = narrator.elevenVoices.where((v) => _q.isEmpty || '${v.name} ${v.traits} ${v.description}'.toLowerCase().contains(_q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RowGroup(children: [
        ListRow(
          leading: const Icon(Icons.key_outlined, size: 20),
          title: 'ElevenLabs key',
          subtitle: s.elevenLabsKey.isEmpty ? 'Not set · elevenlabs.io → Developers → API keys' : 'Connected · $masked',
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          onTap: () => showAppSheet(context, builder: (_) => const _ElevenKeySheet()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Model', style: T.body()),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final (id, name, _) in elevenModels) ButtonSegment(value: id, label: Text(name, maxLines: 1))],
              selected: {s.elevenModel},
              onSelectionChanged: (v) => s.update((s) => s.elevenModel = v.first),
            ),
            const SizedBox(height: 6),
            Text('${elevenModels.firstWhere((m) => m.$1 == s.elevenModel, orElse: () => elevenModels.first).$3} · about ${fmtCost(elevenPricePerChar(s.elevenModel) * 1000)} per 1K characters (estimate; your plan sets the real price).', style: T.caption()),
          ]),
        ),
      ]),
      if (s.elevenLabsKey.isNotEmpty) ...[
        SectionLabel('Narrator voice', trailing: GestureDetector(onTap: () => narrator.loadElevenVoices(force: true), child: Text('Refresh', style: T.caption(color: AppColors.textMuted)))),
        TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search voices, accents, styles', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
        const SizedBox(height: 8),
        if (narrator.elevenLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        if (narrator.elevenError != null) Text("Couldn't load voices: ${narrator.elevenError}", style: T.small(color: AppColors.danger)),
        if (!narrator.elevenLoading && narrator.elevenError == null && voices.isEmpty) Text('No voices found.', style: T.small()),
        if (voices.isNotEmpty)
          RowGroup(children: [
            for (final v in voices.take(120))
              ListRow(
                title: v.name,
                subtitle: [if (v.traits.isNotEmpty) v.traits, if (v.category.isNotEmpty) v.category].join(' · '),
                onTap: () {
                  s.update((s) => s
                    ..elevenVoice = v.id
                    ..elevenVoiceName = v.name);
                  if (v.previewUrl != null) narrator.playSample(v.previewUrl!);
                },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (v.previewUrl != null) IconButton(tooltip: 'Play sample', icon: const Icon(Icons.play_circle_outline), onPressed: () => narrator.playSample(v.previewUrl!)),
                  Icon((s.elevenVoice.isEmpty ? narrator.elevenVoices.first.id : s.elevenVoice) == v.id ? Icons.check_circle : Icons.circle_outlined, size: 20, color: (s.elevenVoice.isEmpty ? narrator.elevenVoices.first.id : s.elevenVoice) == v.id ? AppColors.accent : AppColors.textFaint),
                ]),
              ),
          ]),
        const SizedBox(height: 10),
        AppButton(label: 'Hear the narrator', icon: Icons.volume_up_outlined, kind: ButtonKind.secondary, onPressed: () => narrator.speakNow('The torches gutter as the iron door groans open. Something stirs in the dark.')),
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Samples are free. Spoken lines use your ElevenLabs characters and are cached, so replays are free. Characters get distinct voices automatically; pick one for anyone from their profile in People.', style: T.caption())),
      ],
    ]);
  }
}

class _ElevenKeySheet extends StatefulWidget {
  const _ElevenKeySheet();

  @override
  State<_ElevenKeySheet> createState() => _ElevenKeySheetState();
}

class _ElevenKeySheetState extends State<_ElevenKeySheet> {
  late final _ctrl = TextEditingController(text: context.read<SettingsController>().elevenLabsKey);
  bool _testing = false;
  bool? _ok;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsController>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('ElevenLabs key', subtitle: 'Create one at elevenlabs.io → Developers → API keys (allow Voices and Text to Speech). Stored only on this device.'),
        TextField(
          controller: _ctrl,
          obscureText: true,
          autofocus: true,
          style: T.body(),
          onChanged: (_) => setState(() => _ok = null),
          decoration: InputDecoration(
            hintText: 'sk_…',
            suffixIcon: _ok == null ? null : Icon(_ok! ? Icons.check_circle : Icons.error_outline, size: 20, color: _ok! ? AppColors.success : AppColors.danger),
          ),
        ),
        if (_ok == false) Padding(padding: const EdgeInsets.only(top: 8), child: Text('ElevenLabs rejected the key, or it lacks the Voices permission.', style: T.small(color: AppColors.danger))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Test',
              kind: ButtonKind.secondary,
              busy: _testing,
              onPressed: _ctrl.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => _testing = true);
                      final c = ElevenLabsClient(_ctrl.text.trim());
                      final ok = await c.verify();
                      c.close();
                      if (mounted) {
                        setState(() {
                          _testing = false;
                          _ok = ok;
                        });
                      }
                    },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              label: 'Save',
              onPressed: () {
                s.update((s) {
                  s.elevenLabsKey = _ctrl.text.trim();
                  if (s.elevenLabsKey.isNotEmpty) s.voiceEngine = 'elevenlabs';
                });
                context.read<Narrator>().loadElevenVoices(force: true);
                Navigator.pop(context);
              },
            ),
          ),
        ]),
        if (s.elevenLabsKey.isNotEmpty) ...[
          const SizedBox(height: 8),
          AppButton(
            label: 'Remove key',
            kind: ButtonKind.ghost,
            onPressed: () {
              s.update((s) {
                s.elevenLabsKey = '';
                if (s.voiceEngine == 'elevenlabs') s.voiceEngine = 'device';
              });
              Navigator.pop(context);
            },
          ),
        ],
      ]),
    );
  }
}

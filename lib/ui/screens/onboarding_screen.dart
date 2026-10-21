import 'package:flutter/material.dart';

import '../../art/scene_painter.dart';
import 'settings/profile_editor.dart' show AvatarPicker;
import 'package:provider/provider.dart';

import '../../data/tale_genres.dart';
import '../../data/tales/tales.dart';
import '../../services/ai/gateway_client.dart';
import '../../services/ai/model_catalog.dart';
import '../../services/audio/audio_service.dart';
import '../../services/narrator.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import '../widgets/dice.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _useAi = false;
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _avatar;
  bool _testing = false;
  bool? _keyOk;
  AiMode _aiMode = AiMode.text;
  bool _openRouter = false;
  int? _rolled;
  String _start = 'tutorial';

  /// 'dnd' or 'tales': what the home screen opens to.
  String _mode = 'dnd';

  static const _steps = 9;

  /// Index of the storyteller (API key) step.
  static const _keyStep = 5;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsController>();
    _openRouter = !s.hasVercelKey && s.hasOpenRouterKey;
    _keyCtrl.text = _openRouter ? s.openRouterKey : s.apiKey;
    _useAi = s.hasApiKey;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
      return;
    }
    HomeScreen.pendingAction = _start == 'explore' ? null : _start;
    final cat = context.read<ModelCatalog>();
    context.read<SettingsController>().update((s) {
      final key = _useAi ? _keyCtrl.text.trim() : '';
      if (_openRouter) {
        s.openRouterKey = key;
        if (key.isNotEmpty && !s.hasVercelKey) adoptOpenRouterModels(s, cat);
      } else {
        s.apiKey = key;
      }
      s.aiMode = _useAi ? _aiMode : AiMode.none;
      s.playerName = _nameCtrl.text.trim();
      s.playerBio = _bioCtrl.text.trim();
      s.playerAvatar = _avatar ?? '';
      s.homeMode = _mode;
      s.onboarded = true;
    });
  }

  Future<void> _testKey() async {
    setState(() {
      _testing = true;
      _keyOk = null;
    });
    final key = _keyCtrl.text.trim();
    final c = GatewayClient(apiKey: _openRouter ? '' : key, openRouterKey: _openRouter ? key : null, captureTarget: false);
    final fast = context.read<SettingsController>().fastModel;
    final ok = await c.verifyKey(_openRouter ? '${AiRoute.prefix}openai/gpt-4o-mini' : (AiRoute.isOpenRouter(fast) ? 'anthropic/claude-haiku-5.5' : fast));
    c.close();
    if (mounted) {
      setState(() {
        _testing = false;
        _keyOk = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _step != _keyStep || !_useAi || _keyCtrl.text.trim().isNotEmpty;
    final labels = [
      'Begin',
      'Next',
      'Next',
      'Next',
      'Continue',
      'Continue',
      'Continue',
      'Continue',
      switch (_start) {
        'tutorial' => 'Start the tutorial',
        'create' => 'Create my hero',
        'tale_ai' => 'Write my story',
        _ when _start.startsWith('tale:') => 'Start reading',
        _ => 'Enter DnD',
      },
    ];
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 520,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                for (var i = 0; i < _steps; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 3,
                      margin: EdgeInsets.only(right: i < _steps - 1 ? 6 : 0),
                      decoration: BoxDecoration(color: i <= _step ? AppColors.accent : AppColors.surface3, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
              SizedBox(
                height: 48,
                child: _step == 0
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(onPressed: () => setState(() => _step--), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Back')),
                      ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim), child: child),
                  ),
                  child: KeyedSubtree(key: ValueKey(_step), child: [_welcome, _tourCharacters, _tourMedia, _tourTools, _modeStep, _storyteller, _profile, _preferences, _ready][_step]()),
                ),
              ),
              const SizedBox(height: 12),
              AppButton(label: labels[_step], kind: _step == _steps - 1 ? ButtonKind.accent : ButtonKind.primary, onPressed: canContinue ? _next : null),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- welcome

  Widget _welcome() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Center(
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppColors.accent.withValues(alpha: 0.28), AppColors.accent.withValues(alpha: 0.0)]),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/icon/icon.png', width: 104, height: 104, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => SizedBox(width: 104, height: 104, child: CustomPaint(painter: DieFacePainter(sides: 20, value: 20)))),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Center(child: Text('DnD', style: T.h1().copyWith(fontSize: 48, letterSpacing: -2))),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Solo Dungeons & Dragons and text adventures in any genre.',
            textAlign: TextAlign.center,
            style: T.body(color: AppColors.textMuted).copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(height: 22),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            RollableDie(sides: 20, size: 64, onRolled: (v) => setState(() => _rolled = v)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_rolled == null ? 'Roll for initiative' : (_rolled == 20 ? 'Natural 20!' : (_rolled == 1 ? 'Natural 1. Ouch.' : 'You rolled $_rolled')), style: T.h3()),
                const SizedBox(height: 2),
                Text(_rolled == null ? 'Tap or flick the die. Every roll in DnD is a real die like this one.' : (_rolled! >= 15 ? 'The dice like you. A good omen.' : 'The adventure has already begun.'), style: T.small()),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        _feature(Icons.person_outline, 'Heroes your way', 'Build with real 5e rules, use a preset, a photo, or let AI design everything.'),
        _feature(Icons.auto_stories_outlined, 'Stories that remember', 'Handcrafted campaigns, endless quests, or an AI Dungeon Master with memory.'),
        _feature(Icons.casino_outlined, 'Real dice, real rules', 'Checks, tactical combat, subclasses, feats, magic items and loot.'),
        _feature(Icons.menu_book_outlined, 'Text adventures', 'Sci-fi, horror, western, noir, cyberpunk and more. Handcrafted or written live by AI.'),
        _feature(Icons.help_outline, 'Solo tools', 'Oracle, random tables, journals you can export, and companions with opinions.'),
        _feature(Icons.wifi_off_outlined, 'Works offline', 'Art, sound and music are made on your device. AI is optional.'),
      ]),
    );
  }

  Widget _feature(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Icon(icon, size: 18, color: AppColors.text),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.h3()),
            const SizedBox(height: 2),
            Text(sub, style: T.small()),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ tour

  Widget _tourPage({required IconData icon, required Color color, required String kicker, required String title, required String sub, required Widget demo, required List<(IconData, String, String)> points}) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.5))),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Text(kicker.toUpperCase(), style: T.overline(color: color).copyWith(letterSpacing: 2)),
        ]),
        const SizedBox(height: 14),
        Text(title, style: T.h1()),
        const SizedBox(height: 6),
        Text(sub, style: T.body(color: AppColors.textMuted)),
        const SizedBox(height: 18),
        demo,
        const SizedBox(height: 20),
        for (final (i, t, d) in points) _feature(i, t, d),
      ]),
    );
  }

  Widget _bubble(String text, {bool me = false, String? who}) => Align(
        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(color: me ? AppColors.text : AppColors.surface2, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (who != null) Text(who, style: T.caption(color: AppColors.textMuted)),
            Text(text, style: T.small(color: me ? AppColors.bg : AppColors.text)),
          ]),
        ),
      );

  Widget _meter(IconData icon, Color color, String label, double v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          SizedBox(width: 92, child: Text(label, style: T.caption(color: color))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: v, minHeight: 6, color: color, backgroundColor: AppColors.surface3))),
        ]),
      );

  Widget _tourCharacters() => _tourPage(
        icon: Icons.forum_outlined,
        color: const Color(0xFFF472B6),
        kicker: 'Characters',
        title: 'Characters who remember you',
        sub: 'Talk to anyone in your story, from companions to the innkeeper. What you say changes how they feel.',
        demo: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _bubble('You stayed. After everything.', who: 'Nyx'),
            _bubble('I wasn\'t going to leave you in that crypt.', me: true),
            _bubble('*smiles* Then I owe you a drink. Maybe two.', who: 'Nyx'),
            const SizedBox(height: 4),
            _meter(Icons.handshake_outlined, AppColors.success, 'Close friend', 0.72),
            _meter(Icons.favorite, const Color(0xFFF472B6), 'Courting', 0.5),
          ]),
        ),
        points: const [
          (Icons.chat_bubble_outline, 'Chat with anyone', 'Tap a character in the story, in your party or in the journal. Conversations are saved.'),
          (Icons.favorite_border, 'Friendship and romance', 'Tracked separately, with a history of the moments that changed them.'),
          (Icons.record_voice_over_outlined, 'Their own voices', 'The AI casts a voice for each character. Use your device, an AI voice, or ElevenLabs.'),
        ],
      );

  Widget _tourMedia() => _tourPage(
        icon: Icons.auto_awesome_outlined,
        color: AppColors.accent,
        kicker: 'Art, video & voice',
        title: 'See it. Hear it.',
        sub: 'Every scene can be painted, filmed or read aloud. And everything works on device for free when AI is off.',
        demo: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              const SceneView(location: 'castle', time: 'dusk', mood: 'triumph', seed: 7),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(child: Text('A critical hit shatters the warden\'s shield.', style: T.small(color: Colors.white))),
                ]),
              ),
            ]),
          ),
        ),
        points: const [
          (Icons.image_outlined, 'Scenes, portraits and special effects', 'AI art for new places, everyone you meet, and big moments you choose.'),
          (Icons.movie_outlined, 'Short video clips', 'Cheap 4-second clips instead of still images, if you want them.'),
          (Icons.photo_library_outlined, 'A gallery for every story', 'Save any picture to your phone, AI-made or drawn on device.'),
        ],
      );

  Widget _tourTools() => _tourPage(
        icon: Icons.handyman_outlined,
        color: AppColors.info,
        kicker: 'Your tools',
        title: 'Same tools, both modes',
        sub: 'D&D and text adventures share a journal, map, notes and AI helpers, plus tools that belong to each mode.',
        demo: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (i, t) in const [
            (Icons.book_outlined, 'Journal'),
            (Icons.map_outlined, 'Map'),
            (Icons.sticky_note_2_outlined, 'Notes'),
            (Icons.psychology_outlined, 'Recap & ideas'),
            (Icons.picture_as_pdf_outlined, 'PDF & web export'),
            (Icons.style_outlined, 'Share cards'),
            (Icons.toll_outlined, 'Cost tracking'),
            (Icons.text_fields, 'Fonts'),
          ])
            Chip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              avatar: Icon(i, size: 16), label: Text(t, style: T.small(color: AppColors.text))),
        ]),
        points: const [
          (Icons.history_edu_outlined, '"Previously on…"', 'Come back after a while and get a quick recap. Ask about the world without using a turn.'),
          (Icons.hub_outlined, 'Any AI you like', 'Vercel AI Gateway or OpenRouter, with free models and limits on what you spend.'),
          (Icons.ios_share, 'Keep your stories', 'Export illustrated PDFs and interactive web pages, or share a hero card.'),
        ],
      );

  // ------------------------------------------------------------------ mode

  Widget _modeStep() {
    Widget card(String id, IconData icon, String title, String sub, List<String> bullets) => SelectCard(
          selected: _mode == id,
          onTap: () => setState(() {
            _mode = id;
            _start = id == 'tales' ? 'tale:hollow_lane' : 'tutorial';
          }),
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: AppColors.text),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: T.h3())),
              ]),
              const SizedBox(height: 6),
              Text(sub, style: T.small()),
              const SizedBox(height: 10),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.check, size: 14, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b, style: T.caption(color: AppColors.textMuted))),
                  ]),
                ),
            ]),
          ),
        );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What do you feel like playing?', style: T.h1()),
        const SizedBox(height: 8),
        Text('You can switch any time from the home screen.', style: T.bodyMuted()),
        const SizedBox(height: 24),
        card('dnd', Icons.shield_outlined, 'Dungeons & Dragons', 'Build a hero and adventure with real 5e rules.', const ['Characters, levels, spells and loot', 'Dice, tactical combat on a grid', 'Handcrafted campaigns and an AI Dungeon Master']),
        const SizedBox(height: 10),
        card('tales', Icons.menu_book_outlined, 'Text adventures', 'Pure story. No rules to learn, just choices.', const ['Sci-fi, horror, western, noir, cyberpunk, post-apocalyptic', 'Handcrafted stories with multiple endings', 'Endless AI stories in any genre']),
      ]),
    );
  }

  // ------------------------------------------------------------- storyteller

  Widget _storyteller() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Your storyteller', style: T.h1()),
        const SizedBox(height: 8),
        Text('Who runs your games? You can mix both and change it any time.', style: T.bodyMuted()),
        const SizedBox(height: 24),
        SelectCard(
          selected: !_useAi,
          onTap: () => setState(() => _useAi = false),
          child: _option(Icons.offline_bolt_outlined, 'Offline storyteller', 'Handcrafted adventures and endless generated quests. Free, private, no account.'),
        ),
        const SizedBox(height: 10),
        SelectCard(
          selected: _useAi,
          onTap: () => setState(() => _useAi = true),
          child: _option(Icons.auto_awesome_outlined, 'AI storyteller', 'Improvised stories, art, voices and video through Vercel AI Gateway or OpenRouter, with any model you like.'),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: !_useAi
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [ButtonSegment(value: false, label: Text('Vercel AI Gateway')), ButtonSegment(value: true, label: Text('OpenRouter'))],
                      selected: {_openRouter},
                      onSelectionChanged: (v) => setState(() {
                        _openRouter = v.first;
                        _keyOk = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _keyCtrl,
                      obscureText: true,
                      style: T.body(),
                      onChanged: (_) => setState(() => _keyOk = null),
                      decoration: InputDecoration(
                        labelText: _openRouter ? 'OpenRouter API key' : 'AI Gateway API key',
                        suffixIcon: _keyOk == null ? null : Icon(_keyOk! ? Icons.check_circle : Icons.error_outline, color: _keyOk! ? AppColors.success : AppColors.danger, size: 20),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_openRouter ? 'Create one at openrouter.ai → Keys. OpenRouter also has free models. Stored only on this device.' : 'Create one in Vercel → AI Gateway → API Keys. It is stored only on this device.', style: T.caption()),
                    const SizedBox(height: 12),
                    AppButton(label: 'Test key', kind: ButtonKind.secondary, busy: _testing, height: 42, onPressed: _keyCtrl.text.trim().isEmpty ? null : _testKey),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _option(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(children: [
          Icon(icon, color: AppColors.text),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.h3()),
              const SizedBox(height: 2),
              Text(sub, style: T.small()),
            ]),
          ),
        ]),
      );

  // ----------------------------------------------------------------- profile

  Widget _profile() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Who\'s playing?', style: T.h1()),
        const SizedBox(height: 8),
        Text('Your profile shows your stats and stories. All optional, and it stays on this device.', style: T.bodyMuted()),
        const SizedBox(height: 24),
        AvatarPicker(path: _avatar, name: _nameCtrl.text, bio: _bioCtrl.text, onChanged: (p) => setState(() => _avatar = p)),
        const SizedBox(height: 22),
        TextField(controller: _nameCtrl, style: T.body(), textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 12),
        TextField(
          controller: _bioCtrl,
          style: T.body(),
          minLines: 3,
          maxLines: 5,
          maxLength: 400,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Bio', hintText: 'Favorite genres, the hero you always play…', alignLabelWithHint: true),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------- preferences

  Widget _preferences() {
    final s = context.watch<SettingsController>();
    final audio = context.read<AudioService>();
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Make it yours', style: T.h1()),
        const SizedBox(height: 8),
        Text('Everything here can be changed later in Settings.', style: T.bodyMuted()),
        const SizedBox(height: 24),
        if (_useAi) ...[
          const SectionLabel('Use AI for'),
          SegmentedButton<AiMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: AiMode.text, label: Text('Story')),
              ButtonSegment(value: AiMode.images, label: Text('Images')),
              ButtonSegment(value: AiMode.both, label: Text('Both')),
            ],
            selected: {_aiMode == AiMode.none ? AiMode.text : _aiMode},
            onSelectionChanged: (v) => setState(() => _aiMode = v.first),
          ),
          const SizedBox(height: 6),
          Text('Anything not using AI runs on your device. Image generation costs credits.', style: T.caption()),
          const SizedBox(height: 10),
          RowGroup(children: [
            ListRow(
              leading: const Icon(Icons.toll_outlined, size: 20),
              title: 'Show tokens & spend',
              subtitle: 'A live cost meter with insights',
              trailing: Switch(value: s.showUsage, onChanged: (v) => s.update((s) => s.showUsage = v)),
            ),
          ]),
        ],
        const SectionLabel('Sound & voice'),
        RowGroup(children: [
          ListRow(
            title: 'Sound effects',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: () => audio.play('success')),
              Switch(value: s.sfxEnabled, onChanged: (v) => s.update((s) => s.sfxEnabled = v)),
            ]),
          ),
          ListRow(
            title: 'Background music',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: () => audio.music('calm')),
              Switch(value: s.musicEnabled, onChanged: (v) => s.update((s) => s.musicEnabled = v)),
            ]),
          ),
          ListRow(
            title: 'Voice narration',
            subtitle: 'Your device reads the story aloud',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (s.ttsEnabled) IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: () => context.read<Narrator>().say('Welcome, adventurer. Your story begins tonight.')),
              Switch(value: s.ttsEnabled, onChanged: (v) => s.update((s) => s.ttsEnabled = v)),
            ]),
          ),
        ]),
        const SectionLabel('Reading'),
        RowGroup(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Text('Aa', style: T.small()),
              Expanded(child: Slider(value: s.textScale, min: 0.85, max: 1.5, divisions: 13, onChanged: (v) => s.update((s) => s.textScale = v))),
              Text('Aa', style: T.h2()),
            ]),
          ),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ ready

  Widget _ready() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_nameCtrl.text.trim().isEmpty ? 'You\'re ready' : 'Ready, ${_nameCtrl.text.trim()}', style: T.h1()),
        const SizedBox(height: 8),
        Text('How would you like to begin?', style: T.bodyMuted()),
        const SizedBox(height: 24),
        if (_mode == 'tales') ...[
          for (final p in [for (final id in const ['hollow_lane', 'silent_ship', 'red_mesa']) taleById(id)!])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectCard(
                selected: _start == 'tale:${p.id}',
                onTap: () => setState(() => _start = 'tale:${p.id}'),
                child: _option(genreById(p.genre).icon, p.title, '${genreById(p.genre).name} · ~${p.minutes} min · ${p.endings} endings'),
              ),
            ),
          if (_useAi)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectCard(selected: _start == 'tale_ai', onTap: () => setState(() => _start = 'tale_ai'), child: _option(Icons.auto_awesome_outlined, 'Write one with AI', 'Pick a genre and an AI narrator improvises around your choices.')),
            ),
          SelectCard(selected: _start == 'explore', onTap: () => setState(() => _start = 'explore'), child: _option(Icons.explore_outlined, 'Look around first', 'Browse every story and genre.')),
        ] else ...[
        SelectCard(
          selected: _start == 'tutorial',
          onTap: () => setState(() => _start = 'tutorial'),
          child: _option(Icons.school_outlined, 'Play the 3-minute tutorial', 'A short guided adventure in a tavern cellar. Learn choices, dice, combat and the journal.'),
        ),
        const SizedBox(height: 10),
        SelectCard(
          selected: _start == 'create',
          onTap: () => setState(() => _start = 'create'),
          child: _option(Icons.person_add_alt, 'Create my hero', 'Jump straight into character creation, then pick an adventure.'),
        ),
        const SizedBox(height: 10),
        SelectCard(
          selected: _start == 'explore',
          onTap: () => setState(() => _start = 'explore'),
          child: _option(Icons.explore_outlined, 'Look around first', 'Browse presets, the compendium and the dice tray.'),
        ),
        ],
      ]),
    );
  }
}

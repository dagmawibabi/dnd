import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'story_extras.dart';
import '../../../game/story_host.dart';
import '../../../models/world.dart';
import '../../../services/achievements.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/error_card.dart';
import 'story_tools.dart' show AiNoteActions;

/// Opens the page for one kind of AI help: recaps, ideas, diary or hints.
Future<void> openAiNotes(BuildContext context, StoryHost host, String kind) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiNotesScreen(host: host, kind: kind),
      ),
    );

const _titles = {
  'recap': 'Recaps',
  'ideas': 'Inspire me',
  'diary': 'Diary',
  'insight': 'Hints',
};
const _make = {
  'recap': 'New recap',
  'ideas': 'Give me ideas',
  'diary': 'Write today\'s entry',
};
const _empty = {
  'recap': 'A short "Previously on…" of your story so far, whenever you need a reminder.',
  'ideas': 'Three fresh ideas for what to do next: one bold, one clever, one personal.',
  'diary': 'Your character\'s private diary: what they think and feel about what is happening.',
  'insight': 'Hints you ask for from a quest or goal appear here.',
};
const _icons = {
  'recap': Icons.history_edu_outlined,
  'ideas': Icons.lightbulb_outline,
  'diary': Icons.edit_note,
  'insight': Icons.insights_outlined,
};

class AiNotesScreen extends StatefulWidget {
  const AiNotesScreen({super.key, required this.host, required this.kind});
  final StoryHost host;
  final String kind;

  @override
  State<AiNotesScreen> createState() => _AiNotesScreenState();
}

class _AiNotesScreenState extends State<AiNotesScreen> {
  bool _busy = false;

  Future<void> _new() async {
    final host = widget.host;
    final ai = StoryAi(host.settings);
    setState(() => _busy = true);
    try {
      final AiNote note;
      switch (widget.kind) {
        case 'ideas':
          final r = await ai.inspire(host);
          note = AiNote(
            kind: 'ideas',
            title: 'Ideas',
            ideas: r.value,
            turn: host.turns,
            tokens: r.tokens,
            cost: r.cost,
          );
        case 'diary':
          final r = await ai.diary(host);
          note = AiNote(
            kind: 'diary',
            title: 'Diary',
            text: r.value,
            turn: host.turns,
            tokens: r.tokens,
            cost: r.cost,
          );
        default:
          final r = await ai.recap(host);
          note = AiNote(
            kind: 'recap',
            title: 'Previously on…',
            text: r.value,
            turn: host.turns,
            tokens: r.tokens,
            cost: r.cost,
          );
      }
      host.world.addAiNote(note);
      host.save();
      if (mounted) context.read<Achievements>().add(Stat.aiTools);
    } catch (e) {
      if (mounted)
        showIssueSheet(context, '$e', label: _titles[widget.kind] ?? 'AI');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final kind = widget.kind;
    final on = context.watch<SettingsController>().useAiText;
    final notes = [
      ...host.world.aiNotes.where((n) => n.kind == kind && n.pinned),
      ...host.world.aiNotes.reversed.where((n) => n.kind == kind && !n.pinned),
    ];
    final diary = kind == 'diary';
    return Scaffold(
      bottomNavigationBar: const NowReadingBar(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[kind] ?? 'AI', style: T.h3()),
            Text(
              host.storyTitle,
              style: T.caption(),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      floatingActionButton: _make[kind] == null || !on
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _new,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_icons[kind]),
              label: Text(_busy ? 'Writing…' : _make[kind]!),
            ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _WritingShimmer(diary: diary),
              ),
            if (notes.isEmpty && !_busy)
              EmptyState(
                icon: _icons[kind] ?? Icons.psychology_outlined,
                title: 'Nothing yet',
                message: on
                    ? _empty[kind]
                    : 'Turn on the AI storyteller in Settings to use this.',
              ),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: diary
                    ? _DiaryPage(
                        host: host,
                        note: n,
                        onChanged: () => setState(() {}),
                      )
                    : _Card(
                        host: host,
                        note: n,
                        onChanged: () => setState(() {}),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A page-shaped placeholder that makes it clear the recap or diary is being
/// written without letting a wide progress row overflow on small phones.
class _WritingShimmer extends StatefulWidget {
  const _WritingShimmer({required this.diary});
  final bool diary;

  @override
  State<_WritingShimmer> createState() => _WritingShimmerState();
}

class _WritingShimmerState extends State<_WritingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final base = widget.diary ? const Color(0xFFD8CDB5) : AppColors.surface2;
    final shine = widget.diary ? const Color(0xFFF7F0DF) : AppColors.border;
    Widget line(double width, double height) => FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
    final skeleton = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.diary ? 8 : 16),
        border: widget.diary ? null : Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(0.38, 18),
          const SizedBox(height: 18),
          line(1, 12),
          const SizedBox(height: 10),
          line(0.92, 12),
          const SizedBox(height: 10),
          line(0.72, 12),
          const SizedBox(height: 18),
          Text(
            widget.diary ? 'Writing today\'s entry…' : 'Writing your recap…',
            style: T.caption(
              color: widget.diary
                  ? const Color(0xFF6A5B43)
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
    if (reduceMotion) return skeleton;
    return AnimatedBuilder(
      animation: _controller,
      child: skeleton,
      builder: (context, child) {
        final x = _controller.value * 4 - 2;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: [base, shine, base],
            stops: const [0.2, 0.5, 0.8],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.host,
    required this.note,
    required this.onChanged,
  });
  final StoryHost host;
  final AiNote note;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note.question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(note.question, style: T.h3()),
            ),
          if (note.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SelectableText(note.text, style: T.reading()),
            ),
          for (final idea in note.ideas)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: host.busy || !host.isAi
                    ? null
                    : () {
                        Navigator.pop(context);
                        host.act(idea);
                      },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bolt_outlined,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(idea, style: T.body())),
                      if (host.isAi)
                        const Icon(
                          Icons.send_outlined,
                          size: 15,
                          color: AppColors.textFaint,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          AiNoteActions(host: host, note: note, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A diary entry, set like a page of a journal.
class _DiaryPage extends StatelessWidget {
  const _DiaryPage({
    required this.host,
    required this.note,
    required this.onChanged,
  });
  final StoryHost host;
  final AiNote note;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFEFE6D2);
    const ink = Color(0xFF2B2216);
    final lines = note.text.trim().split('\n');
    final heading = lines.length > 1 && lines.first.length < 70
        ? lines.first.replaceAll('*', '').trim()
        : 'Turn ${note.turn}';
    final body = lines.length > 1 && lines.first.length < 70
        ? lines.skip(1).join('\n').trim()
        : note.text.trim();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.4,
          colors: [Color(0xFFF5EEDC), paper],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            heading,
            style: const TextStyle(
              fontFamily: 'serif',
              color: ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: ink.withValues(alpha: 0.2),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SelectableText(
              body,
              style: TextStyle(
                fontFamily: 'serif',
                color: ink,
                fontSize: 16 * T.readingScale,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context)
                .copyWith(iconTheme: const IconThemeData(color: ink)),
            child: AiNoteActions(host: host, note: note, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

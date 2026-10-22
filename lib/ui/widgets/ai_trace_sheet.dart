import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../game/story_host.dart';
import '../../services/settings.dart';
import '../../services/usage.dart';
import '../../theme/ui.dart';

/// Opens the storyteller's working: steps, thinking, the reply as it is
/// written, the actions it took and everything it was given. Live while it runs.
Future<void> showAiTrace(BuildContext context, StoryHost host) {
  if (host.aiTrace == null) {
    showToast(
      context,
      'Nothing to show yet: the storyteller hasn\'t written anything in this session.',
      icon: Icons.info_outline,
    );
    return Future.value();
  }
  return showAppSheet(context, builder: (_) => _TraceSheet(host: host));
}

class _TraceSheet extends StatefulWidget {
  const _TraceSheet({required this.host});
  final StoryHost host;

  @override
  State<_TraceSheet> createState() => _TraceSheetState();
}

class _TraceSheetState extends State<_TraceSheet> {
  Timer? _tick;
  bool _thinking = true;
  bool _reply = false;
  final Set<int> _open = {};

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (widget.host.aiTrace?.running ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _secs(Duration d) => d.inSeconds < 60
      ? '${d.inSeconds}s'
      : '${d.inMinutes}m ${d.inSeconds % 60}s';

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final showCost = context.watch<SettingsController>().showUsage;
    return ListenableBuilder(
      listenable: Listenable.merge([
        host,
        if (host.aiTrace != null) host.aiTrace!,
      ]),
      builder: (context, _) {
        final t = host.aiTrace!;
        final (color, label) = t.running
            ? (AppColors.accent, 'Working · ${_secs(t.elapsed)}')
            : t.stopped
            ? (AppColors.warning, 'Stopped after ${_secs(t.elapsed)}')
            : t.error != null
            ? (AppColors.danger, 'Failed after ${_secs(t.elapsed)}')
            : (AppColors.success, 'Done in ${_secs(t.elapsed)}');
        Widget section(String title, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Row(
            children: [
              Expanded(child: Text(title.toUpperCase(), style: T.overline())),
              ?trailing,
            ],
          ),
        );
        Widget mono(String text, {int? max}) => SelectableText(
          text,
          maxLines: max,
          style: T
              .mono(11.5, color: AppColors.textMuted)
              .copyWith(height: 1.45),
        );
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              Row(
                children: [
                  if (!t.running) ...[
                    Icon(
                      t.error == null
                          ? Icons.check_circle
                          : (t.stopped
                                ? Icons.stop_circle_outlined
                                : Icons.error_outline),
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Behind the story', style: T.h2()),
                        Text(
                          '$label · ${t.model.replaceFirst('or:', '')}',
                          style: T.caption(color: color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (t.running)
                    Expanded(
                      child: AppButton(
                        label: 'Stop',
                        icon: Icons.stop_rounded,
                        kind: ButtonKind.secondary,
                        onPressed: host.stopAi,
                      ),
                    )
                  else ...[
                    if (t.error != null)
                      Expanded(
                        child: AppButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          onPressed: () {
                            Navigator.pop(context);
                            host.retryAi();
                          },
                        ),
                      )
                    else if (host.canRegenerate)
                      Expanded(
                        child: AppButton(
                          label: 'Write it again',
                          icon: Icons.refresh,
                          kind: ButtonKind.secondary,
                          onPressed: () {
                            Navigator.pop(context);
                            host.regenerate();
                          },
                        ),
                      ),
                  ],
                ],
              ),
              if (!t.running && (t.tokens > 0 || t.cost > 0))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Tag(
                        '${fmtTokens(t.tokens)} tokens',
                        icon: Icons.toll_outlined,
                      ),
                      if (showCost && t.cost > 0)
                        Tag(fmtCost(t.cost), icon: Icons.payments_outlined),
                      Tag(
                        '~${fmtTokens((t.contextChars / 4).round())} context',
                        icon: Icons.input,
                      ),
                    ],
                  ),
                ),
              if (t.error != null && !t.stopped) ...[
                const SizedBox(height: 10),
                Text(t.error!, style: T.small(color: AppColors.danger)),
              ],
              section('Steps'),
              for (final (i, s) in t.steps.indexed)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: s.failed
                                  ? const Icon(
                                      Icons.cancel,
                                      size: 14,
                                      color: AppColors.danger,
                                    )
                                  : s.done
                                  ? const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: AppColors.success,
                                    )
                                  : const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                      ),
                                    ),
                            ),
                            if (i < t.steps.length - 1)
                              Expanded(
                                child: Container(
                                  width: 1.5,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  color: AppColors.border,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.title,
                                      style: T.small(color: AppColors.text),
                                    ),
                                  ),
                                  Text(
                                    '+${_secs(s.at.difference(t.started))}',
                                    style: T.caption(),
                                  ),
                                ],
                              ),
                              if (s.detail.isNotEmpty)
                                Text(s.detail, style: T.caption()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              section(
                'Thinking',
                trailing: GestureDetector(
                  onTap: () => setState(() => _thinking = !_thinking),
                  child: Icon(
                    _thinking ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (_thinking)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: t.reasoning.isEmpty
                      ? Text(
                          t.running ? 'Waiting for the model…' : 'This model didn\'t share its thinking. Reasoning models on OpenRouter (and some on Vercel) do.',
                          style: T.caption(),
                        )
                      : MarkdownBody(
                          data: t.reasoning.toString(),
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: T
                                .small(color: AppColors.textMuted)
                                .copyWith(height: 1.5),
                            h1: T.h3(),
                            h2: T.h3(),
                            h3: T
                                .small(color: AppColors.text)
                                .copyWith(fontWeight: FontWeight.w700),
                            listBullet: T.small(color: AppColors.accent),
                            code: T.mono(11.5, color: AppColors.text),
                            codeblockDecoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            blockquoteDecoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: AppColors.accent,
                                  width: 3,
                                ),
                              ),
                            ),
                            blockquotePadding: const EdgeInsets.only(left: 10),
                          ),
                        ),
                ),
              section(
                'The reply as written',
                trailing: GestureDetector(
                  onTap: () => setState(() => _reply = !_reply),
                  child: Icon(
                    _reply ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (_reply || (t.running && t.output.isNotEmpty))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: t.output.isEmpty
                      ? Text('Nothing yet.', style: T.caption())
                      : mono(t.output.toString()),
                )
              else
                Text(
                  '${t.output.length} characters · tap the arrow to read the raw reply',
                  style: T.caption(),
                ),
              section('Actions it took'),
              if (t.tools.isEmpty)
                Text(
                  t.running
                      ? 'Shown when the reply is complete.'
                      : 'None: just narration and choices.',
                  style: T.caption(),
                ),
              for (final (name, args) in t.tools)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          name,
                          style: T.mono(11, color: AppColors.accent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          args,
                          style: T.caption(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              section('What it was given · ${t.context.length} messages'),
              Text(
                'The storyteller reads all of this every turn: its instructions, the recent story, and the current state (memory, people, quests, condition).',
                style: T.caption(),
              ),
              const SizedBox(height: 8),
              for (final (i, (role, text)) in t.context.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(
                      () => _open.contains(i) ? _open.remove(i) : _open.add(i),
                    ),
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: text));
                      showToast(context, 'Copied');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Tag(switch (role) {
                                'system' => 'Instructions',
                                'assistant' => 'Storyteller',
                                _ =>
                                  i == t.context.length - 1
                                      ? 'This turn + state'
                                      : 'You',
                              }),
                              const Spacer(),
                              Text('${text.length} chars', style: T.caption()),
                              Icon(
                                _open.contains(i)
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                                color: AppColors.textFaint,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          mono(
                            _open.contains(i)
                                ? text
                                : (text.length > 160
                                      ? '${text.substring(0, 160).replaceAll('\n', ' ')}…'
                                      : text.replaceAll('\n', ' ')),
                            max: _open.contains(i) ? null : 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Tap a message to expand it; hold to copy.',
                style: T.caption(),
              ),
            ],
          ),
        );
      },
    );
  }
}

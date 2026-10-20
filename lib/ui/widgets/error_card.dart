import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/ui.dart';
import '../screens/settings/settings_screen.dart';

/// A plain-language reading of an AI or network error.
class AiIssue {
  const AiIssue({required this.title, required this.summary, required this.icon, required this.color, this.hint = '', this.link, this.settings = false, this.status});
  final String title;
  final String summary;
  final IconData icon;
  final Color color;
  final String hint;
  final String? link;

  /// Whether Settings can fix it (keys, models, limits).
  final bool settings;
  final int? status;
}

AiIssue describeIssue(String raw, {String what = 'The AI'}) {
  final status = int.tryParse(RegExp(r'error (\d{3})').firstMatch(raw)?.group(1) ?? '');
  final message = raw.replaceFirst(RegExp(r'^(Exception: )?(AI error \d{3}: )?'), '').trim();
  final link = RegExp(r'https?://[^\s)"]+').firstMatch(message)?.group(0)?.replaceAll(RegExp(r'[.,]$'), '');
  final lower = message.toLowerCase();
  final video = lower.contains('video');
  String short(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
  if (status == 402 || lower.contains('balance') || lower.contains('credit') || lower.contains('insufficient')) {
    final need = RegExp(r'\$\d+(\.\d+)?').firstMatch(message)?.group(0);
    return AiIssue(
      title: 'Out of credits',
      summary: video ? 'Video needs ${need ?? 'more'} balance on your provider account.' : 'Your AI provider account needs more balance.',
      hint: video ? 'Top up your account, or turn video off in Settings → Video and keep using images.' : 'Top up your account, or pick a cheaper or free model in Settings.',
      icon: Icons.account_balance_wallet_outlined,
      color: AppColors.warning,
      link: link,
      settings: true,
      status: status,
    );
  }
  if (status == 401 || status == 403 || lower.contains('invalid api key') || lower.contains('unauthorized')) {
    return AiIssue(title: 'Key rejected', summary: "The provider didn't accept your API key.", hint: 'Check or replace the key in Settings → AI providers.', icon: Icons.key_off_outlined, color: AppColors.danger, link: link, settings: true, status: status);
  }
  if (lower.contains('add a') && lower.contains('key')) {
    return AiIssue(title: 'Key needed', summary: short(message), hint: 'Add it in Settings → AI providers.', icon: Icons.key_outlined, color: AppColors.warning, settings: true, status: status);
  }
  if (lower.contains('limit would be exceeded') || lower.contains('reached its limit') || lower.contains('pricing is unavailable')) {
    return AiIssue(title: 'Usage limit reached', summary: short(message), hint: 'Change your limits in Settings → Usage & limits.', icon: Icons.speed_outlined, color: AppColors.info, settings: true, status: status);
  }
  if (status == 429 || lower.contains('rate limit') || lower.contains('too many requests')) {
    return AiIssue(title: 'Too many requests', summary: 'The provider asked us to slow down.', hint: 'Wait a few seconds and try again.', icon: Icons.hourglass_bottom, color: AppColors.info, link: link, status: status);
  }
  if (status == 404 || (lower.contains('model') && (lower.contains('not found') || lower.contains('not supported') || lower.contains('cannot') || lower.contains('no image')))) {
    return AiIssue(title: 'Model unavailable', summary: short(message), hint: 'Pick another model in Settings.', icon: Icons.memory_outlined, color: AppColors.warning, link: link, settings: true, status: status);
  }
  if (lower.contains('timeout') || lower.contains('socket') || lower.contains('failed host lookup') || lower.contains('connection') || lower.contains('took too long')) {
    return AiIssue(title: "Can't reach the AI", summary: 'The connection failed or timed out.', hint: 'Check your internet connection and try again.', icon: Icons.wifi_off_outlined, color: AppColors.textMuted, status: status);
  }
  if (lower.contains('ran out of room') || lower.contains('incomplete') || lower.contains('empty response')) {
    return AiIssue(title: '$what stopped early', summary: short(message), hint: 'Try again; if it keeps happening, choose a different story model.', icon: Icons.content_cut, color: AppColors.warning, settings: true, status: status);
  }
  return AiIssue(title: 'Something went wrong', summary: short(message), hint: 'Try again in a moment.', icon: Icons.error_outline, color: AppColors.danger, link: link, status: status);
}

/// A compact, friendly error that opens the full story in a bottom sheet.
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.error, this.label, this.onRetry, this.retryLabel = 'Try again', this.onDismiss});
  final String error;

  /// What failed, e.g. "Image" or "Video".
  final String? label;
  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final i = describeIssue(error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showIssueSheet(context, error, label: label, onRetry: onRetry, retryLabel: retryLabel),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(color: i.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: i.color.withValues(alpha: 0.35))),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: i.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(i.icon, size: 18, color: i.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label == null ? i.title : '$label · ${i.title}', style: T.h3().copyWith(fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(i.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small()),
                ]),
              ),
              if (onRetry != null) IconButton(tooltip: retryLabel, icon: const Icon(Icons.refresh, size: 20), onPressed: onRetry),
              if (onDismiss != null) IconButton(tooltip: 'Dismiss', icon: const Icon(Icons.close, size: 18), onPressed: onDismiss) else const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The full error with what to do about it.
Future<void> showIssueSheet(BuildContext context, String error, {String? label, VoidCallback? onRetry, String retryLabel = 'Try again'}) {
  final i = describeIssue(error);
  return showAppSheet(context, builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: i.color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(i.icon, size: 28, color: i.color),
            ),
          ),
          const SizedBox(height: 12),
          Text(i.title, textAlign: TextAlign.center, style: T.h2()),
          if (label != null) Text(label, textAlign: TextAlign.center, style: T.small()),
          const SizedBox(height: 10),
          Text(i.summary, textAlign: TextAlign.center, style: T.body()),
          if (i.hint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(i.hint, textAlign: TextAlign.center, style: T.small(color: AppColors.textMuted)),
          ],
          const SizedBox(height: 18),
          if (i.link != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppButton(
                label: i.title == 'Out of credits' ? 'Top up credits' : 'Open link',
                icon: Icons.open_in_new,
                onPressed: () => launchUrl(Uri.parse(i.link!), mode: LaunchMode.externalApplication),
              ),
            ),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppButton(
                label: retryLabel,
                icon: Icons.refresh,
                kind: i.link != null ? ButtonKind.secondary : ButtonKind.primary,
                onPressed: () {
                  Navigator.pop(ctx);
                  onRetry();
                },
              ),
            ),
          if (i.settings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppButton(
                label: 'Open Settings',
                icon: Icons.settings_outlined,
                kind: ButtonKind.secondary,
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
            ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Technical details', style: T.small()),
            children: [
              Align(alignment: Alignment.centerLeft, child: SelectableText(error, style: T.mono(12, color: AppColors.textMuted))),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    showToast(ctx, 'Copied');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
        ]),
      ));
}

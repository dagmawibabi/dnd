import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/gateway_client.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import '../screens/settings/settings_screen.dart';

/// Why AI writing isn't available right now, in plain words (null if it is).
String? aiTextBlocker(SettingsController s) {
  if (!s.hasApiKey) return 'Add a Vercel AI Gateway or OpenRouter key, or connect LM Studio, in Settings → AI providers. Keys stay on this device.';
  if (!s.aiText) return 'The AI storyteller is turned off. Turn it on in Settings → Text & story.';
  if (!s.canUse(s.textModel) && AiRoute.isLmStudio(s.textModel)) return 'Your story model (${AiRoute.bare(s.textModel)}) runs in LM Studio, but no server address is set. Add it in Settings → AI providers.';
  if (!s.canUse(s.textModel)) return 'Your story model (${AiRoute.bare(s.textModel)}) runs on ${AiRoute.routerName(s.textModel)}, but there\'s no key for it. Add that key, or pick a model from a router you have a key for.';
  return null;
}

/// Explains why an AI feature is off, with a button straight to Settings.
Future<void> showAiUnavailable(BuildContext context, {String feature = 'AI stories'}) {
  final reason = aiTextBlocker(context.read<SettingsController>()) ?? 'This feature is turned off in Settings.';
  return showAppSheet(context, builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.auto_awesome_outlined, size: 32, color: AppColors.accent),
          const SizedBox(height: 10),
          Text('$feature need AI', textAlign: TextAlign.center, style: T.h2()),
          const SizedBox(height: 8),
          Text(reason, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
          const SizedBox(height: 18),
          AppButton(
            label: 'Open Settings',
            icon: Icons.settings_outlined,
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          const SizedBox(height: 8),
          AppButton(label: 'Not now', kind: ButtonKind.ghost, onPressed: () => Navigator.pop(ctx)),
        ]),
      ));
}

/// When a story opens, quietly checks that LM Studio answers if a local model
/// writes it, and says so in a snackbar when it doesn't.
Future<void> checkLocalAi(BuildContext context, {bool confirm = false}) async {
  final s = context.read<SettingsController>();
  if (!s.useAiText || !(AiRoute.isLmStudio(s.textModel) || AiRoute.isLmStudio(s.fastModel))) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await GatewayClient.lmStudioReachable(s.lmStudioUrl);
  if (!context.mounted || messenger == null) return;
  messenger.hideCurrentSnackBar();
  if (ok) {
    if (confirm) messenger.showSnackBar(const SnackBar(content: Text('LM Studio is connected.'), duration: Duration(seconds: 2)));
    return;
  }
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 8),
    content: Text('LM Studio isn\'t answering at ${GatewayClient.normalizeLmUrl(s.lmStudioUrl)}. Start its server on your computer and check you\'re on the same Wi-Fi.'),
    action: SnackBarAction(label: 'Check again', onPressed: () => checkLocalAi(context, confirm: true)),
  ));
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/gateway_client.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import '../screens/settings/settings_screen.dart';

/// Why AI writing isn't available right now, in plain words (null if it is).
String? aiTextBlocker(SettingsController s) {
  if (!s.hasApiKey) return 'Add a Vercel AI Gateway or OpenRouter key in Settings → AI providers. Keys stay on this device.';
  if (!s.aiText) return 'The AI storyteller is turned off. Turn it on in Settings → Text & story.';
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

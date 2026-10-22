import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/narrator.dart';
import '../../services/settings.dart';
import '../../services/voice_input.dart';
import '../../theme/ui.dart';

/// Rebuilds a message bar as its text changes. [typing] is true once something
/// is written (not while dictating, so the microphone stays to stop it), so
/// the bar can hide its picture and microphone buttons and give the box room.
class ComposerBuilder extends StatelessWidget {
  const ComposerBuilder({super.key, required this.controller, required this.builder});
  final TextEditingController controller;
  final Widget Function(BuildContext context, bool typing) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, VoiceInput.instance]),
    builder: (context, _) => builder(context, controller.text.trim().isNotEmpty && !VoiceInput.instance.listening),
  );
}

/// A microphone that transcribes speech straight into [controller].
/// The text stays in the box so it can be checked before sending, unless
/// "Send when you stop speaking" is on.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key, required this.controller, this.onSubmit, this.size = 44, this.flat = false, this.enabled = true});
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  final double size;

  /// A plain icon button (terminal layouts) instead of a round one.
  final bool flat;
  final bool enabled;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final _voice = VoiceInput.instance;
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _voice.addListener(_changed);
  }

  @override
  void dispose() {
    _voice.removeListener(_changed);
    if (_voice.isListening(this)) _voice.stop();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_voice.isListening(this)) {
      await _voice.stop();
      return;
    }
    final settings = context.read<SettingsController>();
    // The narrator would otherwise be transcribed along with the player.
    context.read<Narrator?>()?.stop();
    _typed = widget.controller.text;
    final ok = await _voice.start(this, (words, done) {
      if (!mounted) return;
      final text = joinDictation(_typed, words);
      widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      if (done && words.trim().isNotEmpty && settings.voiceAutoSend) widget.onSubmit?.call();
      if (done && _voice.error != null) showToast(context, _voice.error!, icon: Icons.mic_off_outlined);
    });
    if (!ok && mounted && _voice.error != null) showToast(context, _voice.error!, icon: Icons.mic_off_outlined);
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<SettingsController>().voiceInput) return const SizedBox.shrink();
    final on = _voice.isListening(this);
    final tip = on ? 'Stop listening' : 'Speak';
    final onTap = widget.enabled || on ? _toggle : null;
    if (widget.flat) {
      return IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(on ? Icons.stop_circle_outlined : Icons.mic_none, size: 20, color: on ? AppColors.danger : null),
      );
    }
    final s = widget.size;
    return Semantics(
      label: on ? 'Listening. Tap to stop' : 'Speak your message',
      button: true,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          if (on)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: s + 4 + _voice.level * 14,
              height: s + 4 + _voice.level * 14,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger.withValues(alpha: 0.18)),
            ),
          CircleIconButton(icon: on ? Icons.stop : Icons.mic_none, size: s, tooltip: tip, onPressed: onTap, color: on ? AppColors.danger : null),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/model_catalog.dart';
import '../../services/image_service.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import 'image_viewer.dart';
import 'media_import.dart';

/// Pictures waiting to be sent with the next message (file paths).
class PendingImages extends ValueNotifier<List<String>> {
  PendingImages() : super(const []);

  void add(Iterable<String> paths) => value = [...value, ...paths].take(4).toList();
  void remove(String p) => value = value.where((x) => x != p).toList();

  /// Hands over the pictures and empties the tray.
  List<String> take() {
    final v = value;
    value = const [];
    return v;
  }
}

/// Whether [model] reads images, as far as the catalog knows (null: unknown).
bool? modelSees(BuildContext context, String model) {
  final info = context.read<ModelCatalog>().byId(model);
  if (info == null) return null;
  return info.inputModalities.contains('image');
}

/// A button that adds pictures to [pending] for the AI to look at.
class AttachImageButton extends StatelessWidget {
  const AttachImageButton({super.key, required this.pending, this.model, this.enabled = true, this.flat = false});
  final PendingImages pending;

  /// The model that will see them (to warn when it can't).
  final String? model;
  final bool enabled;
  final bool flat;

  Future<void> _pick(BuildContext context) async {
    final m = model ?? context.read<SettingsController>().textModel;
    if (modelSees(context, m) == false) {
      final go = await confirm(context, title: 'This model may not see pictures', message: '${m.replaceFirst('or:', '')} doesn\'t list image input. Pick a vision model in Settings → Text & story, or send anyway.', action: 'Send anyway');
      if (!go || !context.mounted) return;
    }
    final picked = await chooseImages(context, title: 'Show a picture');
    pending.add(picked.map((f) => f.path));
  }

  @override
  Widget build(BuildContext context) {
    final onTap = enabled ? () => _pick(context) : null;
    if (flat) return IconButton(tooltip: 'Attach a picture', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_photo_alternate_outlined, size: 20), onPressed: onTap);
    return CircleIconButton(icon: Icons.add_photo_alternate_outlined, size: 44, tooltip: 'Attach a picture', onPressed: onTap);
  }
}

/// Thumbnails of the pictures about to be sent, each with a remove button.
class PendingImagesStrip extends StatelessWidget {
  const PendingImagesStrip({super.key, required this.pending});
  final PendingImages pending;

  @override
  Widget build(BuildContext context) {
    final images = context.read<ImageService>();
    return ValueListenableBuilder<List<String>>(
      valueListenable: pending,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 64, height: 64, child: GeneratedImage(path: p, fallback: Container(color: AppColors.surface2), service: images, cacheWidth: 160))),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => pending.remove(p),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                    ),
                  ]),
                ),
              Center(child: Text('${list.length} picture${list.length == 1 ? '' : 's'} will be shown', style: T.caption())),
            ]),
          ),
        );
      },
    );
  }
}

/// Pictures that were sent with a message, small, tap to view.
class SentImages extends StatelessWidget {
  const SentImages({super.key, required this.paths, this.size = 96, this.alignEnd = false});
  final List<String> paths;
  final double size;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final images = context.read<ImageService>();
    return Wrap(alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start, spacing: 6, runSpacing: 6, children: [
      for (final p in paths)
        GestureDetector(
          onTap: () => openImageViewer(context, title: 'Your picture', builder: (_) => GeneratedImage(path: p, fallback: const SizedBox(), service: images, fit: BoxFit.contain)),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: size, height: size, child: GeneratedImage(path: p, fallback: Container(color: AppColors.surface2), service: images, cacheWidth: (size * 2.5).round()))),
        ),
    ]);
  }
}

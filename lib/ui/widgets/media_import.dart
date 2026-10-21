import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/image_service.dart';
import '../../services/user_media.dart';
import '../../theme/ui.dart';

bool get _hasGallery => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Asks where the pictures come from (photo gallery or files), then copies
/// the chosen ones into the app. Returns an empty list when cancelled.
Future<List<ImportedFile>> chooseImages(BuildContext context, {String title = 'Add your pictures'}) async {
  final images = context.read<ImageService>();
  var source = 'files';
  if (_hasGallery) {
    final picked = await showAppSheet<String>(context, builder: (sheet) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          SheetTitle(title),
          RowGroup(children: [
            ListRow(leading: const Icon(Icons.photo_library_outlined, size: 20), title: 'Photo gallery', subtitle: 'Choose one or more photos', onTap: () => Navigator.pop(sheet, 'gallery')),
            ListRow(leading: const Icon(Icons.folder_open_outlined, size: 20), title: 'Files', subtitle: 'Images saved anywhere on this device', onTap: () => Navigator.pop(sheet, 'files')),
          ]),
        ]));
    if (picked == null) return const [];
    source = picked;
  }
  try {
    return source == 'gallery' ? await importGalleryImages(images) : await importImageFiles(images);
  } catch (e) {
    if (context.mounted) showToast(context, 'Couldn’t add those pictures: $e', icon: Icons.error_outline);
    return const [];
  }
}

/// Picks audio files (music, ambience or sound effects) and copies them in.
Future<List<ImportedFile>> chooseAudio(BuildContext context) async {
  try {
    return await importAudioFiles();
  } on UnsupportedError catch (e) {
    if (context.mounted) showToast(context, e.message ?? 'Not available here.', icon: Icons.info_outline);
  } catch (e) {
    if (context.mounted) showToast(context, 'Couldn’t add those files: $e', icon: Icons.error_outline);
  }
  return const [];
}

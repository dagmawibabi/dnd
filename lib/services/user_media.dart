import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/character.dart' show newId;
import 'image_service.dart';

/// A picked file, already copied into the app so it keeps working if the
/// original is moved or deleted.
class ImportedFile {
  const ImportedFile(this.name, this.path);
  final String name;
  final String path;
}

String _title(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final t = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return t.isEmpty ? 'Untitled' : t[0].toUpperCase() + t.substring(1);
}

/// Pictures from the phone's photo gallery.
Future<List<ImportedFile>> importGalleryImages(ImageService images) async {
  final picked = await ImagePicker().pickMultiImage(maxWidth: 2400, imageQuality: 90);
  return [
    for (final x in picked) ImportedFile(_title(x.name), await images.savePhoto(await x.readAsBytes(), ext: _ext(x.name, 'jpg'))),
  ];
}

/// Pictures from anywhere in the device's files.
Future<List<ImportedFile>> importImageFiles(ImageService images) async {
  final picked = await FilePicker.pickFiles(type: FileType.image, dialogTitle: 'Choose images');
  return [
    for (final f in picked) ImportedFile(_title(f.name), await images.savePhoto(await f.readAsBytes(), ext: _ext(f.name, 'png'))),
  ];
}

/// Songs, ambience or sound effects from the device's files.
Future<List<ImportedFile>> importAudioFiles() async {
  if (kIsWeb) throw UnsupportedError('Adding your own audio files works in the phone and desktop apps.');
  final picked = await FilePicker.pickFiles(type: FileType.audio, dialogTitle: 'Choose audio files');
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}user_audio');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final out = <ImportedFile>[];
  for (final f in picked) {
    final dest = File('${dir.path}${Platform.pathSeparator}${newId()}.${_ext(f.name, 'mp3')}');
    await dest.writeAsBytes(await f.readAsBytes(), flush: true);
    out.add(ImportedFile(_title(f.name), dest.path));
  }
  return out;
}

String _ext(String name, String fallback) {
  final dot = name.lastIndexOf('.');
  final e = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(e) ? e : fallback;
}

/// Removes an imported file from app storage.
Future<void> deleteImported(String path) async {
  if (kIsWeb || path.startsWith('db:') || path.startsWith('data:')) return;
  try {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  } catch (_) {}
}

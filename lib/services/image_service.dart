import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/gateway_client.dart';
import 'db/database.dart';
import 'ai/model_catalog.dart';
import 'settings.dart';

const artStyle = 'Dark fantasy painterly illustration, dramatic chiaroscuro lighting, rich gold and crimson accents, highly detailed, Dungeons & Dragons concept art, no text, no watermark.';

/// D&D art style tuned to the adventure's setting.
String artStyleFor(String setting) {
  final s = setting.toLowerCase();
  final flavor = s.contains('horror') || s.contains('gothic')
      ? 'Gothic horror palette: cold moonlight, fog, deep shadows.'
      : s.contains('pirate') || s.contains('sea') || s.contains('coast')
          ? 'Swashbuckling seafaring palette: sea spray, warm sunset, salt-weathered wood.'
          : s.contains('desert') || s.contains('sand')
              ? 'Sun-scorched desert palette: amber light, heat haze.'
              : s.contains('fey') || s.contains('fairy') || s.contains('whimsical')
                  ? 'Whimsical fey palette: luminous colors, glowing flora.'
                  : s.contains('steampunk') || s.contains('arcane punk')
                      ? 'Arcane-industrial palette: brass, steam and lightning.'
                      : '';
  return flavor.isEmpty ? artStyle : '$artStyle $flavor';
}

/// Generates and caches AI images through the AI Gateway.
class ImageService extends ChangeNotifier {
  ImageService(this.settings, this.catalog);
  final SettingsController settings;
  final ModelCatalog catalog;

  final _memory = <String, Uint8List>{};
  final busy = <String>{};
  final errors = <String, String>{};

  /// Live status of long jobs (videos): key -> "Queued", "Rendering"…
  final status = <String, String>{};

  /// What each generated file cost, by path.
  final costs = <String, double>{};

  /// Kinds of generation ('image', 'video') paused after a failure a retry
  /// won't fix (no credits, bad key, missing model, a usage limit). Stored with
  /// the model and keys in use, so changing them in Settings resumes.
  final _suspended = <String, (String, String)>{};

  String _fingerprint(String kind) => '${kind == 'video' ? settings.videoModel : settings.imageModel}|${settings.apiKey.hashCode}|${settings.openRouterKey.hashCode}';

  bool isSuspended(String kind) {
    final s = _suspended[kind];
    if (s == null) return false;
    if (s.$1 != _fingerprint(kind)) {
      _suspended.remove(kind);
      return false;
    }
    return true;
  }

  /// Turns paused generation back on (Retry).
  void resume() {
    _suspended.clear();
    notifyListeners();
  }

  static bool isHardFailure(Object e) {
    final t = e.toString().toLowerCase();
    if (e is GatewayException && const {401, 402, 403, 404}.contains(e.status)) return true;
    return t.contains('balance') || t.contains('credit') || t.contains('add a') && t.contains('key') || t.contains('limit would be exceeded') || t.contains('reached its limit') || t.contains('pricing is unavailable') || t.contains('cannot generate images') || t.contains('no image twice');
  }

  void _fail(String kind, String key, Object e) {
    // Only the first failure is shown; after that this kind quietly falls back.
    if (!isSuspended(kind)) errors[key] = e.toString();
    if (isHardFailure(e)) _suspended[kind] = (_fingerprint(kind), e.toString());
  }
  final tokens = <String, int>{};

  bool isBusy(String key) => busy.contains(key);

  Future<Directory?> _dir() async {
    if (kIsWeb) return null;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}grimoire_images');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Uint8List? memory(String path) => _memory[path];

  /// Bytes for a `db:` image, from memory or the database (web persistence).
  Future<Uint8List?> loadStored(String path) async {
    final hit = _memory[path];
    if (hit != null) return hit;
    if (!AppDatabase.isOpen) return null;
    final bytes = await AppDatabase.instance.image(path.substring(3));
    if (bytes != null) _memory[path] = bytes;
    return bytes;
  }

  /// Persists bytes where no file system exists (web): SQLite on IndexedDB.
  Future<String> _storeBytes(String key, Uint8List bytes) async {
    final k = 'db:$key';
    _memory[k] = bytes;
    if (AppDatabase.isOpen) await AppDatabase.instance.putImage(key, bytes);
    return k;
  }

  /// Stores a user photo (camera/gallery). Returns a file path, or a data URI on web.
  Future<String> savePhoto(Uint8List bytes, {String ext = 'jpg'}) async {
    final dir = await _dir();
    if (dir == null) return _storeBytes('photo-${DateTime.now().millisecondsSinceEpoch}', bytes);
    final f = File('${dir.path}${Platform.pathSeparator}photo-${DateTime.now().millisecondsSinceEpoch}.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Returns a path (file path or `mem:` key) for the generated image.
  static bool isPortraitKey(String key) => key.startsWith('npc_') || key.startsWith('comp_') || key.startsWith('portrait');

  /// Keeps whole heads in frame; models love to crop at the forehead.
  static const portraitFraming = 'Composition: a square head-and-shoulders portrait, framed from mid-chest up. The ENTIRE head is inside the frame, including the top of the hair, any hat, horns, hood or ears, with clear empty space above the head and on both sides. Center the face slightly above the middle. Do not crop the head. Do not zoom in on the torso or armor.';

  Future<String> _write(String key, Uint8List bytes, String ext) async {
    final dir = await _dir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (dir == null) return _storeBytes('$key-$stamp', bytes);
    final f = File('${dir.path}${Platform.pathSeparator}$key-$stamp.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Bytes of any stored media path (file, `db:` or `data:`).
  Future<Uint8List?> bytesOf(String path) async {
    if (path.startsWith('data:')) return base64Decode(path.substring(path.indexOf(',') + 1));
    if (path.startsWith('db:')) return loadStored(path);
    if (path.startsWith('mem:')) return _memory[path];
    if (kIsWeb) return null;
    final f = File(path);
    return f.existsSync() ? f.readAsBytes() : null;
  }

  /// Saves drawn art (PNG bytes) to the phone's gallery.
  Future<String?> saveBytesToDevice(Uint8List bytes, {String album = 'DnD'}) async {
    if (kIsWeb) return 'Saving to the gallery is not available on the web. Use Share instead.';
    final tmp = await getTemporaryDirectory();
    final file = '${tmp.path}${Platform.pathSeparator}dnd-${DateTime.now().millisecondsSinceEpoch}.png';
    await File(file).writeAsBytes(bytes, flush: true);
    return saveToDevice(file, album: album);
  }

  /// Saves an image or video to the phone's gallery (Photos / Gallery app).
  Future<String?> saveToDevice(String path, {bool video = false, String album = 'DnD'}) async {
    if (kIsWeb) return 'Saving to the gallery is not available on the web. Use Share instead.';
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) return 'Allow photo access to save images.';
      }
      var file = path;
      if (!File(path).existsSync()) {
        final bytes = await bytesOf(path);
        if (bytes == null) return 'The file is missing.';
        final tmp = await getTemporaryDirectory();
        file = '${tmp.path}${Platform.pathSeparator}dnd-${DateTime.now().millisecondsSinceEpoch}.${video ? 'mp4' : 'png'}';
        await File(file).writeAsBytes(bytes, flush: true);
      }
      if (video) {
        await Gal.putVideo(file, album: album);
      } else {
        await Gal.putImage(file, album: album);
      }
      return null;
    } on GalException catch (e) {
      return e.type.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Generates a short video clip. Returns its file path.
  Future<String?> generateVideo(String key, String prompt, {Map<String, num>? usageTarget, String aspect = '16:9'}) async {
    if (!settings.useAiVideo || isSuspended('video')) return null;
    if (busy.contains(key)) return null;
    busy.add(key);
    errors.remove(key);
    status[key] = 'Starting';
    notifyListeners();
    final client = GatewayClient(apiKey: settings.apiKey, category: 'video', target: usageTarget);
    try {
      if (catalog.models.isEmpty) await catalog.ensureLoaded();
      final info = catalog.byId(settings.videoModel);
      var duration = settings.videoDuration;
      if (info != null && info.durations.isNotEmpty && !info.durations.contains(duration)) {
        duration = info.durations.reduce((a, b) => (a - duration).abs() <= (b - duration).abs() ? a : b);
      }
      var res = settings.videoResolution;
      if (info != null && info.resolutions.isNotEmpty && !info.resolutions.map((r) => r.toLowerCase()).contains(res)) {
        res = info.resolutions.first.toLowerCase();
      }
      final media = await client.generateVideo(
        model: settings.videoModel,
        prompt: '$prompt Cinematic, painterly fantasy look, smooth subtle camera motion, no text.',
        duration: duration,
        aspectRatio: aspect,
        resolution: res,
        audio: settings.videoAudio,
        onStatus: (s) {
          status[key] = s;
          notifyListeners();
        },
      );
      final path = await _write(key, media.bytes, media.extension);
      costs[path] = client.spentCost;
      return path;
    } catch (e) {
      _fail('video', key, e);
      return null;
    } finally {
      busy.remove(key);
      status.remove(key);
      client.close();
      notifyListeners();
    }
  }

  Future<String?> generate(String key, String prompt, {String size = '1024x1024', Map<String, num>? usageTarget, String category = 'images', String? style}) async {
    if (!settings.hasApiKey || !settings.canUse(settings.imageModel)) {
      _fail('image', key, GatewayException('Add a key for ${settings.imageModel} in Settings → AI providers to generate images.'));
      notifyListeners();
      return null;
    }
    if (isSuspended('image')) return null;
    if (busy.contains(key)) return null;
    busy.add(key);
    errors.remove(key);
    notifyListeners();
    final client = GatewayClient(apiKey: settings.apiKey, category: category, target: usageTarget);
    try {
      if (catalog.models.isEmpty) await catalog.ensureLoaded();
      final info = catalog.byId(settings.imageModel);
      if (info != null && !info.canMakeImages) throw GatewayException('The selected model cannot generate images. Choose an image model in Settings.');
      if (isPortraitKey(key)) prompt = '$prompt $portraitFraming';
      final multimodal = info?.multimodalImage ?? settings.imageModel.contains('gemini');
      final bytes = await client.generateImage(model: settings.imageModel, prompt: '$prompt\n\nStyle: ${style ?? artStyle}', multimodal: multimodal, size: size);
      final path = await _write(key, bytes, 'png');
      costs[path] = client.spentCost;
      tokens[path] = client.spentTokens;
      return path;
    } catch (e) {
      _fail('image', key, e);
      return null;
    } finally {
      busy.remove(key);
      client.close();
      notifyListeners();
    }
  }
}

/// Displays an AI image if available, otherwise the procedural [fallback].
class GeneratedImage extends StatelessWidget {
  const GeneratedImage({super.key, required this.path, required this.fallback, this.fit = BoxFit.cover, this.service, this.cacheWidth, this.alignment = Alignment.center});

  final Alignment alignment;

  /// Decode width in pixels; small avatars don't need full-size bitmaps.
  final int? cacheWidth;
  final String? path;
  final Widget fallback;
  final BoxFit fit;
  final ImageService? service;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null || p.isEmpty) return fallback;
    if (p.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(p.substring(p.indexOf(',') + 1)), fit: fit, alignment: alignment, gaplessPlayback: true, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
      } catch (_) {
        return fallback;
      }
    }
    if (p.startsWith('db:')) {
      final svc = service;
      final cached = svc?.memory(p);
      if (cached != null) return Image.memory(cached, fit: fit, alignment: alignment, gaplessPlayback: true, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
      if (svc == null) return fallback;
      return FutureBuilder<Uint8List?>(
        future: svc.loadStored(p),
        builder: (context, snap) => snap.data == null ? fallback : Image.memory(snap.data!, fit: fit, alignment: alignment, gaplessPlayback: true, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback),
      );
    }
    if (p.startsWith('mem:')) {
      final bytes = service?.memory(p);
      if (bytes == null) return fallback;
      return Image.memory(bytes, fit: fit, alignment: alignment, gaplessPlayback: true, cacheWidth: cacheWidth);
    }
    if (kIsWeb) return fallback;
    final f = File(p);
    if (!f.existsSync()) return fallback;
    return Image.file(f, fit: fit, alignment: alignment, gaplessPlayback: true, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Rasterizes expensive procedural paintings once and reuses the bitmap.
///
/// Scenes and portraits are drawn from noise and dozens of paths; caching them
/// as images keeps long story feeds and lists smooth.
class PaintCache {
  PaintCache._();

  static const _maxEntries = 48;
  static final _images = <String, ui.Image>{}; // insertion-ordered
  static final _pending = <String, Future<ui.Image?>>{};

  static ui.Image? peek(String key) {
    final img = _images.remove(key);
    if (img != null) _images[key] = img; // mark as recently used
    return img;
  }

  static Future<ui.Image?> render(String key, Size size, double dpr, CustomPainter painter) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);
    return _pending[key] ??= () async {
      try {
        final w = (size.width * dpr).round().clamp(1, 2048);
        final h = (size.height * dpr).round().clamp(1, 2048);
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)..scale(w / size.width, h / size.height);
        painter.paint(canvas, size);
        final img = await rec.endRecording().toImage(w, h);
        _images[key] = img;
        while (_images.length > _maxEntries) {
          _images.remove(_images.keys.first); // may still be on screen; let GC free it
        }
        return img;
      } catch (_) {
        return null;
      } finally {
        _pending.remove(key);
      }
    }();
  }
}

/// Paints [painter] once into a cached bitmap keyed by [cacheKey] and the size.
class CachedPaint extends StatefulWidget {
  const CachedPaint({super.key, required this.cacheKey, required this.painter});
  final String cacheKey;
  final CustomPainter painter;

  @override
  State<CachedPaint> createState() => _CachedPaintState();
}

class _CachedPaintState extends State<CachedPaint> {
  ui.Image? _image;
  String? _forKey;

  void _ensure(String key, Size size, double dpr) {
    if (_forKey == key) return;
    _forKey = key;
    final hit = PaintCache.peek(key);
    if (hit != null) {
      _image = hit;
      return;
    }
    _image = null;
    PaintCache.render(key, size, dpr, widget.painter).then((img) {
      if (mounted && _forKey == key && img != null) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth.isFinite ? box.maxWidth : 100, box.maxHeight.isFinite ? box.maxHeight : 100);
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final key = '${widget.cacheKey}@${size.width.round()}x${size.height.round()}@${dpr.toStringAsFixed(1)}';
      _ensure(key, size, dpr);
      final img = _image;
      if (img != null) return RawImage(image: img, width: size.width, height: size.height, fit: BoxFit.fill);
      return CustomPaint(painter: widget.painter, size: size);
    });
  }
}

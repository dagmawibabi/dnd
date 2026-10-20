import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/adventure.dart';
import '../models/character.dart';
import 'map_painter.dart';
import 'portrait_painter.dart';
import 'scene_painter.dart';

/// Paints procedural art off-screen into a PNG (for saving and sharing).
Future<Uint8List?> paintPng(Size size, void Function(Canvas canvas, Size size) paint) async {
  try {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    paint(canvas, size);
    final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (e) {
    debugPrint('Render failed: $e');
    return null;
  }
}

Future<Uint8List?> portraitPng(PortraitSpec spec, String raceId, {String? classId, double size = 1024}) =>
    paintPng(Size.square(size), (c, s) => PortraitPainter(spec: spec, raceId: raceId, classId: classId, frame: false).paint(c, s));

Future<Uint8List?> scenePng(SceneInfo s, {double width = 1920, double height = 1080}) =>
    paintPng(Size(width, height), (c, size) => ScenePainter(location: s.location, time: s.time, mood: s.mood, seed: s.seed).paint(c, size));

/// The drawn map with labels and the "you are here" marker.
Future<Uint8List?> mapPng(MapState m, {double width = 2000}) {
  final aspect = m.kind == MapKind.dungeon ? 1.5 : (m.kind == MapKind.town ? 40 / 28 : 1.45);
  // Painters lay out in the map screen's 1400-wide space; scale up for detail.
  const base = 1400.0;
  final logical = Size(base, base / aspect);
  final k = width / base;
  return paintPng(Size(width, width / aspect), (c, _) {
    c.scale(k, k);
    MapBasePainter(state: m).paint(c, logical);
    MapMarkerPainter(state: m, showLabels: true).paint(c, logical);
  });
}

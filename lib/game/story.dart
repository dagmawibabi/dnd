import 'dart:convert';

import '../models/adventure.dart';

/// One response from a story engine (AI or offline).
class DmTurn {
  DmTurn({
    required this.narration,
    this.speaker,
    this.scene,
    List<Choice>? choices,
    List<Map<String, dynamic>>? events,
    List<(String, String)>? banter,
    List<Map<String, String>>? memory,
    List<(String, int, String)>? approval,
    this.title,
  })  : choices = choices ?? [],
        events = events ?? [],
        banter = banter ?? [],
        memory = memory ?? [],
        approval = approval ?? [];

  final String narration;
  final String? speaker;
  final SceneInfo? scene;
  final List<Choice> choices;
  final List<Map<String, dynamic>> events;
  final List<(String, String)> banter;

  /// New durable facts for the canon: {kind, name, text}.
  final List<Map<String, String>> memory;

  /// Companion approval changes: (name, change, reason).
  final List<(String, int, String)> approval;
  final String? title;

  /// Tokens and estimated cost of the call that produced this turn.
  int tokens = 0;
  double cost = 0;

  static List<Choice> get _fallbackChoices => [
        Choice(text: 'Continue', type: ChoiceType.explore),
        Choice(text: 'Look around carefully', type: ChoiceType.explore),
      ];

  static DmTurn parse(String raw) {
    final j = extractJsonObject(raw);
    if (j == null) return DmTurn(narration: readableNarration(raw), choices: _fallbackChoices);
    final prose = (j['narration'] ?? j['text'] ?? '').toString().trim();
    if (prose.isEmpty) {
      // A cut-off reply may still hold the start of the narration.
      final partial = partialJsonString(raw, 'narration');
      if (partial == null || partial.trim().isEmpty) throw const FormatException('The AI response was incomplete. Please try again.');
      j['narration'] = partial.trim();
    }
    SceneInfo? scene;
    final s = j['scene'];
    if (s is Map) {
      scene = SceneInfo(
        title: (s['title'] ?? '').toString(),
        location: (s['location_type'] ?? s['location'] ?? 'forest').toString().toLowerCase(),
        time: (s['time'] ?? 'day').toString().toLowerCase(),
        mood: (s['mood'] ?? 'calm').toString().toLowerCase(),
        imagePrompt: (s['image_prompt'] ?? '').toString(),
        weather: (s['weather'] ?? '').toString().toLowerCase(),
      );
    }
    final choices = <Choice>[];
    final cs = j['choices'];
    if (cs is List) {
      for (final c in cs) {
        if (c is String) {
          choices.add(Choice(text: c));
        } else if (c is Map) {
          choices.add(Choice.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    final events = <Map<String, dynamic>>[];
    final ev = j['events'];
    if (ev is List) {
      for (final e in ev) {
        if (e is Map) events.add(Map<String, dynamic>.from(e));
      }
    }
    final banter = <(String, String)>[];
    final b = j['party_banter'] ?? j['banter'];
    if (b is List) {
      for (final x in b) {
        if (x is Map && x['name'] != null && x['line'] != null) banter.add((x['name'].toString(), x['line'].toString()));
      }
    }
    final memory = <Map<String, String>>[];
    final m = j['memory'];
    if (m is List) {
      for (final x in m) {
        if (x is Map && (x['name'] ?? '').toString().trim().isNotEmpty) {
          memory.add({'kind': (x['kind'] ?? 'fact').toString(), 'name': x['name'].toString(), 'text': (x['text'] ?? '').toString()});
        }
      }
    }
    final approval = <(String, int, String)>[];
    final ap = j['approval'];
    if (ap is List) {
      for (final x in ap) {
        if (x is Map && x['name'] != null && x['change'] is num) {
          approval.add((x['name'].toString(), (x['change'] as num).toInt().clamp(-15, 15), (x['reason'] ?? '').toString()));
        }
      }
    }
    final ends = events.any((e) => e['type'] == 'end' || e['type'] == 'combat');
    if (choices.isEmpty && !ends) choices.addAll(_fallbackChoices);
    return DmTurn(
      memory: memory,
      approval: approval,
      narration: (j['narration'] ?? j['text'] ?? '').toString().trim(),
      speaker: j['speaker']?.toString(),
      scene: scene,
      choices: choices,
      events: events,
      banter: banter,
      title: j['adventure_title']?.toString(),
    );
  }
}

/// Recovers prose from an interrupted structured response, including old saves.
/// Never display the JSON envelope as story text.
String readableNarration(String raw) {
  final text = raw.trim();
  if (text.isEmpty) throw const FormatException('The AI sent back an empty reply twice. Tap Try again, or pick a different story model in Settings → Text & story.');
  if (!text.startsWith('{') && !text.startsWith('```') && !RegExp(r'"narration"\s*:').hasMatch(text)) return text;
  final object = extractJsonObject(text);
  final prose = object?['narration'] ?? object?['text'];
  if (prose is String && prose.trim().isNotEmpty) return prose.trim();
  final partial = partialJsonString(text, 'narration') ?? partialJsonString(text, 'text');
  if (partial != null && partial.trim().isNotEmpty) return partial.trim();
  throw const FormatException('The AI response was incomplete. Please try again.');
}

/// Finds and decodes the first JSON object in a model response, repairing the
/// usual model mistakes (raw line breaks in strings, bad escapes, trailing
/// commas, a reply cut off mid-object).
Map<String, dynamic>? extractJsonObject(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)(?:```|$)').firstMatch(s);
  if (fence != null && fence.group(1)!.contains('{')) s = fence.group(1)!.trim();
  final start = s.indexOf('{');
  if (start < 0) return null;
  final strict = _strictObject(s, start);
  if (strict != null) return strict;
  try {
    final v = jsonDecode(repairJson(s.substring(start)));
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  return null;
}

Map<String, dynamic>? _strictObject(String s, int start) {
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (ch == r'\') {
        esc = true;
      } else if (ch == '"') {
        inStr = false;
      }
      continue;
    }
    if (ch == '"') {
      inStr = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        try {
          final v = jsonDecode(s.substring(start, i + 1));
          if (v is Map<String, dynamic>) return v;
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

/// Extracts the (possibly incomplete) value of a string field from a JSON
/// document still being streamed, for live typewriter display.
String? partialJsonString(String raw, String field) {
  final key = RegExp('"$field"\\s*:\\s*"');
  final m = key.firstMatch(raw);
  if (m == null) return null;
  final sb = StringBuffer();
  var i = m.end;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch == r'\') {
      if (i + 1 >= raw.length) break;
      final n = raw[i + 1];
      switch (n) {
        case 'n':
          sb.write('\n');
        case 't':
          sb.write('\t');
        case '"':
          sb.write('"');
        case r'\':
          sb.write(r'\');
        case 'u':
          if (i + 5 < raw.length) {
            final code = int.tryParse(raw.substring(i + 2, i + 6), radix: 16);
            if (code != null) sb.writeCharCode(code);
            i += 4;
          } else {
            return sb.toString();
          }
        default:
          sb.write(n);
      }
      i += 2;
      continue;
    }
    if (ch == '"') break;
    sb.write(ch);
    i++;
  }
  return sb.toString();
}

/// Best-effort repair of almost-JSON from a language model.
String repairJson(String input) {
  const backslash = r'\';
  final sb = StringBuffer();
  final stack = <String>[];
  var inStr = false;
  var i = 0;
  void trimTrailingComma() {
    var t = sb.toString().trimRight();
    if (t.endsWith(',')) t = t.substring(0, t.length - 1);
    sb
      ..clear()
      ..write(t);
  }

  while (i < input.length) {
    final ch = input[i];
    if (inStr) {
      if (ch == backslash) {
        if (i + 1 >= input.length) break;
        final n = input[i + 1];
        if (n == "'") {
          sb.write("'");
        } else if ('"/bfnrtu$backslash'.contains(n)) {
          sb
            ..write(ch)
            ..write(n);
        } else {
          sb
            ..write('$backslash$backslash')
            ..write(n);
        }
        i += 2;
        continue;
      }
      if (ch == '"') {
        // A quote followed by text rather than , : } ] ends nothing: it is an unescaped quote.
        var k = i + 1;
        while (k < input.length && (input[k] == ' ' || input[k] == '\t')) {
          k++;
        }
        final next = k < input.length ? input[k] : '';
        if (next.isEmpty || ',:}]\n\r'.contains(next)) {
          inStr = false;
          sb.write(ch);
        } else {
          sb.write('$backslash"');
        }
        i++;
        continue;
      }
      if (ch == '\n') {
        sb.write('${backslash}n');
      } else if (ch == '\t') {
        sb.write('${backslash}t');
      } else if (ch.codeUnitAt(0) >= 0x20) {
        sb.write(ch);
      }
      i++;
      continue;
    }
    switch (ch) {
      case '"':
        inStr = true;
        sb.write(ch);
      case '{':
        stack.add('}');
        sb.write(ch);
      case '[':
        stack.add(']');
        sb.write(ch);
      case '}' || ']':
        trimTrailingComma();
        if (stack.isNotEmpty) stack.removeLast();
        sb.write(ch);
        if (stack.isEmpty) return sb.toString();
      default:
        sb.write(ch);
    }
    i++;
  }
  // Cut off: close the open string, drop a dangling key or comma, close brackets.
  if (inStr) sb.write('"');
  var t = sb.toString().trimRight();
  if (t.endsWith(':')) t = '$t null';
  if (t.endsWith(',')) t = t.substring(0, t.length - 1);
  if (stack.isNotEmpty && stack.last == '}') {
    // `{"a": 1, "b"` -> drop the orphan key.
    final orphan = RegExp(r',\s*"[^"]*"$').firstMatch(t);
    if (orphan != null) t = t.substring(0, orphan.start);
    final lone = RegExp(r'\{\s*"[^"]*"$').firstMatch(t);
    if (lone != null) t = '${t.substring(0, lone.start)}{';
  }
  return t + stack.reversed.join();
}


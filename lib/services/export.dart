import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../art/scene_painter.dart';
import '../data/tale_genres.dart';
import '../game/story_host.dart';
import '../models/adventure.dart';
import '../models/tale.dart';
import '../models/world.dart';
import '../theme/ui.dart';
import 'achievements.dart';
import 'game_store.dart';
import 'tale_store.dart';
import 'image_service.dart';
import 'settings.dart';
import 'codex_art.dart';
import 'usage.dart';
import 'story_archive.dart';

// ------------------------------------------------------------------ model

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

/// A character in an export, with how they feel about the protagonist.
class ExportPerson {
  ExportPerson({required this.name, this.role = '', this.description = '', this.portrait, this.bond});
  final String name;
  final String role;
  final String description;
  final String? portrait;
  final Bond? bond;
}

/// Everything an export needs, from a D&D adventure or a text adventure.
class ExportDoc {
  ExportDoc({
    required this.title,
    required this.kind,
    required this.byline,
    this.premise = '',
    this.summary = '',
    this.heroName,
    this.heroPortrait,
    this.heroStory = '',
    required this.log,
    this.sceneImages = const {},
    this.people = const [],
    this.canon = const [],
    this.quests = const [],
    this.questLabel = 'Quests',
    this.inventory = const [],
    this.stats = const [],
    this.usage = const {},
    this.gallery = const [],
    this.accent = const Color(0xFF8B7CF6),
    this.ending = '',
    this.notes = const [],
  });
  final List<StoryNote> notes;
  final String title;
  final String kind;
  final String byline;
  final String premise;
  final String summary;
  final String? heroName;
  final String? heroPortrait;
  final String heroStory;
  final List<LogEntry> log;
  final Map<String, String> sceneImages;
  final List<ExportPerson> people;
  final List<CanonEntry> canon;
  final List<Quest> quests;
  final String questLabel;
  final List<String> inventory;
  final List<(String, String)> stats;
  final Map<String, num> usage;
  final List<MediaItem> gallery;
  final Color accent;
  final String ending;

  int get words => log.where((e) => e.kind == LogKind.narration || e.kind == LogKind.dialogue).fold(0, (n, e) => n + e.text.split(RegExp(r'\s+')).length);
}

ExportDoc exportDocFromAdventure(Adventure a) {
  final h = a.hero;
  return ExportDoc(
    title: a.title,
    kind: 'A D&D adventure',
    byline: '${h.name} · level ${h.level} ${h.raceLabel} ${h.classSummary} · ${a.setting}',
    premise: a.premise,
    summary: a.memory,
    heroName: h.name,
    heroPortrait: h.portrait.aiImagePath,
    heroStory: [h.appearance, h.backstory].where((s) => s.trim().isNotEmpty).join('\n\n'),
    log: a.log,
    sceneImages: a.sceneImages,
    people: [for (final n in a.people) ExportPerson(name: n.name, role: n.role, description: n.description, portrait: n.portrait.aiImagePath, bond: a.bonds[n.id])],
    canon: a.canon,
    quests: a.quests,
    inventory: [for (final i in h.inventory) i.qty > 1 ? '${i.name} ×${i.qty}' : i.name],
    stats: [('Turns', '${a.turns}'), ('Level', '${h.level}'), ('Gold', '${h.gold} gp'), ('People met', '${a.people.length}')],
    usage: a.usage,
    gallery: a.gallery,
    notes: a.notes.where((n) => !n.isEmpty).toList(),
    ending: a.finished ? (h.dead ? 'Fallen' : 'Completed') : '',
  );
}

ExportDoc exportDocFromTale(Tale t) {
  final g = genreById(t.genre);
  return ExportDoc(
    title: t.title,
    kind: 'A ${g.name.toLowerCase()} story',
    byline: '${t.protagonist == 'You' ? 'You' : t.protagonist} · ${g.name}${t.engine == TaleEngine.ai ? ' · told with AI' : ''}',
    premise: t.premise,
    summary: t.memory,
    log: t.log,
    sceneImages: t.sceneImages,
    people: [for (final n in t.npcs) ExportPerson(name: n.name, role: n.role, description: n.description, portrait: n.portrait.aiImagePath, bond: t.bonds[n.id])],
    canon: t.canon,
    quests: t.goals,
    questLabel: 'Goals',
    inventory: t.inventory,
    stats: [('Turns', '${t.turns}'), (g.healthLabel, '${t.health}/100'), ('People met', '${t.npcs.length}'), if (t.finished) ('Ending', t.ending)],
    usage: t.usage,
    gallery: t.gallery,
    notes: t.notes.where((n) => !n.isEmpty).toList(),
    accent: g.color,
    ending: t.finished ? '${t.ending[0].toUpperCase()}${t.ending.substring(1)} ending' : '',
  );
}

ExportDoc exportDocFor(StoryHost host) {
  final r = host.record;
  return r is Adventure ? exportDocFromAdventure(r) : exportDocFromTale(r as Tale);
}

// ------------------------------------------------------------------- text

/// The story as Markdown.
String storyMarkdown(ExportDoc d) {
  final b = StringBuffer()
    ..writeln('# ${d.title}')
    ..writeln()
    ..writeln('*${d.kind} · ${d.byline}*')
    ..writeln();
  if (d.premise.isNotEmpty) {
    b
      ..writeln('> ${d.premise}')
      ..writeln();
  }
  for (final e in d.log) {
    switch (e.kind) {
      case LogKind.narration:
        b
          ..writeln(e.text)
          ..writeln();
      case LogKind.dialogue:
        b
          ..writeln('**${e.speaker ?? ''}:** ${e.text}')
          ..writeln();
      case LogKind.companion:
        b
          ..writeln('*${e.speaker ?? ''}:* "${e.text}"')
          ..writeln();
      case LogKind.player:
        b
          ..writeln('**› ${e.text}**')
          ..writeln();
      case LogKind.roll:
        b
          ..writeln('`🎲 ${e.text}`')
          ..writeln();
      case LogKind.oracle:
        b
          ..writeln('`🔮 ${e.meta['q'] ?? ''} → ${e.text}${e.meta['event'] != null ? ' · ${e.meta['event']}' : ''}`')
          ..writeln();
      case LogKind.levelup:
      case LogKind.loot:
        b.writeln('- *${e.text}*');
      case LogKind.combat:
        b.writeln('- ${e.text}');
      case LogKind.system:
        if (e.meta['scene'] != null) {
          b
            ..writeln()
            ..writeln('## ${e.text}')
            ..writeln();
        } else if (e.meta['media'] != null) {
          b
            ..writeln('*✦ ${e.text}*')
            ..writeln();
        } else if (e.meta['bond'] != null) {
          b.writeln('- ♥ ${e.text}');
        }
    }
  }
  if (d.quests.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## ${d.questLabel}');
    for (final q in d.quests) {
      b.writeln('- **${q.title}** (${q.status.name})${q.description.isEmpty ? '' : ': ${q.description}'}');
    }
  }
  if (d.people.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Cast');
    for (final p in d.people) {
      b.writeln('- **${p.name}**${p.role.isEmpty ? '' : ', ${p.role}'}${p.bond == null ? '' : ' — ${p.bond!.label}'}${p.description.isEmpty ? '' : ': ${p.description}'}');
    }
  }
  if (d.notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## My notes');
    for (final n in d.notes) {
      b
        ..writeln()
        ..writeln('### ${n.heading}')
        ..writeln(n.body.trim());
    }
  }
  if (d.canon.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Remembered');
    for (final c in d.canon) {
      b.writeln('- [${c.kind}] **${c.name}**${c.text.isEmpty ? '' : ': ${c.text}'}');
    }
  }
  b
    ..writeln()
    ..writeln('---')
    ..writeln('*Exported from DnD on ${DateTime.now().toIso8601String().substring(0, 10)}.*');
  return b.toString();
}

/// Plain text without Markdown symbols.
String storyText(ExportDoc d) => storyMarkdown(d).replaceAll(RegExp(r'[*`#>]'), '').replaceAll(RegExp(r'\n{3,}'), '\n\n');

// ----------------------------------------------------------------- images

/// Renders the procedural scene art for a scene log entry to PNG.
Future<Uint8List?> renderScenePng(Map scene, {double width = 960, double height = 400}) async {
  try {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    ScenePainter(
      location: (scene['location'] ?? scene['loc'] ?? 'forest').toString(),
      time: (scene['time'] ?? 'day').toString(),
      mood: (scene['mood'] ?? 'calm').toString(),
      seed: (scene['seed'] ?? 1) as int,
    ).paint(canvas, Size(width, height));
    final img = await rec.endRecording().toImage(width.toInt(), height.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (e) {
    debugPrint('Scene render failed: $e');
    return null;
  }
}

Future<Uint8List?> _fileBytes(String? path, ImageService? images) async {
  if (path == null || path.isEmpty) return null;
  final lower = path.toLowerCase();
  if (lower.endsWith('.mp4') || lower.endsWith('.webm') || lower.endsWith('.mov')) return null;
  if (images != null) return images.bytesOf(path);
  if (path.startsWith('data:')) return base64Decode(path.substring(path.indexOf(',') + 1));
  if (kIsWeb) return null;
  final f = File(path);
  return f.existsSync() ? f.readAsBytes() : null;
}

/// Downscales an image so exports stay small.
Future<Uint8List?> shrinkImage(Uint8List bytes, int maxWidth) async {
  try {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = await probe.getNextFrame();
    if (first.image.width <= maxWidth) return bytes;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List() ?? bytes;
  } catch (_) {
    return null;
  }
}

/// Scene, moment and portrait images an export embeds.
class _ExportArt {
  final scenes = <int, Uint8List>{};
  final moments = <int, Uint8List>{};
  final portraits = <String, Uint8List>{};
  Uint8List? cover;
  Uint8List? hero;
}

Future<_ExportArt> _collectArt(ExportDoc d, ImageService? images, {int sceneWidth = 900, int maxScenes = 20}) async {
  final art = _ExportArt();
  for (final (i, e) in d.log.indexed) {
    final s = e.meta['scene'];
    if (s is Map && art.scenes.length < maxScenes) {
      var png = await _fileBytes(d.sceneImages[e.text], images);
      png = png == null ? await renderScenePng(s, width: sceneWidth.toDouble(), height: sceneWidth * 0.42) : await shrinkImage(png, sceneWidth);
      if (png != null) art.scenes[i] = png;
    }
    final m = e.meta['media'];
    if (m is String && art.moments.length < 10) {
      final raw = await _fileBytes(m, images);
      final png = raw == null ? null : await shrinkImage(raw, sceneWidth);
      if (png != null) art.moments[i] = png;
    }
  }
  for (final p in d.people.take(24)) {
    final raw = await _fileBytes(p.portrait, images);
    final png = raw == null ? null : await shrinkImage(raw, 220);
    if (png != null) art.portraits[p.name] = png;
  }
  final heroRaw = await _fileBytes(d.heroPortrait, images);
  if (heroRaw != null) art.hero = await shrinkImage(heroRaw, 320);
  art.cover = art.scenes.values.firstOrNull;
  return art;
}

// ------------------------------------------------------------------- html

String _esc(String s) => const HtmlEscape().convert(s);
String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
String _png(Uint8List b) => 'data:image/png;base64,${base64Encode(b)}';
String _initials(String n) => n.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();

const _htmlStyle = r'''
:root{--bg:#0b0b0d;--fg:#ececf1;--muted:#a1a1aa;--faint:#5f5f68;--card:#16161a;--line:#26262c;--accent:ACCENT;--size:18px}
[data-theme=sepia]{--bg:#f4ecd8;--fg:#3b2f1e;--muted:#7a6a4f;--faint:#a8977a;--card:#ebe0c6;--line:#d8c9a6}
[data-theme=light]{--bg:#fafafa;--fg:#18181b;--muted:#52525b;--faint:#a1a1aa;--card:#f0f0f2;--line:#e4e4e7}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--fg);font:var(--size)/1.75 Georgia,'Iowan Old Style',serif;transition:background .3s,color .3s}
.ui{font-family:system-ui,-apple-system,'Segoe UI',sans-serif}
#progress{position:fixed;top:0;left:0;height:3px;width:0;background:var(--accent);z-index:30}
.bar{position:sticky;top:0;z-index:20;display:flex;gap:8px;align-items:center;padding:10px 16px;background:color-mix(in srgb,var(--bg) 86%,transparent);backdrop-filter:blur(10px);border-bottom:1px solid var(--line);font:14px system-ui,sans-serif}
.bar .t{flex:1;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar button,.bar select,.bar input{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:999px;padding:6px 12px;font:13px system-ui,sans-serif;cursor:pointer}
.bar input{width:150px;cursor:text}
.cover{position:relative;min-height:62vh;display:flex;align-items:flex-end;background:#000 center/cover no-repeat}
.cover::after{content:'';position:absolute;inset:0;background:linear-gradient(180deg,transparent 20%,rgba(0,0,0,.35) 55%,var(--bg))}
.cover .in{position:relative;z-index:1;max-width:760px;margin:0 auto;width:100%;padding:0 22px 28px}
.kind{font:600 12px system-ui,sans-serif;letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
h1{font:800 clamp(34px,7vw,56px)/1.05 system-ui,sans-serif;letter-spacing:-.03em;margin:8px 0 10px;color:#fff;text-shadow:0 2px 24px rgba(0,0,0,.5)}
.cover .by{color:#d4d4d8;font:15px system-ui,sans-serif}
.nocover h1{color:var(--fg);text-shadow:none}.nocover .by{color:var(--muted)}
main{max-width:720px;margin:0 auto;padding:12px 22px 80px}
.premise{font-size:1.1em;font-style:italic;color:var(--muted);border-left:3px solid var(--accent);padding:4px 0 4px 16px;margin:24px 0}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:10px;margin:22px 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 14px}
.stat b{display:block;font:700 20px system-ui,sans-serif}.stat span{font:12px system-ui,sans-serif;color:var(--muted)}
section.ch{scroll-margin-top:64px}
h2{font:700 26px/1.25 system-ui,sans-serif;letter-spacing:-.01em;margin:56px 0 14px;display:flex;align-items:center;gap:10px}
h2 a{color:var(--faint);text-decoration:none;font-size:.6em;opacity:0;transition:opacity .2s}h2:hover a{opacity:1}
.art{margin:6px 0 22px;border-radius:16px;overflow:hidden;cursor:zoom-in;box-shadow:0 20px 50px -25px rgba(0,0,0,.6)}
.art img{width:100%;display:block;transition:transform .6s}.art:hover img{transform:scale(1.02)}
.moment{position:relative}.moment figcaption{position:absolute;left:0;right:0;bottom:0;padding:24px 16px 12px;background:linear-gradient(transparent,rgba(0,0,0,.75));color:#fff;font:14px system-ui,sans-serif}
p{margin:0 0 1.05em}p.first::first-letter{float:left;font:700 3.4em/0.9 Georgia,serif;margin:6px 10px 0 0;color:var(--accent)}
.you{font:600 15px system-ui,sans-serif;color:var(--accent);margin:26px 0 14px;display:flex;gap:8px}
.say{display:flex;gap:12px;align-items:flex-start;margin:0 0 1.1em}
.av{flex:none;width:42px;height:42px;border-radius:50%;background:var(--card) center/cover;border:1px solid var(--line);display:grid;place-items:center;font:700 14px system-ui,sans-serif;color:var(--muted)}
.say .who{font:600 14px system-ui,sans-serif;color:var(--muted);display:block}
.bubble{background:var(--card);border-radius:4px 16px 16px 16px;padding:10px 14px;font:15px/1.55 system-ui,sans-serif}
.mech{font:13px/1.5 ui-monospace,Menlo,monospace;color:var(--muted);margin:3px 0;padding-left:12px;border-left:2px solid var(--line)}
.mech.ok{border-color:#4ade80}.mech.bad{border-color:#f87171}.bond{color:#f472b6}
body.clean .mech{display:none}
.cast{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px}
.person{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px;font:14px/1.5 system-ui,sans-serif}
.person .top{display:flex;gap:10px;align-items:center}.person .av{width:52px;height:52px}
.person h3{margin:0;font-size:16px}.person small{color:var(--muted)}
.meter{height:6px;border-radius:9px;background:var(--line);margin:8px 0 2px;overflow:hidden}.meter i{display:block;height:100%;border-radius:9px}
details{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 16px;margin:10px 0;font:15px/1.6 system-ui,sans-serif}
summary{cursor:pointer;font-weight:600}
mark{background:var(--accent);color:#fff;border-radius:3px}
.hide{display:none!important}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;align-items:center;justify-content:center;z-index:40;cursor:zoom-out}
#lb img{max-width:96vw;max-height:92vh;border-radius:10px}
footer{color:var(--faint);font:13px system-ui,sans-serif;margin-top:64px;text-align:center}
@media print{.bar,#progress,#lb{display:none!important}body{background:#fff;color:#000}.cover{min-height:40vh}section.ch{break-inside:avoid-page}}
''';

const _htmlScript = r'''
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const root=document.documentElement;
const themes=['dark','sepia','light'];let ti=themes.indexOf(localStorage.getItem('dnd-theme')||'dark');if(ti<0)ti=0;root.dataset.theme=themes[ti];
$('#theme').onclick=()=>{ti=(ti+1)%3;root.dataset.theme=themes[ti];localStorage.setItem('dnd-theme',themes[ti]);};
let size=+(localStorage.getItem('dnd-size')||18);const setSize=v=>{size=Math.max(14,Math.min(26,v));root.style.setProperty('--size',size+'px');localStorage.setItem('dnd-size',size)};setSize(size);
$('#smaller').onclick=()=>setSize(size-1);$('#bigger').onclick=()=>setSize(size+1);
$('#clean').onclick=e=>{document.body.classList.toggle('clean');e.target.textContent=document.body.classList.contains('clean')?'Show dice':'Hide dice'};
const toc=$('#toc');if(toc)toc.onchange=()=>{location.hash=toc.value;};
addEventListener('scroll',()=>{const h=document.body.scrollHeight-innerHeight;$('#progress').style.width=(h>0?scrollY/h*100:0)+'%';
 const chs=$$('section.ch');let cur=chs[0];for(const c of chs){if(c.getBoundingClientRect().top<120)cur=c}if(toc&&cur)toc.value='#'+cur.id;},{passive:true});
const lb=$('#lb');$$('.art img').forEach(i=>i.onclick=()=>{lb.firstElementChild.src=i.src;lb.style.display='flex'});lb.onclick=()=>lb.style.display='none';
const q=$('#q');let marks=[];
q.oninput=()=>{const t=q.value.trim().toLowerCase();$$('main p, main .say, main .you').forEach(el=>{el.classList.toggle('hide',!!t&&!el.textContent.toLowerCase().includes(t))});};
addEventListener('keydown',e=>{if(e.target.tagName==='INPUT')return;const chs=$$('section.ch');if(!chs.length)return;
 let i=chs.findIndex(c=>c.getBoundingClientRect().top>130);if(i<0)i=chs.length;
 if(e.key==='j'||e.key==='ArrowRight'){(chs[i]||chs[chs.length-1]).scrollIntoView()}
 if(e.key==='k'||e.key==='ArrowLeft'){(chs[Math.max(0,i-2)]).scrollIntoView()}
 if(e.key==='Escape')lb.style.display='none';});
''';

/// A self-contained, interactive, illustrated story page.
Future<String> storyHtml(ExportDoc d, {ImageService? images}) async {
  final art = await _collectArt(d, images);
  final accent = _hex(d.accent);
  final avatar = <String, String>{for (final e in art.portraits.entries) e.key: _png(e.value)};
  String av(String? name) {
    final src = name == null ? null : avatar[name];
    return src == null ? '<div class="av">${_esc(_initials(name ?? '?'))}</div>' : '<div class="av" style="background-image:url($src)"></div>';
  }

  final chapters = <(String, String)>[];
  final body = StringBuffer();
  var open = false;
  var firstPara = true;
  for (final (i, e) in d.log.indexed) {
    switch (e.kind) {
      case LogKind.narration:
        body.writeln('<p${firstPara ? ' class="first"' : ''}>${_esc(e.text).replaceAll('\n', '<br>')}</p>');
        firstPara = false;
      case LogKind.dialogue:
        body.writeln('<div class="say">${av(e.speaker)}<div><span class="who">${_esc(e.speaker ?? '')}</span>${_esc(e.text).replaceAll('\n', '<br>')}</div></div>');
      case LogKind.companion:
        body.writeln('<div class="say">${av(e.speaker)}<div class="bubble"><span class="who">${_esc(e.speaker ?? '')}</span>${_esc(e.text)}</div></div>');
      case LogKind.player:
        body.writeln('<div class="you">› ${_esc(e.text)}</div>');
      case LogKind.roll:
        body.writeln('<div class="mech ${e.meta['ok'] == true ? 'ok' : 'bad'}">🎲 ${_esc(e.text)}</div>');
      case LogKind.oracle:
        body.writeln('<div class="mech">🔮 ${_esc('${e.meta['q'] ?? ''} → ${e.text}${e.meta['event'] != null ? ' · ${e.meta['event']}' : ''}')}</div>');
      case LogKind.combat:
      case LogKind.loot:
      case LogKind.levelup:
        body.writeln('<div class="mech">${_esc(e.text)}</div>');
      case LogKind.system:
        if (e.meta['scene'] != null) {
          if (open) body.writeln('</section>');
          final id = 'ch${chapters.length + 1}';
          chapters.add((id, e.text));
          body.writeln('<section class="ch" id="$id"><h2>${_esc(e.text)} <a href="#$id" aria-label="Link to chapter">#</a></h2>');
          final img = art.scenes[i];
          if (img != null) body.writeln('<div class="art"><img loading="lazy" alt="${_esc(e.text)}" src="${_png(img)}"></div>');
          open = true;
          firstPara = true;
        } else if (e.meta['media'] != null) {
          final img = art.moments[i];
          if (img != null) body.writeln('<figure class="art moment"><img loading="lazy" alt="" src="${_png(img)}"><figcaption>${_esc(e.text)}</figcaption></figure>');
        } else if (e.meta['bond'] != null) {
          body.writeln('<div class="mech bond">♥ ${_esc(e.text)}</div>');
        }
    }
  }
  if (open) body.writeln('</section>');

  String meter(int value, int min, String color) => '<div class="meter"><i style="width:${((value - min) / (100 - min) * 100).clamp(2, 100).round()}%;background:$color"></i></div>';
  final cast = StringBuffer();
  for (final p in d.people) {
    final b = p.bond;
    cast.writeln('<div class="person"><div class="top">${av(p.name)}<div><h3>${_esc(p.name)}</h3><small>${_esc(p.role)}</small></div></div>');
    if (b != null) {
      cast.writeln('<small>${_esc(b.label)}</small>${meter(b.friendship, -100, b.friendship >= 0 ? '#4ade80' : '#f87171')}');
      if (b.romance > 0) cast.writeln(meter(b.romance, 0, '#f472b6'));
    }
    if (p.description.isNotEmpty) cast.writeln('<p style="margin:8px 0 0;font-size:13px;color:var(--muted)">${_esc(p.description)}</p>');
    cast.writeln('</div>');
  }

  final totalCost = (d.usage['cost'] ?? 0).toDouble();
  final stats = [...d.stats, ('Words', '${d.words}'), if (art.scenes.isNotEmpty || d.gallery.isNotEmpty) ('Illustrations', '${d.gallery.length}'), if (totalCost > 0) ('AI cost', fmtCost(totalCost))];
  final cover = art.cover;
  final html = StringBuffer()
    ..writeln('<!doctype html><html lang="en" data-theme="dark"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    ..writeln('<title>${_esc(d.title)}</title><meta name="description" content="${_esc(d.premise)}">')
    ..writeln('<style>${_htmlStyle.replaceAll('ACCENT', accent)}</style></head><body>')
    ..writeln('<div id="progress"></div>')
    ..writeln('<div class="bar"><span class="t">${_esc(d.title)}</span>')
    ..writeln(chapters.isEmpty ? '' : '<select id="toc" aria-label="Chapters">${chapters.map((c) => '<option value="#${c.$1}">${_esc(c.$2)}</option>').join()}</select>')
    ..writeln('<input id="q" type="search" placeholder="Search…" aria-label="Search the story"><button id="clean">Hide dice</button><button id="smaller" aria-label="Smaller text">A−</button><button id="bigger" aria-label="Larger text">A+</button><button id="theme" aria-label="Change theme">◐</button></div>')
    ..writeln('<header class="cover${cover == null ? ' nocover' : ''}"${cover == null ? '' : ' style="background-image:url(${_png(cover)})"'}><div class="in"><div class="kind">${_esc(d.kind)}</div><h1>${_esc(d.title)}</h1><div class="by">${_esc(d.byline)}${d.ending.isEmpty ? '' : ' · ${_esc(d.ending)}'}</div></div></header>')
    ..writeln('<main>');
  if (d.premise.isNotEmpty) html.writeln('<p class="premise">${_esc(d.premise)}</p>');
  html.writeln('<div class="stats ui">${stats.map((s) => '<div class="stat"><b>${_esc(s.$2)}</b><span>${_esc(s.$1)}</span></div>').join()}</div>');
  if (d.heroName != null && (art.hero != null || d.heroStory.isNotEmpty)) {
    html.writeln('<details open><summary>${_esc(d.heroName!)}</summary><div style="display:flex;gap:14px;align-items:flex-start;margin-top:10px">${art.hero == null ? '' : '<img src="${_png(art.hero!)}" alt="" style="width:96px;border-radius:14px">'}<div>${_esc(d.heroStory).replaceAll('\n', '<br>')}</div></div></details>');
  }
  html
    ..writeln(body.toString())
    ..writeln(d.people.isEmpty ? '' : '<h2>Cast</h2><div class="cast">$cast</div>');
  if (d.quests.isNotEmpty) {
    html.writeln('<details><summary>${_esc(d.questLabel)} (${d.quests.length})</summary><ul>${d.quests.map((q) => '<li>${q.status == QuestStatus.completed ? '✓' : q.status == QuestStatus.failed ? '✗' : '○'} <b>${_esc(q.title)}</b>${q.description.isEmpty ? '' : ' — ${_esc(q.description)}'}</li>').join()}</ul></details>');
  }
  if (d.inventory.isNotEmpty) html.writeln('<details><summary>Inventory (${d.inventory.length})</summary><p>${d.inventory.map(_esc).join(' · ')}</p></details>');
  if (d.summary.isNotEmpty) html.writeln('<details><summary>The story so far</summary><p>${_esc(d.summary)}</p></details>');
  if (d.notes.isNotEmpty) {
    html.writeln('<details open><summary>My notes (${d.notes.length})</summary>${d.notes.map((n) => '<h3 style="margin:14px 0 4px;font-size:16px">${_esc(n.heading)}</h3><p style="white-space:pre-wrap;margin:0">${_esc(n.body.trim())}</p>').join()}</details>');
  }
  if (d.canon.isNotEmpty) {
    html.writeln('<details><summary>Remembered (${d.canon.length})</summary><ul>${d.canon.map((c) => '<li><b>${_esc(c.name)}</b> <small>${_esc(c.kind)}</small>${c.text.isEmpty ? '' : ' — ${_esc(c.text)}'}</li>').join()}</ul></details>');
  }
  html
    ..writeln('<footer>Exported from DnD · ${DateTime.now().toIso8601String().substring(0, 10)} · <span class="ui">J/K or ←/→ to jump chapters</span></footer></main>')
    ..writeln('<div id="lb"><img alt=""></div>')
    ..writeln('<script>$_htmlScript</script></body></html>');
  return html.toString();
}

// -------------------------------------------------------------------- pdf

/// A book-sized, illustrated PDF of the story.
Future<Uint8List> storyPdf(ExportDoc d, {ImageService? images}) async {
  final art = await _collectArt(d, images, sceneWidth: 760, maxScenes: 16);
  pw.Font font;
  try {
    font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
  } catch (_) {
    font = pw.Font.helvetica();
  }
  final accent = PdfColor.fromInt(d.accent.toARGB32());
  final muted = PdfColor.fromHex('#6b6b73');
  final doc = pw.Document(title: d.title, author: d.heroName ?? 'DnD', creator: 'DnD', theme: pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font));
  const format = PdfPageFormat.a5;
  pw.TextStyle st(double size, {PdfColor? color, double height = 1.45}) => pw.TextStyle(fontSize: size, color: color, lineSpacing: size * (height - 1));

  // Cover
  doc.addPage(pw.Page(
    pageFormat: format,
    margin: pw.EdgeInsets.zero,
    build: (ctx) => pw.Stack(children: [
      if (art.cover != null) pw.Positioned.fill(child: pw.Image(pw.MemoryImage(art.cover!), fit: pw.BoxFit.cover)) else pw.Positioned.fill(child: pw.Container(color: PdfColor.fromHex('#111114'))),
      pw.Positioned.fill(child: pw.Container(decoration: pw.BoxDecoration(gradient: pw.LinearGradient(begin: pw.Alignment.topCenter, end: pw.Alignment.bottomCenter, colors: [PdfColor.fromHex('#00000000'), PdfColor.fromHex('#000000E6')])))),
      pw.Positioned(
        left: 32,
        right: 32,
        bottom: 40,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(d.kind.toUpperCase(), style: st(9, color: accent)),
          pw.SizedBox(height: 8),
          pw.Text(d.title, style: st(30, color: PdfColors.white, height: 1.1)),
          pw.SizedBox(height: 8),
          pw.Text(d.byline, style: st(10, color: PdfColor.fromHex('#d4d4d8'))),
          if (d.premise.isNotEmpty) ...[pw.SizedBox(height: 16), pw.Text(d.premise, style: st(10, color: PdfColor.fromHex('#e4e4e7')))],
        ]),
      ),
    ]),
  ));

  final content = <pw.Widget>[];
  for (final (i, e) in d.log.indexed) {
    switch (e.kind) {
      case LogKind.narration:
        content.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Text(e.text, style: st(10.5), textAlign: pw.TextAlign.justify)));
      case LogKind.dialogue:
        content.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '${e.speaker ?? ''}  ', style: st(10, color: accent)), pw.TextSpan(text: e.text, style: st(10.5))])),
        ));
      case LogKind.companion:
        content.add(pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#f1f1f4'), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '${e.speaker ?? ''}: ', style: st(9.5, color: accent)), pw.TextSpan(text: e.text, style: st(9.5))])),
        ));
      case LogKind.player:
        content.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 8), child: pw.Text('›  ${e.text}', style: st(10, color: accent))));
      case LogKind.roll || LogKind.oracle || LogKind.combat || LogKind.loot || LogKind.levelup:
        content.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text(e.text, style: st(8, color: muted))));
      case LogKind.system:
        if (e.meta['scene'] != null) {
          content.add(pw.Header(level: 1, margin: const pw.EdgeInsets.only(top: 14, bottom: 8), decoration: const pw.BoxDecoration(), child: pw.Text(e.text, style: st(16, height: 1.2))));
          final img = art.scenes[i];
          if (img != null) content.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: pw.Image(pw.MemoryImage(img), fit: pw.BoxFit.cover, height: 150, width: double.infinity))));
        } else if (e.meta['media'] != null && art.moments[i] != null) {
          content.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Column(children: [
              pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: pw.Image(pw.MemoryImage(art.moments[i]!), fit: pw.BoxFit.cover, height: 150, width: double.infinity)),
              pw.SizedBox(height: 4),
              pw.Text(e.text, style: st(8.5, color: muted), textAlign: pw.TextAlign.center),
            ]),
          ));
        } else if (e.meta['bond'] != null) {
          content.add(pw.Text('♥ ${e.text}', style: st(8, color: PdfColor.fromHex('#db2777'))));
        }
    }
  }
  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
    header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : pw.Text(d.title, style: st(7.5, color: muted)),
    footer: (ctx) => pw.Align(alignment: pw.Alignment.center, child: pw.Text('${ctx.pageNumber}', style: st(8, color: muted))),
    build: (ctx) => content.isEmpty ? [pw.Text('The story has not begun yet.')] : content,
  ));

  if (d.people.isNotEmpty || d.canon.isNotEmpty) {
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      build: (ctx) => [
        if (d.people.isNotEmpty) ...[
          pw.Text('Cast', style: st(18)),
          pw.SizedBox(height: 10),
          for (final p in d.people)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (art.portraits[p.name] != null) pw.ClipOval(child: pw.Image(pw.MemoryImage(art.portraits[p.name]!), width: 36, height: 36, fit: pw.BoxFit.cover)) else pw.SizedBox(width: 36),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('${p.name}${p.bond == null ? '' : '  ·  ${p.bond!.label}'}', style: st(10.5)),
                    if (p.role.isNotEmpty) pw.Text(p.role, style: st(8.5, color: muted)),
                    if (p.description.isNotEmpty) pw.Text(p.description, style: st(8.5)),
                  ]),
                ),
              ]),
            ),
        ],
        if (d.canon.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text('Remembered', style: st(18)),
          pw.SizedBox(height: 8),
          for (final c in d.canon) pw.Bullet(text: '${c.name}${c.text.isEmpty ? '' : ': ${c.text}'}', style: st(9)),
        ],
      ],
    ));
  }
  return doc.save();
}

// ----------------------------------------------------------------- output

/// Saves (desktop/web) or shares (mobile) a file.
Future<bool> deliverFile(BuildContext context, {required String name, required Uint8List bytes, required String mime, String? text}) async {
  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  try {
    if (mobile) {
      final r = await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: mime, name: name)], fileNameOverrides: [name], text: text, subject: name));
      return r.status != ShareResultStatus.unavailable;
    }
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Save $name');
    return uri != null || kIsWeb;
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not export: $e', icon: Icons.error_outline);
    return false;
  }
}

void showExportSheet(BuildContext context, Adventure a) => showExportFor(context, exportDocFromAdventure(a), record: a);

void showStoryExport(BuildContext context, StoryHost host) => showExportFor(context, exportDocFor(host), record: host.record, canSave: !host.busy);

void showExportFor(BuildContext context, ExportDoc d, {StoryRecord? record, bool canSave = true}) {
  final images = context.read<ImageService>();
  showAppSheet(context, builder: (ctx) {
    String? busy;
    return StatefulBuilder(builder: (ctx, setState) {
      Future<void> run(String what, Future<void> Function() f) async {
        if (busy != null) return;
        setState(() => busy = what);
        try {
          await f();
        } catch (e) {
          if (ctx.mounted) showToast(ctx, 'Export failed: $e', icon: Icons.error_outline);
        } finally {
          if (ctx.mounted) setState(() => busy = null);
        }
      }

      Widget row(IconData icon, String title, String sub, String ext, String mime, Future<Uint8List> Function() make) => ListRow(
            leading: busy == title ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 20),
            title: title,
            subtitle: sub,
            onTap: () => run(title, () async {
              final bytes = await make();
              if (!ctx.mounted) return;
              final ok = await deliverFile(ctx, name: '${_slug(d.title)}.$ext', bytes: bytes, mime: mime);
              if (ok && ctx.mounted) showToast(ctx, 'Exported');
            }),
          );

      return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
        SheetTitle('Export', subtitle: '${d.title} · ${d.log.length} entries · ${d.words} words'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RowGroup(children: [
            if (record != null)
              ListRow(
                leading: const Icon(Icons.save_alt, size: 20),
                title: 'Playable adventure',
                subtitle: canSave ? 'JSON save with progress, notes and available artwork' : 'Wait for the current turn to finish',
                onTap: !canSave ? null : () => run('Playable adventure', () async {
                  final archive = await portableStoryArchive(record, images.bytesOf);
                  if (!ctx.mounted) return;
                  final ok = await deliverFile(ctx, name: '${_slug(d.title)}.adventure.json',
                    bytes: Uint8List.fromList(utf8.encode(jsonEncode(archive))), mime: 'application/json');
                  if (ok && ctx.mounted) {
                    showToast(ctx, archive['missingMedia'] == 0
                      ? 'Adventure saved. Import it from Home to continue.'
                      : 'Adventure saved; ${archive['missingMedia']} unavailable media files could not be included.');
                  }
                }),
              ),
            row(Icons.picture_as_pdf_outlined, 'PDF book', 'Illustrated, book-sized pages with a cover and cast list', 'pdf', 'application/pdf', () => storyPdf(d, images: images)),
            row(Icons.web_outlined, 'Interactive web page', 'Chapters, search, themes, art and your cast — opens in any browser', 'html', 'text/html', () async => Uint8List.fromList(utf8.encode(await storyHtml(d, images: images)))),
            row(Icons.description_outlined, 'Markdown', 'For notes apps, Obsidian or Notion', 'md', 'text/markdown', () async => Uint8List.fromList(utf8.encode(storyMarkdown(d)))),
            row(Icons.notes, 'Plain text', 'Just the story', 'txt', 'text/plain', () async => Uint8List.fromList(utf8.encode(storyText(d)))),
            ListRow(
              leading: const Icon(Icons.copy_outlined, size: 20),
              title: 'Copy to clipboard',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: storyText(d)));
                if (ctx.mounted) showToast(ctx, 'Copied to clipboard');
              },
            ),
          ]),
        ),
      ]);
    });
  });
}

// ----------------------------------------------------------------- backup

Future<StoryRecord?> importStory(BuildContext context) async {
  final games = context.read<GameStore>();
  final tales = context.read<TaleStore>();
  final images = context.read<ImageService>();
  try {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json'], dialogTitle: 'Import playable adventure');
    if (file == null) return null;
    final archive = decodeStoryArchive(utf8.decode(await file.xFile.readAsBytes()));
    final assets = archiveAssets(archive);
    final paths = <String, String>{};
    for (final e in assets.entries) {
      paths[e.key] = await images.savePhoto(e.value.$2, ext: e.value.$1);
    }
    final record = restoreStoryArchive(archive, media: paths);
    if (record is Adventure) {
      await games.saveAdventure(record, syncHero: false);
    } else {
      await tales.save(record as Tale);
    }
    if (context.mounted) showToast(context, 'Adventure imported as a separate save');
    return record;
  } catch (e) {
    if (context.mounted) showToast(context, 'Import failed: $e', icon: Icons.error_outline);
    return null;
  }
}


Future<void> exportBackup(BuildContext context) async {
  final store = context.read<GameStore>();
  final ach = context.read<Achievements>();
  final tales = context.read<TaleStore>();
  final images = context.read<ImageService>();
  final settings = context.read<SettingsController>();
  final codex = context.read<CodexArt?>();
  final data = {
    ...await store.backup(),
    'tales': await tales.backup(),
    'achievements': ach.toJson(),
    'profile': await profileBackup(settings, images),
    if (codex != null) 'codexArt': await codexArtBackup(codex, images),
  };
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  if (!context.mounted) return;
  final ok = await deliverFile(context, name: 'dnd-backup-$stamp.json', bytes: bytes, mime: 'application/json');
  if (ok && context.mounted) showToast(context, 'Backup saved');
}

Future<void> importBackup(BuildContext context) async {
  final store = context.read<GameStore>();
  final ach = context.read<Achievements>();
  try {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json'], dialogTitle: 'Choose a DnD backup');
    if (file == null) return;
    final raw = utf8.decode(await file.xFile.readAsBytes());
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['app'] != 'DnD') throw const FormatException('This is not a DnD backup file.');
    final (c, a, cp) = await store.restore(j);
    if (j['tales'] is List && context.mounted) await context.read<TaleStore>().restore(j['tales'] as List);
    if (j['achievements'] is Map) ach.restore(Map<String, dynamic>.from(j['achievements']));
    if (context.mounted) await restoreProfileAndArt(context, j);
    if (context.mounted) showToast(context, 'Restored $c heroes, $a adventures, $cp campaigns');
  } catch (e) {
    if (context.mounted) showToast(context, 'Import failed: $e', icon: Icons.error_outline);
  }
}


// ------------------------------------------------- profile and codex art

/// Images travel inside the backup as small PNGs.
Future<String?> _packImage(String? path, ImageService images, int width) async {
  if (path == null || path.isEmpty) return null;
  final raw = await images.bytesOf(path);
  if (raw == null) return null;
  final png = await shrinkImage(raw, width);
  return png == null ? null : base64Encode(png);
}

Future<Map<String, dynamic>> profileBackup(SettingsController s, ImageService images) async => {
      'name': s.playerName,
      'bio': s.playerBio,
      'avatar': ?await _packImage(s.playerAvatar, images, 512),
    };

Future<Map<String, String>> codexArtBackup(CodexArt art, ImageService images) async {
  final out = <String, String>{};
  for (final e in art.paths.entries) {
    final packed = await _packImage(e.value, images, 512);
    if (packed != null) out[e.key] = packed;
  }
  return out;
}

/// Puts the profile and codex paintings from a backup back on this device.
Future<void> restoreProfileAndArt(BuildContext context, Map<String, dynamic> j) async {
  final images = context.read<ImageService>();
  final settings = context.read<SettingsController>();
  final codex = context.read<CodexArt?>();
  final p = j['profile'];
  if (p is Map) {
    String? avatar;
    if (p['avatar'] is String) avatar = await images.savePhoto(base64Decode(p['avatar'] as String), ext: 'png');
    settings.update((s) {
      if ((p['name'] ?? '').toString().isNotEmpty) s.playerName = p['name'].toString();
      if ((p['bio'] ?? '').toString().isNotEmpty) s.playerBio = p['bio'].toString();
      if (avatar != null) s.playerAvatar = avatar;
    });
  }
  final art = j['codexArt'];
  if (art is Map && codex != null) {
    final restored = <String, String>{};
    for (final e in art.entries) {
      if (e.value is! String) continue;
      restored[e.key.toString()] = await images.savePhoto(base64Decode(e.value as String), ext: 'png');
    }
    codex.restore(restored);
  }
}

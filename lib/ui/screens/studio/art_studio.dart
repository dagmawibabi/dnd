import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/map_painter.dart';
import '../../../art/monster_painter.dart';
import '../../../art/portrait_painter.dart';
import '../../../art/render_png.dart';
import '../../../art/scene_painter.dart';
import '../../../data/srd.dart';
import '../../../models/adventure.dart';
import '../../../models/character.dart';
import '../../../services/image_service.dart';
import '../../../services/studio.dart';
import '../../../services/user_media.dart' show deleteImported;
import '../../../theme/ui.dart';
import '../../widgets/media_import.dart';
import '../../widgets/media_view.dart';
import 'studio_common.dart';

const sceneLocations = ['forest', 'plains', 'road', 'coast', 'mountain', 'swamp', 'tundra', 'desert', 'town', 'tavern', 'camp', 'castle', 'ruins', 'temple', 'tower', 'dungeon', 'cave', 'crypt', 'sewer'];
const sceneTimes = ['dawn', 'day', 'dusk', 'night'];
const sceneMoods = ['calm', 'mystery', 'eerie', 'tense', 'combat', 'triumph', 'festive', 'sad'];
const creatureTypes = ['humanoid', 'beast', 'undead', 'dragon', 'ooze', 'construct', 'giant', 'monstrosity'];
const creatureColors = [Color(0xFF8B7CF6), Color(0xFF4ADE80), Color(0xFFF87171), Color(0xFF60A5FA), Color(0xFFFBBF24), Color(0xFFA1A1AA), Color(0xFFF472B6), Color(0xFF2DD4BF), Color(0xFF7C2D12)];
const _skins = [Color(0xFFF5D0B5), Color(0xFFE0AC85), Color(0xFFC68B59), Color(0xFF8D5524), Color(0xFF5C3A21), Color(0xFF9DB4C0), Color(0xFFB34747), Color(0xFF6B8E5A)];
const _hairs = [Color(0xFF1C1C1C), Color(0xFF3B2416), Color(0xFF7A4A24), Color(0xFFC9A35C), Color(0xFFE8E2D0), Color(0xFFB0412E), Color(0xFF3F6E9E), Color(0xFF6E3F9E)];
const _eyes = [Color(0xFF4F7FC9), Color(0xFF5E9E4F), Color(0xFF6A4325), Color(0xFFC9A55C), Color(0xFFB3202A), Color(0xFF8A8A9A), Color(0xFF7B4FC9)];

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _mapKindLabel(MapKind k) => switch (k) { MapKind.overworld => 'Region', MapKind.town => 'Town', MapKind.dungeon => 'Dungeon' };

/// Explore the painters behind the game's on-device art: scenes, portraits,
/// creatures and maps. Change anything, keep favourites, save images.
class ArtStudioScreen extends StatefulWidget {
  const ArtStudioScreen({super.key});

  @override
  State<ArtStudioScreen> createState() => _ArtStudioScreenState();
}

class _ArtStudioScreenState extends State<ArtStudioScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 6, vsync: this);
  final _rng = math.Random();

  // Scene
  String _loc = 'forest', _time = 'dusk', _mood = 'calm';
  int _sceneSeed = 7;
  bool _animate = true;

  // Portrait
  String _race = 'human';
  String? _class = 'fighter';
  late PortraitSpec _face = PortraitSpec.random('human', seed: 11);

  // Creature
  String _type = 'dragon';
  Color _color = creatureColors[2];
  int _creatureSeed = 3;
  double _hurt = 0;
  bool _down = false;

  // Map
  MapKind _mapKind = MapKind.overworld;
  int _mapSeed = 42;
  int _mapCount = 6;
  String _mapName = 'The Shattered Coast';
  bool _mapLabels = true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  MapState get _map => MapState(
        kind: _mapKind,
        seed: _mapSeed,
        name: _mapName,
        current: 1,
        locations: [
          for (var i = 0; i < _mapCount; i++) MapLocation(name: _placeName(i), visited: i < 1),
        ],
      );

  String _placeName(int i) {
    final r = math.Random(_mapSeed * 31 + i);
    const a = ['Old', 'Grey', 'Raven', 'Thorn', 'Silver', 'Wolf', 'Ember', 'Hollow', 'Mist', 'Iron'];
    const b = {
      MapKind.overworld: ['Ford', 'Keep', 'Woods', 'Hill', 'Village', 'Tower', 'Pass', 'Mere', 'Ruins', 'Camp'],
      MapKind.town: ['Market', 'Tavern', 'Temple', 'Gate', 'Docks', 'Smithy', 'Square', 'Guildhall', 'Alley', 'Inn'],
      MapKind.dungeon: ['Hall', 'Vault', 'Crypt', 'Shrine', 'Cell', 'Stair', 'Pool', 'Armory', 'Library', 'Throne'],
    };
    return '${a[r.nextInt(a.length)]} ${b[_mapKind]![r.nextInt(10)]}';
  }

  // -------------------------------------------------------- save & load

  Map<String, dynamic> _params(String kind) => switch (kind) {
        'scene' => {'loc': _loc, 'time': _time, 'mood': _mood, 'seed': _sceneSeed},
        'portrait' => {'race': _race, 'class': _class, 'spec': _face.toJson()},
        'creature' => {'type': _type, 'color': _color.toARGB32(), 'seed': _creatureSeed, 'hurt': _hurt, 'down': _down},
        _ => {'kind': _mapKind.name, 'seed': _mapSeed, 'count': _mapCount, 'name': _mapName},
      };

  void _load(ArtPiece p) {
    final j = p.params;
    setState(() {
      switch (p.kind) {
        case 'scene':
          _loc = j['loc'] ?? _loc;
          _time = j['time'] ?? _time;
          _mood = j['mood'] ?? _mood;
          _sceneSeed = j['seed'] ?? 0;
        case 'portrait':
          _race = j['race'] ?? 'human';
          _class = j['class'];
          _face = PortraitSpec.fromJson(Map<String, dynamic>.from(j['spec'] ?? const {}));
        case 'creature':
          _type = j['type'] ?? 'beast';
          _color = Color(j['color'] ?? 0xFF8B7CF6);
          _creatureSeed = j['seed'] ?? 0;
          _hurt = ((j['hurt'] ?? 0) as num).toDouble();
          _down = j['down'] ?? false;
        default:
          _mapKind = MapKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => MapKind.overworld);
          _mapSeed = j['seed'] ?? 1;
          _mapCount = j['count'] ?? 6;
          _mapName = j['name'] ?? 'A map';
      }
    });
    _tabs.animateTo(const ['scene', 'portrait', 'creature', 'map'].indexOf(p.kind).clamp(0, 3));
  }

  Future<void> _keep(String kind, String suggested) async {
    final name = await askName(context, title: 'Add to your collection', initial: suggested);
    if (name == null || !mounted) return;
    context.read<StudioStore>().update((s) => s.art.insert(0, ArtPiece(kind: kind, name: name.isEmpty ? suggested : name, params: _params(kind))));
    showToast(context, 'Added to your collection');
  }

  Future<void> _saveImage(Future<Uint8List?> Function() render) async {
    final images = context.read<ImageService>();
    final png = await render();
    final err = png == null ? 'Could not draw the image.' : await images.saveBytesToDevice(png);
    if (mounted) showToast(context, err ?? 'Saved to your gallery', icon: err == null ? Icons.check_circle_outline : Icons.error_outline);
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Procedural art'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(text: 'Scenes'),
          Tab(text: 'Portraits'),
          Tab(text: 'Creatures'),
          Tab(text: 'Maps'),
          Tab(text: 'My images'),
          Tab(text: 'Collection'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [_scenes(), _portraits(), _creatures(), _maps(), _myImages(), _collection()]),
    );
  }

  Widget _editor({required Widget preview, required double aspect, required List<Widget> controls, required VoidCallback onShuffle, required String kind, required String name, required Future<Uint8List?> Function() png}) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 820;
      final view = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: AspectRatio(aspectRatio: aspect, child: preview)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppButton(label: 'Shuffle', icon: Icons.casino_outlined, kind: ButtonKind.secondary, height: 42, onPressed: onShuffle)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: 'Keep', icon: Icons.bookmark_add_outlined, kind: ButtonKind.secondary, height: 42, onPressed: () => _keep(kind, name))),
          const SizedBox(width: 8),
          CircleIconButton(icon: Icons.download_outlined, size: 42, tooltip: 'Save image to device', onPressed: () => _saveImage(png)),
        ]),
      ]);
      final list = [for (final c in controls) c];
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: Padding(padding: const EdgeInsets.all(16), child: view)),
          Expanded(flex: 4, child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 40), children: list)),
        ]);
      }
      return ListView(padding: const EdgeInsets.only(bottom: 40), children: [Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: view), ...list]);
    });
  }

  Widget _scenes() => _editor(
        kind: 'scene',
        name: '${_cap(_time)} ${_loc == 'camp' ? 'at camp' : 'in the $_loc'}',
        aspect: 16 / 9,
        preview: SceneView(key: ValueKey('$_loc$_time$_mood$_sceneSeed$_animate'), location: _loc, time: _time, mood: _mood, seed: _sceneSeed, animate: _animate, own: false),
        onShuffle: () => setState(() {
          _loc = sceneLocations[_rng.nextInt(sceneLocations.length)];
          _time = sceneTimes[_rng.nextInt(sceneTimes.length)];
          _mood = sceneMoods[_rng.nextInt(sceneMoods.length)];
          _sceneSeed = _rng.nextInt(100000);
        }),
        png: () => scenePng(SceneInfo(location: _loc, time: _time, mood: _mood, seed: _sceneSeed)),
        controls: [
          _ownRow(context.watch<StudioStore>().sceneImages, _loc, 'the ${_cap(_loc).toLowerCase()}'),
          ChipPicker<String>(label: 'Place', options: sceneLocations, value: _loc, labelOf: _cap, onChanged: (v) => setState(() => _loc = v)),
          ChipPicker<String>(label: 'Time of day', options: sceneTimes, value: _time, labelOf: _cap, onChanged: (v) => setState(() => _time = v)),
          ChipPicker<String>(label: 'Mood', options: sceneMoods, value: _mood, labelOf: _cap, onChanged: (v) => setState(() => _mood = v)),
          ParamSlider(label: 'Variation', value: _sceneSeed.toDouble(), min: 0, max: 999, divisions: 999, format: (v) => '#${v.round()}', onChanged: (v) => setState(() => _sceneSeed = v.round())),
          SwitchListTile(title: Text('Animate', style: T.body()), subtitle: Text('Drifting particles, fireflies and embers', style: T.caption()), value: _animate, onChanged: (v) => setState(() => _animate = v)),
        ],
      );

  Widget _portraits() {
    final f = _face;
    Widget swatches(String label, List<Color> colors, Color current, void Function(Color) pick) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: T.body()),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in colors)
                GestureDetector(
                  onTap: () => setState(() => pick(c)),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: c.toARGB32() == current.toARGB32() ? Colors.white : AppColors.border, width: 2)),
                  ),
                ),
            ]),
          ]),
        );
    return _editor(
      kind: 'portrait',
      name: '${raceById(_race).name}${_class == null ? '' : ' ${classes.where((c) => c.id == _class).firstOrNull?.name ?? ''}'}',
      aspect: 1,
      preview: Container(color: AppColors.surface2, child: CustomPaint(painter: PortraitPainter(spec: f, raceId: _race, classId: _class))),
      onShuffle: () => setState(() => _face = PortraitSpec.random(_race, seed: _rng.nextInt(1 << 30))),
      png: () => portraitPng(f, _race, classId: _class),
      controls: [
        ChipPicker<String>(label: 'People', options: [for (final r in races) r.id], value: _race, labelOf: (id) => raceById(id).name, onChanged: (v) => setState(() {
              _race = v;
              _face = PortraitSpec.random(v, seed: f.seed);
            })),
        ChipPicker<String?>(label: 'Calling', options: [null, for (final c in classes) c.id], value: _class, labelOf: (id) => id == null ? 'None' : classes.firstWhere((c) => c.id == id).name, onChanged: (v) => setState(() => _class = v)),
        swatches('Skin', _skins, f.skin, (c) => f.skin = c),
        swatches('Hair', _hairs, f.hair, (c) => f.hair = c),
        swatches('Eyes', _eyes, f.eyes, (c) => f.eyes = c),
        ParamSlider(label: 'Hair style', value: f.hairStyle.toDouble(), min: 0, max: 7, divisions: 7, format: (v) => '${v.round() + 1} of 8', onChanged: (v) => setState(() => f.hairStyle = v.round())),
        ParamSlider(label: 'Beard', value: f.beard.toDouble(), min: 0, max: 3, divisions: 3, format: (v) => const ['None', 'Stubble', 'Short', 'Full'][v.round()], onChanged: (v) => setState(() => f.beard = v.round())),
        ParamSlider(label: 'Features', value: f.feminine, min: 0, max: 1, help: 'From angular to soft', format: (v) => '${(v * 100).round()}%', onChanged: (v) => setState(() => f.feminine = v)),
        ChipPicker<int>(
          label: 'Accessory',
          options: const [0, 1, 2, 3, 4, 5],
          value: f.accessory,
          labelOf: (v) => const ['None', 'Circlet', 'Hood', 'Earring', 'Eyepatch', 'Warpaint'][v],
          onChanged: (v) => setState(() => f.accessory = v),
        ),
        ParamSlider(label: 'Backdrop', value: f.background.toDouble(), min: 0, max: 7, divisions: 7, format: (v) => '${v.round() + 1}', onChanged: (v) => setState(() => f.background = v.round())),
        SwitchListTile(title: Text('Scar', style: T.body()), value: f.scar, onChanged: (v) => setState(() => f.scar = v)),
      ],
    );
  }

  Widget _creatures() => _editor(
        kind: 'creature',
        name: _cap(_type),
        aspect: 1,
        preview: Container(color: AppColors.surface2, padding: const EdgeInsets.all(24), child: CustomPaint(painter: MonsterPainter(type: _type, color: _color, seed: _creatureSeed, hurt: _hurt, down: _down))),
        onShuffle: () => setState(() {
          _type = creatureTypes[_rng.nextInt(creatureTypes.length)];
          _color = creatureColors[_rng.nextInt(creatureColors.length)];
          _creatureSeed = _rng.nextInt(100000);
        }),
        png: () => paintPng(const Size.square(1024), (c, s) => MonsterPainter(type: _type, color: _color, seed: _creatureSeed, hurt: _hurt, down: _down).paint(c, s)),
        controls: [
          ChipPicker<String>(label: 'Kind', options: creatureTypes, value: _type, labelOf: _cap, onChanged: (v) => setState(() => _type = v)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Colour', style: T.body()),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in creatureColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(width: 30, height: 30, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: c == _color ? Colors.white : AppColors.border, width: 2))),
                  ),
              ]),
            ]),
          ),
          ParamSlider(label: 'Variation', value: _creatureSeed.toDouble() % 1000, min: 0, max: 999, divisions: 999, format: (v) => '#${v.round()}', onChanged: (v) => setState(() => _creatureSeed = v.round())),
          ParamSlider(label: 'Wounds', value: _hurt, min: 0, max: 1, format: (v) => '${(v * 100).round()}%', onChanged: (v) => setState(() => _hurt = v)),
          SwitchListTile(title: Text('Defeated', style: T.body()), value: _down, onChanged: (v) => setState(() => _down = v)),
        ],
      );

  Widget _maps() {
    final m = _map;
    final aspect = _mapKind == MapKind.dungeon ? 1.5 : (_mapKind == MapKind.town ? 40 / 28 : 1.45);
    return _editor(
      kind: 'map',
      name: _mapName,
      aspect: aspect,
      preview: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: MapBasePainter(state: m)),
        CustomPaint(painter: MapMarkerPainter(state: m, showLabels: _mapLabels, scale: 0.6)),
      ]),
      onShuffle: () => setState(() => _mapSeed = _rng.nextInt(1 << 20)),
      png: () => mapPng(m),
      controls: [
        _ownRow(context.watch<StudioStore>().mapImages, _mapKind.name, '${_mapKindLabel(_mapKind).toLowerCase()} maps'),
        ChipPicker<MapKind>(label: 'Kind', options: MapKind.values, value: _mapKind, labelOf: _mapKindLabel, onChanged: (v) => setState(() => _mapKind = v)),
        ParamSlider(label: 'Places', value: _mapCount.toDouble(), min: 3, max: 10, divisions: 7, format: (v) => '${v.round()}', onChanged: (v) => setState(() => _mapCount = v.round())),
        ParamSlider(label: 'Land', value: (_mapSeed % 1000).toDouble(), min: 0, max: 999, divisions: 999, format: (v) => '#${v.round()}', onChanged: (v) => setState(() => _mapSeed = v.round())),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextFormField(initialValue: _mapName, style: T.body(), decoration: const InputDecoration(labelText: 'Name'), onChanged: (v) => setState(() => _mapName = v)),
        ),
        SwitchListTile(title: Text('Labels', style: T.body()), value: _mapLabels, onChanged: (v) => setState(() => _mapLabels = v)),
      ],
    );
  }

  /// "2 of your pictures show for the forest in stories" with a way to change it.
  Widget _ownRow(Map<String, List<String>> slots, String key, String what) {
    final n = slots[key]?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        color: n > 0 ? AppColors.accentSoft : null,
        child: Row(children: [
          Icon(Icons.photo_library_outlined, size: 20, color: n > 0 ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(n == 0 ? 'Use your own pictures for $what in stories' : '$n of your ${n == 1 ? 'pictures shows' : 'pictures show'} for $what in stories', style: T.small(color: AppColors.text))),
          TextButton(onPressed: () => _pickOwnFor(slots, key, what), child: Text(n == 0 ? 'Add' : 'Change')),
        ]),
      ),
    );
  }

  Future<void> _pickOwnFor(Map<String, List<String>> slots, String key, String what) async {
    final studio = context.read<StudioStore>();
    await showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
          return SizedBox(
            height: MediaQuery.sizeOf(sheet).height * 0.75,
            child: Column(children: [
              SheetTitle('Pictures for $what', subtitle: 'Tick one or more. Stories pick one for each scene.'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppButton(
                  label: 'Add from gallery or files',
                  icon: Icons.add_photo_alternate_outlined,
                  kind: ButtonKind.secondary,
                  height: 42,
                  onPressed: () async {
                    final added = await _importImages();
                    if (added.isEmpty) return;
                    studio.update((s) => slots.putIfAbsent(key, () => []).addAll([for (final a in added) a.id]));
                    set(() {});
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: studio.images.isEmpty
                    ? const EmptyState(icon: Icons.photo_outlined, title: 'No pictures yet', message: 'Add pictures from your gallery or files.')
                    : GridView.count(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        crossAxisCount: MediaQuery.sizeOf(sheet).width > 600 ? 4 : 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [
                          for (final img in studio.images)
                            Builder(builder: (context) {
                              final on = slots[key]?.contains(img.id) ?? false;
                              return GestureDetector(
                                onTap: () {
                                  studio.update((_) => StudioStore.toggle(slots, key, img.id, !on));
                                  set(() {});
                                },
                                child: Stack(fit: StackFit.expand, children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(10), child: MediaView(path: img.path, fallback: const ColoredBox(color: AppColors.surface2))),
                                  Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? AppColors.accent : Colors.transparent, width: 3))),
                                  if (on) const Positioned(right: 6, top: 6, child: Icon(Icons.check_circle, color: AppColors.accent)),
                                ]),
                              );
                            }),
                        ],
                      ),
              ),
            ]),
          );
        }));
  }

  Future<List<StudioImage>> _importImages() async {
    final files = await chooseImages(context);
    if (files.isEmpty || !mounted) return const [];
    final added = [for (final f in files) StudioImage(name: f.name, path: f.path)];
    context.read<StudioStore>().update((s) => s.images.addAll(added));
    showToast(context, 'Added ${added.length} ${added.length == 1 ? 'picture' : 'pictures'}');
    return added;
  }

  Widget _myImages() {
    final studio = context.watch<StudioStore>();
    final cols = MediaQuery.sizeOf(context).width > 700 ? 4 : 2;
    String uses(StudioImage img) => [
          for (final e in studio.sceneImages.entries) if (e.value.contains(img.id)) _cap(e.key),
          for (final e in studio.mapImages.entries) if (e.value.contains(img.id)) '${_mapKindLabel(MapKind.values.firstWhere((k) => k.name == e.key, orElse: () => MapKind.overworld))} map',
        ].join(', ');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Bring your own art. Give a picture to places (forest, tavern, crypt…) or kinds of map, and stories show it instead of the painted version. Inside a story you can also use a picture for just the current scene or map.', style: T.small()),
      const SizedBox(height: 12),
      AppButton(label: 'Add from gallery or files', icon: Icons.add_photo_alternate_outlined, onPressed: _importImages),
      const SizedBox(height: 16),
      if (studio.images.isEmpty)
        const EmptyState(icon: Icons.photo_outlined, title: 'No pictures yet', message: 'Pictures you add appear here.')
      else
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: [
            for (final img in studio.images)
              AppCard(
                padding: EdgeInsets.zero,
                onTap: () => _imageSheet(img),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: MediaView(path: img.path, fallback: const ColoredBox(color: AppColors.surface2)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(img.name, style: T.small(color: AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(uses(img).isEmpty ? 'Not used yet' : uses(img), style: T.caption(color: uses(img).isEmpty ? AppColors.textFaint : AppColors.accent), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
    ]);
  }

  Future<void> _imageSheet(StudioImage img) => showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
        final studio = context.read<StudioStore>();
        Widget chip(String label, Map<String, List<String>> slots, String key) {
          final on = slots[key]?.contains(img.id) ?? false;
          return FilterChip(
            label: Text(label),
            selected: on,
            onSelected: (v) {
              studio.update((_) => StudioStore.toggle(slots, key, img.id, v));
              set(() {});
            },
          );
        }

        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.85,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            SheetTitle(img.name),
            ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: 16 / 9, child: MediaView(path: img.path, fallback: const ColoredBox(color: AppColors.surface2)))),
            const SectionLabel('Show for these places'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final l in sceneLocations) chip(_cap(l), studio.sceneImages, l)]),
            const SectionLabel('Show for these maps'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final k in MapKind.values) chip(_mapKindLabel(k), studio.mapImages, k.name)]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: AppButton(label: 'Rename', icon: Icons.edit_outlined, kind: ButtonKind.secondary, height: 42, onPressed: () async {
                  final n = await askName(context, title: 'Rename picture', initial: img.name);
                  if (n != null && n.isNotEmpty) {
                    studio.update((_) => img.name = n);
                    set(() {});
                  }
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(label: 'Remove', icon: Icons.delete_outline, kind: ButtonKind.secondary, height: 42, onPressed: () async {
                  if (!await confirm(context, title: 'Remove "${img.name}"?', message: 'Places and maps using it go back to the painted art.', action: 'Remove')) return;
                  studio.update((s) => s.images.remove(img));
                  unawaited(deleteImported(img.path));
                  if (sheet.mounted) Navigator.pop(sheet);
                }),
              ),
            ]),
          ]),
        );
      }));

  Widget _collection() {
    final studio = context.watch<StudioStore>();
    if (studio.art.isEmpty) {
      return const EmptyState(icon: Icons.collections_outlined, title: 'Nothing kept yet', message: 'Tap Keep on any scene, portrait, creature or map to collect it here. Tap a piece to open it again.');
    }
    final cols = MediaQuery.sizeOf(context).width > 700 ? 4 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.9),
      itemCount: studio.art.length,
      itemBuilder: (context, i) {
        final p = studio.art[i];
        return AppCard(
          padding: EdgeInsets.zero,
          onTap: () => _load(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: _thumb(p))),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: T.small(color: AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(_cap(p.kind), style: T.caption()),
                  ]),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => studio.update((s) => s.art.remove(p)),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _thumb(ArtPiece p) {
    final j = p.params;
    try {
      switch (p.kind) {
        case 'scene':
          return SceneView(location: j['loc'] ?? 'forest', time: j['time'] ?? 'day', mood: j['mood'] ?? 'calm', seed: j['seed'] ?? 0, own: false);
        case 'portrait':
          return Container(color: AppColors.surface2, child: CustomPaint(painter: PortraitPainter(spec: PortraitSpec.fromJson(Map<String, dynamic>.from(j['spec'] ?? const {})), raceId: j['race'] ?? 'human', classId: j['class'])));
        case 'creature':
          return Container(
            color: AppColors.surface2,
            padding: const EdgeInsets.all(12),
            child: CustomPaint(painter: MonsterPainter(type: j['type'] ?? 'beast', color: Color(j['color'] ?? 0xFF8B7CF6), seed: j['seed'] ?? 0, hurt: ((j['hurt'] ?? 0) as num).toDouble(), down: j['down'] ?? false)),
          );
        default:
          final kind = MapKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => MapKind.overworld);
          final m = MapState(kind: kind, seed: j['seed'] ?? 1, name: j['name'] ?? '', current: 1, locations: [for (var i = 0; i < (j['count'] ?? 6); i++) MapLocation(name: '${i + 1}', visited: i < 1)]);
          return CustomPaint(painter: MapPainter(state: m));
      }
    } catch (_) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
  }
}

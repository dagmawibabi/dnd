import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/tale_genres.dart';
import '../../../game/archive_host.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../models/world.dart';
import '../../../services/game_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/tale_store.dart';
import '../../../theme/ui.dart';
import '../../widgets/portrait.dart';
import 'cover_screen.dart';
import 'story_tools.dart' show showPersonSheet, romanceColor;

class _Met {
  _Met(this.npc, this.host);
  final Npc npc;
  final ArchiveHost host;
  Bond get bond => host.world.bondFor(npc);
  int get chats => host.world.chats[npc.id]?.length ?? 0;
  DateTime get last {
    final c = host.world.chats[npc.id];
    final b = bond.moments;
    final times = [if (c != null && c.isNotEmpty) c.last.at, if (b.isNotEmpty) b.last.at];
    if (times.isEmpty) return host.record is Adventure ? (host.record as Adventure).updatedAt : (host.record as Tale).updatedAt;
    return times.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

Future<void> openCharacterHistory(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CharacterHistoryScreen()));

/// Everyone you have met, in every story: tap anyone for their profile.
class CharacterHistoryScreen extends StatefulWidget {
  const CharacterHistoryScreen({super.key});

  @override
  State<CharacterHistoryScreen> createState() => _CharacterHistoryScreenState();
}

class _CharacterHistoryScreenState extends State<CharacterHistoryScreen> {
  List<_Met>? _all;
  String _q = '';
  String _filter = 'all';
  String _sort = 'recent';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final games = context.read<GameStore>();
    final tales = context.read<TaleStore>();
    final settings = context.read<SettingsController>();
    final images = context.read<ImageService>();
    final narrator = context.read<Narrator>();
    final out = <_Met>[];
    for (final s in games.adventures.toList()) {
      final a = await games.loadAdventure(s.id);
      if (a == null) continue;
      final host = ArchiveHost(a, settings: settings, images: images, narrator: narrator, onSave: () => games.saveAdventure(a, syncHero: false));
      for (final p in a.people) {
        out.add(_Met(p, host));
      }
    }
    for (final s in tales.tales.toList()) {
      final t = await tales.load(s.id);
      if (t == null) continue;
      final host = ArchiveHost(t, settings: settings, images: images, narrator: narrator, onSave: () => tales.save(t));
      for (final p in t.npcs) {
        out.add(_Met(p, host));
      }
    }
    if (mounted) setState(() => _all = out);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = (all ?? const <_Met>[]).where((m) {
      if (_q.isNotEmpty && !'${m.npc.name} ${m.npc.role} ${m.host.storyTitle}'.toLowerCase().contains(_q)) return false;
      return switch (_filter) {
        'friends' => m.bond.friendship >= 20,
        'enemies' => m.bond.isHostile,
        'romance' => m.bond.isRomantic,
        'talked' => m.chats > 0,
        'dnd' => m.host.record is Adventure,
        'tales' => m.host.record is Tale,
        _ => true,
      };
    }).toList();
    shown.sort((a, b) => switch (_sort) {
          'name' => a.npc.name.toLowerCase().compareTo(b.npc.name.toLowerCase()),
          'close' => b.bond.friendship.compareTo(a.bond.friendship),
          _ => b.last.compareTo(a.last),
        });
    final counts = all == null
        ? const <String, int>{}
        : {
            'friends': all.where((m) => m.bond.friendship >= 20).length,
            'enemies': all.where((m) => m.bond.isHostile).length,
            'romance': all.where((m) => m.bond.isRomantic).length,
            'talked': all.where((m) => m.chats > 0).length,
          };
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Characters you\'ve met', style: T.h3()),
          Text(all == null ? 'Gathering everyone…' : '${all.length} people across ${{for (final m in all) m.host.storyId}.length} stories', style: T.caption()),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('Most recent')),
              PopupMenuItem(value: 'close', child: Text('Closest first')),
              PopupMenuItem(value: 'name', child: Text('Name')),
            ],
          ),
        ],
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ContentWidth(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search names, roles, stories', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (id, label) in [('all', 'Everyone'), ('friends', 'Friends ${counts['friends']}'), ('romance', 'Romances ${counts['romance']}'), ('enemies', 'Enemies ${counts['enemies']}'), ('talked', 'Talked to ${counts['talked']}'), ('dnd', 'D&D'), ('tales', 'Text adventures')])
                      Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
                  ]),
                ),
                const SizedBox(height: 10),
                if (shown.isEmpty) EmptyState(icon: Icons.people_outline, title: all.isEmpty ? 'No one yet' : 'Nobody matches', message: all.isEmpty ? 'Everyone you meet in your stories is gathered here.' : null),
                for (final m in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () async {
                        await showPersonSheet(context, m.host, m.npc);
                        if (mounted) setState(() {});
                      },
                      child: Row(children: [
                        Opacity(opacity: m.npc.alive ? 1 : 0.45, child: NpcPortrait(npc: m.npc, size: 50)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(m.npc.name, style: T.h3(), overflow: TextOverflow.ellipsis)),
                              Tag(m.bond.label, color: m.bond.isRomantic ? romanceColor : (m.bond.isHostile ? AppColors.danger : AppColors.info)),
                            ]),
                            const SizedBox(height: 2),
                            Text([if (m.npc.role.isNotEmpty) m.npc.role, if (!m.npc.alive) 'Dead'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption()),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => m.host.record is Adventure ? openAdventureCover(context, m.host.storyId) : openTaleCover(context, m.host.storyId),
                              child: Row(children: [
                                Icon(m.host.record is Adventure ? Icons.shield_outlined : genreById((m.host.record as Tale).genre).icon, size: 12, color: AppColors.textFaint),
                                const SizedBox(width: 4),
                                Expanded(child: Text('${m.host.storyTitle}${m.chats > 0 ? ' · ${m.chats} messages' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: AppColors.textMuted))),
                              ]),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }
}

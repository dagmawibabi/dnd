import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/campaign.dart';
import '../../services/game_store.dart';
import '../../theme/ui.dart';
import '../widgets/portrait.dart';
import 'adventure/campaign_flow.dart';
import 'adventure/sheets.dart' show editTextDialog;
import 'home_screen.dart' show openAdventure;

class CampaignScreen extends StatelessWidget {
  const CampaignScreen({super.key, required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final camp = store.campaign(campaignId);
    if (camp == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.auto_stories_outlined, title: 'Campaign not found'));
    final hero = store.character(camp.heroId);
    final chapters = [for (final id in camp.chapters) (id, store.adventures.where((a) => a.id == id).firstOrNull)];
    final last = chapters.isEmpty ? null : chapters.last.$2;
    return Scaffold(
      appBar: AppBar(
        title: Text(camp.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) async {
              if (v == 'rename') {
                final n = await editTextDialog(context, title: 'Rename campaign', initial: camp.name);
                if (n != null && n.trim().isNotEmpty) {
                  camp.name = n.trim();
                  store.saveCampaign(camp);
                }
              }
              if (v == 'delete' && context.mounted) {
                if (await confirm(context, title: 'Delete campaign?', message: 'The chapters stay in your adventures; only the campaign link and its memory are removed.')) {
                  await store.deleteCampaign(camp.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete campaign')),
            ],
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          AppCard(
            child: Row(children: [
              if (hero != null) CharacterPortrait(character: hero, size: 56, viewable: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(hero?.name ?? 'Unknown hero', style: T.h3()),
                  Text(hero == null ? '' : 'Level ${hero.level} ${hero.raceLabel} ${hero.classSummary}', style: T.small()),
                  const SizedBox(height: 6),
                  Text('${camp.chapters.length} ${camp.chapters.length == 1 ? 'chapter' : 'chapters'} · ${camp.canon.length} facts remembered', style: T.caption()),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (last != null && !last.finished)
            AppButton(label: 'Continue chapter ${chapters.length}', icon: Icons.play_arrow_rounded, onPressed: () => openAdventure(context, last.id))
          else if (last != null && !(hero?.dead ?? false))
            AppButton(
              label: 'Begin chapter ${chapters.length + 1}',
              icon: Icons.auto_stories_outlined,
              kind: ButtonKind.accent,
              onPressed: () async {
                final adv = await store.loadAdventure(last.id);
                if (adv != null && context.mounted) startNextChapter(context, adv);
              },
            ),
          const SectionLabel('Chapters'),
          RowGroup(children: [
            for (final (i, (id, s)) in chapters.indexed)
              ListRow(
                leading: CircleAvatar(radius: 14, backgroundColor: AppColors.surface3, child: Text('${i + 1}', style: T.caption(color: AppColors.text))),
                title: s?.title ?? 'Missing chapter',
                subtitle: s == null ? 'This adventure was deleted' : '${s.finished ? 'Completed' : 'In progress'} · ${s.turns} turns · level ${s.level}',
                trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
                onTap: s == null ? null : () => openAdventure(context, id),
              ),
          ]),
          SectionLabel('Story so far', trailing: GestureDetector(onTap: () => _editSummary(context, store, camp), child: Text('Edit', style: T.caption(color: AppColors.textMuted)))),
          AppCard(child: Text(camp.summary.isEmpty ? 'The summary grows with each chapter.' : camp.summary, style: T.small(color: camp.summary.isEmpty ? AppColors.textFaint : AppColors.text))),
          if (camp.canon.isNotEmpty) ...[
            SectionLabel('Remembered · ${camp.canon.length}'),
            RowGroup(children: [
              for (final c in camp.canon)
                ListRow(
                  title: c.name,
                  subtitle: '${c.kind}${c.text.isEmpty ? '' : ' · ${c.text}'}',
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
                    onPressed: () {
                      camp.canon.remove(c);
                      store.saveCampaign(camp);
                    },
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _editSummary(BuildContext context, GameStore store, Campaign camp) async {
    final t = await editTextDialog(context, title: 'Story so far', initial: camp.summary, lines: 8);
    if (t != null) {
      camp.summary = t.trim();
      store.saveCampaign(camp);
    }
  }
}

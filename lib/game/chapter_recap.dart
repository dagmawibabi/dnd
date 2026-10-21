import '../models/adventure.dart';
import '../models/chronicle.dart';
import '../models/tale.dart';
import '../models/world.dart';

/// How one relationship moved during a chapter.
class BondShift {
  BondShift({required this.person, required this.bond, required this.friendship, required this.romance, required this.moments});
  final Npc person;
  final Bond bond;
  final int friendship;
  final int romance;
  final List<BondMoment> moments;
}

/// Everything that changed during one chapter, for the end-of-chapter screen.
class ChapterChanges {
  ChapterChanges({
    required this.title,
    required this.turns,
    required this.changes,
    required this.reputation,
    required this.bonds,
    required this.arcs,
    required this.completed,
    required this.failed,
    required this.open,
    required this.campDays,
    required this.conversations,
    required this.approaches,
    required this.peopleKnown,
  });
  final String title;
  final int turns;

  /// World changes recorded in this chapter, oldest first.
  final List<WorldChange> changes;

  /// Faction -> standing now, for factions whose standing moved this chapter.
  final Map<String, int> reputation;
  final List<BondShift> bonds;
  final List<CompanionArc> arcs;
  final List<Quest> completed, failed, open;
  final int campDays;

  /// Lines exchanged in private conversations this chapter.
  final int conversations;

  /// Times someone came to the player on their own.
  final int approaches;
  final int peopleKnown;

  bool get isEmpty => changes.isEmpty && bonds.isEmpty && arcs.isEmpty && completed.isEmpty && failed.isEmpty;

  /// Changes grouped by kind, in the order kinds first appeared.
  Map<String, List<WorldChange>> get byKind {
    final out = <String, List<WorldChange>>{};
    for (final c in changes.where((c) => c.kind != 'camp')) {
      out.putIfAbsent(c.kind, () => []).add(c);
    }
    return out;
  }

  /// A plain-text version for sharing.
  String toText() {
    final b = StringBuffer('What changed: $title\n');
    b.writeln('$turns turns · ${changes.length} world changes · $campDays days at camp');
    for (final e in byKind.entries) {
      b.writeln('\n${kindTitle(e.key)}');
      for (final c in e.value) {
        b.writeln('- ${c.name}: ${c.before.isEmpty ? '' : '${c.before} → '}${c.after} (${c.reason})');
      }
    }
    if (reputation.isNotEmpty) {
      b.writeln('\nReputation');
      for (final e in reputation.entries) {
        b.writeln('- ${e.key}: ${e.value > 0 ? '+' : ''}${e.value}');
      }
    }
    if (bonds.isNotEmpty) {
      b.writeln('\nRelationships');
      for (final s in bonds) {
        b.writeln('- ${s.person.name}: ${s.bond.label} (friendship ${_signed(s.friendship)}${s.romance != 0 ? ', romance ${_signed(s.romance)}' : ''})');
      }
    }
    if (arcs.isNotEmpty) {
      b.writeln('\nCompanion stories');
      for (final a in arcs) {
        b.writeln('- ${a.name}: ${a.title} · ${stageLabel(a.stage)}${a.outcome.isEmpty ? '' : ' · ${a.outcome}'}');
      }
    }
    if (completed.isNotEmpty || failed.isNotEmpty) {
      b.writeln('\nQuests');
      for (final q in completed) {
        b.writeln('✓ ${q.title}');
      }
      for (final q in failed) {
        b.writeln('✗ ${q.title}');
      }
    }
    return b.toString().trim();
  }
}

String _signed(int n) => n > 0 ? '+$n' : '$n';

String kindTitle(String kind) => switch (kind) {
      'place' => 'Places',
      'faction' => 'Factions',
      'npc' || 'person' => 'People',
      'companion' => 'Companions',
      'item' => 'Items & treasures',
      'quest' => 'Quests',
      'camp' => 'Camp',
      'lore' => 'Lore',
      _ => kind.isEmpty ? 'Other' : '${kind[0].toUpperCase()}${kind.substring(1)}',
    };

String stageLabel(String stage) => switch (stage) {
      'revealed' => 'Revealed',
      'pursuing' => 'Following leads',
      'choice' => 'Final decision',
      'resolved' => 'Resolved',
      'failed' => 'Failed',
      'departed' => 'Departed',
      _ => stage,
    };

/// Builds the summary of the chapter [record] (an [Adventure] or a [Tale]).
ChapterChanges summarizeChapter(StoryRecord record, List<Npc> people) {
  final w = record as WorldData;
  final id = record.id;
  final (title, turns, since, quests) = switch (record) {
    Adventure a => (a.title, a.turns, a.createdAt, a.quests),
    Tale t => (t.title, t.turns, t.createdAt, t.goals),
    _ => ('This chapter', 0, DateTime.fromMillisecondsSinceEpoch(0), <Quest>[]),
  };
  final changes = [for (final h in w.chronicle.history) if (h.chapter == id) h];
  final touched = {for (final c in changes) c.name.toLowerCase()};
  final reputation = <String, int>{
    for (final f in w.chronicle.facts)
      if (f.reputation != 0 && touched.contains(f.name.toLowerCase())) f.name: f.reputation,
  };
  final bonds = <BondShift>[];
  for (final p in people) {
    final b = w.bonds[p.id];
    if (b == null) continue;
    final moments = [for (final m in b.moments) if (!m.at.isBefore(since)) m];
    if (moments.isEmpty) continue;
    bonds.add(BondShift(
      person: p,
      bond: b,
      friendship: moments.fold(0, (n, m) => n + m.friendship),
      romance: moments.fold(0, (n, m) => n + m.romance),
      moments: moments,
    ));
  }
  bonds.sort((a, b) => (b.friendship.abs() + b.romance.abs()).compareTo(a.friendship.abs() + a.romance.abs()));
  final arcNames = {for (final c in changes) if (c.kind == 'companion') c.name.toLowerCase()};
  final arcs = [for (final a in w.chronicle.arcs.values) if (arcNames.contains(a.name.toLowerCase()) || !a.ended) a];
  var lines = 0, approaches = 0;
  for (final chat in w.chats.values) {
    for (final l in chat) {
      if (l.at.isBefore(since)) continue;
      lines++;
      if (l.opener.isNotEmpty) approaches++;
    }
  }
  return ChapterChanges(
    title: title,
    turns: turns,
    changes: changes,
    reputation: reputation,
    bonds: bonds,
    arcs: arcs,
    completed: [for (final q in quests) if (q.status == QuestStatus.completed) q],
    failed: [for (final q in quests) if (q.status == QuestStatus.failed) q],
    open: [for (final q in quests) if (q.status == QuestStatus.active) q],
    campDays: changes.where((c) => c.kind == 'camp').length,
    conversations: lines,
    approaches: approaches,
    peopleKnown: people.length,
  );
}

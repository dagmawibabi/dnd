import 'dart:convert';

import '../data/companions.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import '../models/chronicle.dart';

/// Independent copies keep earlier chapters readable as historical snapshots.
void carryChapterWorld(Adventure from, Adventure to) {
  to.worldFromJson(jsonDecode(jsonEncode(from.worldToJson())) as Map<String, dynamic>);
  to.playSeconds = 0;
  to.lastApproachTurn = -1;
  to.npcs = [for (final n in from.npcs) Npc.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>)];
  to.quests = [for (final q in from.quests.where((q) => q.status == QuestStatus.active)) Quest.fromJson(q.toJson())];
  to.pendingNotes = List.of(from.pendingNotes);
  seedCompanionArcs(to);
}

bool rememberWorld(Adventure a, String kind, String name, String state, String reason, {int reputation = 0}) =>
    a.chronicle.record(kind: kind, name: name, state: state, reason: reason, chapter: a.id, chapterTitle: a.title, turn: a.turns, reputation: reputation);

void seedCompanionArcs(Adventure a) {
  for (final c in a.canon) {
    if (a.chronicle.fact(c.kind, c.name) == null) {
      a.chronicle.record(
        kind: c.kind,
        name: c.name,
        state: c.text,
        reason: 'Imported from existing story memory.',
        chapter: a.id,
        chapterTitle: a.title,
        turn: c.turn,
      );
    }
  }
  for (final c in a.companions) {
    if (a.chronicle.arcs.containsKey(c.id)) continue;
    if (c.personalQuest.isEmpty && c.loyalty < 60) continue;
    final template = personalQuestFor(c);
    final title = c.personalQuest.isEmpty ? template.$1 : c.personalQuest;
    c.personalQuest = title;
    var quest = a.quests.where((q) => q.title == title).firstOrNull;
    if (quest == null) {
      quest = Quest(id: newId(), title: title, description: template.$2);
      a.quests.add(quest);
    }
    a.chronicle.arcs[c.id] = CompanionArc(
      companionId: c.id,
      name: c.name,
      title: title,
      description: quest.description,
      stage: quest.status == QuestStatus.completed
          ? 'choice'
          : quest.status == QuestStatus.failed
          ? 'failed'
          : 'revealed',
    );
    rememberWorld(a, 'companion', c.name, 'Revealed personal quest: $title.', 'They trusted you with their story.');
  }
}

/// Quest events and the companion journal share the same lifecycle.
void syncCompanionQuest(Adventure a, Quest q) {
  for (final arc in a.chronicle.arcs.values.where((v) => v.title.toLowerCase() == q.title.toLowerCase() && !v.ended)) {
    if (q.status == QuestStatus.completed) {
      arc.stage = 'choice';
      arc.progress = 2;
    } else if (q.status == QuestStatus.failed) {
      arc.stage = 'failed';
      arc.outcome = 'The personal quest failed: ${q.description}';
    } else {
      continue;
    }
    rememberWorld(a, 'companion', arc.name, '${arc.title}: ${arc.stage}. ${arc.outcome}', 'The quest changed in the story.');
  }
}

void rememberDeparture(Adventure a, Character c, String reason) {
  final arc = a.chronicle.arcs[c.id];
  if (arc != null && !arc.ended) {
    arc.stage = 'departed';
    arc.outcome = reason;
  }
  if (!a.npcs.any((n) => n.id == c.id)) {
    a.npcs.add(
      Npc(
        id: c.id,
        name: c.name,
        role: 'Former companion',
        portrait: c.portrait,
        raceId: c.raceId,
        description: '${c.personality} ${c.backstory}',
        notes: c.notes,
        disposition: a.bonds[c.id]?.friendship ?? 0,
        alive: !c.dead,
      ),
    );
  }
  rememberWorld(a, 'companion', c.name, 'Left the party. $reason', reason);
}

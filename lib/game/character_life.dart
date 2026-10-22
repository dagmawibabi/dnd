import '../models/adventure.dart';
import '../models/world.dart';

/// Sets up a character the story introduced: where they stand with the
/// protagonist, their backstory, personality, goal and need. Returns whether
/// they start out hostile.
bool introduceCharacter(WorldData w, Npc npc, Map<String, dynamic> e, {bool fresh = true}) {
  String s(String k) => (e[k] ?? '').toString().trim();
  final stance = s('stance').isNotEmpty ? s('stance') : s('status');
  final start = stanceFriendship(stance);
  final b = w.bondFor(npc);
  if (fresh && start != null && b.friendship == 0 && npc.disposition == 0) {
    b.friendship = start;
    npc.disposition = start;
  }
  final generic = const {'', 'friendly', 'neutral', 'stranger', 'acquaintance'}.contains(s('status').toLowerCase());
  final label = stanceLabel(stance) ?? (generic ? null : s('status'));
  if (label != null && b.status.isEmpty) b.status = label;
  final p = w.profileOf(npc);
  if (s('backstory').isNotEmpty && p.backstory.isEmpty) p.backstory = s('backstory');
  if (s('personality').isNotEmpty && p.personality.isEmpty) p.personality = s('personality');
  if (s('goal').isNotEmpty && !p.goals.contains(s('goal'))) p.goals.add(s('goal'));
  if (s('need').isNotEmpty && !p.needs.contains(s('need'))) p.needs.add(s('need'));
  if (s('age').isNotEmpty && p.age.isEmpty) p.age = s('age');
  return fresh && b.isHostile;
}

/// The story changed someone. Returns a few words for the log (empty if
/// nothing visible changed).
List<String> growCharacter(WorldData w, Npc npc, Map<String, dynamic> e, int turn) {
  final p = w.profileOf(npc);
  String s(String k) => (e[k] ?? '').toString().trim();
  final changes = <String>[];
  if (s('personality').isNotEmpty && s('personality') != p.personality) {
    if (p.personality.isNotEmpty) p.growth.add('Turn $turn: from "${p.personality}" to "${s('personality')}"');
    p.personality = s('personality');
    changes.add('now ${p.personality}');
  }
  if (s('goal').isNotEmpty && !p.goals.contains(s('goal'))) {
    p.goals.add(s('goal'));
    if (p.goals.length > 5) p.goals.removeAt(0);
    changes.add('wants: ${s('goal')}');
  }
  if (s('need').isNotEmpty && !p.needs.contains(s('need'))) {
    p.needs.add(s('need'));
    if (p.needs.length > 4) p.needs.removeAt(0);
  }
  if (s('memory').isNotEmpty) p.remember(s('memory'), turn: turn);
  if (s('growth').isNotEmpty) {
    p.growth.add('Turn $turn: ${s('growth')}');
    changes.add(s('growth'));
  }
  if (p.growth.length > 20) p.growth.removeAt(0);
  return changes;
}

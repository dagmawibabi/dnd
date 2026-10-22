import 'dart:math' as math;

import '../models/adventure.dart';
import '../models/world.dart';
import '../services/ai/story_ai.dart';
import 'story_host.dart';

/// Why someone comes to the player on their own.
class Approach {
  const Approach({required this.person, required this.topic, required this.why, required this.label, required this.fallback, this.priority = 0});
  final Npc person;

  /// Remembered so the same thing never prompts them twice.
  final String topic;

  /// For the AI: what is on their mind.
  final String why;

  /// For the player: a few words on the banner ("About their personal quest").
  final String label;

  /// What they say when the AI isn't writing it.
  final String fallback;
  final int priority;
}

/// Turns between unprompted conversations, so they stay special.
const approachCooldown = 5;

/// Picks who (if anyone) wants a word, and why. [close] are companions, who
/// always qualify; anyone else must like the player enough to seek them out.
/// [atCamp] means downtime just happened, when people are most likely to talk.
Approach? pickApproach(StoryHost host, {Set<String> close = const {}, bool atCamp = false, math.Random? rng}) {
  final w = host.world;
  final r = rng ?? math.Random();
  if (w.lastApproachTurn >= 0 && host.turns - w.lastApproachTurn < (atCamp ? 2 : approachCooldown) && w.lastApproachTurn <= host.turns) return null;
  // Nobody pulls you aside mid-fight or in a tense standoff; camp is always fine.
  if (!atCamp && const {'combat', 'tense'}.contains(host.scene.mood)) return null;
  final options = <Approach>[];
  for (final p in host.people) {
    if (!p.alive || w.unreadChats.contains(p.id)) continue;
    final b = w.bondFor(p);
    final isClose = close.contains(p.id);
    if (!isClose && b.friendship < 35 && !(b.isRomantic && b.romance >= 20) && b.friendship > -50) continue;
    final first = p.name.split(' ').first;
    bool fresh(String topic) => !w.approachTopics.containsKey(topic);

    // A personal quest that has moved on.
    final arc = w.chronicle.arcs[p.id];
    if (arc != null && !arc.ended) {
      final topic = 'arc:${p.id}:${arc.stage}:${arc.progress}';
      if (fresh(topic)) {
        final decision = arc.stage == 'choice';
        options.add(Approach(
          person: p,
          topic: topic,
          priority: decision ? 9 : 7,
          label: decision ? 'A decision about ${arc.title}' : 'About ${arc.title}',
          why: decision
              ? 'Their personal quest "${arc.title}" has reached its final decision. They want to talk through what to do and what it means to them. ${arc.description}'
              : 'Their personal quest "${arc.title}" is ${arc.stage} (${arc.progress}/2 leads). ${arc.description} They have something new on their mind about it.',
          fallback: decision
              ? 'We\'re close to the end of ${arc.title}. I keep going back and forth on what to do. What would you choose?'
              : 'I\'ve been thinking about ${arc.title} again. Can I tell you what\'s been bothering me?',
        ));
      }
    }

    // A relationship crossing into a new stage, warm or cold.
    final label = b.isRomantic ? b.romanceLabel : b.friendshipLabel;
    final bondTopic = 'bond:${p.id}:$label';
    final notable = b.friendship >= 50 || b.isRomantic || b.friendship <= -20;
    if (notable && fresh(bondTopic) && (b.moments.isNotEmpty || isClose)) {
      final last = b.moments.isEmpty ? '' : b.moments.last.text;
      final cold = b.friendship <= -20 && !b.isRomantic;
      options.add(Approach(
        person: p,
        topic: bondTopic,
        priority: b.isRomantic ? 8 : (cold ? 6 : 5),
        label: cold ? 'Something to clear up' : (b.isRomantic ? 'Something they want to say' : 'A personal word'),
        why: cold
            ? 'They feel $label toward ${host.playerName}${last.isEmpty ? '' : ' after this: $last'}. They want to clear the air, or confront them.'
            : 'Their feelings for ${host.playerName} have grown to "$label"${last.isEmpty ? '' : ', most recently because: $last'}. They want to say something personal about it.',
        fallback: cold
            ? 'We need to talk. ${last.isEmpty ? 'Something between us isn\'t right.' : 'I haven\'t stopped thinking about what happened.'} Can you explain yourself?'
            : b.isRomantic
                ? 'Do you have a moment? Just you and me. There\'s something I\'ve been wanting to say.'
                : 'I don\'t say this often, but I\'m glad we\'re in this together. Walk with me a moment?',
      ));
    }

    // Something big just changed in the world.
    for (final h in w.chronicle.history.reversed.take(4)) {
      // Only real consequences, not introductions; companion and quest news have
      // their own conversations, and nobody comes to talk about themselves.
      if (h.chapter != host.storyId || host.turns - h.turn > 3) continue;
      if (!const {'place', 'faction', 'promise', 'clue', 'fact'}.contains(h.kind) || h.reason == 'Established in the story.' || h.name.toLowerCase() == p.name.toLowerCase()) continue;
      final topic = 'world:${h.id}:${p.id}';
      if (!fresh(topic) || w.approachTopics.keys.any((k) => k.startsWith('world:${h.id}:'))) continue;
      final mentioned = '${h.after} ${h.reason}'.toLowerCase().contains(first.toLowerCase());
      if (!isClose && !mentioned) continue;
      options.add(Approach(
        person: p,
        topic: topic,
        priority: mentioned ? 6 : 4,
        label: 'About ${h.name}',
        why: 'Something just changed: ${h.name} went from "${h.before.isEmpty ? 'unknown' : h.before}" to "${h.after}" because ${h.reason}. They have an opinion about it.',
        fallback: 'What happened with ${h.name}... I can\'t stop thinking about it. ${h.after} Was it the right call?',
      ));
      break;
    }

    // Quiet moments at camp.
    if (atCamp && isClose) {
      final topic = 'camp:${p.id}:${w.chronicle.day}';
      if (fresh(topic)) {
        options.add(Approach(
          person: p,
          topic: topic,
          priority: 2,
          label: 'A quiet word at camp',
          why: 'It is a quiet moment at camp on day ${w.chronicle.day}. They sit down beside ${host.playerName} and bring up something personal: a memory, a worry, or a question about the road ahead.',
          fallback: ['Can\'t sleep either? Sit with me a while.', 'Quiet nights like this make me think about home. Do you ever miss yours?', 'Before we move on tomorrow, can I ask you something?'][r.nextInt(3)],
        ));
      }
    }
  }
  if (options.isEmpty) return null;
  options.sort((a, b) => b.priority.compareTo(a.priority));
  final best = options.first;
  // Big moments always land; smaller ones only sometimes, so it never feels scripted.
  final chance = atCamp ? 0.75 : (best.priority >= 7 ? 0.9 : 0.4);
  return r.nextDouble() < chance ? best : null;
}

/// The character opens the conversation, then waits for the player.
Future<ChatLine?> deliverApproach(StoryHost host, Approach a, {StoryAi? ai}) async {
  final w = host.world;
  w.lastApproachTurn = host.turns;
  var text = a.fallback;
  var label = a.label;
  var tokens = 0;
  var cost = 0.0;
  if (ai != null && host.isAi && host.settings.useAiNpcChat) {
    try {
      final r = await ai.opener(host, a.person, a.why);
      tokens = r.tokens;
      cost = r.cost;
      if (r.value.skip) {
        // A bad moment: they wait and may try again in a couple of turns.
        w.lastApproachTurn = host.turns - approachCooldown + 2;
        host.save();
        return null;
      }
      if (r.value.text.trim().isNotEmpty) text = r.value.text.trim();
      if (r.value.topic.isNotEmpty) label = r.value.topic;
    } catch (_) {
      // The written-in line still lets them start the conversation.
    }
  }
  w.approachTopics[a.topic] = host.turns;
  final line = ChatLine(fromPlayer: false, text: text, tokens: tokens, cost: cost, opener: label);
  w.chatWith(a.person.id).add(line);
  w.unreadChats.add(a.person.id);
  host.refresh();
  host.save();
  return line;
}

/// Marks a conversation as read when it is opened.
void readChat(StoryHost host, Npc person) {
  if (host.world.unreadChats.remove(person.id)) {
    host.refresh();
    host.save();
  }
}

/// The most recent unread opener, for the banner.
(Npc, ChatLine)? latestApproach(StoryHost host) {
  (Npc, ChatLine)? best;
  for (final id in host.world.unreadChats) {
    final p = host.people.where((n) => n.id == id).firstOrNull;
    final chat = host.world.chats[id];
    if (p == null || chat == null || chat.isEmpty) continue;
    final l = chat.last;
    if (best == null || l.at.isAfter(best.$2.at)) best = (p, l);
  }
  return best;
}

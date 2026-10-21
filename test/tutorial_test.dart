import 'package:dnd/data/presets.dart';
import 'package:dnd/game/adventure_controller.dart';
import 'package:dnd/game/approaches.dart';
import 'package:dnd/game/chapter_recap.dart';
import 'package:dnd/game/module_engine.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AdventureController> start() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs)
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false
      ..haptics = false
      ..aiNpcChat = false;
    final audio = AudioService(settings);
    final store = GameStore.memory();
    final mod = moduleById('tutorial')!;
    final a = Adventure(id: 'tut', title: mod.title, premise: mod.tagline, hero: presets.first.create(), engine: StoryEngine.module, offline: ModuleEngine.createState(mod.id));
    final ctl = AdventureController(adventure: a, settings: settings, store: store, audio: audio, images: ImageService(settings, ModelCatalog(prefs)));
    addTearDown(() async {
      await ctl.flush();
      ctl.dispose();
      audio.dispose();
      store.dispose();
    });
    await ctl.start();
    return ctl;
  }

  Future<void> pick(AdventureController ctl, String text) async {
    final c = ctl.adventure.choices.firstWhere((c) => c.text.contains(text), orElse: () => throw StateError('No "$text" in ${ctl.adventure.choices.map((c) => c.text)}'));
    await ctl.choose(c);
    if (ctl.pendingRoll != null) await ctl.pendingRoll!.onResult(20);
  }

  for (final (ending, choice) in [('follow', 'Follow Tam'), ('tell', 'Seal it')]) {
    test('the tutorial shows a companion, a world that remembers, an approach and what changed ($ending)', () async {
      final ctl = await start();
      final a = ctl.adventure;
      await pick(ctl, 'Of course');
      await pick(ctl, 'Listen');
      final pip = a.companions.singleWhere((c) => c.name == 'Pip');
      expect(a.chronicle.arcs[pip.id]?.title, "Pip's Lost Brother", reason: 'Pip arrives with a personal quest');

      await pick(ctl, 'Head down');
      expect(ctl.inCombat, isTrue);
      // Let the rats act, then slip away when it's the hero's turn.
      for (var i = 0; i < 40 && ctl.inCombat; i++) {
        if (a.combat!.current.isPlayer && !ctl.busy) await ctl.playerFlee(20);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(ctl.inCombat, isFalse);

      // Pip comes to you after the fight, and the world has changed.
      expect(latestApproach(ctl)?.$1.name, 'Pip');
      expect(a.chats[pip.id]!.last.opener, 'About his lost brother');
      expect(a.chronicle.fact('faction', 'Lantern Inn regulars')?.reputation, 10);

      await pick(ctl, 'Rest at camp');
      await pick(ctl, 'Investigate');
      await pick(ctl, choice);
      expect(a.finished, isTrue);

      final recap = summarizeChapter(a, a.people);
      expect(recap.changes.map((c) => c.name), containsAll(['The Lantern Inn', 'Lantern Inn regulars', "Smugglers' Tunnel"]));
      expect(recap.reputation['Lantern Inn regulars'], 10);
      expect(recap.bonds.map((b) => b.person.name), containsAll(['Hester', 'Pip']));
      expect(recap.arcs.single.name, 'Pip');
      expect(recap.completed.map((q) => q.title), contains('Rats in the Cellar'));
      expect(recap.approaches, 1, reason: [for (final e in a.chats.entries) for (final l in e.value) if (l.opener.isNotEmpty) '${a.people.firstWhere((p) => p.id == e.key).name}: ${l.opener}'].join('; '));
      final pipShift = recap.bonds.firstWhere((b) => b.person.name == 'Pip').friendship;
      expect(ending == 'follow' ? pipShift > 0 : pipShift < 0, isTrue, reason: 'the ending changes how Pip feels');
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}

import 'package:dnd/services/codex_art.dart';
import 'package:dnd/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('profile fields persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    SettingsController(prefs).update((s) => s
      ..playerName = 'Dagmawi'
      ..playerBio = 'Plays bards. Always bards.'
      ..playerAvatar = '/x/me.png');
    final back = SettingsController(prefs);
    expect((back.playerName, back.playerBio, back.playerAvatar), ('Dagmawi', 'Plays bards. Always bards.', '/x/me.png'));
  });

  test('codex art covers races, classes and monsters and is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final subjects = codexSubjects();
    expect(subjects.map((s) => s.kind).toSet(), {'race', 'class', 'monster'});
    final art = CodexArt(prefs);
    final total = art.missing();
    art.set(subjects.first.key, '/x/elf.png');
    expect(art.missing(), total - 1);
    expect(CodexArt(prefs).pathOf(subjects.first.kind, subjects.first.id), '/x/elf.png');
  });
}

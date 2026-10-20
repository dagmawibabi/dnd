import 'package:dnd/models/adventure.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/theme/app_theme.dart';
import 'package:dnd/ui/screens/adventure/log_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('quest and goal cards recognise new and older log entries', () {
    final legacy = questOf(LogEntry(kind: LogKind.levelup, text: 'New goal: Find the ledger'));
    expect(legacy, {'title': 'Find the ledger', 'goal': true, 'state': 'new'});
    expect(questOf(LogEntry(kind: LogKind.levelup, text: 'Quest complete: The Bell'))?['state'], 'done');
    expect(questOf(LogEntry(kind: LogKind.levelup, text: 'Goal failed: Escape'))?['state'], 'failed');
    expect(questOf(LogEntry(kind: LogKind.levelup, text: 'Ser Kell reached level 3!')), isNull);
    expect(questOf(LogEntry(kind: LogKind.levelup, text: 'x', meta: {'quest': {'title': 'Bell', 'state': 'update'}}))?['title'], 'Bell');
  });

  test('reading font and size apply to story text', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController(await SharedPreferences.getInstance());
    s.update((s) => s
      ..readingFont = 'mono'
      ..readingScale = 1.4);
    expect(T.reading().fontFamily, 'JetBrainsMono');
    expect(T.reading().fontSize, closeTo(16.5 * 1.4 * 0.94, 0.01));
    expect(T.monoStory(14).fontSize, closeTo(14 * 1.4, 0.01));
    s.update((s) => s
      ..readingFont = 'sans'
      ..readingScale = 1);
    expect(T.reading().fontFamily, 'Inter');
    expect(T.chat().fontSize, 15);
  });
}

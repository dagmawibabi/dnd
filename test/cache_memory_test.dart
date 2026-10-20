import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('relevant memory: pinned first, then mentioned, then recent, capped', () {
    final canon = [
      for (var i = 0; i < 30; i++) CanonEntry(id: 'f$i', kind: 'fact', name: 'Fact $i', turn: i),
      CanonEntry(id: 'old', kind: 'npc', name: 'Mirela Vance', turn: 0),
      CanonEntry(id: 'pin', kind: 'promise', name: 'Oath to the king', turn: 1, pinned: true),
    ];
    final shown = relevantCanon(canon, 'You ask Mirela about the map.', max: 5);
    expect(shown.length, 5);
    expect(shown[0].id, 'pin');
    expect(shown[1].id, 'old');
    expect(shown[2].id, 'f29');
  });

  test('cached tokens are counted and survive a round trip', () {
    final t = UsageTotals()..add(UsageEvent(model: 'anthropic/x', inputTokens: 1000, outputTokens: 50, cachedTokens: 800), 0.01);
    expect(t.cacheShare, closeTo(0.8, 1e-9));
    expect(t.detail, contains('80% cached'));
    expect(UsageTotals.fromJson(t.toJson()).cachedTokens, 800);
  });

  test('chat messages can mark a cacheable prefix', () {
    const m = ChatMessage('system', 'rules', cache: true);
    expect(m.cache, isTrue);
    expect(const ChatMessage('user', 'hi').cache, isFalse);
  });

  test('combat narration is off by default and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsController(prefs);
    expect(s.aiCombatNarration, isFalse);
    s.update((s) => s.aiCombatNarration = true);
    expect(SettingsController(prefs).aiCombatNarration, isTrue);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dnd/game/money.dart';
import 'package:dnd/game/tale_controller.dart';
import 'package:dnd/models/character.dart';
import 'package:dnd/models/companion.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/companion_store.dart';
import 'package:dnd/services/narrator.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/story_archive.dart';
import 'package:dnd/services/tale_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(TaleController, SettingsController)> _story() async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsController(await SharedPreferences.getInstance())
    ..musicEnabled = false
    ..ambienceEnabled = false
    ..sfxEnabled = false;
  final tale = Tale.create(title: 'The Glass Harbor', genre: 'mystery', engine: TaleEngine.ai);
  final ctl = TaleController(tale: tale, settings: settings, store: TaleStore.memory(), audio: AudioService(settings));
  return (ctl, settings);
}

Companion _friend() => Companion(id: 'mira', name: 'Mira', kind: 'Robot', pronouns: 'she/her', gender: 'female', personality: 'Dry wit, fiercely loyal', backstory: 'Built to tend a lighthouse.', portrait: PortraitSpec.random('human', seed: 3));

void main() {
  setUp(() => CompanionStore.instance = CompanionStore.memory());

  group('companions', () {
    test('survive a save and load with everything they know', () {
      final c = _friend()
        ..trips.add(CompanionTrip(storyId: 's1', title: 'Old Story', personId: 'p1', origin: true, summary: 'They met at the docks.'))
        ..chat.add(ChatLine(fromPlayer: false, text: 'Hey!', suggest: 'The Silent Ship'));
      c.profile.remember('You saved my lamp.');
      final back = Companion.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.name, 'Mira');
      expect(back.kind, 'Robot');
      expect(back.origin?.title, 'Old Story');
      expect(back.profile.memories.single.text, 'You saved my lamp.');
      expect(back.chat.single.suggest, 'The Silent Ship');
    });

    test('joining a story brings their past, and what they learn comes back', () async {
      final (ctl, _) = await _story();
      final store = CompanionStore.instance;
      final c = _friend()..trips.add(CompanionTrip(storyId: 'old', title: 'Rust Road', summary: 'Fought sand pirates together.'));
      c.profile.remember('You owe me a sunrise.');
      store.add(c);

      expect(ctl.bringCompanion(c), isNull);
      expect(ctl.bringCompanion(c), isNotNull, reason: 'they are already here');
      final npc = ctl.people.firstWhere((p) => p.name == 'Mira');
      final p = ctl.world.profiles[npc.id]!;
      expect(p.backstory, contains('Rust Road'));
      expect(p.memories.map((m) => m.text), contains('You owe me a sunrise.'));

      // The story changes them.
      p.remember('The harbor master lied to us.');
      ctl.world.bonds[npc.id]!.friendship = 77;
      store.syncFrom(ctl);
      store.syncFrom(ctl);
      final texts = c.profile.memories.map((m) => m.text).toList();
      expect(texts.where((t) => t == 'The harbor master lied to us.').length, 1);
      expect(c.profile.memories.firstWhere((m) => m.text.startsWith('The harbor')).source, 'story:The Glass Harbor');
      expect(c.bond.friendship, 77);
      expect(c.tripFor(ctl.storyId)?.lastSeen, isNotNull);
      ctl.dispose();
    });

    test('anyone in a story can become a companion and stays linked to it', () async {
      final (ctl, _) = await _story();
      final npc = ctl.meet('Captain Vale', role: 'smuggler', description: 'A scarred woman with a silver tooth');
      ctl.world.profileOf(npc).remember('The player kept my secret.');
      final c = CompanionStore.instance.promote(ctl, npc);
      expect(c.name, 'Captain Vale');
      expect(c.origin?.storyId, ctl.storyId);
      expect(c.profile.memories.map((m) => m.text), contains('The player kept my secret.'));
      expect(c.profile.memories.any((m) => m.source == 'companion'), isTrue, reason: 'they know they became a companion');
      expect(CompanionStore.instance.promote(ctl, npc), same(c));
      expect(CompanionStore.instance.companionFor(ctl.storyId, npc.id), same(c));
      ctl.dispose();
    });

    test('a saved story takes a companion from its overview page', () {
      final tale = Tale.create(title: 'Neon Rain', genre: 'cyberpunk', engine: TaleEngine.ai);
      final c = _friend();
      CompanionStore.instance.add(c);
      expect(bringCompanionTo(tale, c), isNull);
      expect(bringCompanionTo(tale, c), isNotNull);
      expect(tale.npcs.where((n) => n.name == 'Mira'), hasLength(1));
      expect(tale.pendingNotes.last, contains('has joined the story'));
      expect(c.tripFor(tale.id)?.personId, 'companion_mira');
    });

    test('D&D sheets keep their identity and catch up to the hero', () {
      final c = _friend()..kind = 'Elf';
      final sheet = companionSheet(c, level: 3);
      expect(sheet.name, 'Mira');
      expect(sheet.isCompanion, isTrue);
      expect(sheet.level, 3);
      expect(sheet.backstory, contains('lighthouse'));
    });
  });

  group('money', () {
    test('changes made without a record show up as adjustments', () async {
      final (ctl, _) = await _story();
      final w = ctl.world.wallet;
      logMoney(ctl, 0, category: 'other');
      expect(spend(ctl, 50, category: 'reward', tellStory: false), isNull);
      expect(reconcile(ctl), 0);
      w.cash += 12.5; // moved by something that didn't log it
      expect(reconcile(ctl), 12.5);
      expect(w.ledger.last.category, 'adjustment');
      expect(reconcile(ctl), 0);
      ctl.dispose();
    });

    test('loans are credit, not earnings, and net worth counts debts', () async {
      final (ctl, _) = await _story();
      final w = ctl.world.wallet;
      final friend = ctl.meet('Ozzie');
      spend(ctl, 100, category: 'wage', tellStory: false);
      applyMoneyEvent(ctl, {'amount': 40, 'counterparty': 'Bank of Rook', 'category': 'loan'});
      expect(giveMoney(ctl, friend, 30, kind: 'loan', dueIn: 10, rate: 10), isNull);
      expect(w.income, 100);
      expect(w.spent, 0);
      expect(w.receivable, 30);
      expect(w.payable, 40);
      expect(w.due['Ozzie'], ctl.turns + 10);
      expect(walletPrompt(ctl.record), contains('10% interest'));
      // Paying a debt back in full clears its terms.
      expect(giveMoney(ctl, ctl.meet('Bank of Rook'), 40, kind: 'repayment'), isNull);
      expect(w.owed.containsKey('Bank of Rook'), isFalse);
      ctl.dispose();
    });

    test('interest grows savings and debts every 10 turns', () async {
      final (ctl, _) = await _story();
      final w = ctl.world.wallet
        ..bank = 200
        ..bankRate = 5
        ..owed['Ozzie'] = 100
        ..rates['Ozzie'] = 10;
      accrueInterest(ctl); // starts the clock
      ctl.tale.turns += 20;
      final lines = accrueInterest(ctl);
      expect(lines, hasLength(2));
      expect(w.bank, closeTo(220.5, 0.001));
      expect(w.owed['Ozzie'], closeTo(121, 0.001));
      expect(accrueInterest(ctl), isEmpty);
      ctl.dispose();
    });

    test('card payments and undo keep the books balanced', () async {
      final (ctl, _) = await _story();
      final w = ctl.world.wallet;
      spend(ctl, 80, category: 'reward', tellStory: false);
      expect(bankTransfer(ctl, 50), isNull);
      expect(payByCard(ctl, 20, category: 'purchase', note: 'boots'), isNull);
      expect(payByCard(ctl, 999, category: 'purchase'), isNotNull);
      expect((w.cash, w.bank), (30.0, 30.0));
      final boots = w.ledger.last;
      expect(boots.account, 'bank');
      expect(reverseMove(ctl, boots), isNull);
      expect(reverseMove(ctl, boots), isNotNull, reason: 'only once');
      expect(w.bank, 50);
      expect(reconcile(ctl), 0, reason: 'every move was recorded');
      expect(ledgerCsv(ctl.record).split('\n').first, startsWith('Date,Turn'));
      ctl.dispose();
    });
  });

  group('export and import', () {
    test('companions survive a backup with their pictures', () async {
      final store = CompanionStore.instance;
      final c = _friend()..portrait.aiImagePath = '/phone/mira.png';
      c.avatars.add('/phone/mira.png');
      c.chat.add(ChatLine(fromPlayer: false, text: 'Selfie!', images: ['/phone/selfie.jpg']));
      c.profile.remember('The lighthouse burned down.');
      c.trips.add(CompanionTrip(storyId: 's', title: 'Glass Harbor', origin: true));
      store.add(c);
      final backup = jsonDecode(jsonEncode(await store.backup((p) async => Uint8List.fromList(utf8.encode(p))))) as Map<String, dynamic>;

      CompanionStore.instance = CompanionStore.memory();
      final saved = <String>[];
      final n = await CompanionStore.instance.restore(backup, (bytes, ext) async {
        final path = '/new/${utf8.decode(bytes).split('/').last}';
        saved.add(path);
        return path;
      });
      expect(n, 1);
      final back = CompanionStore.instance.byId('mira')!;
      expect(back.portrait.aiImagePath, '/new/mira.png');
      expect(back.chat.single.images, ['/new/selfie.jpg']);
      expect(back.profile.memories.single.text, 'The lighthouse burned down.');
      expect(back.origin?.title, 'Glass Harbor');
      expect(saved, hasLength(2), reason: 'each picture once');

      // A copy used more recently than the backup isn't overwritten.
      back.chat.add(ChatLine(fromPlayer: true, text: 'newer'));
      expect(await CompanionStore.instance.restore(backup, (b, e) async => '/x'), 0);
      expect(CompanionStore.instance.byId('mira')!.chat.last.text, 'newer');
    });

    test('a story export keeps money terms, chats with pictures and companions', () async {
      final (ctl, _) = await _story();
      final c = _friend();
      CompanionStore.instance.add(c);
      ctl.bringCompanion(c);
      final ozzie = ctl.meet('Ozzie');
      spend(ctl, 100, category: 'wage', tellStory: false);
      bankTransfer(ctl, 40);
      giveMoney(ctl, ozzie, 20, kind: 'loan', dueIn: 10, rate: 5);
      final w = ctl.world.wallet..bankRate = 2;
      ctl.world.chatWith(ozzie.id).add(ChatLine(fromPlayer: true, text: 'Look at this', images: ['/phone/photo.jpg'], suggest: 'Neon Rain'));
      ctl.world.itemImages['locket'] = '/phone/locket.png';
      final archive = await portableStoryArchive(ctl.record, (p) async => Uint8List.fromList(utf8.encode(p)));
      final decoded = decodeStoryArchive(jsonEncode(archive));
      final media = {for (final k in archiveAssets(decoded).keys) k: '/new/$k'};
      final t = restoreStoryArchive(decoded, media: media) as Tale;
      expect(t.id, isNot(ctl.storyId), reason: 'imported as a separate save');
      expect((t.wallet.cash, t.wallet.bank, t.wallet.bankRate), (w.cash, w.bank, 2.0));
      expect(t.wallet.owed['Ozzie'], 20);
      expect(t.wallet.due['Ozzie'], w.due['Ozzie']);
      expect(t.wallet.rates['Ozzie'], 5);
      expect(t.wallet.tracked, w.tracked);
      expect(t.wallet.ledger.length, w.ledger.length);
      final chat = t.chatWith(t.npcs.firstWhere((n) => n.name == 'Ozzie').id).single;
      expect(chat.suggest, 'Neon Rain');
      expect(chat.images.single, startsWith('/new/asset:'));
      expect(t.itemImages['locket'], startsWith('/new/asset:'));
      expect(t.npcs.any((n) => n.name == 'Mira'), isTrue);
      expect(t.profiles['companion_mira']?.backstory, contains('lighthouse'));
      ctl.dispose();
    });
  });

  group('voices', () {
    test('a refused voice teaches the narrator which ones the model takes', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController(await SharedPreferences.getInstance())
        ..voiceEngine = 'ai'
        ..speechModel = 'openai/tts-1';
      final n = Narrator(settings);
      expect(n.aiVoices, isNot(contains('ballad')), reason: 'tts-1 never offered ballad');
      settings.speechModel = 'openai/gpt-4o-mini-tts';
      expect(n.aiVoices, contains('ballad'));
      const err = '''AI error 400: [{'type': 'enum', 'loc': ('body', 'voice'), 'msg': "Input should be 'nova', 'shimmer', 'echo', 'onyx', 'fable', 'alloy', 'ash', 'sage' or 'coral'", 'ctx': {'expected': "'nova', 'shimmer', 'echo', 'onyx', 'fable', 'alloy', 'ash', 'sage' or 'coral'"}}]''';
      expect(n.learnVoices(err), isTrue);
      expect(n.learnVoices(err), isFalse, reason: 'nothing new the second time');
      expect(n.aiVoices, isNot(contains('ballad')));
      expect(n.aiVoices, contains('coral'));
      expect(n.learnVoices('AI error 500: busy'), isFalse);
      n.dispose();
    });
  });

  group('thinking limits', () {
    tearDown(() {
      GatewayClient.thinking = 'auto';
      GatewayClient.thinkingSeconds = 0;
      GatewayClient.maxReplyTokens = 0;
    });

    test('requests carry the thinking level and the reply cap', () async {
      GatewayClient.thinking = 'off';
      GatewayClient.maxReplyTokens = 1500;
      final bodies = <Map>[];
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        openRouterKey: 'or',
        client: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map);
          return http.Response(jsonEncode({'choices': [{'message': {'content': 'ok'}}]}), 200);
        }),
      );
      await client.complete(model: 'or:some/model', messages: const [ChatMessage('user', 'hi')], maxTokens: 2500);
      GatewayClient.thinking = 'medium';
      await client.complete(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')], maxTokens: 800);
      expect(bodies[0]['reasoning'], {'enabled': false});
      expect(bodies[0]['max_tokens'], 1500);
      expect(bodies[1]['reasoning'], {'effort': 'medium'});
      expect(bodies[1]['max_tokens'], 800);
    });

    test('a model that rejects the options is asked again without them', () async {
      GatewayClient.thinking = 'low';
      final bodies = <Map>[];
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        client: MockClient((r) async {
          final b = jsonDecode(r.body) as Map;
          bodies.add(b);
          if (b.containsKey('reasoning')) return http.Response(jsonEncode({'error': {'message': 'unknown field reasoning'}}), 400);
          return http.Response(jsonEncode({'choices': [{'message': {'content': 'fine'}}]}), 200);
        }),
      );
      expect(await client.complete(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')]), 'fine');
      expect(bodies, hasLength(2));
    });

    test('a stream that thinks past the limit is asked again without thinking', () async {
      GatewayClient.thinking = 'high';
      GatewayClient.thinkingSeconds = 1;
      final bodies = <Map>[];
      String frame(Map delta) => 'data: ${jsonEncode({'choices': [{'delta': delta}]})}\n\n';
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        client: MockClient.streaming((r, bytes) async {
          final b = jsonDecode(await bytes.bytesToString()) as Map;
          bodies.add(b);
          final thinking = b['reasoning'] is Map && (b['reasoning'] as Map)['enabled'] != false;
          final out = StreamController<List<int>>();
          () async {
            if (thinking) {
              for (var i = 0; i < 6; i++) {
                if (out.isClosed) return;
                out.add(utf8.encode(frame({'reasoning': 'hmm $i '})));
                await Future<void>.delayed(const Duration(milliseconds: 300));
              }
            } else {
              out.add(utf8.encode(frame({'content': 'Straight to it.'})));
            }
            out.add(utf8.encode('data: [DONE]\n\n'));
            await out.close();
          }();
          return http.StreamedResponse(out.stream, 200);
        }),
      );
      final notes = <String>[];
      client.onReasoning = notes.add;
      final text = await client.stream(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')]).join();
      expect(text, 'Straight to it.');
      expect(bodies, hasLength(2));
      expect(bodies.last['reasoning'], {'enabled': false});
      expect(notes.join(), contains('Thought for too long'));
    });

    test('an empty streamed reply is asked again, then without streaming', () async {
      GatewayClient.thinking = 'low';
      var streamed = 0, plain = 0;
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        client: MockClient.streaming((r, bytes) async {
          final b = jsonDecode(await bytes.bytesToString()) as Map;
          if (b['stream'] == true) {
            streamed++;
            // Thinks, then finishes without a word.
            return http.StreamedResponse(Stream.value(utf8.encode('data: ${jsonEncode({'choices': [{'delta': {}, 'finish_reason': 'stop'}]})}\n\ndata: [DONE]\n\n')), 200);
          }
          plain++;
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': '{"narration":"At last."}'}}]}))), 200);
        }),
      );
      final text = await client.stream(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')]).join();
      expect(text, contains('At last.'));
      expect((streamed, plain), (2, 1));
    });

    test('streamed content sent as parts still arrives', () async {
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        client: MockClient.streaming((r, bytes) async => http.StreamedResponse(Stream.value(utf8.encode('data: ${jsonEncode({'choices': [{'delta': {'content': [{'type': 'text', 'text': 'Hello there.'}]}}]})}\n\ndata: [DONE]\n\n')), 200)),
      );
      expect(await client.stream(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')]).join(), 'Hello there.');
    });

    test('a model that thinks silently is stopped at the limit too', () async {
      GatewayClient.thinking = 'high';
      GatewayClient.thinkingSeconds = 1;
      var calls = 0;
      final client = GatewayClient(
        apiKey: 'k',
        captureTarget: false,
        client: MockClient.streaming((r, bytes) async {
          final b = jsonDecode(await bytes.bytesToString()) as Map;
          calls++;
          final silent = b['reasoning'] is Map && (b['reasoning'] as Map)['enabled'] != false;
          final out = StreamController<List<int>>();
          () async {
            // Nothing at all for 5 seconds while it "thinks".
            if (silent) await Future<void>.delayed(const Duration(seconds: 5));
            if (out.isClosed) return;
            out.add(utf8.encode('data: ${jsonEncode({'choices': [{'delta': {'content': 'Done.'}}]})}\n\ndata: [DONE]\n\n'));
            await out.close();
          }();
          return http.StreamedResponse(out.stream, 200);
        }),
      );
      final sw = Stopwatch()..start();
      expect(await client.stream(model: 'openai/gpt-5', messages: const [ChatMessage('user', 'hi')]).join(), 'Done.');
      expect(calls, 2);
      expect(sw.elapsed.inSeconds, lessThan(4));
    });
  });
}

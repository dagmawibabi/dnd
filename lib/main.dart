import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ai/model_catalog.dart';
import 'services/audio/audio_service.dart';
import 'services/db/database.dart';
import 'services/game_store.dart';
import 'services/tale_store.dart';
import 'services/image_service.dart';
import 'services/achievements.dart';
import 'services/codex_art.dart';
import 'services/narrator.dart';
import 'services/usage.dart';
import 'services/settings.dart';
import 'theme/app_theme.dart';
import 'ui/screens/achievements_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/onboarding_screen.dart';

/// App-wide messenger so services can show toasts (e.g. achievements).
final rootMessenger = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  runZonedGuarded(_start, (e, st) => debugPrint('Uncaught: $e $st'));
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  // In release builds a broken widget shows a readable card instead of a grey box.
  ErrorWidget.builder = (details) => _ErrorCard(message: details.exceptionAsString());
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
  ));
  try {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs);
    final db = await AppDatabase.open();
    final store = await GameStore.open(prefs, db);
    final tales = await TaleStore.open(db);
    final catalog = ModelCatalog(prefs);
    final images = ImageService(settings, catalog);
    final audio = AudioService(settings);
    final usage = UsageTracker(prefs, catalog, settings: settings);
    final narrator = Narrator(settings, catalog: catalog);
    final codexArt = CodexArt(prefs);
    final achievements = Achievements(prefs)..onUnlock = (a) => showAchievementToast(rootMessenger.currentState, a);
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: tales),
          ChangeNotifierProvider.value(value: catalog),
          ChangeNotifierProvider.value(value: images),
          Provider.value(value: audio),
          ChangeNotifierProvider.value(value: usage),
          ChangeNotifierProvider.value(value: narrator),
          ChangeNotifierProvider.value(value: achievements),
          ChangeNotifierProvider.value(value: codexArt),
        ],
        child: const DndApp(),
      ),
    );
    unawaited(catalog.ensureLoaded());
    // Warm up common sounds without blocking startup.
    Future.delayed(const Duration(seconds: 2), () => audio.warmUp().catchError((Object e) => debugPrint('Audio warm-up failed: $e')));
  } catch (e, st) {
    debugPrint('Startup failed: $e $st');
    runApp(_StartupError(error: '$e', stack: '$st'));
  }
}

/// Shown if the app cannot start, so the problem is visible on the device.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stack});
  final String error;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
            const SizedBox(height: 16),
            Text('DnD could not start', style: T.h2()),
            const SizedBox(height: 8),
            Text('Take a screenshot of this screen so the problem can be fixed.', style: T.bodyMuted()),
            const SizedBox(height: 16),
            SelectableText(error, style: T.mono(13, color: AppColors.text)),
            const SizedBox(height: 12),
            SelectableText(stack, style: T.mono(11, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                try {
                  if (AppDatabase.isOpen) await AppDatabase.instance.clearAll();
                } catch (_) {}
                await _start();
              },
              child: const Text('Reset app data and try again'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0x22F87171), borderRadius: BorderRadius.circular(10)),
      child: Text('Something went wrong here: $message', style: const TextStyle(color: AppColors.danger, fontSize: 12, decoration: TextDecoration.none)),
    );
  }
}

class DndApp extends StatelessWidget {
  const DndApp({super.key});

  @override
  Widget build(BuildContext context) {
    final onboarded = context.select<SettingsController, bool>((s) => s.onboarded);
    final textScale = context.select<SettingsController, double>((s) => s.textScale);
    final reducedMotion = context.select<SettingsController, bool>((s) => s.reducedMotion);
    final highContrast = context.select<SettingsController, bool>((s) => s.highContrast);
    return MaterialApp(
      title: 'DnD',
      scaffoldMessengerKey: rootMessenger,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(highContrast: highContrast),
      darkTheme: buildAppTheme(highContrast: highContrast),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: mq.disableAnimations || reducedMotion,
            highContrast: mq.highContrast || highContrast,
          ),
          child: child!,
        );
      },
      themeMode: ThemeMode.dark,
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}

# DnD

Solo Dungeons & Dragons in a minimal, dark Flutter app. Play with an AI Dungeon Master (Vercel AI Gateway) or fully offline.

## Features

- **Stories:** five handcrafted branching adventures with multiple endings, endless procedurally generated quests, or an AI Dungeon Master (any AI Gateway model, with model data from models.dev).
- **Characters:** a full creator (race, class, background, point buy / standard array / 4d6, skills, appearance), 12 presets, multiclass level-ups, and an Aurora-style sheet with HP tracking, conditions, inventory, spells, notes and text export.
- **Play:** tactile dice, turn-based combat with companions, tappable log entries that explain every roll, an interactive map and NPC chat.
- **On-device art and audio:** portraits, scenes, maps and synthesized sound effects and music. AI images are optional (Settings → AI).
- **Compendium:** races, classes, spells, equipment, monsters, conditions and core rules.

## Development

```bash
flutter pub get
flutter run
flutter test
```

Regenerate the launcher icons after changing the artwork:

```bash
flutter test tool/generate_icon_test.dart
dart run flutter_launcher_icons
```

Rules content is adapted from the 5e System Reference Document (CC-BY-4.0). Fonts: Inter and JetBrains Mono (SIL OFL).

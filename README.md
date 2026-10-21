# DnD

Solo Dungeons & Dragons in a minimal, dark Flutter app. Play with an AI Dungeon Master (Vercel AI Gateway) or fully offline.

## Features

- **Stories:** five handcrafted branching adventures with multiple endings, endless procedurally generated quests, or an AI Dungeon Master (any AI Gateway model, with model data from models.dev).
- **Characters:** a full creator (race, class, background, point buy / standard array / 4d6, skills, appearance), 12 presets, multiclass level-ups, and an Aurora-style sheet with HP tracking, conditions, inventory, spells, notes and text export.
- **Play:** tactile dice, turn-based combat with companions, tappable log entries that explain every roll, an interactive map and NPC chat.
- **On-device art and audio:** portraits, scenes, maps and synthesized sound effects and music. AI images are optional (Settings → AI).
- **Compendium:** races, classes, spells, equipment, monsters, conditions and core rules.
- **Living campaigns:** relationships, private conversations, voices, notes and world consequences carry between chapters. Open **World memory** from the story tools or campaign to search current facts, pin or correct them during play, and browse the before/after history with its causes and chapter references. AI narration and character chats receive this state.
- **Camp & companions:** train, work, brew potions, research or spend time with a companion. Activity limits persist in saves. At 60 loyalty, companions reveal a personal arc: follow two successful leads during downtime or complete their quest in the story, then choose a lasting resolution at camp. Outcomes, Inspiration rewards and departures are remembered across chapters. Town activities require a settlement; camp actions work offline too.

## Development

Story exports (PDF, HTML, Markdown, text and clipboard) include world memory, consequence history, companion arcs, camp progress and private conversations. Playable saves and library backups retain that state for resuming; importing a standalone story preserves the spent downtime action under its new identity. Character cards and copied sheets include Inspiration, companion loyalty and personal quests.

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

# DnD

Solo Dungeons & Dragons in a minimal, dark Flutter app. Play with an AI Dungeon Master (Vercel AI Gateway) or fully offline.

## Features

- **Stories:** five handcrafted branching adventures with multiple endings, endless procedurally generated quests, or an AI Dungeon Master (any AI Gateway model, with model data from models.dev).
- **Characters:** a full creator (race, class, background, point buy / standard array / 4d6, skills, appearance), 12 presets, multiclass level-ups, and an Aurora-style sheet with HP tracking, conditions, inventory, spells, notes and text export.
- **Play:** tactile dice, turn-based combat with companions, tappable log entries that explain every roll, an interactive map and NPC chat.
- **On-device art and audio:** portraits, scenes, maps and synthesized sound effects and music. AI images are optional (Settings → AI).
- **Compendium:** races, classes, spells, equipment, monsters, conditions and core rules.
- **Living campaigns:** relationships, private conversations, voices, notes and world consequences carry between chapters. Open **World memory** from the story tools or campaign to search current facts, pin or correct them during play, and browse the before/after history with its causes and chapter references. AI narration and character chats receive this state.
- **Characters with inner lives:** every character gets a backstory, personality, goals, needs and memories (viewable and editable on their profile) that grow with the story. Relationships are labeled accurately (enemies stay enemies), voices are matched to gender and kept all story, and portraits keep a history to choose from. **Characters you've met** (Settings) gathers everyone from every story.
- **Narration player:** faster, chunked AI narration with pause, ±10 s, restart, previous/next and speed; all speech is cached on the device so replays (and "Play from here") are free.
- **Story pages:** a cover page per story (recap, cast, open quests, stats), an inventory with readable books and letters and an item-creation tool, a timeline, goal details with hints, a condition page (energy, hunger, thirst, sickness, stamina, morale, composure), saved AI-tool results, a narrator tone you can set or change, "wrap up the story", fullscreen mode and a picture-book replay.
- **Sharing:** story, relationship (with an AI group photo), lifetime-stats and achievement cards; share an AI adventure as a fresh start anyone can import; complete backups carry pictures and narration.
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

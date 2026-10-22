import 'package:flutter/material.dart';

/// A genre for text adventures: look, sound and the AI narrator's style.
class TaleGenre {
  const TaleGenre(this.id, this.name, this.tagline, this.icon, this.color, {required this.scene, required this.time, required this.music, required this.ambience, required this.style, this.healthLabel = 'Health'});
  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color color;

  /// Procedural backdrop to reuse (location id for the scene painter).
  final String scene;
  final String time;
  final String music;
  final String ambience;

  /// Guidance for the AI narrator.
  final String style;

  /// What the health bar means in this genre.
  final String healthLabel;
}

const taleGenres = <TaleGenre>[
  TaleGenre('scifi', 'Sci-fi', 'Derelict ships, alien signals, the long dark.', Icons.rocket_launch_outlined, Color(0xFF60A5FA),
      scene: 'tundra', time: 'night', music: 'mystery', ambience: 'cave', healthLabel: 'Suit integrity',
      style: 'Hard-edged science fiction. Cold metal, humming machines, unknown signals. Technology has rules; use them.'),
  TaleGenre('horror', 'Horror', 'Something is in the house. It knows your name.', Icons.dark_mode_outlined, Color(0xFFF87171),
      scene: 'crypt', time: 'night', music: 'mystery', ambience: 'wind', healthLabel: 'Sanity',
      style: 'Slow-burn psychological horror. Dread over gore. Small wrong details. Never explain the monster fully.'),
  TaleGenre('western', 'Western', 'Dust, debts and a six-shooter at high noon.', Icons.landscape_outlined, Color(0xFFFBBF24),
      scene: 'desert', time: 'dusk', music: 'forest', ambience: 'wind',
      style: 'A gritty frontier western. Laconic dialogue, sun-bleached towns, moral grey, honor and revenge.'),
  TaleGenre('noir', 'Noir mystery', 'Rain on the window. A dame, a dead man, a lie.', Icons.search, Color(0xFFA1A1AA),
      scene: 'town', time: 'night', music: 'mystery', ambience: 'rain', healthLabel: 'Nerve',
      style: '1940s hardboiled noir in the first person voice of a detective, but address the player as "you". Rain, neon, cynical wit, clues and red herrings.'),
  TaleGenre('cyberpunk', 'Cyberpunk', 'Neon, chrome, and a job that pays too well.', Icons.memory, Color(0xFFE879F9),
      scene: 'town', time: 'night', music: 'combat', ambience: 'crowd', healthLabel: 'Integrity',
      style: 'High-tech low-life cyberpunk. Megacorps, implants, hackers, rain-slicked neon streets, street slang.'),
  TaleGenre('postapoc', 'Post-apocalyptic', 'The world ended. You didn\'t.', Icons.local_fire_department_outlined, Color(0xFFFB923C),
      scene: 'ruins', time: 'dusk', music: 'mystery', ambience: 'wind',
      style: 'Post-apocalyptic survival. Scarce water, rusted ruins, desperate survivors, hard choices about who to trust.'),
  TaleGenre('fantasy', 'Fantasy', 'Swords, spells and a kingdom on the edge.', Icons.auto_awesome_outlined, Color(0xFF8B7CF6),
      scene: 'castle', time: 'dusk', music: 'forest', ambience: 'wind',
      style: 'Classic fantasy adventure without game rules. Wonder, danger and clever solutions.'),
  TaleGenre('pirate', 'Pirates', 'Salt, gold and a map with a bloodstain.', Icons.sailing_outlined, Color(0xFF2DD4BF),
      scene: 'coast', time: 'day', music: 'tavern', ambience: 'surf',
      style: 'Swashbuckling pirate adventure. Sea shanties, treasure, betrayal, storms and bold escapes.'),
  TaleGenre('comedy', 'Comedy', 'A very bad day, told very well.', Icons.sentiment_very_satisfied_outlined, Color(0xFF4ADE80),
      scene: 'tavern', time: 'day', music: 'tavern', ambience: 'crowd', healthLabel: 'Dignity',
      style: 'Absurd, warm comedy. Escalating misunderstandings, witty narration, everyone is a little ridiculous, nothing too dark.'),
];

/// Genres the player made (loaded from Settings).
List<TaleGenre> customTaleGenres = [];

/// Built-in genres, then the player's own.
List<TaleGenre> get allTaleGenres => [...taleGenres, ...customTaleGenres];

TaleGenre genreById(String id) => allTaleGenres.firstWhere((g) => g.id == id, orElse: () => taleGenres.first);

const customGenreIcons = [Icons.auto_awesome_outlined, Icons.castle_outlined, Icons.rocket_outlined, Icons.forest_outlined, Icons.water_outlined, Icons.local_police_outlined, Icons.psychology_outlined, Icons.favorite_border, Icons.sports_esports_outlined, Icons.school_outlined, Icons.pets_outlined, Icons.bolt_outlined];
const customGenreColors = [Color(0xFF8B7CF6), Color(0xFF60A5FA), Color(0xFF2DD4BF), Color(0xFF4ADE80), Color(0xFFFBBF24), Color(0xFFFB923C), Color(0xFFF87171), Color(0xFFF472B6), Color(0xFFE879F9), Color(0xFFA1A1AA)];

/// Places the scene painter can draw, for a custom genre's backdrop.
const genreScenes = ['castle', 'forest', 'town', 'tavern', 'cave', 'ruins', 'coast', 'desert', 'tundra', 'swamp', 'crypt', 'tower', 'mountain', 'plains'];

/// A player-made genre from its saved form.
TaleGenre genreFromJson(Map<String, dynamic> j) {
  final scene = (j['scene'] ?? 'castle').toString();
  return TaleGenre(
    (j['id'] ?? 'custom').toString(),
    (j['name'] ?? 'My genre').toString(),
    (j['tagline'] ?? '').toString(),
    customGenreIcons[((j['icon'] ?? 0) as num).toInt().clamp(0, customGenreIcons.length - 1)],
    customGenreColors[((j['color'] ?? 0) as num).toInt().clamp(0, customGenreColors.length - 1)],
    scene: scene,
    time: (j['time'] ?? 'dusk').toString(),
    music: (j['music'] ?? 'mystery').toString(),
    ambience: (j['ambience'] ?? 'wind').toString(),
    style: (j['style'] ?? '').toString(),
    healthLabel: (j['health'] ?? 'Health').toString().trim().isEmpty ? 'Health' : j['health'].toString(),
  );
}

bool isCustomGenre(String id) => id.startsWith('custom_');

/// Illustration style for a genre's AI images and videos.
String taleArtStyle(TaleGenre g) {
  final look = switch (g.id) {
    'scifi' => 'Cinematic hard sci-fi concept art, cold blue and amber lighting, volumetric haze, detailed hardware',
    'horror' => 'Atmospheric horror film still, desaturated palette, deep shadows, subtle film grain, unsettling composition',
    'western' => 'Painterly western film still, sun-bleached ochre palette, long shadows, dusty air',
    'noir' => 'Black-and-white film noir still, hard rim light, venetian-blind shadows, rain-slick reflections',
    'cyberpunk' => 'Neon-drenched cyberpunk concept art, magenta and cyan lights, rain, dense signage without readable text',
    'postapoc' => 'Gritty post-apocalyptic concept art, rust and dust palette, overcast light, ruined scale',
    'pirate' => 'Swashbuckling painterly adventure art, sea spray, golden-hour light, rich wood and canvas',
    'comedy' => 'Warm storybook illustration, expressive characters, playful saturated colors',
    _ => 'Painterly fantasy illustration, dramatic lighting, rich color, highly detailed',
  };
  return '$look. No text, no watermark.';
}

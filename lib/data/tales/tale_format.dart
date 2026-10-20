/// Handcrafted text adventures: scenes, options, and their consequences.
class TaleOption {
  const TaleOption(
    this.text,
    this.go, {
    this.requires,
    this.unless,
    this.gives,
    this.takes,
    this.sets,
    this.damage = 0,
    this.heal = 0,
    this.chance,
    this.fail,
  });

  final String text;

  /// Next scene id.
  final String go;

  /// Shown only if the flag (or `item:Name`) is present.
  final String? requires;

  /// Hidden if the flag (or `item:Name`) is present.
  final String? unless;
  final String? gives;
  final String? takes;
  final String? sets;
  final int damage;
  final int heal;

  /// Risky options succeed with this probability; otherwise go to [fail].
  final double? chance;
  final String? fail;
}

class TaleNode {
  const TaleNode(this.text, {this.title, this.options = const [], this.end, this.gives, this.sets, this.damage = 0, this.status});
  final String? title;
  final String text;
  final List<TaleOption> options;

  /// good | bad | neutral when the story ends here.
  final String? end;
  final String? gives;
  final String? sets;
  final int damage;
  final String? status;
}

class TalePreset {
  const TalePreset({required this.id, required this.title, required this.genre, required this.blurb, required this.minutes, required this.start, required this.nodes});
  final String id;
  final String title;
  final String genre;
  final String blurb;
  final int minutes;
  final String start;
  final Map<String, TaleNode> nodes;

  int get endings => nodes.values.where((n) => n.end != null).length;
}

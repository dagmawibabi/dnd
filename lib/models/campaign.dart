import 'adventure.dart';

/// A multi-chapter saga: the same hero carried through linked adventures.
class Campaign {
  Campaign({
    required this.id,
    required this.name,
    required this.heroId,
    this.description = '',
    List<String>? chapters,
    List<CanonEntry>? canon,
    this.summary = '',
    this.seriesId,
    DateTime? createdAt,
  })  : chapters = chapters ?? [],
        canon = canon ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  String heroId;
  String description;

  /// Adventure ids, in play order.
  List<String> chapters;

  /// Facts that persist between chapters.
  List<CanonEntry> canon;

  /// Story-so-far across all chapters.
  String summary;

  /// For handcrafted multi-part series (e.g. "ember_crown").
  String? seriesId;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hero': heroId,
        'desc': description,
        'chapters': chapters,
        'canon': canon.map((c) => c.toJson()).toList(),
        'summary': summary,
        'series': seriesId,
        'created': createdAt.toIso8601String(),
      };

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id: j['id'],
        name: j['name'] ?? 'Campaign',
        heroId: j['hero'] ?? '',
        description: j['desc'] ?? '',
        chapters: List<String>.from(j['chapters'] ?? []),
        canon: [for (final c in (j['canon'] as List? ?? [])) CanonEntry.fromJson(Map<String, dynamic>.from(c))],
        summary: j['summary'] ?? '',
        seriesId: j['series'],
        createdAt: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
      );
}

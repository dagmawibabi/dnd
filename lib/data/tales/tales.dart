import 'frontier_city.dart';
import 'neon_wasteland.dart';
import 'scifi_horror.dart';
import 'tale_format.dart';

export 'tale_format.dart';

/// Handcrafted text adventures, one or more per genre.
const talePresets = <TalePreset>[silentShip, hollowLane, redMesa, rainLedger, neonGhost, lastWell];

TalePreset? taleById(String? id) => talePresets.where((t) => t.id == id).firstOrNull;

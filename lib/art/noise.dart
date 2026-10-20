import 'dart:math' as math;

/// Small seeded value-noise implementation used by map and scene painters.
class ValueNoise {
  ValueNoise(int seed) {
    final r = math.Random(seed);
    _perm = List<int>.generate(256, (i) => i)..shuffle(r);
    _vals = List<double>.generate(256, (_) => r.nextDouble());
  }

  late final List<int> _perm;
  late final List<double> _vals;

  double _lattice(int x, int y) => _vals[_perm[(_perm[x & 255] + y) & 255]];

  static double _smooth(double t) => t * t * (3 - 2 * t);

  double noise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final tx = _smooth(x - xi);
    final ty = _smooth(y - yi);
    final a = _lattice(xi, yi);
    final b = _lattice(xi + 1, yi);
    final c = _lattice(xi, yi + 1);
    final d = _lattice(xi + 1, yi + 1);
    final top = a + (b - a) * tx;
    final bot = c + (d - c) * tx;
    return top + (bot - top) * ty;
  }

  double fbm(double x, double y, {int octaves = 4, double lacunarity = 2, double gain = 0.5}) {
    var amp = 0.5;
    var freq = 1.0;
    var sum = 0.0;
    var norm = 0.0;
    for (var i = 0; i < octaves; i++) {
      sum += amp * noise(x * freq, y * freq);
      norm += amp;
      amp *= gain;
      freq *= lacunarity;
    }
    return sum / norm;
  }
}

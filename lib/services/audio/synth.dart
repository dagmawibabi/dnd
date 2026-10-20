import 'dart:math' as math;
import 'dart:typed_data';

/// Tiny offline synthesizer that renders sound effects and ambient music
/// loops to 16-bit mono WAV, entirely on device.
const int kSampleRate = 22050;

Uint8List encodeWav(Float32List samples, {int sampleRate = kSampleRate}) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  var o = 44;
  for (final s in samples) {
    b.setInt16(o, (s.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    o += 2;
  }
  return b.buffer.asUint8List();
}

double midiToHz(num m) => 440.0 * math.pow(2, (m - 69) / 12).toDouble();

class _Buf {
  _Buf(double seconds) : data = Float32List((seconds * kSampleRate).round());
  final Float32List data;
  int get length => data.length;

  void add(int i, double v) {
    if (i >= 0 && i < data.length) data[i] += v;
  }

  /// Adds with wrap-around (for seamless loops).
  void addWrap(int i, double v) => data[i % data.length] += v;

  void normalize([double peak = 0.85]) {
    var m = 0.0;
    for (final s in data) {
      m = math.max(m, s.abs());
    }
    if (m < 1e-6) return;
    final g = peak / m;
    for (var i = 0; i < data.length; i++) {
      data[i] *= g;
    }
  }

  void fadeEdges({double inSec = 0.005, double outSec = 0.05}) {
    final fi = (inSec * kSampleRate).round();
    final fo = (outSec * kSampleRate).round();
    for (var i = 0; i < fi && i < data.length; i++) {
      data[i] *= i / fi;
    }
    for (var i = 0; i < fo && i < data.length; i++) {
      data[data.length - 1 - i] *= i / fo;
    }
  }
}

final _rand = math.Random(1234);
double _noise() => _rand.nextDouble() * 2 - 1;

double _env(double t, double a, double d, {double s = 0, double r = 0, double hold = 0}) {
  if (t < a) return t / a;
  t -= a;
  if (t < hold) return 1;
  t -= hold;
  if (t < d) return 1 - (1 - s) * (t / d);
  if (s <= 0) return 0;
  t -= d;
  if (r <= 0) return s;
  return t < r ? s * (1 - t / r) : 0;
}

void _tone(_Buf b, double start, double dur, double hz, double amp, {String wave = 'sine', double a = 0.005, double d = 0.2, double s = 0.0, double r = 0.1, double sweep = 0, bool wrap = false, double vibrato = 0}) {
  final n = ((dur + r) * kSampleRate).round();
  final si = (start * kSampleRate).round();
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final f = hz * (1 + sweep * t / dur) * (1 + vibrato * math.sin(t * 2 * math.pi * 5.5));
    phase += f / kSampleRate;
    final p = phase % 1.0;
    double v;
    switch (wave) {
      case 'saw':
        v = 2 * p - 1;
      case 'square':
        v = p < 0.5 ? 0.6 : -0.6;
      case 'tri':
        v = 4 * (p < 0.5 ? p : 1 - p) - 1;
      default:
        v = math.sin(p * 2 * math.pi);
    }
    final e = _env(t, a, d, s: s, r: r, hold: math.max(0, dur - a - d));
    final sample = v * e * amp;
    wrap ? b.addWrap(si + i, sample) : b.add(si + i, sample);
  }
}

void _noiseBurst(_Buf b, double start, double dur, double amp, {double lp = 0.5, double a = 0.002, bool wrap = false, double hp = 0}) {
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  var y = 0.0, prev = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final x = _noise();
    y += lp * (x - y);
    final out = hp > 0 ? y - prev * hp : y;
    prev = y;
    final e = t < a ? t / a : math.pow(1 - (t - a) / (dur - a).clamp(1e-4, 100), 2).toDouble();
    wrap ? b.addWrap(si + i, out * e * amp) : b.add(si + i, out * e * amp);
  }
}

/// Karplus–Strong plucked string (lute/harp).
void _pluck(_Buf b, double start, double hz, double amp, {double decay = 0.996, double dur = 2.0, bool wrap = false, double bright = 0.5}) {
  final period = math.max(2, (kSampleRate / hz).round());
  final ring = Float32List(period);
  for (var i = 0; i < period; i++) {
    ring[i] = _noise();
  }
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  var idx = 0;
  for (var i = 0; i < n; i++) {
    final cur = ring[idx];
    final next = ring[(idx + 1) % period];
    ring[idx] = decay * (bright * cur + (1 - bright) * next);
    final fade = i > n - 400 ? (n - i) / 400 : 1.0;
    wrap ? b.addWrap(si + i, cur * amp * fade) : b.add(si + i, cur * amp * fade);
    idx = (idx + 1) % period;
  }
}

void _kick(_Buf b, double start, double amp, {bool wrap = false}) {
  final n = (0.35 * kSampleRate).round();
  final si = (start * kSampleRate).round();
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final f = 45 + 110 * math.exp(-t * 30);
    phase += f / kSampleRate;
    final v = math.sin(phase * 2 * math.pi) * math.exp(-t * 9) * amp;
    wrap ? b.addWrap(si + i, v) : b.add(si + i, v);
  }
}

void _reverb(_Buf b, {double mix = 0.3, bool wrap = true}) {
  final src = Float32List.fromList(b.data);
  const taps = [0.031, 0.047, 0.071, 0.113, 0.167, 0.233];
  const gains = [0.5, 0.42, 0.36, 0.3, 0.24, 0.18];
  for (var t = 0; t < taps.length; t++) {
    final off = (taps[t] * kSampleRate).round();
    for (var i = 0; i < src.length; i++) {
      final j = i + off;
      if (wrap) {
        b.data[j % b.length] += src[i] * gains[t] * mix;
      } else if (j < b.length) {
        b.data[j] += src[i] * gains[t] * mix;
      }
    }
  }
  // second, longer diffusion pass
  final src2 = Float32List.fromList(b.data);
  for (final d in [0.29, 0.41]) {
    final off = (d * kSampleRate).round();
    for (var i = 0; i < src2.length; i++) {
      final j = i + off;
      if (wrap) {
        b.data[j % b.length] += src2[i] * 0.22 * mix;
      } else if (j < b.length) {
        b.data[j] += src2[i] * 0.22 * mix;
      }
    }
  }
}

// --------------------------------------------------------------------- SFX

/// RBJ biquad filter.
class _Biquad {
  _Biquad.lowpass(double f, {double q = 0.707}) {
    _set(f, q, 0);
  }
  _Biquad.highpass(double f, {double q = 0.707}) {
    _set(f, q, 1);
  }
  _Biquad.bandpass(double f, {double q = 1}) {
    _set(f, q, 2);
  }

  double b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;
  int _type = 0;
  double _q = 0.707;

  void _set(double f, double q, int type) {
    _type = type;
    _q = q;
    final w = 2 * math.pi * f.clamp(20, kSampleRate / 2.2) / kSampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    final a0 = 1 + alpha;
    switch (type) {
      case 0:
        b0 = (1 - cw) / 2 / a0;
        b1 = (1 - cw) / a0;
        b2 = b0;
      case 1:
        b0 = (1 + cw) / 2 / a0;
        b1 = -(1 + cw) / a0;
        b2 = b0;
      default:
        b0 = alpha / a0;
        b1 = 0;
        b2 = -alpha / a0;
    }
    a1 = -2 * cw / a0;
    a2 = (1 - alpha) / a0;
  }

  /// Retune without resetting state (for sweeps).
  void tune(double f) => _set(f, _q, _type);

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// Modal impact: a bank of exponentially decaying partials (metal, wood, plastic).
void _modal(_Buf b, double start, double base, List<double> ratios, List<double> decays, double amp, {List<double>? gains, double strike = 0.002}) {
  final n = (decays.reduce(math.max) * 5 * kSampleRate).round();
  final si = (start * kSampleRate).round();
  final phases = List<double>.generate(ratios.length, (_) => _rand.nextDouble() * math.pi * 2);
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final attack = t < strike ? t / strike : 1.0;
    var v = 0.0;
    for (var k = 0; k < ratios.length; k++) {
      final g = gains == null ? 1 / (k + 1) : gains[k];
      v += math.sin(2 * math.pi * base * ratios[k] * t + phases[k]) * math.exp(-t / decays[k]) * g;
    }
    b.add(si + i, v * amp * attack);
  }
}

/// Filtered noise with a moving band (whooshes, swishes, wind).
void _sweep(_Buf b, double start, double dur, double fromHz, double toHz, double amp, {double q = 2, double attack = 0.3}) {
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  final f = _Biquad.bandpass(fromHz, q: q);
  for (var i = 0; i < n; i++) {
    final p = i / n;
    if (i % 32 == 0) f.tune(fromHz * math.pow(toHz / fromHz, p));
    final env = p < attack ? p / attack : math.pow(1 - (p - attack) / (1 - attack), 1.6).toDouble();
    b.add(si + i, f.process(_noise()) * env * amp);
  }
}

/// Short filtered-noise transient.
void _click(_Buf b, double start, double amp, {double hz = 3000, double q = 1.5, double dur = 0.012}) {
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  final f = _Biquad.bandpass(hz, q: q);
  for (var i = 0; i < n; i++) {
    b.add(si + i, f.process(_noise()) * math.exp(-i / (n * 0.25)) * amp);
  }
}

/// Low thump with a downward pitch glide.
void _thud(_Buf b, double start, double amp, {double from = 140, double to = 50, double dur = 0.25}) {
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  var ph = 0.0;
  final lp = _Biquad.lowpass(400);
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final f = to + (from - to) * math.exp(-t * 25);
    ph += f / kSampleRate;
    final body = math.sin(ph * 2 * math.pi) * math.exp(-t * 14);
    final grit = lp.process(_noise()) * math.exp(-t * 40) * 0.6;
    b.add(si + i, (body + grit) * amp);
  }
}

/// FM bell partial.
void _bell(_Buf b, double start, double hz, double amp, {double dur = 1.2, double ratio = 3.5, double index = 4}) {
  final n = (dur * kSampleRate).round();
  final si = (start * kSampleRate).round();
  for (var i = 0; i < n; i++) {
    final t = i / kSampleRate;
    final env = math.exp(-t * 3.2 / dur * 2);
    final mod = math.sin(2 * math.pi * hz * ratio * t) * index * env;
    b.add(si + i, math.sin(2 * math.pi * hz * t + mod) * env * amp * (t < 0.003 ? t / 0.003 : 1));
  }
}

/// Plastic die hitting a wooden table.
void _dieHit(_Buf b, double t, double amp) {
  final base = 1800 + _rand.nextDouble() * 900;
  _modal(b, t, base, const [1, 1.71, 2.53, 3.48], const [0.012, 0.009, 0.006, 0.004], amp * 0.55);
  _click(b, t, amp * 0.7, hz: 4200 + _rand.nextDouble() * 2000, q: 1.2, dur: 0.008);
  _modal(b, t, 210 + _rand.nextDouble() * 40, const [1, 2.3], const [0.03, 0.015], amp * 0.35); // table body
}

/// Ringing steel.
void _clang(_Buf b, double t, double base, double amp, {double ring = 0.35}) {
  _modal(b, t, base, const [1, 2.32, 4.25, 6.63, 9.38], [ring, ring * 0.8, ring * 0.55, ring * 0.35, ring * 0.2], amp, gains: const [1, 0.7, 0.5, 0.35, 0.2]);
  _click(b, t, amp * 0.8, hz: 5000, q: 0.8, dur: 0.01);
}

const sfxNames = [
  'dice', 'dice_land', 'crit', 'fumble', 'sword', 'hit', 'miss', 'spell', 'heal', 'coin', 'door', 'levelup', 'click', 'page', 'roar',
  'death', 'thunder', 'chime', 'creak', 'splash', 'footsteps', 'magic', 'quest', 'fail', 'success', 'buff', 'flee',
];

Uint8List renderSfx(String name) {
  late _Buf b;
  var reverbMix = 0.0;
  switch (name) {
    case 'dice':
      b = _Buf(1.0);
      // Tumbling: hits get closer together and quieter, with a soft roll underneath.
      var t = 0.0;
      var gap = 0.11;
      for (var i = 0; i < 11 && t < 0.85; i++) {
        _dieHit(b, t, 0.9 - i * 0.06);
        if (_rand.nextDouble() < 0.4) _dieHit(b, t + 0.012 + _rand.nextDouble() * 0.01, 0.4 - i * 0.02);
        t += gap * (0.6 + _rand.nextDouble() * 0.8);
        gap *= 0.86;
      }
      _sweep(b, 0, 0.8, 900, 500, 0.06, q: 0.7, attack: 0.1);
      reverbMix = 0.08;
    case 'dice_land':
      b = _Buf(0.45);
      _dieHit(b, 0, 1);
      _dieHit(b, 0.07, 0.45);
      _dieHit(b, 0.11, 0.2);
      reverbMix = 0.08;
    case 'sword':
      b = _Buf(1.4);
      _sweep(b, 0, 0.22, 500, 3500, 0.7, q: 1.6, attack: 0.6);
      _clang(b, 0.17, 1150 + _rand.nextDouble() * 150, 0.45, ring: 0.45);
      reverbMix = 0.18;
    case 'hit':
      b = _Buf(0.6);
      _sweep(b, 0, 0.1, 700, 2500, 0.35, q: 1.4, attack: 0.7);
      _thud(b, 0.08, 0.9, from: 160, to: 55, dur: 0.3);
      _click(b, 0.08, 0.5, hz: 1200, q: 0.9, dur: 0.03);
      reverbMix = 0.06;
    case 'miss':
      b = _Buf(0.5);
      _sweep(b, 0, 0.35, 400, 2200, 0.55, q: 1.8, attack: 0.55);
      reverbMix = 0.1;
    case 'crit':
      b = _Buf(1.8);
      _sweep(b, 0, 0.12, 600, 3000, 0.4, q: 1.4, attack: 0.7);
      _thud(b, 0.1, 1.0, from: 200, to: 45, dur: 0.4);
      _clang(b, 0.1, 1450, 0.35, ring: 0.6);
      for (final (i, m) in [76, 79, 84, 88].indexed) {
        _bell(b, 0.2 + i * 0.05, midiToHz(m), 0.12, dur: 1.2, ratio: 2, index: 1.5);
      }
      reverbMix = 0.3;
    case 'fumble':
    case 'fail':
      b = _Buf(1.0);
      final lp = _Biquad.lowpass(900, q: 4);
      final n = (0.8 * kSampleRate).round();
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        final step = t < 0.25 ? 0 : (t < 0.5 ? 1 : 2);
        final f = midiToHz(52 - step * 2) * (1 - (t % 0.25) * 0.08);
        final saw = 2 * ((t * f) % 1) - 1 + 2 * ((t * f * 1.006) % 1) - 1;
        lp.tune(500 + 900 * math.exp(-(t % 0.25) * 12));
        final env = (t % 0.25) < 0.01 ? (t % 0.25) / 0.01 : math.exp(-(t % 0.25) * 5);
        b.add(i, lp.process(saw * 0.25) * env * (step == 2 ? 1.2 : 1));
      }
      reverbMix = 0.15;
    case 'success':
      b = _Buf(1.2);
      _bell(b, 0, midiToHz(76), 0.35, dur: 0.9, ratio: 2, index: 1.2);
      _bell(b, 0.09, midiToHz(83), 0.35, dur: 1.0, ratio: 2, index: 1.2);
      reverbMix = 0.3;
    case 'spell':
    case 'magic':
      b = _Buf(1.8);
      _sweep(b, 0, 1.2, 400, 6000, 0.25, q: 3, attack: 0.5);
      for (final (i, m) in [64, 71, 76, 83].indexed) {
        _bell(b, i * 0.06, midiToHz(m), 0.12, dur: 1.3, ratio: 1.5, index: 2.5);
      }
      for (var i = 0; i < 18; i++) {
        _tone(b, 0.2 + _rand.nextDouble() * 1.0, 0.04, 2500 + _rand.nextDouble() * 4000, 0.05, d: 0.06, r: 0.05);
      }
      reverbMix = 0.45;
    case 'buff':
      b = _Buf(1.4);
      _sweep(b, 0, 0.9, 300, 3000, 0.25, q: 4, attack: 0.8);
      for (final (i, m) in [67, 74, 79].indexed) {
        _bell(b, 0.25 + i * 0.08, midiToHz(m), 0.1, dur: 1.0, ratio: 2, index: 1);
      }
      reverbMix = 0.4;
    case 'heal':
      b = _Buf(2.0);
      for (final (i, m) in [67, 71, 74, 79, 83, 86].indexed) {
        _pluck(b, i * 0.07, midiToHz(m), 0.22, decay: 0.997, dur: 1.4, bright: 0.4);
      }
      for (final m in [79, 83, 86]) {
        _tone(b, 0.1, 1.1, midiToHz(m), 0.04, a: 0.3, d: 0.8, r: 0.4, vibrato: 0.004);
      }
      reverbMix = 0.45;
    case 'coin':
      b = _Buf(0.9);
      void ping(double t, double amp) => _modal(b, t, 3300 + _rand.nextDouble() * 900, const [1, 2.71, 5.04], const [0.25, 0.12, 0.05], amp, gains: const [1, 0.6, 0.3]);
      ping(0, 0.4);
      ping(0.09, 0.3);
      _click(b, 0.14, 0.25, hz: 2500, dur: 0.01);
      ping(0.16, 0.18);
      reverbMix = 0.15;
    case 'door':
    case 'creak':
      b = _Buf(1.6);
      final bp = _Biquad.bandpass(900, q: 8);
      final n = (1.1 * kSampleRate).round();
      var ph = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        final f = 70 + 40 * math.sin(t * 3) + _rand.nextDouble() * 25;
        ph += f / kSampleRate;
        final pulse = (ph % 1) < 0.08 ? 1.0 : 0.0;
        if (i % 64 == 0) bp.tune(700 + 500 * math.sin(t * 2.2));
        final env = t < 0.1 ? t / 0.1 : (t > 0.9 ? (1.1 - t) / 0.2 : 1.0);
        b.add(i, bp.process(pulse) * env * 0.9);
      }
      _thud(b, 1.12, 0.8, from: 120, to: 50, dur: 0.4);
      reverbMix = 0.25;
    case 'levelup':
    case 'quest':
      b = _Buf(2.4);
      final notes = name == 'quest' ? [60, 67, 72] : [60, 64, 67, 72];
      final lp = _Biquad.lowpass(600, q: 1.5);
      for (final (i, m) in notes.indexed) {
        final start = i * 0.12;
        final len = i == notes.length - 1 ? 1.1 : 0.14;
        final n = (len * kSampleRate).round();
        final si = (start * kSampleRate).round();
        final f = midiToHz(m);
        for (var k = 0; k < n; k++) {
          final t = k / kSampleRate;
          final env = t < 0.02 ? t / 0.02 : math.exp(-t * (i == notes.length - 1 ? 1.6 : 6));
          lp.tune(500 + 2500 * env);
          final saw = (2 * ((t * f) % 1) - 1) + (2 * ((t * f * 1.004) % 1) - 1) + 0.5 * (2 * ((t * f * 2) % 1) - 1);
          b.add(si + k, lp.process(saw) * env * 0.12);
        }
      }
      _thud(b, notes.length * 0.12 - 0.12, 0.6, from: 110, to: 70, dur: 0.6);
      for (final m in [84, 88, 91]) {
        _bell(b, notes.length * 0.12, midiToHz(m), 0.06, dur: 1.4, ratio: 2, index: 1);
      }
      reverbMix = 0.35;
    case 'click':
      b = _Buf(0.06);
      _click(b, 0, 0.6, hz: 2200, q: 2, dur: 0.02);
    case 'page':
      b = _Buf(0.5);
      final hp = _Biquad.highpass(1500);
      final n = (0.4 * kSampleRate).round();
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        final crinkle = _rand.nextDouble() < 0.02 ? 3.0 : 1.0;
        final env = math.sin(math.pi * t / 0.4);
        b.add(i, hp.process(_noise()) * env * 0.25 * crinkle);
      }
    case 'roar':
      b = _Buf(1.8);
      final f1 = _Biquad.bandpass(420, q: 4), f2 = _Biquad.bandpass(950, q: 5), f3 = _Biquad.bandpass(2400, q: 6);
      final n = (1.5 * kSampleRate).round();
      var ph = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        final f = 85 - 20 * t + 6 * math.sin(t * 9);
        ph += f / kSampleRate;
        final src = (2 * (ph % 1) - 1) * (0.7 + 0.3 * math.sin(t * 2 * math.pi * 32)) + _noise() * 0.5;
        final env = t < 0.2 ? t / 0.2 : math.exp(-(t - 0.2) * 1.8);
        b.add(i, (f1.process(src) + f2.process(src) * 0.8 + f3.process(src) * 0.3) * env * 0.9);
      }
      reverbMix = 0.25;
    case 'death':
      b = _Buf(1.5);
      _thud(b, 0, 1, from: 120, to: 35, dur: 0.6);
      _tone(b, 0.05, 1.0, 220, 0.18, wave: 'tri', d: 1.0, sweep: -0.55);
      _tone(b, 0.05, 1.0, 233, 0.12, wave: 'tri', d: 1.0, sweep: -0.55);
      reverbMix = 0.3;
    case 'thunder':
      b = _Buf(3.0);
      _click(b, 0, 1, hz: 3000, q: 0.5, dur: 0.08);
      final lp = _Biquad.lowpass(180);
      final n = (2.8 * kSampleRate).round();
      var rumble = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        if (i % 400 == 0) rumble = 0.5 + _rand.nextDouble();
        final env = t < 0.05 ? t / 0.05 : math.exp(-t * 1.3);
        b.add(i, lp.process(_noise()) * env * rumble * 2.2);
      }
      reverbMix = 0.2;
    case 'chime':
      b = _Buf(2.0);
      for (final (i, m) in [84, 88, 91, 96].indexed) {
        _bell(b, i * 0.11, midiToHz(m), 0.14, dur: 1.5, ratio: 3.5, index: 2);
      }
      reverbMix = 0.45;
    case 'splash':
      b = _Buf(1.0);
      final hp = _Biquad.highpass(800);
      final n = (0.6 * kSampleRate).round();
      for (var i = 0; i < n; i++) {
        final t = i / kSampleRate;
        b.add(i, hp.process(_noise()) * math.exp(-t * 7) * 0.7);
      }
      for (var i = 0; i < 8; i++) {
        _tone(b, 0.05 + _rand.nextDouble() * 0.5, 0.05, 500 + _rand.nextDouble() * 700, 0.12, d: 0.05, sweep: 1.2);
      }
      reverbMix = 0.15;
    case 'footsteps':
      b = _Buf(1.7);
      for (var i = 0; i < 4; i++) {
        final t = i * 0.38 + _rand.nextDouble() * 0.03;
        _thud(b, t, 0.55, from: 110, to: 60, dur: 0.15);
        for (var g = 0; g < 6; g++) {
          _click(b, t + 0.01 + _rand.nextDouble() * 0.05, 0.15, hz: 2500 + _rand.nextDouble() * 2500, q: 2, dur: 0.006);
        }
      }
      reverbMix = 0.1;
    case 'flee':
      b = _Buf(1.2);
      for (var i = 0; i < 6; i++) {
        _thud(b, i * 0.14, 0.4, from: 120, to: 70, dur: 0.1);
        _click(b, i * 0.14, 0.12, hz: 3000, dur: 0.008);
      }
      _sweep(b, 0.2, 0.6, 600, 2400, 0.3, q: 1.2, attack: 0.5);
    default:
      b = _Buf(0.1);
      _click(b, 0, 0.5);
  }
  if (reverbMix > 0) _reverb(b, mix: reverbMix, wrap: false);
  b.fadeEdges();
  b.normalize(0.8);
  return encodeWav(b.data);
}

// ------------------------------------------------------------------- MUSIC

const musicThemes = ['menu', 'tavern', 'town', 'forest', 'dungeon', 'combat', 'mystery', 'triumph', 'calm', 'boss'];

String themeForScene(String location, String mood) {
  if (mood == 'combat') return 'combat';
  if (mood == 'triumph' || mood == 'festive') return 'triumph';
  if (mood == 'eerie' || mood == 'mystery') return 'mystery';
  return switch (location) {
    'tavern' => 'tavern',
    'town' => 'town',
    'forest' || 'plains' || 'road' || 'coast' || 'mountain' || 'swamp' || 'tundra' || 'desert' => 'forest',
    'camp' => 'calm',
    'dungeon' || 'cave' || 'crypt' || 'sewer' || 'tower' || 'temple' || 'castle' || 'ruins' => 'dungeon',
    _ => 'calm',
  };
}

/// Renders a seamless music loop for [theme]. Heavy: call in an isolate.
Uint8List renderMusic(String theme) {
  final spec = switch (theme) {
    'tavern' => (bpm: 112.0, beats: 32, root: 57, minor: false),
    'town' => (bpm: 92.0, beats: 32, root: 55, minor: false),
    'forest' => (bpm: 76.0, beats: 24, root: 62, minor: false),
    'dungeon' => (bpm: 58.0, beats: 16, root: 50, minor: true),
    'combat' => (bpm: 138.0, beats: 32, root: 52, minor: true),
    'boss' => (bpm: 150.0, beats: 32, root: 50, minor: true),
    'mystery' => (bpm: 64.0, beats: 16, root: 53, minor: true),
    'triumph' => (bpm: 100.0, beats: 32, root: 60, minor: false),
    'calm' => (bpm: 70.0, beats: 16, root: 60, minor: false),
    _ => (bpm: 66.0, beats: 24, root: 50, minor: true),
  };
  final beat = 60.0 / spec.bpm;
  final total = beat * spec.beats;
  final b = _Buf(total);
  final scale = spec.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11];
  int deg(int d) => spec.root + scale[d % 7] + 12 * (d ~/ 7);
  // chord progression (scale degrees of root)
  final prog = spec.minor ? [0, 5, 3, 4] : [0, 3, 4, 0];
  final prog2 = spec.minor ? [0, 6, 5, 4] : [0, 5, 3, 4];
  final chords = theme == 'menu' || theme == 'mystery' ? prog2 : prog;
  final barBeats = spec.beats / chords.length;
  final rnd = math.Random(stableSeed(theme));

  for (var c = 0; c < chords.length; c++) {
    final start = c * barBeats * beat;
    final dur = barBeats * beat;
    final d = chords[c];
    final triad = [deg(d), deg(d + 2), deg(d + 4)];
    // Pad
    if (theme != 'tavern') {
      for (final m in triad) {
        for (final det in [-0.004, 0.004]) {
          _tone(b, start, dur, midiToHz(m) * (1 + det), theme == 'combat' || theme == 'boss' ? 0.035 : 0.05, wave: 'saw', a: dur * 0.3, d: dur * 0.6, s: 0.6, r: dur * 0.4, wrap: true, vibrato: 0.002);
        }
      }
    }
    // Bass
    final bassAmp = theme == 'combat' || theme == 'boss' ? 0.22 : 0.16;
    if (theme == 'combat' || theme == 'boss') {
      for (var i = 0; i < barBeats * 2; i++) {
        _tone(b, start + i * beat / 2, beat / 2 * 0.9, midiToHz(triad[0] - 24), bassAmp, wave: 'saw', a: 0.005, d: beat * 0.4, s: 0.2, r: 0.05, wrap: true);
      }
    } else {
      _tone(b, start, dur, midiToHz(triad[0] - 12), bassAmp, wave: 'tri', a: 0.05, d: dur, s: 0.5, r: 0.3, wrap: true);
    }
    // Arpeggio / melody
    switch (theme) {
      case 'tavern':
      case 'town':
      case 'triumph':
        final pattern = [0, 1, 2, 1, 0, 2, 1, 2];
        final steps = (barBeats * 2).round();
        for (var i = 0; i < steps; i++) {
          final m = triad[pattern[i % pattern.length]] + (i % 4 == 3 ? 12 : 0);
          _pluck(b, start + i * beat / 2, midiToHz(m), 0.28, decay: 0.994, dur: beat * 1.6, wrap: true);
        }
        // melody on top
        for (var i = 0; i < barBeats; i++) {
          if (rnd.nextDouble() < 0.6) {
            final m = deg(d + 7 + rnd.nextInt(5));
            _pluck(b, start + i * beat, midiToHz(m), 0.2, decay: 0.996, dur: beat * 2, wrap: true, bright: 0.6);
          }
        }
        if (theme == 'tavern') {
          for (var i = 0; i < barBeats; i++) {
            _noiseBurst(b, start + i * beat, 0.08, i % 2 == 0 ? 0.25 : 0.12, lp: 0.3, wrap: true);
          }
        }
      case 'forest':
      case 'calm':
      case 'menu':
        for (var i = 0; i < barBeats; i++) {
          if (rnd.nextDouble() < 0.7) {
            final m = triad[rnd.nextInt(3)] + 12;
            _pluck(b, start + i * beat + rnd.nextDouble() * 0.05, midiToHz(m), 0.18, decay: 0.997, dur: beat * 3, wrap: true, bright: 0.45);
          }
        }
        if (theme == 'forest') {
          for (var k = 0; k < 3; k++) {
            final t = start + rnd.nextDouble() * dur;
            final f = 2600 + rnd.nextDouble() * 1400;
            _tone(b, t, 0.06, f, 0.04, d: 0.06, sweep: 0.3, wrap: true);
            _tone(b, t + 0.09, 0.08, f * 1.1, 0.035, d: 0.08, sweep: -0.2, wrap: true);
          }
        }
      case 'dungeon':
      case 'mystery':
        for (var i = 0; i < barBeats; i++) {
          if (rnd.nextDouble() < 0.4) {
            final m = deg(d + rnd.nextInt(7)) + 12;
            _tone(b, start + i * beat, beat * 2, midiToHz(m), 0.06, wave: 'sine', a: 0.01, d: beat * 2, r: beat, wrap: true, vibrato: 0.004);
          }
          if (theme == 'dungeon' && rnd.nextDouble() < 0.25) {
            // water drip
            _tone(b, start + i * beat + rnd.nextDouble() * beat, 0.05, 1200 + rnd.nextDouble() * 600, 0.08, d: 0.05, sweep: 1.5, wrap: true);
          }
        }
      case 'combat':
      case 'boss':
        final steps = (barBeats * 2).round();
        for (var i = 0; i < steps; i++) {
          final m = triad[(i * 2) % 3] + 12 + (i % 8 == 7 ? 12 : 0);
          _tone(b, start + i * beat / 2, beat / 2 * 0.8, midiToHz(m), 0.06, wave: 'square', a: 0.003, d: beat * 0.35, s: 0.1, r: 0.03, wrap: true);
        }
        for (var i = 0; i < barBeats; i++) {
          _kick(b, start + i * beat, 0.55, wrap: true);
          if (i % 2 == 1) _noiseBurst(b, start + i * beat, 0.14, 0.3, lp: 0.6, wrap: true);
          _noiseBurst(b, start + i * beat + beat / 2, 0.03, 0.1, lp: 0.95, hp: 0.9, wrap: true);
        }
    }
  }
  _reverb(b, mix: theme == 'combat' || theme == 'boss' ? 0.18 : 0.4);
  b.normalize(0.7);
  return encodeWav(b.data);
}

int stableSeed(String s) => s.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x3FFFFFFF);

// ------------------------------------------------------------------ ambience

/// Weather and place soundscapes, rendered as seamless loops.
const ambienceNames = ['rain', 'storm', 'wind', 'snow', 'forest', 'cave', 'crowd', 'fire', 'surf'];

/// Crossfades the tail of [raw] into its head so playback loops without a click.
Float32List _loopify(Float32List raw, int length, int fade) {
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    out[i] = raw[i];
  }
  for (var i = 0; i < fade; i++) {
    final t = i / fade;
    out[i] = raw[i] * t + raw[length + i] * (1 - t);
  }
  return out;
}

Uint8List renderAmbience(String kind) {
  const seconds = 10.0;
  final length = (seconds * kSampleRate).round();
  final fade = (1.5 * kSampleRate).round();
  final total = length + fade;
  final raw = Float32List(total);
  final r = math.Random(kind.hashCode);
  double n() => r.nextDouble() * 2 - 1;

  // Shaped noise bed shared by most soundscapes.
  void bed(double lp, double hp, double amp, {double lfoHz = 0, double lfoDepth = 0}) {
    final low = _Biquad.lowpass(lp);
    final high = _Biquad.highpass(hp);
    for (var i = 0; i < total; i++) {
      final t = i / kSampleRate;
      final lfo = lfoHz == 0 ? 1.0 : 1 - lfoDepth * (0.5 + 0.5 * math.sin(2 * math.pi * lfoHz * t + math.sin(t * 0.37) * 2));
      raw[i] += high.process(low.process(n())) * amp * lfo;
    }
  }

  // Short filtered clicks (raindrops, drips, crackles).
  void drops(int count, double minHz, double maxHz, double amp, double decay) {
    for (var k = 0; k < count; k++) {
      final start = r.nextInt(total);
      final hz = minHz + r.nextDouble() * (maxHz - minHz);
      final a = amp * (0.3 + r.nextDouble() * 0.7);
      final len = (decay * kSampleRate).round();
      for (var i = 0; i < len && start + i < total; i++) {
        final t = i / kSampleRate;
        raw[start + i] += math.sin(2 * math.pi * hz * t * (1 + t * 3)) * a * math.exp(-t / (decay / 5));
      }
    }
  }

  void birds(int count) {
    for (var k = 0; k < count; k++) {
      final start = r.nextInt(total);
      final base = 2400 + r.nextDouble() * 1800;
      final notes = 2 + r.nextInt(4);
      for (var j = 0; j < notes; j++) {
        final s0 = start + j * (0.09 * kSampleRate).round();
        final len = (0.07 * kSampleRate).round();
        for (var i = 0; i < len && s0 + i < total; i++) {
          final t = i / len;
          raw[s0 + i] += math.sin(2 * math.pi * (base + 900 * math.sin(t * math.pi)) * i / kSampleRate) * 0.12 * math.sin(t * math.pi);
        }
      }
    }
  }

  void rumble(double at, double amp) {
    final low = _Biquad.lowpass(120);
    final start = (at * kSampleRate).round();
    final len = (3.5 * kSampleRate).round();
    for (var i = 0; i < len && start + i < total; i++) {
      final t = i / kSampleRate;
      raw[start + i] += low.process(n()) * amp * math.min(1, t * 8) * math.exp(-t / 1.2);
    }
  }

  switch (kind) {
    case 'rain':
      bed(5200, 400, 0.35, lfoHz: 0.08, lfoDepth: 0.25);
      drops(900, 2500, 6000, 0.12, 0.012);
    case 'storm':
      bed(4200, 200, 0.45, lfoHz: 0.12, lfoDepth: 0.4);
      drops(1300, 2000, 5500, 0.14, 0.012);
      rumble(2.5, 1.6);
      rumble(7.2, 1.1);
    case 'wind':
      bed(900, 120, 0.9, lfoHz: 0.09, lfoDepth: 0.75);
      bed(2400, 1200, 0.08, lfoHz: 0.21, lfoDepth: 0.9);
    case 'snow':
      bed(1600, 300, 0.35, lfoHz: 0.06, lfoDepth: 0.6);
    case 'forest':
      bed(1800, 200, 0.18, lfoHz: 0.07, lfoDepth: 0.5);
      birds(9);
    case 'cave':
      bed(220, 40, 0.5, lfoHz: 0.05, lfoDepth: 0.3);
      drops(14, 900, 1800, 0.35, 0.18);
    case 'crowd':
      for (var v = 0; v < 6; v++) {
        bed(500 + v * 160.0, 180 + v * 40.0, 0.12, lfoHz: 0.6 + v * 0.27, lfoDepth: 0.9);
      }
      drops(10, 3000, 4200, 0.08, 0.04); // clinking mugs
    case 'fire':
      bed(700, 60, 0.4, lfoHz: 0.3, lfoDepth: 0.3);
      drops(260, 800, 4000, 0.28, 0.008);
    case 'surf':
      bed(1100, 80, 0.9, lfoHz: 0.11, lfoDepth: 0.85);
      bed(5000, 2500, 0.05, lfoHz: 0.11, lfoDepth: 0.9);
    default:
      bed(800, 100, 0.2);
  }
  final out = _loopify(raw, length, fade);
  var peak = 0.0;
  for (final s in out) {
    peak = math.max(peak, s.abs());
  }
  if (peak > 0) {
    for (var i = 0; i < out.length; i++) {
      out[i] = out[i] / peak * 0.7;
    }
  }
  return encodeWav(out);
}

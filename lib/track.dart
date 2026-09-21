import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';

const double kWorldW = 720;
const double kWorldH = 1440;
const double kRoadHalf = 64;
const double kCurb = 9;
const double kBarrier = 112;
const double kSpacing = 12;
const int kWindow = 20;

double wrapPi(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

class TrackDef {
  final String name;
  final String level;
  final int seed;
  final List<List<num>> ctrl;

  const TrackDef(this.name, this.level, this.seed, this.ctrl);
}

const List<TrackDef> kTrackDefs = <TrackDef>[
  TrackDef('Dirt Loop', 'Medium', 11, <List<num>>[
    <num>[100, 830],
    <num>[100, 600],
    <num>[105, 380],
    <num>[175, 215],
    <num>[335, 140],
    <num>[520, 155],
    <num>[640, 290],
    <num>[610, 470],
    <num>[500, 590],
    <num>[395, 715],
    <num>[380, 860],
    <num>[450, 975],
    <num>[590, 1040],
    <num>[640, 1170],
    <num>[565, 1295],
    <num>[380, 1345],
    <num>[210, 1325],
    <num>[110, 1215],
    <num>[95, 1030],
  ]),
  TrackDef('Speedway', 'Easy', 23, <List<num>>[
    <num>[110, 720],
    <num>[118, 450],
    <num>[200, 225],
    <num>[360, 150],
    <num>[520, 225],
    <num>[602, 450],
    <num>[610, 720],
    <num>[602, 990],
    <num>[520, 1215],
    <num>[360, 1290],
    <num>[200, 1215],
    <num>[118, 990],
  ]),
  TrackDef('Switchback', 'Hard', 37, <List<num>>[
    <num>[100, 830],
    <num>[100, 300],
    <num>[144, 194],
    <num>[250, 150],
    <num>[360, 150],
    <num>[470, 150],
    <num>[576, 194],
    <num>[620, 300],
    <num>[620, 395],
    <num>[583, 483],
    <num>[490, 520],
    <num>[397, 557],
    <num>[360, 645],
    <num>[360, 765],
    <num>[397, 853],
    <num>[490, 890],
    <num>[583, 927],
    <num>[620, 1015],
    <num>[620, 1110],
    <num>[576, 1216],
    <num>[470, 1260],
    <num>[250, 1260],
    <num>[144, 1216],
    <num>[100, 1110],
  ]),
  TrackDef('Hourglass', 'Easy', 41, <List<num>>[
    <num>[222, 720],
    <num>[210, 600],
    <num>[150, 480],
    <num>[108, 340],
    <num>[150, 215],
    <num>[270, 145],
    <num>[450, 145],
    <num>[570, 215],
    <num>[612, 340],
    <num>[585, 480],
    <num>[510, 600],
    <num>[498, 720],
    <num>[510, 840],
    <num>[585, 960],
    <num>[612, 1100],
    <num>[570, 1225],
    <num>[450, 1295],
    <num>[270, 1295],
    <num>[150, 1225],
    <num>[108, 1100],
    <num>[140, 960],
    <num>[210, 840],
  ]),
];

class Obstacle {
  final double x;
  final double y;
  final double r;
  final int kind; // 0 tree, 1 pond, 2 rock, 3 tire

  const Obstacle(this.x, this.y, this.r, this.kind);
}

class Track {
  static final Map<int, Track> _cache = <int, Track>{};

  static Track byId(int id) {
    final i = (id < 0 || id >= kTrackDefs.length) ? 0 : id;
    return _cache.putIfAbsent(i, () => Track(kTrackDefs[i]));
  }

  final TrackDef def;
  late final int count;
  late final double ds;
  late final double length;
  late final Float64List px;
  late final Float64List py;
  late final Float64List ang;
  late final Float64List kap;
  late final Float64List safe;
  late final List<Obstacle> obs;

  Track(this.def) {
    _build();
  }

  static double _cr(double a, double b, double c, double d, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
  }

  void _build() {
    final c = def.ctrl;
    final n = c.length;
    final dense = <double>[];
    for (int i = 0; i < n; i++) {
      final p0 = c[(i - 1 + n) % n];
      final p1 = c[i];
      final p2 = c[(i + 1) % n];
      final p3 = c[(i + 2) % n];
      for (int k = 0; k < 24; k++) {
        final t = k / 24.0;
        dense.add(_cr(p0[0].toDouble(), p1[0].toDouble(), p2[0].toDouble(), p3[0].toDouble(), t));
        dense.add(_cr(p0[1].toDouble(), p1[1].toDouble(), p2[1].toDouble(), p3[1].toDouble(), t));
      }
    }
    final m = dense.length ~/ 2;
    final cum = List<double>.filled(m + 1, 0.0);
    for (int i = 0; i < m; i++) {
      final nj = (i + 1) % m;
      final dx = dense[2 * nj] - dense[2 * i];
      final dy = dense[2 * nj + 1] - dense[2 * i + 1];
      cum[i + 1] = cum[i] + math.sqrt(dx * dx + dy * dy);
    }
    final total = cum[m];
    final cnt = (total / kSpacing).round();
    final step = total / cnt;
    final xs = Float64List(cnt);
    final ys = Float64List(cnt);
    int w = 0;
    for (int i = 0; i < cnt; i++) {
      final target = i * step;
      while (w < m - 1 && cum[w + 1] < target) {
        w++;
      }
      final seg = cum[w + 1] - cum[w];
      final f = seg == 0 ? 0.0 : (target - cum[w]) / seg;
      final a = w;
      final b = (w + 1) % m;
      xs[i] = dense[2 * a] + (dense[2 * b] - dense[2 * a]) * f;
      ys[i] = dense[2 * a + 1] + (dense[2 * b + 1] - dense[2 * a + 1]) * f;
    }
    final an = Float64List(cnt);
    for (int i = 0; i < cnt; i++) {
      final a = (i - 1 + cnt) % cnt;
      final b = (i + 1) % cnt;
      an[i] = math.atan2(ys[b] - ys[a], xs[b] - xs[a]);
    }
    final kp = Float64List(cnt);
    for (int i = 0; i < cnt; i++) {
      final a = an[(i - 3 + cnt) % cnt];
      final b = an[(i + 3) % cnt];
      kp[i] = wrapPi(b - a).abs() / (6 * step);
    }
    final ks = Float64List(cnt);
    for (int i = 0; i < cnt; i++) {
      double s = 0;
      for (int o = -2; o <= 2; o++) {
        s += kp[(i + o + cnt) % cnt];
      }
      ks[i] = s / 5;
    }
    final corner = Float64List(cnt);
    for (int i = 0; i < cnt; i++) {
      final v = 2.0 / math.max(ks[i], 1e-4);
      corner[i] = math.max(150.0, math.min(1000.0, v));
    }
    final sf = Float64List(cnt);
    for (int i = 0; i < cnt; i++) {
      double v = 1e9;
      for (int o = 0; o < 16; o++) {
        v = math.min(v, corner[(i + o) % cnt]);
      }
      sf[i] = v;
    }
    count = cnt;
    ds = step;
    length = step * cnt;
    px = xs;
    py = ys;
    ang = an;
    kap = ks;
    safe = sf;
    obs = _makeObstacles();
  }

  double _distToCenter(double x, double y) {
    double best = 1e18;
    for (int i = 0; i < count; i++) {
      final dx = x - px[i];
      final dy = y - py[i];
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
      }
    }
    return math.sqrt(best);
  }

  List<Obstacle> _makeObstacles() {
    final rnd = math.Random(def.seed);
    final list = <Obstacle>[];
    final start = (count * 0.06).round();
    const double off = kRoadHalf + kCurb + 15;
    for (int k = 0; k < 10; k++) {
      final i = (start + k * 2) % count;
      final a = ang[i];
      list.add(Obstacle(px[i] - math.sin(a) * off, py[i] + math.cos(a) * off, 11, 3));
    }
    int tries = 0;
    while (list.length < 30 && tries < 1200) {
      tries++;
      final roll = rnd.nextInt(10);
      final kind = roll < 2 ? 1 : (roll < 3 ? 2 : 0);
      final r = kind == 1 ? 44.0 : (kind == 2 ? 17.0 : 27.0);
      final x = r + 12 + rnd.nextDouble() * (kWorldW - 2 * r - 24);
      final y = r + 12 + rnd.nextDouble() * (kWorldH - 2 * r - 24);
      if (_distToCenter(x, y) < kRoadHalf + kCurb + r + 10) {
        continue;
      }
      bool ok = true;
      for (final o in list) {
        final dx = o.x - x;
        final dy = o.y - y;
        final need = o.r + r + 16;
        if (dx * dx + dy * dy < need * need) {
          ok = false;
          break;
        }
      }
      if (ok) {
        list.add(Obstacle(x, y, r, kind));
      }
    }
    return list;
  }
}

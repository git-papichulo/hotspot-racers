import 'dart:math' as math;

import 'model.dart';
import 'track.dart';

const double kMaxSpeed = 290;
const double kAccel = 210;
const double kBrake = 460;
const double kTurnRate = 2.7;
const double kGrip = 12;
const double kOffroad = 0.55;
const double kCarRadius = 16;
const double kStep = 1 / 60.0;

class Car {
  final int slot;
  String name;
  int color;
  bool isBot;
  int humanId;

  double x = 0;
  double y = 0;
  double a = 0;
  double vx = 0;
  double vy = 0;
  double steer = 0;
  double inSteer = 0;
  bool inBrake = false;

  int idx = 0;
  double dist = 0;
  int crossings = 0;
  double progress = 0;
  bool finished = false;
  double finishTime = 0;
  int place = 1;

  double skill = 1.0;
  double lane = 0;
  double laneTimer = 0;
  final math.Random rnd = math.Random();

  Car(this.slot, this.name, this.color, {this.isBot = false, this.humanId = -1});

  double get speed => math.sqrt(vx * vx + vy * vy);
}

void locateCar(Track t, Car c) {
  final n = t.count;
  int best = c.idx;
  double bd = double.infinity;
  for (int o = -kWindow; o <= kWindow; o++) {
    final i = (c.idx + o + n) % n;
    final dx = c.x - t.px[i];
    final dy = c.y - t.py[i];
    final d = dx * dx + dy * dy;
    if (d < bd) {
      bd = d;
      best = i;
    }
  }
  final prev = c.idx;
  if (prev > n * 3 ~/ 4 && best < n ~/ 4) {
    c.crossings++;
  } else if (prev < n ~/ 4 && best > n * 3 ~/ 4) {
    c.crossings--;
  }
  c.idx = best;
  c.dist = math.sqrt(bd);
  c.progress = c.crossings * t.length + best * t.ds;
}

/// Global nearest-sample search (used once when a car is created).
void snapToTrack(Track t, Car c) {
  int best = 0;
  double bd = double.infinity;
  for (int i = 0; i < t.count; i++) {
    final dx = c.x - t.px[i];
    final dy = c.y - t.py[i];
    final d = dx * dx + dy * dy;
    if (d < bd) {
      bd = d;
      best = i;
    }
  }
  c.idx = best;
  c.dist = math.sqrt(bd);
  c.crossings = 0;
}

void stepCar(Car c, double dt, Track tr, bool go) {
  c.steer += (c.inSteer - c.steer) * math.min(1.0, 10 * dt);
  final spd0 = math.sqrt(c.vx * c.vx + c.vy * c.vy);
  double fx = math.cos(c.a);
  double fy = math.sin(c.a);
  double vf = c.vx * fx + c.vy * fy;
  if (go) {
    final turn = c.steer * kTurnRate * math.min(1.0, spd0 / 130.0) * (vf >= 0 ? 1.0 : -1.0);
    c.a += turn * dt;
  }
  fx = math.cos(c.a);
  fy = math.sin(c.a);
  vf = c.vx * fx + c.vy * fy;
  double vl = -c.vx * fy + c.vy * fx;
  final onRoad = c.dist <= kRoadHalf + 6;
  final vmax = kMaxSpeed * (onRoad ? 1.0 : kOffroad) * c.skill;
  if (go) {
    if (c.inBrake) {
      vf -= kBrake * dt;
      if (vf < -70) {
        vf = -70;
      }
    } else if (vf < vmax) {
      vf = math.min(vmax, vf + kAccel * dt);
    } else {
      vf -= (vf - vmax) * math.min(1.0, 3.0 * dt);
    }
  } else {
    vf *= math.max(0.0, 1 - 4 * dt);
  }
  vf -= vf * c.steer.abs() * 0.30 * dt;
  vl *= math.exp(-kGrip * dt);
  c.vx = fx * vf - fy * vl;
  c.vy = fy * vf + fx * vl;
  c.x += c.vx * dt;
  c.y += c.vy * dt;
  locateCar(tr, c);
  if (c.dist > kBarrier) {
    final i = c.idx;
    final k = kBarrier / c.dist;
    final nx = (c.x - tr.px[i]) / c.dist;
    final ny = (c.y - tr.py[i]) / c.dist;
    c.x = tr.px[i] + (c.x - tr.px[i]) * k;
    c.y = tr.py[i] + (c.y - tr.py[i]) * k;
    final vo = c.vx * nx + c.vy * ny;
    if (vo > 0) {
      c.vx -= nx * vo * 1.4;
      c.vy -= ny * vo * 1.4;
    }
    c.vx *= 0.96;
    c.vy *= 0.96;
    c.dist = kBarrier;
  }
  for (final o in tr.obs) {
    final dx = c.x - o.x;
    final dy = c.y - o.y;
    final rr = o.r + kCarRadius;
    final d2 = dx * dx + dy * dy;
    if (d2 < rr * rr && d2 > 0.0001) {
      final d = math.sqrt(d2);
      final nx = dx / d;
      final ny = dy / d;
      c.x = o.x + nx * rr;
      c.y = o.y + ny * rr;
      final vn = c.vx * nx + c.vy * ny;
      if (vn < 0) {
        c.vx -= nx * vn * 1.5;
        c.vy -= ny * vn * 1.5;
      }
      c.vx *= 0.85;
      c.vy *= 0.85;
    }
  }
}

void botControl(Car c, Track tr, double dt) {
  final n = tr.count;
  final spd = c.speed;
  c.laneTimer -= dt;
  if (c.laneTimer <= 0) {
    c.laneTimer = 1.0 + c.rnd.nextDouble() * 2.0;
    c.lane = (c.rnd.nextDouble() * 2 - 1) * 30;
  }
  final look = 4 + (spd / 55).floor();
  final ti = (c.idx + look) % n;
  final nx = -math.sin(tr.ang[ti]);
  final ny = math.cos(tr.ang[ti]);
  final tx = tr.px[ti] + nx * c.lane;
  final ty = tr.py[ti] + ny * c.lane;
  final desired = math.atan2(ty - c.y, tx - c.x);
  final diff = wrapPi(desired - c.a);
  c.inSteer = (diff * 2.4).clamp(-1.0, 1.0).toDouble();
  final vs = tr.safe[c.idx] * c.skill;
  c.inBrake = spd > vs * 1.08;
}

void placeOnGrid(Track t, List<Car> cars, math.Random rnd) {
  final order = List<int>.generate(cars.length, (int i) => i);
  order.shuffle(rnd);
  final n = t.count;
  for (int k = 0; k < cars.length; k++) {
    final c = cars[order[k]];
    final row = k ~/ 2;
    final col = k % 2;
    final idx = (n - ((40 + row * 55) / t.ds).round()) % n;
    final a = t.ang[idx];
    final off = col == 0 ? -26.0 : 26.0;
    c.x = t.px[idx] - math.sin(a) * off;
    c.y = t.py[idx] + math.cos(a) * off;
    c.a = a;
    c.vx = 0;
    c.vy = 0;
    c.steer = 0;
    c.idx = idx;
    c.crossings = 0;
    c.finished = false;
    locateCar(t, c);
  }
}

class RaceSim {
  final Track track;
  final int laps;
  final List<Car> cars;

  RacePhase phase = RacePhase.countdown;
  double clock = -3.5;
  double _acc = 0;
  double _firstFinish = -1;

  RaceSim(this.track, this.laps, this.cars);

  void update(double frameDt) {
    _acc += frameDt;
    if (_acc > 0.25) {
      _acc = 0.25;
    }
    while (_acc >= kStep) {
      _acc -= kStep;
      _tick(kStep);
    }
  }

  void _tick(double dt) {
    if (phase == RacePhase.countdown) {
      clock += dt;
      if (clock >= 0) {
        phase = RacePhase.racing;
      }
    } else if (phase == RacePhase.racing) {
      clock += dt;
    }
    final go = phase == RacePhase.racing;
    for (final c in cars) {
      if (go && (c.isBot || c.finished)) {
        botControl(c, track, dt);
      }
      stepCar(c, dt, track, go);
      if (go && !c.finished && c.crossings > laps) {
        c.finished = true;
        c.finishTime = clock;
        if (_firstFinish < 0) {
          _firstFinish = clock;
        }
      }
    }
    _collide();
    _rank();
    if (phase == RacePhase.racing) {
      bool humansLeft = false;
      for (final c in cars) {
        if (!c.isBot && !c.finished) {
          humansLeft = true;
        }
      }
      final timeout = _firstFinish >= 0 && clock - _firstFinish > 30;
      if (!humansLeft || timeout) {
        phase = RacePhase.finished;
      }
    }
  }

  void _collide() {
    const double r2 = kCarRadius * 2;
    for (int i = 0; i < cars.length; i++) {
      final a = cars[i];
      if (a.finished) {
        continue;
      }
      for (int j = i + 1; j < cars.length; j++) {
        final b = cars[j];
        if (b.finished) {
          continue;
        }
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= r2 * r2 || d2 < 0.0001) {
          continue;
        }
        final d = math.sqrt(d2);
        final nx = dx / d;
        final ny = dy / d;
        final overlap = r2 - d;
        a.x -= nx * overlap * 0.5;
        a.y -= ny * overlap * 0.5;
        b.x += nx * overlap * 0.5;
        b.y += ny * overlap * 0.5;
        final rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
        if (rv < 0) {
          final imp = -rv * 0.6;
          a.vx -= nx * imp;
          a.vy -= ny * imp;
          b.vx += nx * imp;
          b.vy += ny * imp;
        }
      }
    }
  }

  void _rank() {
    final order = List<Car>.from(cars);
    order.sort((Car a, Car b) {
      if (a.finished && b.finished) {
        return a.finishTime.compareTo(b.finishTime);
      }
      if (a.finished) {
        return -1;
      }
      if (b.finished) {
        return 1;
      }
      return b.progress.compareTo(a.progress);
    });
    for (int i = 0; i < order.length; i++) {
      order[i].place = i + 1;
    }
  }
}

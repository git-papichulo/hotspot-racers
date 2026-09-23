import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';
import 'session.dart';
import 'sim.dart';
import 'track.dart';

const Color _grassA = Color(0xFF8CB30B);
const Color _grassB = Color(0xFF83AA07);
const Color _curbCol = Color(0xFFD9A521);
const Color _roadCol = Color(0xFF6D4A3A);
const Color _ink = Color(0xFF111111);

/// World units visible top-to-bottom in the in-race chase camera. Smaller =
/// closer / more zoomed in. Tune this to taste.
const double kCameraViewH = 640;

Future<ui.Image> renderTrackImage(Track t, double scale) async {
  final w = (kWorldW * scale).round();
  final h = (kWorldH * scale).round();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.scale(scale, scale);
  paintWorld(canvas, t);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  return img;
}

Path _trackPath(Track t) {
  final path = Path()..moveTo(t.px[0], t.py[0]);
  for (int i = 1; i < t.count; i++) {
    path.lineTo(t.px[i], t.py[i]);
  }
  path.close();
  return path;
}

void paintWorld(Canvas canvas, Track t) {
  final p = Paint()..isAntiAlias = true;
  p.style = PaintingStyle.fill;
  p.color = _grassA;
  canvas.drawRect(Rect.fromLTWH(0, 0, kWorldW, kWorldH), p);
  p.color = _grassB;
  for (int r = 0; r < 16; r++) {
    for (int c = 0; c < 8; c++) {
      if ((r + c) % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(c * 90.0, r * 90.0, 90, 90), p);
      }
    }
  }

  // road: yellow curb band, then dirt on top
  final path = _trackPath(t);
  p.style = PaintingStyle.stroke;
  p.strokeCap = StrokeCap.round;
  p.strokeJoin = StrokeJoin.round;
  p.strokeWidth = 2 * (kRoadHalf + kCurb);
  p.color = _curbCol;
  canvas.drawPath(path, p);
  p.strokeWidth = 2 * kRoadHalf;
  p.color = _roadCol;
  canvas.drawPath(path, p);

  // dirt scuffs
  final rnd = math.Random(t.def.seed + 99);
  for (int k = 0; k < 90; k++) {
    final i = rnd.nextInt(t.count);
    final a = t.ang[i];
    final off = (rnd.nextDouble() * 2 - 1) * (kRoadHalf - 14);
    final cx = t.px[i] - math.sin(a) * off;
    final cy = t.py[i] + math.cos(a) * off;
    final len = 10 + rnd.nextDouble() * 22;
    p.strokeWidth = 3 + rnd.nextDouble() * 3;
    p.color = (k % 3 == 0) ? const Color(0x22FFFFFF) : const Color(0x33381F14);
    canvas.drawLine(Offset(cx, cy), Offset(cx + math.cos(a) * len, cy + math.sin(a) * len), p);
  }

  // checkered start line
  p.style = PaintingStyle.fill;
  canvas.save();
  canvas.translate(t.px[0], t.py[0]);
  canvas.rotate(t.ang[0]);
  const double cell = 2 * kRoadHalf / 8;
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 2; col++) {
      p.color = ((row + col) % 2 == 0) ? const Color(0xFFFFFFFF) : _ink;
      canvas.drawRect(Rect.fromLTWH(-cell + col * cell, -kRoadHalf + row * cell, cell, cell), p);
    }
  }
  canvas.restore();

  // obstacles
  for (final o in t.obs) {
    if (o.kind == 0) {
      _tree(canvas, p, o);
    } else if (o.kind == 1) {
      _pond(canvas, p, o);
    } else if (o.kind == 2) {
      _rock(canvas, p, o);
    } else {
      _tire(canvas, p, o);
    }
  }
}

void _tree(Canvas c, Paint p, Obstacle o) {
  final x = o.x;
  final y = o.y;
  final r = o.r;
  p.style = PaintingStyle.fill;
  p.color = const Color(0x33000000);
  c.drawOval(Rect.fromCenter(center: Offset(x + 6, y + 10), width: r * 2.6, height: r * 1.9), p);
  p.color = _ink;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + r * 0.5, y - 6, r, 14), Radius.circular(5)), p);
  p.color = const Color(0xFF7B5236);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + r * 0.55, y - 3, r * 0.9, 8), Radius.circular(4)), p);
  final blobs = <List<double>>[
    <double>[0.0, 0.0, 0.78],
    <double>[-0.5, 0.1, 0.55],
    <double>[0.35, -0.42, 0.5],
    <double>[0.1, 0.5, 0.5],
  ];
  p.color = _ink;
  for (final b in blobs) {
    c.drawCircle(Offset(x + b[0] * r, y + b[1] * r), r * b[2] + 4, p);
  }
  p.color = const Color(0xFF32B45A);
  for (final b in blobs) {
    c.drawCircle(Offset(x + b[0] * r, y + b[1] * r), r * b[2], p);
  }
  p.color = const Color(0x3300400F);
  c.drawCircle(Offset(x + r * 0.15, y + r * 0.2), r * 0.35, p);
  p.color = const Color(0x44FFFFFF);
  c.drawCircle(Offset(x - r * 0.25, y - r * 0.25), r * 0.25, p);
}

void _pond(Canvas c, Paint p, Obstacle o) {
  p.style = PaintingStyle.fill;
  p.color = const Color(0x33C5E86A);
  c.drawCircle(Offset(o.x, o.y), o.r + 18, p);
  final blobs = <List<double>>[
    <double>[0.0, 0.0, 0.85],
    <double>[-0.4, 0.4, 0.6],
    <double>[0.35, -0.35, 0.6],
  ];
  p.color = _ink;
  for (final b in blobs) {
    c.drawCircle(Offset(o.x + b[0] * o.r, o.y + b[1] * o.r), o.r * b[2] + 5, p);
  }
  p.color = const Color(0xFF12B5C9);
  for (final b in blobs) {
    c.drawCircle(Offset(o.x + b[0] * o.r, o.y + b[1] * o.r), o.r * b[2], p);
  }
  p.color = const Color(0x55FFFFFF);
  c.drawCircle(Offset(o.x - o.r * 0.25, o.y - o.r * 0.3), o.r * 0.22, p);
}

void _rock(Canvas c, Paint p, Obstacle o) {
  p.style = PaintingStyle.fill;
  p.color = const Color(0x33000000);
  c.drawOval(Rect.fromCenter(center: Offset(o.x + 4, o.y + 7), width: o.r * 2.4, height: o.r * 1.6), p);
  p.color = _ink;
  c.drawCircle(Offset(o.x, o.y), o.r + 4, p);
  c.drawCircle(Offset(o.x + o.r * 0.5, o.y + o.r * 0.2), o.r * 0.7 + 4, p);
  p.color = const Color(0xFF8A939B);
  c.drawCircle(Offset(o.x, o.y), o.r, p);
  c.drawCircle(Offset(o.x + o.r * 0.5, o.y + o.r * 0.2), o.r * 0.7, p);
  p.color = const Color(0x55FFFFFF);
  c.drawCircle(Offset(o.x - o.r * 0.3, o.y - o.r * 0.3), o.r * 0.3, p);
}

void _tire(Canvas c, Paint p, Obstacle o) {
  p.style = PaintingStyle.fill;
  p.color = const Color(0x33000000);
  c.drawCircle(Offset(o.x + 2, o.y + 3), o.r, p);
  p.color = _ink;
  c.drawCircle(Offset(o.x, o.y), o.r, p);
  p.color = const Color(0xFF3E4650);
  c.drawCircle(Offset(o.x, o.y), o.r * 0.62, p);
  p.color = _ink;
  c.drawCircle(Offset(o.x, o.y), o.r * 0.36, p);
}

void drawCar(Canvas canvas, Car c, Paint p) {
  canvas.save();
  canvas.translate(c.x, c.y);
  canvas.rotate(c.a);
  p.style = PaintingStyle.fill;
  p.color = const Color(0x55000000);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-19, -9, 44, 24), Radius.circular(9)), p);
  p.color = _ink;
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-24, -14, 48, 28), Radius.circular(10)), p);
  p.color = kPalette[c.color % kPalette.length];
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-22, -12, 44, 24), Radius.circular(8)), p);
  p.color = const Color(0xCCFFFFFF);
  canvas.drawRect(Rect.fromLTWH(-20, -2.5, 30, 5), p);
  p.color = const Color(0xFF263238);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-2, -8, 13, 16), Radius.circular(4)), p);
  p.color = const Color(0xFFFFF176);
  canvas.drawCircle(Offset(20, -7), 2.5, p);
  canvas.drawCircle(Offset(20, 7), 2.5, p);
  canvas.restore();
}

void drawPin(Canvas canvas, double x, double y, Paint p) {
  final tri = Path()
    ..moveTo(x - 9, y - 40)
    ..lineTo(x + 9, y - 40)
    ..lineTo(x, y - 24)
    ..close();
  p.style = PaintingStyle.stroke;
  p.strokeWidth = 5;
  p.strokeJoin = StrokeJoin.round;
  p.color = _ink;
  canvas.drawPath(tri, p);
  p.style = PaintingStyle.fill;
  p.color = const Color(0xFFFFEB3B);
  canvas.drawPath(tri, p);
  p.color = _ink;
  canvas.drawCircle(Offset(x, y - 44), 14, p);
  p.color = const Color(0xFFFFEB3B);
  canvas.drawCircle(Offset(x, y - 44), 10, p);
  p.color = _ink;
  canvas.drawCircle(Offset(x, y - 44), 4, p);
}

class RacePainter extends CustomPainter {
  final Session s;
  final ui.Image? bg;
  final Paint _p = Paint()..isAntiAlias = true;
  final Paint _img = Paint()..filterQuality = ui.FilterQuality.low;

  RacePainter(this.s, this.bg, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    _p.style = PaintingStyle.fill;
    _p.color = _grassA;
    canvas.drawRect(Offset.zero & size, _p);

    final me = s.myCar;
    canvas.save();
    if (me != null) {
      // Close chase camera: follow the player's own car and zoom in for an
      // immersive, driver's-eye feel instead of showing the whole track.
      final zoom = size.height / kCameraViewH;
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(zoom, zoom);
      canvas.translate(-me.x, -me.y);
    } else {
      // No car of our own yet (e.g. between races) - fall back to a full
      // fit-the-track view instead of centering on nothing.
      final scale = math.min(size.width / kWorldW, size.height / kWorldH);
      canvas.translate((size.width - kWorldW * scale) / 2, (size.height - kWorldH * scale) / 2);
      canvas.scale(scale, scale);
    }
    final image = bg;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, kWorldW, kWorldH),
        _img,
      );
    }
    for (final c in s.cars) {
      if (c != me) {
        drawCar(canvas, c, _p);
      }
    }
    if (me != null) {
      drawCar(canvas, me, _p);
      drawPin(canvas, me.x, me.y, _p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RacePainter old) => old.bg != bg || old.s != s;
}

class TrackPreviewPainter extends CustomPainter {
  final Track t;

  TrackPreviewPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final sc = math.min(size.width / kWorldW, size.height / kWorldH);
    final ox = (size.width - kWorldW * sc) / 2;
    final oy = (size.height - kWorldH * sc) / 2;
    final p = Paint()..isAntiAlias = true;
    p.color = _grassA;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(8)), p);
    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(sc, sc);
    final path = _trackPath(t);
    p.style = PaintingStyle.stroke;
    p.strokeCap = StrokeCap.round;
    p.strokeJoin = StrokeJoin.round;
    p.strokeWidth = 2 * (kRoadHalf + kCurb);
    p.color = _curbCol;
    canvas.drawPath(path, p);
    p.strokeWidth = 2 * kRoadHalf;
    p.color = _roadCol;
    canvas.drawPath(path, p);
    p.style = PaintingStyle.fill;
    p.color = _ink;
    canvas.drawCircle(Offset(t.px[0], t.py[0]), 46, p);
    p.color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(t.px[0], t.py[0]), 32, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TrackPreviewPainter old) => old.t != t;
}

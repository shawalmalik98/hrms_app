// Draws the app icon: a bold, fast-leaning "N" (Nexora) in light colours on the
// dark brand teal. Like a real italic letter: two full-height stems and a mint
// diagonal joining them, all leaning the same way. Run
// `dart run tool/make_icon.dart`, then `dart run flutter_launcher_icons` to put
// it into the Android / iOS projects.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';

const size = 1024;

// The letter, drawn upright first and then leaned. It stays inside the middle
// ~65% so Android's adaptive icon masks never cut a corner.
const _x0 = 312.0, _x1 = 712.0, _y0 = 302.0, _y1 = 722.0;
const _stem = 104.0; // width of a stem
const _round = 10.0; // a hint of rounding on the corners
const _lean = 0.30; // how far the top leans to the right
const _band =
    1.2; // the diagonal's width, in stems (leans make it look thinner)

/// Signed distance to a rounded box (negative inside).
double _box(double px, double py, double l, double t, double r, double b) {
  final cx = (l + r) / 2, cy = (t + b) / 2;
  final hw = (r - l) / 2, hh = (b - t) / 2;
  final qx = (px - cx).abs() - (hw - _round);
  final qy = (py - cy).abs() - (hh - _round);
  return sqrt(pow(max(qx, 0), 2) + pow(max(qy, 0), 2)) +
      min(max(qx, qy), 0) -
      _round;
}

/// Signed distance to a convex polygon (negative inside).
double _poly(double px, double py, List<(double, double)> pts) {
  var best = double.infinity;
  var pos = true, neg = true;
  for (var i = 0; i < pts.length; i++) {
    final (ax, ay) = pts[i];
    final (bx, by) = pts[(i + 1) % pts.length];
    final dx = bx - ax, dy = by - ay;
    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    best = min(
      best,
      sqrt(pow(px - (ax + t * dx), 2) + pow(py - (ay + t * dy), 2)),
    );
    final c = dx * (py - ay) - dy * (px - ax);
    if (c < 0) pos = false;
    if (c > 0) neg = false;
  }
  return (pos || neg) ? -best : best;
}

final _diagonalShape = [
  (_x0, _y0),
  (_x0 + _stem * _band, _y0),
  (_x1, _y1),
  (_x1 - _stem * _band, _y1),
];

double _left(double x, double y) => _box(x, y, _x0, _y0, _x0 + _stem, _y1);
double _right(double x, double y) => _box(x, y, _x1 - _stem, _y0, _x1, _y1);
double _diagonal(double x, double y) => _poly(x, y, _diagonalShape);

double _cover(double d) => (0.5 - d).clamp(0.0, 1.0);
double _mix(double a, double b, double t) => a + (b - a) * t;

/// Premultiplied RGBA accumulator for one pixel.
class _Px {
  double r = 0, g = 0, b = 0, a = 0;

  void over(double sr, double sg, double sb, double sa) {
    r = sr * sa + r * (1 - sa);
    g = sg * sa + g * (1 - sa);
    b = sb * sa + b * (1 - sa);
    a = sa + a * (1 - sa);
  }
}

void _render(
  String path, {
  required bool background,
  required bool glyph,
  bool rounded = false,
}) {
  final img = Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final px = x + 0.5, py = y + 0.5;
      final p = _Px();

      if (background) {
        // The brand teal: a little deeper at the top left, lighter at the
        // bottom right, with a soft glow behind the letter and two big circles.
        final t = ((px * 0.5 + py * 0.5) / size).clamp(0.0, 1.0);
        p.over(_mix(9, 15, t), _mix(58, 122, t), _mix(58, 114, t), 1);
        final glow = exp(
          -(pow(px - 520, 2) + pow(py - 500, 2)) / (2 * 330 * 330),
        );
        p.over(255, 255, 255, 0.16 * glow);
        double disc(double cx, double cy, double r) {
          final d = sqrt(pow(px - cx, 2) + pow(py - cy, 2)) - r;
          return (0.5 - d / 2).clamp(0.0, 1.0);
        }

        p.over(255, 255, 255, 0.07 * disc(900, 130, 330));
        p.over(255, 255, 255, 0.05 * disc(110, 930, 300));
      }

      if (glyph) {
        // Lean the letter: look up the upright shapes at the un-leaned spot.
        final ux = px - (512 - py) * _lean;
        final dl = _left(ux, py), dr = _right(ux, py), dd = _diagonal(ux, py);

        // Soft shadow under the whole letter.
        final shadow = min(
          _left(ux, py - 24),
          min(_right(ux, py - 24), _diagonal(ux, py - 24)),
        );
        p.over(0, 52, 48, 0.32 * (1 - (shadow / 48)).clamp(0.0, 1.0));

        final k = ((py - _y0) / (_y1 - _y0)).clamp(0.0, 1.0);

        // The diagonal first: bright mint, fading to aqua towards the bottom.
        final diag = _cover(dd);
        p.over(_mix(52, 20, k), _mix(214, 172, k), _mix(194, 154, k), diag);

        // A thin dark line along the stems where the diagonal runs into them,
        // so the three pieces read as one built letter.
        final seam = (1 - min(dl.abs(), dr.abs()) / 3).clamp(0.0, 1.0);
        p.over(0, 70, 64, 0.34 * seam * diag);

        // The two stems on top, full height: white fading to pale mint.
        final stem = max(_cover(dl), _cover(dr));
        p.over(_mix(255, 208, k), _mix(255, 246, k), _mix(255, 238, k), stem);
      }

      if (rounded) {
        // Rounded square (Android icons before adaptive icons).
        const radius = size * 0.225;
        final cx = (px - size / 2).abs() - (size / 2 - radius);
        final cy = (py - size / 2).abs() - (size / 2 - radius);
        final d =
            sqrt(pow(max(cx, 0), 2) + pow(max(cy, 0), 2)) +
            min(max(cx, cy), 0) -
            radius;
        final m = (0.5 - d).clamp(0.0, 1.0);
        p.r *= m;
        p.g *= m;
        p.b *= m;
        p.a *= m;
      }

      final a = p.a;
      img.setPixelRgba(
        x,
        y,
        a == 0 ? 0 : (p.r / a).round().clamp(0, 255),
        a == 0 ? 0 : (p.g / a).round().clamp(0, 255),
        a == 0 ? 0 : (p.b / a).round().clamp(0, 255),
        (a * 255).round().clamp(0, 255),
      );
    }
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(encodePng(img));
}

void main() {
  _render('assets/icon/icon.png', background: true, glyph: true);
  _render(
    'assets/icon/icon_android.png',
    background: true,
    glyph: true,
    rounded: true,
  );
  _render('assets/icon/foreground.png', background: false, glyph: true);
  _render('assets/icon/background.png', background: true, glyph: false);

  // A small copy of the full icon: shown in the app as the logo (avatar).
  final full = decodePng(File('assets/icon/icon.png').readAsBytesSync())!;
  File('assets/images/nexora-mark.png')
      .writeAsBytesSync(encodePng(copyResize(full, width: 256)));
  stdout.writeln(
    'Icons written to assets/icon/ and assets/images/nexora-mark.png',
  );
}

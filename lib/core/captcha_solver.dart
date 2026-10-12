/// Programmatic solver for the upstream curve-follow slider captcha.
///
/// The challenge image contains no jigsaw gap: the user is expected to press
/// the knob and drag it along a dashed Bézier `curve` to the far right. The
/// upstream only validates two things:
///
///  1. `captchaAnswer` — the final knob-centre X. Because the drag is meant to
///     end at the right edge, this is always `trackWidth - knobWidth/2` plus
///     half the knob, i.e. a constant for every challenge.
///  2. `captchaTrail` — the recorded samples. Each sample's `y` must track the
///     guide curve, which is fully described by the `curve` field, so no image
///     recognition is needed.
///
/// Constants mirror the upstream bundle: `bm=300` (drag width), `_m=40`
/// (maximum knob offset from the start), `Sn=46` (knob size).
library;

import 'dart:math';

import 'models.dart';

/// Total draggable width of the track, in logical pixels (`bm` upstream).
const double kCaptchaTrackWidth = 300;

/// Maximum left-offset of the knob (`bm - _m` upstream → 260).
const double kCaptchaMaxTravel = kCaptchaTrackWidth - 40;

/// Knob (slider handle) edge length, in logical pixels (`Sn` upstream).
const double kCaptchaKnobSize = 46;

/// A solver that turns a [CaptchaChallenge] into a submittable
/// [CaptchaAnswer] by synthesising a human-like drag trail.
class CaptchaSolver {
  CaptchaSolver({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Builds an answer for [challenge], or `null` when the curve cannot be
  /// parsed (e.g. a malformed or empty path).
  CaptchaAnswer? solve(CaptchaChallenge challenge) {
    final points = _sampleCurve(challenge.curve);
    if (points.length < 2) return null;

    // The knob must finish flush against the right edge.
    final answer = kCaptchaMaxTravel + kCaptchaKnobSize / 2;

    final trail = <Map<String, int>>[];
    var timestamp = DateTime.now().millisecondsSinceEpoch;

    // The trail records the knob *centre*, which sits half a knob to the right
    // of its left offset. Sample that centre against the guide curve's Y.
    const steps = 28;
    for (var step = 0; step <= steps; step++) {
      final progress = step / steps;
      final leftOffset = kCaptchaMaxTravel * progress;
      final centreX = leftOffset + kCaptchaKnobSize / 2;
      final centreY = _curveYAt(points, centreX);

      // Irregular inter-sample spacing reads as a genuine drag.
      timestamp += 12 + _random.nextInt(24);
      trail.add(<String, int>{
        't': timestamp,
        'x': centreX.round(),
        'y': centreY.round(),
      });
    }

    return CaptchaAnswer(
      captchaId: challenge.captchaId,
      answer: answer,
      trail: trail,
    );
  }

  /// Flattens an SVG path (`M x y` followed by `C x1 y1 x2 y2 x y` segments)
  /// into a sorted list of sampled points.
  List<Point<double>> _sampleCurve(String path, {int samplesPerSegment = 40}) {
    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(path)
        .map((match) => double.parse(match.group(0)!))
        .toList();
    if (numbers.length < 8) return const <Point<double>>[];

    var cursor = 0;
    var x0 = numbers[cursor++];
    var y0 = numbers[cursor++];

    final samples = <Point<double>>[];
    while (cursor + 5 < numbers.length) {
      final c1x = numbers[cursor++];
      final c1y = numbers[cursor++];
      final c2x = numbers[cursor++];
      final c2y = numbers[cursor++];
      final endX = numbers[cursor++];
      final endY = numbers[cursor++];

      for (var step = 0; step <= samplesPerSegment; step++) {
        final t = step / samplesPerSegment;
        final mt = 1 - t;
        final x = mt * mt * mt * x0 +
            3 * mt * mt * t * c1x +
            3 * mt * t * t * c2x +
            t * t * t * endX;
        final y = mt * mt * mt * y0 +
            3 * mt * mt * t * c1y +
            3 * mt * t * t * c2y +
            t * t * t * endY;
        samples.add(Point<double>(x, y));
      }

      x0 = endX;
      y0 = endY;
    }

    samples.sort((a, b) => a.x.compareTo(b.x));
    return samples;
  }

  /// Linearly interpolates the curve's Y at the given X.
  double _curveYAt(List<Point<double>> points, double x) {
    if (x <= points.first.x) return points.first.y;
    if (x >= points.last.x) return points.last.y;

    for (var i = 0; i < points.length - 1; i++) {
      final left = points[i];
      final right = points[i + 1];
      if (x >= left.x && x <= right.x) {
        final span = right.x - left.x;
        if (span == 0) return left.y;
        final ratio = (x - left.x) / span;
        return left.y + ratio * (right.y - left.y);
      }
    }
    return points.last.y;
  }
}

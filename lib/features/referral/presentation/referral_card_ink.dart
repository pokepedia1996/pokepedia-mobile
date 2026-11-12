import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/formatters.dart';
import '../repository/models/referral_models.dart';
import 'referral_style.dart';

/// Hand-drawn ink on the prize card front (03 §3), from the design export
/// `assets/data/referral_card_ink.json`. Card units: 264 × 384.
///
/// shortcut: the underline and sparkles are placed for the design amounts
/// (Rp5.000–Rp50.000); scale them to the measured amount width if tier
/// amounts ever change.
class CardInk {
  const CardInk({
    required this.word,
    required this.loop,
    required this.loopWidth,
    required this.underline,
    required this.underlineWidth,
    required this.extras,
  });

  factory CardInk.fromJson(Map<String, dynamic> j) => CardInk(
    word: j['word'] as String,
    loop: parseScribblePath(j['loopPath'] as String),
    loopWidth: (j['loopStrokeWidth'] as num).toDouble(),
    underline: parseScribblePath(j['underlinePath'] as String),
    underlineWidth: (j['underlineStrokeWidth'] as num).toDouble(),
    extras: [
      for (final e in (j['extras'] as List? ?? const []))
        InkExtra.fromJson(e as Map<String, dynamic>),
    ],
  );

  final String word;
  final Path loop;
  final double loopWidth;
  final Path underline;
  final double underlineWidth;
  final List<InkExtra> extras;
}

/// A sparkle or the jackpot crown, in local coordinates.
class InkExtra {
  const InkExtra({
    required this.path,
    required this.translate,
    required this.scale,
    required this.rotateDeg,
    required this.strokeWidth,
  });

  factory InkExtra.fromJson(Map<String, dynamic> j) {
    final t = j['translate'] as List;
    return InkExtra(
      path: parseScribblePath(j['path'] as String),
      translate: Offset((t[0] as num).toDouble(), (t[1] as num).toDouble()),
      scale: (j['scale'] as num).toDouble(),
      rotateDeg: (j['rotateDeg'] as num).toDouble(),
      strokeWidth: (j['strokeWidth'] as num).toDouble(),
    );
  }

  final Path path;
  final Offset translate;
  final double scale, rotateDeg, strokeWidth;
}

Map<ReferralTierKey, CardInk> parseCardInk(String raw) {
  final tiers = (jsonDecode(raw) as Map<String, dynamic>)['tiers'] as Map;
  return {
    for (final e in tiers.entries)
      if (ReferralTierKey.fromRaw(e.key) case final key?)
        key: CardInk.fromJson(e.value as Map<String, dynamic>),
  };
}

Future<Map<ReferralTierKey, CardInk>>? _inkCache;

/// Loaded once per app run; empty (card drawn without ink) if it fails.
Future<Map<ReferralTierKey, CardInk>> loadCardInk() => _inkCache ??= rootBundle
    .loadString('assets/data/referral_card_ink.json')
    .then(parseCardInk)
    .catchError((Object e) {
      debugPrint('[referral] card ink failed to load: $e');
      return <ReferralTierKey, CardInk>{};
    });

/// Absolute M/L/Q/Z path data (from the design's `scribble_drawing.dart`).
Path parseScribblePath(String d) {
  final tokens = RegExp(
    r'[MLQZ]|-?\d*\.?\d+',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'M' || t == 'L' || t == 'Q' || t == 'Z') {
      cmd = t;
      i++;
      if (cmd == 'Z') path.close();
      continue;
    }
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
        cmd = 'L';
      case 'L':
        path.lineTo(next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
      default:
        i++;
    }
  }
  return path;
}

/// Reveal order after the flip, in ms (ink JSON `_readme`): word wipe, loop,
/// odds, count-up, then underline and each extra.
class CardTimeline {
  const CardTimeline({required this.countMs, required this.extras});

  final int countMs;
  final int extras;

  static const wordStart = 120.0, wordMs = 420.0;
  static const loopStart = 420.0, loopMs = 540.0;
  static const oddsStart = 520.0, oddsMs = 300.0;
  static const countStart = 540.0;
  static const underlineMs = 420.0, extraMs = 260.0, extraGap = 150.0;

  double get countEnd => countStart + countMs;
  double get underlineEnd => countEnd + underlineMs;
  double get total =>
      underlineEnd + (extras == 0 ? 0 : (extras - 1) * extraGap + extraMs);

  static double seg(double ms, double start, double len) =>
      ((ms - start) / len).clamp(0.0, 1.0);
}

/// Paints the card's text and ink in 264-unit space. Text is laid out at
/// fixed sizes, so the system text scale can't push it off the card.
class CardFacePainter extends CustomPainter {
  CardFacePainter({
    required this.tier,
    required this.amount,
    required this.odds,
    required this.ink,
    required this.timeline,
    required this.ms,
  });

  final ReferralTierKey tier;
  final int amount;
  final num? odds;
  final CardInk? ink;
  final CardTimeline timeline;

  /// Elapsed reveal time; `double.infinity` paints it settled.
  final double ms;

  static const _deg = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = TierStyle.of(tier).ink;
    final seg = CardTimeline.seg;
    canvas.save();
    canvas.scale(size.width / 264);

    // Word, wiped in left to right, 3° around its baseline start.
    final word = _text(
      this.ink?.word ?? tier.label,
      handStyle(accent, size: 27),
    );
    canvas.save();
    canvas.translate(34, 282);
    canvas.rotate(3 * _deg);
    final wipe = Curves.easeOut.transform(
      seg(ms, CardTimeline.wordStart, CardTimeline.wordMs),
    );
    canvas.clipRect(Rect.fromLTWH(-4, -40, (word.width + 8) * wipe, 60));
    _paintAtBaseline(canvas, word, Offset.zero);
    canvas.restore();
    word.dispose();

    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ink = this.ink;
    if (ink != null) {
      canvas.drawPath(
        _partial(
          ink.loop,
          Curves.easeInOut.transform(
            seg(ms, CardTimeline.loopStart, CardTimeline.loopMs),
          ),
        ),
        stroke..strokeWidth = ink.loopWidth,
      );
    }

    final odds = this.odds;
    if (odds != null) {
      final o = seg(ms, CardTimeline.oddsStart, CardTimeline.oddsMs);
      final tp = _text(
        'peluang ${formatOdds(odds)}%',
        handStyle(ReferralColors.muted.withValues(alpha: o), size: 16),
      );
      _paintAtBaseline(canvas, tp, Offset(240 - tp.width, 280));
      tp.dispose();
    }

    // Amount counts up from Rp0 in whole hundreds.
    final c = Curves.easeOutCubic.transform(
      seg(ms, CardTimeline.countStart, timeline.countMs.toDouble()),
    );
    final shown = (amount * c / 100).round() * 100;
    final amountTp = _text(
      formatRupiah(shown),
      handStyle(ReferralColors.ink, size: 54),
    );
    canvas.save();
    canvas.translate(26, 333);
    canvas.rotate(2 * _deg);
    _paintAtBaseline(canvas, amountTp, Offset.zero);
    canvas.restore();
    amountTp.dispose();

    if (ink != null) {
      canvas.drawPath(
        _partial(
          ink.underline,
          Curves.easeInOut.transform(
            seg(ms, timeline.countEnd, CardTimeline.underlineMs),
          ),
        ),
        stroke..strokeWidth = ink.underlineWidth,
      );
      for (var i = 0; i < ink.extras.length; i++) {
        final e = ink.extras[i];
        final p = seg(
          ms,
          timeline.underlineEnd + i * CardTimeline.extraGap,
          CardTimeline.extraMs,
        );
        if (p == 0) continue;
        canvas.save();
        canvas.translate(e.translate.dx, e.translate.dy);
        canvas.rotate(e.rotateDeg * _deg);
        canvas.scale(e.scale);
        canvas.drawPath(
          _partial(e.path, p),
          stroke..strokeWidth = e.strokeWidth,
        );
        canvas.restore();
      }
    }

    final footer = _text(
      'Hadiah Ajak Teman · Pokepedia',
      GoogleFonts.urbanist(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: ReferralColors.muted,
      ),
    );
    footer.paint(canvas, Offset((264 - footer.width) / 2, 360));
    footer.dispose();

    canvas.restore();
  }

  static TextPainter _text(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  static void _paintAtBaseline(Canvas c, TextPainter tp, Offset baseline) {
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, baseline - Offset(0, ascent));
  }

  /// The first [t] of [path]'s length, across all its sub-paths.
  static Path _partial(Path path, double t) {
    if (t >= 1) return path;
    final out = Path();
    if (t <= 0) return out;
    final metrics = path.computeMetrics().toList();
    var left = metrics.fold(0.0, (a, m) => a + m.length) * t;
    for (final m in metrics) {
      if (left <= 0) break;
      out.addPath(m.extractPath(0, math.min(left, m.length)), Offset.zero);
      left -= m.length;
    }
    return out;
  }

  @override
  bool shouldRepaint(CardFacePainter old) =>
      old.ms != ms ||
      old.tier != tier ||
      old.amount != amount ||
      old.odds != odds ||
      old.ink != ink;
}

// Reference widget for the hand-drawn ("coretan") onboarding art.
//
// Reads `assets/data/onboarding_scribble.json` (exported from the onboarding
// prototype) and replays the same draw-on animation: strokes are drawn along
// their length, fills fade in, cards pop in, handwritten words are wiped in
// from the left, sparkles spin in. After the draw-on, optional idle loops
// keep the art alive (cards bob, sparkles twinkle, scan line sweeps, ...).
//
// Usage:
//   ScribbleDrawing(drawing: 'intro_scan', key: ValueKey(slideIndex))
//   ScribbleDrawing(drawing: 'icon_koleksi', size: 52)
// Give it a new key (or call replay()) to play the draw-on again.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Every drawing file the widget knows about; keys are unique across files.
const _jsonAssets = [
  'assets/data/onboarding_scribble.json',
  'assets/data/buka_toko_scribble.json',
];

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

enum ScribbleKind { fill, stroke, image, text, sparkle }

class ScribbleItem {
  ScribbleItem._({
    required this.kind,
    required this.seq,
    this.loop,
    this.path,
    this.color = const Color(0xFF1C1413),
    this.width = 2.4,
    this.dash = false,
    this.asset,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.rotationDeg = 0,
    this.text,
    this.fontSize = 18,
    this.scale = 1,
    this.origin,
  });

  factory ScribbleItem.fromJson(Map<String, dynamic> j) {
    double d(String k, [double fallback = 0]) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    final o = j['origin'] as List?;
    return ScribbleItem._(
      kind: ScribbleKind.values.byName(j['type'] as String),
      seq: (j['seq'] as num).toInt(),
      loop: j['loop'] as String?,
      path: j['path'] == null ? null : parseScribblePath(j['path'] as String),
      color: j['color'] == null
          ? const Color(0xFF1C1413)
          : _hex(j['color'] as String),
      width: d('width', 2.4),
      dash: j['dash'] == true,
      asset: j['asset'] as String?,
      x: d('x'),
      y: d('y'),
      w: d('w'),
      h: d('h'),
      rotationDeg: d('rotationDeg'),
      text: j['text'] as String?,
      fontSize: d('fontSize', 18),
      scale: d('scale', 1),
      origin: o == null
          ? null
          : Offset((o[0] as num).toDouble(), (o[1] as num).toDouble()),
    );
  }

  final ScribbleKind kind;

  /// Items with the same seq start together; each seq starts 46 ms later.
  final int seq;

  /// Idle loop after the draw-on: pulse, scan, up, drive (or null).
  final String? loop;
  final Path? path;
  final Color color;
  final double width;
  final bool dash;
  final String? asset;
  final double x, y, w, h;

  /// Pencil convention: positive = counter-clockwise, around (x, y).
  final double rotationDeg;
  final String? text;
  final double fontSize;
  final double scale;

  /// Pivot for the pulse loop, in viewBox units.
  final Offset? origin;

  /// Length of the stroke path, cached for the draw-on.
  late final double length = path == null
      ? 0
      : path!.computeMetrics().fold(0.0, (sum, m) => sum + m.length);
}

class ScribbleData {
  ScribbleData(this.viewBox, this.items);

  final Rect viewBox;
  final List<ScribbleItem> items;

  static Future<Map<String, ScribbleData>>? _all;

  /// Forgets the loaded drawings, so the next [load] reads them again. For
  /// tests: a load started under a widget test's fake clock never finishes,
  /// and would otherwise be what every later test waits on.
  @visibleForTesting
  static void clearCache() => _all = null;

  static Future<ScribbleData> load(String key) async {
    // A failed read is not kept: the next drawing tries again rather than
    // every drawing in the app staying blank.
    final all = await (_all ??= _loadAll().catchError((Object e) {
      _all = null;
      throw e;
    }));
    final data = all[key];
    if (data == null) throw ArgumentError('Unknown scribble drawing "$key"');
    return data;
  }

  static Future<Map<String, ScribbleData>> _loadAll() async {
    final drawings = <String, dynamic>{};
    for (final asset in _jsonAssets) {
      // Read as bytes and decoded here: loadString hands anything over
      // 50 KB to a background isolate, which a widget test's clock never
      // lets finish — and this load is cached for every drawing after.
      final bytes = await rootBundle.load(asset);
      final raw = utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      drawings.addAll(
        (jsonDecode(raw) as Map<String, dynamic>)['drawings']
            as Map<String, dynamic>,
      );
    }
    return drawings.map((key, value) {
      final m = value as Map<String, dynamic>;
      final vb = (m['viewBox'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      return MapEntry(
        key,
        ScribbleData(
          Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]),
          (m['items'] as List)
              .map((e) => ScribbleItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
    });
  }
}

/// The exported paths only use M, L, Q and Z.
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
    if (cmd == 'M') {
      path.moveTo(next(), next());
      cmd = 'L';
    } else if (cmd == 'L') {
      path.lineTo(next(), next());
    } else if (cmd == 'Q') {
      final x1 = next(), y1 = next(), x2 = next(), y2 = next();
      path.quadraticBezierTo(x1, y1, x2, y2);
    } else {
      i++;
    }
  }
  return path;
}

Color _hex(String s) {
  var h = s.replaceFirst('#', '');
  if (h.length == 6) h = '${h}FF';
  final v = int.parse(h, radix: 16);
  // #RRGGBBAA -> 0xAARRGGBB
  return Color(((v & 0xFF) << 24) | (v >> 8));
}

// ---------------------------------------------------------------------------
// Timing (same numbers as the prototype)
// ---------------------------------------------------------------------------

class _Timing {
  const _Timing(this.start, this.duration, this.curve);
  final double start; // ms
  final double duration; // ms
  final Curve curve;

  double at(double ms) =>
      curve.transform(((ms - start) / duration).clamp(0.0, 1.0));
}

const _strokeCurve = Cubic(.45, .05, .3, 1);
const _popCurve = Cubic(.3, .7, .3, 1);
const _wipeCurve = Cubic(.4, 0, .3, 1);

_Timing _timingFor(ScribbleItem it, double baseMs, double stepMs) {
  final d = baseMs + 60 + it.seq * stepMs;
  switch (it.kind) {
    case ScribbleKind.stroke:
      final dur = (220 + it.length * .9)
          .clamp(it.dash ? 160.0 : 240.0, 900.0)
          .toDouble();
      return _Timing(d, dur, _strokeCurve);
    case ScribbleKind.fill:
      return _Timing(d + 150, 380, Curves.easeOut);
    case ScribbleKind.image:
      return _Timing(d, 640, _popCurve);
    case ScribbleKind.text:
      final width = (it.text?.length ?? 0) * it.fontSize * .45;
      return _Timing(d, math.min(700.0, 260 + width * 4), _wipeCurve);
    case ScribbleKind.sparkle:
      return _Timing(d, 480, Curves.easeOut);
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class ScribbleDrawing extends StatefulWidget {
  const ScribbleDrawing({
    super.key,
    required this.drawing,
    this.size,
    this.delay = Duration.zero,
    this.stepMs = 46,
    this.idle = true,
    this.animate = true,
  });

  /// Key in onboarding_scribble.json, e.g. intro_welcome, icon_koleksi,
  /// portfolio_empty.
  final String drawing;

  /// Square box for icons; null = fill the parent and keep aspect ratio.
  final double? size;
  final Duration delay;

  /// Gap between sequence steps. 46 for big drawings, 40 for icons.
  final double stepMs;

  /// Keep the idle loops running after the draw-on.
  final bool idle;

  /// False = show the finished drawing at once (reduced motion).
  final bool animate;

  @override
  State<ScribbleDrawing> createState() => ScribbleDrawingState();
}

class ScribbleDrawingState extends State<ScribbleDrawing>
    with TickerProviderStateMixin {
  ScribbleData? _data;
  late List<_Timing> _timings;
  // Made up front rather than lazily: one first touched in dispose(), for a
  // drawing torn down before its data loaded, would look up the tree from
  // an element that has already left it.
  late final AnimationController _draw;
  late final AnimationController _loop;
  double _total = 1;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(vsync: this);
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    ScribbleData.load(widget.drawing).then((data) {
      if (!mounted) return;
      final base = widget.delay.inMilliseconds.toDouble();
      _timings = [
        for (final it in data.items) _timingFor(it, base, widget.stepMs),
      ];
      _total = _timings.fold(1.0, (m, t) => math.max(m, t.start + t.duration));
      setState(() => _data = data);
      replay();
    });
  }

  /// Plays the draw-on again from the start.
  void replay() {
    if (_data == null) return;
    final reduce =
        !widget.animate || MediaQuery.maybeDisableAnimationsOf(context) == true;
    _loop.stop();
    _draw.duration = Duration(milliseconds: _total.round());
    if (reduce) {
      _draw.value = 1;
      return;
    }
    _draw.forward(from: 0).whenComplete(() {
      // Loop clock in seconds; each idle motion derives its own phase.
      if (mounted && widget.idle) {
        _loop.repeat(period: const Duration(hours: 1));
      }
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final vb = data.viewBox;
    final children = <Widget>[];
    var vector = <int>[];

    void flushVector() {
      if (vector.isEmpty) return;
      final ids = vector;
      vector = [];
      children.add(
        Positioned.fill(
          child: CustomPaint(painter: _VectorPainter(this, data, ids)),
        ),
      );
    }

    for (var i = 0; i < data.items.length; i++) {
      final it = data.items[i];
      if (it.kind == ScribbleKind.image || it.kind == ScribbleKind.text) {
        flushVector();
        children.add(_positioned(it, i, vb));
      } else {
        vector.add(i);
      }
    }
    flushVector();

    final canvas = SizedBox(
      width: vb.width,
      height: vb.height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
    final fitted = FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      child: canvas,
    );
    return widget.size == null
        ? fitted
        : SizedBox.square(dimension: widget.size, child: fitted);
  }

  double _loopSeconds() =>
      (_loop.lastElapsedDuration ?? Duration.zero).inMicroseconds / 1e6;

  Widget _positioned(ScribbleItem it, int index, Rect vb) {
    final t = _timings[index];
    final rotation = -it.rotationDeg * math.pi / 180;
    if (it.kind == ScribbleKind.image) {
      return Positioned(
        left: it.x - vb.left,
        top: it.y - vb.top,
        width: it.w,
        height: it.h,
        child: Transform.rotate(
          angle: rotation,
          alignment: Alignment.topLeft,
          child: AnimatedBuilder(
            animation: Listenable.merge([_draw, _loop]),
            builder: (context, child) {
              final p = t.at(_draw.value * _total);
              // 0 -> 65%: rise and overshoot, 65% -> 100%: settle.
              final a = (p / .65).clamp(0.0, 1.0),
                  b = ((p - .65) / .35).clamp(0.0, 1.0);
              final dy = p < .65 ? 28 + (-4 - 28) * a : -4 + 4 * b;
              final s = p < .65 ? .7 + (1.04 - .7) * a : 1.04 - .04 * b;
              final r = p < .65 ? -6 + 7 * a : 1 - b;
              // Bob 5 px every 3.4 s, each card starting a little later.
              // A "peek" image (the letter in the envelope) rises 7 px instead.
              final since = _loopSeconds() - (index % 5) * .35;
              final idleOn = widget.idle && _loop.isAnimating;
              final bob = !idleOn
                  ? 0.0
                  : it.loop == 'peek'
                  ? -3.5 * (1 - math.cos(_loopSeconds() / 2.6 * 2 * math.pi))
                  : since > 0
                  ? -2.5 + 2.5 * math.cos(since / 3.4 * 2 * math.pi)
                  : 0.0;
              return Opacity(
                opacity: a,
                child: Transform.translate(
                  offset: Offset(0, dy + bob),
                  child: Transform.rotate(
                    angle: r * math.pi / 180,
                    child: Transform.scale(scale: s, child: child),
                  ),
                ),
              );
            },
            child: Image.asset(it.asset!, fit: BoxFit.contain),
          ),
        ),
      );
    }
    // Handwritten word, wiped in from the left.
    return Positioned(
      left: it.x - vb.left,
      top: it.y - vb.top,
      child: Transform.rotate(
        angle: rotation,
        alignment: Alignment.topLeft,
        child: AnimatedBuilder(
          animation: _draw,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: t.at(_draw.value * _total),
              child: child,
            ),
          ),
          child: Text(
            it.text!,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'PatrickHand',
              fontSize: it.fontSize,
              height: 1.15,
              color: it.color,
            ),
          ),
        ),
      ),
    );
  }
}

const _sparkle = 'M0 -7 Q0 0 7 0 Q0 0 0 7 Q0 0 -7 0 Q0 0 0 -7 Z';
final _sparklePath = parseScribblePath(_sparkle);

class _VectorPainter extends CustomPainter {
  _VectorPainter(this.state, this.data, this.ids)
    : super(repaint: Listenable.merge([state._draw, state._loop]));

  final ScribbleDrawingState state;
  final ScribbleData data;
  final List<int> ids;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = state._draw.value * state._total;
    final loops = state.widget.idle && state._loop.isAnimating;
    final sec = state._loopSeconds();
    canvas.save();
    canvas.translate(-data.viewBox.left, -data.viewBox.top);
    for (final i in ids) {
      final it = data.items[i];
      final p = state._timings[i].at(ms);
      if (p <= 0) continue;
      canvas.save();
      final fade = loops ? _applyLoop(canvas, it, sec) : 1.0;
      if (fade <= 0) {
        canvas.restore();
        continue;
      }
      switch (it.kind) {
        case ScribbleKind.stroke:
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = it.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = it.color.withValues(alpha: it.color.a * fade);
          if (p >= 1) {
            canvas.drawPath(it.path!, paint);
          } else {
            var left = it.length * p;
            for (final m in it.path!.computeMetrics()) {
              if (left <= 0) break;
              canvas.drawPath(
                m.extractPath(0, math.min(left, m.length)),
                paint,
              );
              left -= m.length;
            }
          }
        case ScribbleKind.fill:
          canvas.drawPath(
            it.path!,
            Paint()..color = it.color.withValues(alpha: it.color.a * p),
          );
        case ScribbleKind.sparkle:
          // scale 0 -> 1.35 (60%) -> 1, rotate -90deg -> 12deg -> 0
          final s = p < .6 ? 1.35 * p / .6 : 1.35 - .35 * (p - .6) / .4;
          final r = p < .6 ? -90 + 102 * p / .6 : 12 - 12 * (p - .6) / .4;
          final tw = loops
              ? 1 - .15 * (1 - math.cos(sec / 2.2 * 2 * math.pi))
              : 1.0;
          canvas.translate(it.x, it.y);
          canvas.scale(it.scale * s * tw);
          canvas.rotate(r * math.pi / 180);
          canvas.drawPath(
            _sparklePath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2 / it.scale
              ..strokeJoin = StrokeJoin.round
              ..color = it.color,
          );
        case ScribbleKind.image:
        case ScribbleKind.text:
          break;
      }
      canvas.restore();
    }
    canvas.restore();
  }

  /// Moves the canvas for the item's idle loop and returns an opacity
  /// multiplier (only the halo fades).
  double _applyLoop(Canvas canvas, ScribbleItem it, double sec) {
    switch (it.loop) {
      case 'pulse': // scale 1 -> 1.05 -> 1 every 1.8 s
        final o = it.origin ?? Offset.zero;
        final s = 1 + .025 * (1 - math.cos(sec / 1.8 * 2 * math.pi));
        canvas.translate(o.dx, o.dy);
        canvas.scale(s);
        canvas.translate(-o.dx, -o.dy);
      case 'scan': // 0 -> -58 -> +58 -> 0 every 4.8 s
        canvas.translate(0, -58 * math.sin(sec / 4.8 * 2 * math.pi));
      case 'up': // -6 px every 1.6 s
        canvas.translate(0, -3 * (1 - math.cos(sec / 1.6 * 2 * math.pi)));
      case 'drive': // +5 px every 1.8 s
        canvas.translate(2.5 * (1 - math.cos(sec / 1.8 * 2 * math.pi)), 0);
      case 'peek': // letter in the envelope rises 7 px every 2.6 s
        canvas.translate(0, -3.5 * (1 - math.cos(sec / 2.6 * 2 * math.pi)));
      case 'pin': // map pin bobs 6 px every 2 s
        canvas.translate(0, -3 * (1 - math.cos(sec / 2 * 2 * math.pi)));
      case 'swing': // hanging sign / price tag, ±4° around its top edge
        final b = it.path?.getBounds();
        if (b != null) {
          final a = 4 * math.sin(sec / 2.6 * 2 * math.pi) * math.pi / 180;
          canvas.translate(b.center.dx, b.top);
          canvas.rotate(a);
          canvas.translate(-b.center.dx, -b.top);
        }
      case 'halo': // dashed ring grows 0.85 → 1.25 and fades, every 2 s
        final o = it.origin ?? Offset.zero;
        final t = (sec / 2) % 1;
        final s = .85 + .4 * t;
        canvas.translate(o.dx, o.dy);
        canvas.scale(s);
        canvas.translate(-o.dx, -o.dy);
        return 1 - t;
    }
    return 1;
  }

  @override
  bool shouldRepaint(_VectorPainter old) => old.ids != ids || old.data != data;
}

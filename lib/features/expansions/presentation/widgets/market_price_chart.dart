import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/condition_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../repository/models/market_models.dart';

/// Ports `features/card-detail/components/market-activity-chart.tsx`. The
/// web draws it with Recharts; there's no charting package in this app, so
/// the same picture is painted directly: one dashed line per condition for
/// the daily average, a solid line for the EWMA, an area fill when a single
/// condition is shown, and a draggable crosshair in place of the hover
/// tooltip.
class MarketPriceChart extends StatefulWidget {
  const MarketPriceChart({
    super.key,
    required this.points,
    required this.visibleConditions,
    this.height = 180,
  });

  final List<MarketPricePoint> points;
  final Set<CardCondition> visibleConditions;
  final double height;

  @override
  State<MarketPriceChart> createState() => _MarketPriceChartState();
}

class _MarketPriceChartState extends State<MarketPriceChart> {
  /// The day the crosshair is parked on, or null when untouched.
  DateTime? _selectedDay;

  @override
  void didUpdateWidget(MarketPriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _selectedDay = null;
  }

  @override
  Widget build(BuildContext context) {
    final series = _buildSeries(widget.points, widget.visibleConditions);
    if (series.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Belum ada data harga',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ),
      );
    }

    final days = <DateTime>{};
    for (final entry in series.values) {
      for (final p in entry) {
        days.add(DateTime(p.day.year, p.day.month, p.day.day));
      }
    }
    final sortedDays = days.toList()..sort();

    final colors = {
      for (final condition in series.keys)
        condition: conditionColorOf(context, condition),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendLine(
                label: 'EWMA',
                color: context.appColors.onSurface,
                dashed: false,
              ),
              const SizedBox(width: 16),
              _LegendLine(
                label: 'Rata-rata',
                color: context.mutedForeground,
                dashed: true,
              ),
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void select(Offset local) {
                final day = _dayAt(local.dx, constraints.maxWidth, sortedDays);
                if (day != _selectedDay) setState(() => _selectedDay = day);
              }

              return GestureDetector(
                onTapDown: (d) => select(d.localPosition),
                onHorizontalDragStart: (d) => select(d.localPosition),
                onHorizontalDragUpdate: (d) => select(d.localPosition),
                onHorizontalDragEnd: (_) => setState(() => _selectedDay = null),
                onTapCancel: () => setState(() => _selectedDay = null),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _ChartPainter(
                    series: series,
                    days: sortedDays,
                    colors: colors,
                    selectedDay: _selectedDay,
                    gridColor: context.borderColor,
                    labelColor: context.mutedForeground,
                    foreground: context.appColors.onSurface,
                    surface: Theme.of(context).cardColor,
                    singleCondition: series.length == 1,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The chart is plotted on an evenly spaced day axis, so the nearest
  /// point to a touch is just the nearest slot.
  DateTime? _dayAt(double dx, double width, List<DateTime> days) {
    if (days.isEmpty) return null;
    final plotLeft = _ChartPainter.leftPadding;
    final plotWidth = width - plotLeft - _ChartPainter.rightPadding;
    if (plotWidth <= 0) return null;
    final t = ((dx - plotLeft) / plotWidth).clamp(0.0, 1.0);
    final index = (t * (days.length - 1)).round();
    return days[index];
  }
}

/// Groups the flat RPC rows by condition, keeping only visible ones and
/// ordering each series oldest → newest.
Map<CardCondition, List<MarketPricePoint>> _buildSeries(
  List<MarketPricePoint> points,
  Set<CardCondition> visible,
) {
  final out = <CardCondition, List<MarketPricePoint>>{};
  for (final p in points) {
    if (!visible.contains(p.condition)) continue;
    out.putIfAbsent(p.condition, () => []).add(p);
  }
  for (final list in out.values) {
    list.sort((a, b) => a.day.compareTo(b.day));
  }
  out.removeWhere((_, list) => list.isEmpty);
  return out;
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.label,
    required this.color,
    required this.dashed,
  });

  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 6,
          child: CustomPaint(
            painter: _LegendLinePainter(color: color, dashed: dashed),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  const _LegendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.5 : 2.5;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.days,
    required this.colors,
    required this.selectedDay,
    required this.gridColor,
    required this.labelColor,
    required this.foreground,
    required this.surface,
    required this.singleCondition,
  });

  static const leftPadding = 52.0;
  static const rightPadding = 8.0;
  static const topPadding = 8.0;
  static const bottomPadding = 20.0;

  final Map<CardCondition, List<MarketPricePoint>> series;
  final List<DateTime> days;
  final Map<CardCondition, Color> colors;
  final DateTime? selectedDay;
  final Color gridColor;
  final Color labelColor;
  final Color foreground;
  final Color surface;
  final bool singleCondition;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      leftPadding,
      topPadding,
      size.width - rightPadding,
      size.height - bottomPadding,
    );
    if (plot.width <= 0 || plot.height <= 0 || days.isEmpty) return;

    // Y domain, padded the same way the web chart pads its `yDomain`.
    var min = double.infinity;
    var max = -double.infinity;
    for (final list in series.values) {
      for (final p in list) {
        for (final v in [p.rawPrice, if (p.avgPrice != null) p.avgPrice!]) {
          if (v < min) min = v.toDouble();
          if (v > max) max = v.toDouble();
        }
      }
    }
    if (min == double.infinity) return;
    final pad = [
      500.0,
      (max - min) * 0.1,
      min * 0.05,
    ].reduce((a, b) => a > b ? a : b);
    final yMin = (min - pad).clamp(0.0, double.infinity);
    final yMax = max + pad;
    final ySpan = yMax - yMin == 0 ? 1.0 : yMax - yMin;

    double xOf(DateTime day) {
      if (days.length == 1) return plot.center.dx;
      final index = days.indexWhere((d) => !d.isBefore(_dayKey(day)));
      final i = index < 0 ? days.length - 1 : index;
      return plot.left + plot.width * (i / (days.length - 1));
    }

    double yOf(num price) =>
        plot.bottom - ((price - yMin) / ySpan) * plot.height;

    _paintGrid(canvas, plot, yMin, yMax);

    // Dashed daily-average lines first, so the EWMA reads on top of them.
    for (final entry in series.entries) {
      final color = colors[entry.key]!;
      final path = _pathOf(entry.value, xOf, yOf, avg: false);
      if (path != null) {
        _drawDashed(
          canvas,
          path,
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
    }

    for (final entry in series.entries) {
      final color = colors[entry.key]!;
      final path = _pathOf(entry.value, xOf, yOf, avg: true);
      if (path == null) continue;
      if (singleCondition) {
        final fill = Path.from(path)
          ..lineTo(_lastX(entry.value, xOf), plot.bottom)
          ..lineTo(_firstX(entry.value, xOf), plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(plot.left, plot.top),
              Offset(plot.left, plot.bottom),
              [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
            ),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    _paintXLabels(canvas, plot, xOf);
    if (selectedDay != null) {
      _paintCrosshair(canvas, size, plot, xOf, yOf);
    }
  }

  DateTime _dayKey(DateTime day) => DateTime(day.year, day.month, day.day);

  Path? _pathOf(
    List<MarketPricePoint> points,
    double Function(DateTime) xOf,
    double Function(num) yOf, {
    required bool avg,
  }) {
    final path = Path();
    var started = false;
    for (final p in points) {
      final value = avg ? p.avgPrice : p.rawPrice;
      if (value == null) continue;
      final offset = Offset(xOf(p.day), yOf(value));
      if (!started) {
        path.moveTo(offset.dx, offset.dy);
        started = true;
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    return started ? path : null;
  }

  double _firstX(
    List<MarketPricePoint> points,
    double Function(DateTime) xOf,
  ) => xOf(points.first.day);

  double _lastX(List<MarketPricePoint> points, double Function(DateTime) xOf) =>
      xOf(points.last.day);

  void _paintGrid(Canvas canvas, Rect plot, double yMin, double yMax) {
    const lines = 4;
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final t = i / lines;
      final y = plot.bottom - plot.height * t;
      final path = Path()
        ..moveTo(plot.left, y)
        ..lineTo(plot.right, y);
      _drawDashed(canvas, path, paint, dash: 3, gap: 3);

      final value = yMin + (yMax - yMin) * t;
      final label = _text(formatRupiahCompact(value), labelColor, 10);
      label.paint(
        canvas,
        Offset(plot.left - 8 - label.width, y - label.height / 2),
      );
    }
  }

  void _paintXLabels(Canvas canvas, Rect plot, double Function(DateTime) xOf) {
    if (days.isEmpty) return;
    // Roughly one label per 60px, like Recharts' `minTickGap`.
    final maxLabels = (plot.width / 60).floor().clamp(2, 6);
    final step = (days.length / maxLabels).ceil().clamp(1, days.length);
    for (var i = 0; i < days.length; i += step) {
      final day = days[i];
      final label = _text(formatShortDateId(day), labelColor, 10);
      var dx = xOf(day) - label.width / 2;
      dx = dx.clamp(plot.left, plot.right - label.width);
      label.paint(canvas, Offset(dx, plot.bottom + 6));
    }
  }

  void _paintCrosshair(
    Canvas canvas,
    Size size,
    Rect plot,
    double Function(DateTime) xOf,
    double Function(num) yOf,
  ) {
    final day = _dayKey(selectedDay!);
    final x = xOf(day);
    _drawDashed(
      canvas,
      Path()
        ..moveTo(x, plot.top)
        ..lineTo(x, plot.bottom),
      Paint()
        ..color = labelColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
      dash: 4,
      gap: 4,
    );

    final entries = <({String label, String value, Color color, bool bold})>[];
    for (final entry in series.entries) {
      MarketPricePoint? match;
      for (final p in entry.value) {
        if (_dayKey(p.day) == day) match = p;
      }
      if (match == null) continue;
      final color = colors[entry.key]!;
      if (match.avgPrice != null) {
        canvas.drawCircle(
          Offset(x, yOf(match.avgPrice!)),
          4,
          Paint()..color = color,
        );
        entries.add((
          label: '${entry.key.short} · EWMA',
          value: formatRupiah(match.avgPrice!),
          color: color,
          bold: true,
        ));
      }
      entries.add((
        label: '${entry.key.short} · rata-rata',
        value: formatRupiah(match.rawPrice),
        color: color.withValues(alpha: 0.6),
        bold: false,
      ));
    }
    if (entries.isEmpty) return;

    // Tooltip card, kept inside the plot area on both edges.
    final title = _text(formatShortDateId(day), labelColor, 10);
    final rows = [
      for (final e in entries)
        (
          left: _text(e.label, e.bold ? foreground : labelColor, 10),
          right: _text(
            e.value,
            e.bold ? foreground : labelColor,
            10,
            bold: e.bold,
          ),
          color: e.color,
        ),
    ];
    var width = title.width;
    for (final row in rows) {
      final w = row.left.width + row.right.width + 24;
      if (w > width) width = w;
    }
    width += 20;
    final height = 14 + title.height + rows.length * 14.0;

    var left = x + 10;
    if (left + width > size.width) left = x - 10 - width;
    if (left < 0) left = 0;
    final top = plot.top + 4;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = surface);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = gridColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    title.paint(canvas, Offset(left + 10, top + 6));
    var y = top + 8 + title.height;
    for (final row in rows) {
      canvas.drawCircle(
        Offset(left + 14, y + row.left.height / 2),
        3,
        Paint()..color = row.color,
      );
      row.left.paint(canvas, Offset(left + 22, y));
      row.right.paint(canvas, Offset(left + width - 10 - row.right.width, y));
      y += 14;
    }
  }

  TextPainter _text(
    String value,
    Color color,
    double size, {
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: AppTypography.caption(
          color,
        ).copyWith(fontSize: size, fontWeight: bold ? FontWeight.w600 : null),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 4,
    double gap = 4,
  }) {
    paint.style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.series != series ||
      old.selectedDay != selectedDay ||
      old.colors != colors ||
      old.gridColor != gridColor;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/portfolio_value.dart';
import '../../usecase/portfolio_value_notifier.dart';

/// The collection-worth history line.
///
/// Draws whatever `price_history` supports for the selected range. When that
/// yields nothing the chart says so plainly instead of drawing a flat line
/// at zero, which would read as a portfolio that lost all its value.
class PortfolioValueChart extends ConsumerWidget {
  const PortfolioValueChart({super.key, this.height = 140});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(portfolioValueSeriesProvider);
    final holdings = ref.watch(portfolioHoldingsProvider).valueOrNull;

    return SizedBox(
      height: height,
      child: async.when(
        loading: () => const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, __) => _ChartMessage(
          title: 'Grafik tidak bisa dimuat',
          detail: 'Coba tarik untuk memuat ulang.',
        ),
        data: (series) {
          // Only genuinely *nothing* gets a message. A single day is a value
          // we already have, and it is drawn as a dot — telling someone to
          // come back tomorrow for a number that is on screen above the
          // chart would be silly.
          if (series.isEmpty) {
            final empty = holdings?.isEmpty ?? true;
            final onList = !ref.watch(selectedPortfolioProvider).isPrimary;
            return _ChartMessage(
              title: empty
                  ? 'Belum ada kartu di portofolio ini'
                  : onList
                  ? 'Grafik hanya untuk Portofolio Utama'
                  : 'Riwayat nilai belum tersedia',
              detail: empty
                  ? 'Tambahkan kartu ke koleksi untuk mulai melacak nilainya.'
                  : onList
                  ? 'Nilai harian dicatat untuk seluruh koleksi, belum per '
                        'list.'
                  : 'Tarik untuk memuat ulang.',
            );
          }
          // A single reading has nothing to put on an axis — see
          // `PortfolioSparkline`'s own note on why it draws that case as a
          // rise with no axis at all. Two or more points get the real chart:
          // value/date axes, plus a crosshair that follows a touch, a drag,
          // or — on desktop/web — a hovering mouse.
          if (series.length < 2) return PortfolioSparkline(series: series);
          return _PortfolioLineChart(series: series);
        },
      ),
    );
  }
}

/// The value line on its own, without the loading/empty handling around it.
/// Shared with the signed-out preview so both draw the same shape.
class PortfolioSparkline extends StatelessWidget {
  const PortfolioSparkline({super.key, required this.series});

  final List<PortfolioValuePoint> series;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A single point has nowhere to have come from, so it is neither up nor
    // down: it takes the neutral accent rather than claiming a gain.
    final line = series.length < 2
        ? colors.primary
        : series.last.value >= series.first.value
        ? context.appSemantic.success
        : colors.error;

    return CustomPaint(
      size: Size.infinite,
      painter: _ValueLinePainter(
        series: series,
        line: line,
        fill: line.withValues(alpha: 0.12),
      ),
    );
  }
}

class _ValueLinePainter extends CustomPainter {
  const _ValueLinePainter({
    required this.series,
    required this.line,
    required this.fill,
  });

  final List<PortfolioValuePoint> series;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || size.width <= 0 || size.height <= 0) return;

    var min = series.first.value;
    var max = series.first.value;
    for (final point in series) {
      if (point.value < min) min = point.value;
      if (point.value > max) max = point.value;
    }

    // Inset so the stroke isn't clipped at the top and bottom.
    const padY = 3.0;
    final usableHeight = size.height - padY * 2;

    // A single reading, or a series that never moved, has no span to spread
    // over. Both sit at mid-height and read as a flat line rather than
    // collapsing onto an edge — the value is real, it just hasn't changed as
    // far as we know it.
    final flat = max == min;
    final span = flat ? 1 : max - min;
    double yFor(int value) => flat
        ? size.height / 2
        : padY + usableHeight - ((value - min) / span) * usableHeight;

    final path = Path();
    if (series.length == 1) {
      // One reading, drawn as a rise from the chart floor to the value at the
      // right, so the shape carries the change rather than sitting flat.
      //
      // The floor is where measuring started, not a claim the collection was
      // once worth nothing — there is no axis and no label on it. As soon as
      // a second day lands this branch is gone and the line is real
      // throughout.
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width, padY);
    } else {
      // Points are spaced by index: snapshots can miss a day, and spacing by
      // date would leave gaps that imply the portfolio didn't exist then.
      final stepX = size.width / (series.length - 1);
      for (var i = 0; i < series.length; i++) {
        final x = stepX * i;
        final y = yFor(series[i].value);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // The marker on the single-reading line: it says where the value is
    // rather than letting a bare rule look like a chart axis. A real series
    // needs no such marker — its own shape says where it ends.
    if (series.length == 1) {
      canvas
        ..drawCircle(
          Offset(size.width, padY),
          4,
          Paint()..color = line.withValues(alpha: 0.25),
        )
        ..drawCircle(Offset(size.width, padY), 2.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_ValueLinePainter old) =>
      old.series != series || old.line != line;
}

/// The full chart: [PortfolioSparkline]'s line and fill, plus value/date
/// axes and a crosshair for the point nearest a touch, a drag, or a hovering
/// mouse.
///
/// Only reached with two or more points — see [PortfolioValueChart]'s call
/// site for why a single reading stays on the bare sparkline instead.
class _PortfolioLineChart extends StatefulWidget {
  const _PortfolioLineChart({required this.series});

  final List<PortfolioValuePoint> series;

  @override
  State<_PortfolioLineChart> createState() => _PortfolioLineChartState();
}

class _PortfolioLineChartState extends State<_PortfolioLineChart> {
  /// Index into [_PortfolioLineChart.series] the crosshair is parked on, or
  /// null when nothing is pressed or hovered.
  int? _selected;

  @override
  void didUpdateWidget(_PortfolioLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new series (a range switch, a portfolio switch) has different days
    // at the same indices, so a held-over selection would point at the
    // wrong one.
    if (oldWidget.series != widget.series) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final series = widget.series;
    // Same rule as the sparkline: the line is neutral only when there's
    // nothing yet to compare against, which can't happen here since this
    // widget is never built for fewer than two points.
    final line = series.last.value >= series.first.value
        ? context.appSemantic.success
        : colors.error;

    return LayoutBuilder(
      builder: (context, constraints) {
        void select(Offset local) {
          final index = _indexAt(
            local.dx,
            constraints.maxWidth,
            series.length,
          );
          if (index != _selected) setState(() => _selected = index);
        }

        return MouseRegion(
          onHover: (event) => select(event.localPosition),
          onExit: (_) => setState(() => _selected = null),
          child: GestureDetector(
            onTapDown: (d) => select(d.localPosition),
            onHorizontalDragStart: (d) => select(d.localPosition),
            onHorizontalDragUpdate: (d) => select(d.localPosition),
            onHorizontalDragEnd: (_) => setState(() => _selected = null),
            onTapCancel: () => setState(() => _selected = null),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _PortfolioChartPainter(
                series: series,
                selected: _selected,
                line: line,
                fill: line.withValues(alpha: 0.12),
                gridColor: context.borderColor,
                labelColor: context.mutedForeground,
                foreground: colors.onSurface,
                surface: Theme.of(context).cardColor,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Points are spaced by index (see [_ValueLinePainter]'s note on why a
  /// missed snapshot day shouldn't leave a gap), so the nearest point to a
  /// touch is just the nearest slot.
  int _indexAt(double dx, double width, int count) {
    final plotLeft = _PortfolioChartPainter.leftPadding;
    final plotWidth = width - plotLeft - _PortfolioChartPainter.rightPadding;
    if (plotWidth <= 0) return 0;
    final t = ((dx - plotLeft) / plotWidth).clamp(0.0, 1.0);
    return (t * (count - 1)).round();
  }
}

class _PortfolioChartPainter extends CustomPainter {
  const _PortfolioChartPainter({
    required this.series,
    required this.selected,
    required this.line,
    required this.fill,
    required this.gridColor,
    required this.labelColor,
    required this.foreground,
    required this.surface,
  });

  static const leftPadding = 50.0;
  static const rightPadding = 6.0;
  static const topPadding = 8.0;
  static const bottomPadding = 16.0;

  final List<PortfolioValuePoint> series;
  final int? selected;
  final Color line;
  final Color fill;
  final Color gridColor;
  final Color labelColor;
  final Color foreground;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      leftPadding,
      topPadding,
      size.width - rightPadding,
      size.height - bottomPadding,
    );
    if (plot.width <= 0 || plot.height <= 0 || series.length < 2) return;

    var min = series.first.value.toDouble();
    var max = min;
    for (final point in series) {
      final v = point.value.toDouble();
      if (v < min) min = v;
      if (v > max) max = v;
    }
    // Same padding floor as the market price chart: a little headroom even
    // over a flat span, so a portfolio that hasn't moved at all still gets a
    // plottable range instead of a division by zero.
    final pad = [
      5000.0,
      (max - min) * 0.1,
      min.abs() * 0.05,
    ].reduce((a, b) => a > b ? a : b);
    final yMin = (min - pad).clamp(0.0, double.infinity);
    final yMax = max + pad;
    final ySpan = yMax - yMin == 0 ? 1.0 : yMax - yMin;

    double xOf(int i) => plot.left + plot.width * (i / (series.length - 1));
    double yOf(num value) =>
        plot.bottom - ((value - yMin) / ySpan) * plot.height;

    _paintYAxis(canvas, plot, yMin, yMax);

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final offset = Offset(xOf(i), yOf(series[i].value));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    final area = Path.from(path)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    _paintXAxis(canvas, plot, xOf);

    final index = selected;
    if (index != null) _paintCrosshair(canvas, size, plot, xOf, yOf, index);
  }

  void _paintYAxis(Canvas canvas, Rect plot, double yMin, double yMax) {
    const lines = 3;
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final t = i / lines;
      final y = plot.bottom - plot.height * t;
      _drawDashed(
        canvas,
        Path()
          ..moveTo(plot.left, y)
          ..lineTo(plot.right, y),
        paint,
      );
      final value = yMin + (yMax - yMin) * t;
      final label = _text(formatRupiahCompact(value), labelColor);
      label.paint(
        canvas,
        Offset(plot.left - 6 - label.width, y - label.height / 2),
      );
    }
  }

  void _paintXAxis(Canvas canvas, Rect plot, double Function(int) xOf) {
    // Roughly one label per 56px, the same spirit as the market price
    // chart's `minTickGap`.
    final maxLabels = (plot.width / 56).floor().clamp(2, 5);
    final step = (series.length / maxLabels).ceil().clamp(1, series.length);
    for (var i = 0; i < series.length; i += step) {
      final label = _text(formatShortDateId(series[i].day), labelColor);
      final dx = (xOf(i) - label.width / 2).clamp(
        plot.left,
        plot.right - label.width,
      );
      label.paint(canvas, Offset(dx, plot.bottom + 4));
    }
  }

  void _paintCrosshair(
    Canvas canvas,
    Size size,
    Rect plot,
    double Function(int) xOf,
    double Function(num) yOf,
    int index,
  ) {
    final point = series[index];
    final x = xOf(index);
    final y = yOf(point.value);

    _drawDashed(
      canvas,
      Path()
        ..moveTo(x, plot.top)
        ..lineTo(x, plot.bottom),
      Paint()
        ..color = labelColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas
      ..drawCircle(Offset(x, y), 5, Paint()..color = line.withValues(alpha: 0.25))
      ..drawCircle(Offset(x, y), 3, Paint()..color = line);

    // Date above value, the same order the sparkline's own tooltip-free
    // neighbor — the market price chart's crosshair — uses.
    final dateLabel = _text(formatShortDateId(point.day), labelColor);
    final valueLabel = _text(
      formatRupiah(point.value),
      foreground,
      bold: true,
    );
    final width =
        [dateLabel.width, valueLabel.width].reduce((a, b) => a > b ? a : b) +
        20;
    final height = 10 + dateLabel.height + valueLabel.height;

    var left = x + 10;
    if (left + width > size.width) left = x - 10 - width;
    if (left < 0) left = 0;
    var top = y - height - 10;
    if (top < topPadding) top = y + 10;
    if (top + height > size.height) top = size.height - height;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas
      ..drawRRect(rect, Paint()..color = surface)
      ..drawRRect(
        rect,
        Paint()
          ..color = gridColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    dateLabel.paint(canvas, Offset(left + 10, top + 5));
    valueLabel.paint(canvas, Offset(left + 10, top + 7 + dateLabel.height));
  }

  TextPainter _text(String value, Color color, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: AppTypography.caption(
          color,
        ).copyWith(fontSize: 10, fontWeight: bold ? FontWeight.w600 : null),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 3,
    double gap = 3,
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
  bool shouldRepaint(_PortfolioChartPainter old) =>
      old.series != series || old.selected != selected || old.line != line;
}

class _ChartMessage extends StatelessWidget {
  const _ChartMessage({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmSemibold(context.mutedForeground),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

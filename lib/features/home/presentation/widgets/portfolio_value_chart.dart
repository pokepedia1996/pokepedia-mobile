import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
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
          return PortfolioSparkline(series: series);
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

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
          if (series.length < 2) {
            return _ChartMessage(
              title: (holdings?.isEmpty ?? true)
                  ? 'Belum ada kartu di portofolio ini'
                  : 'Riwayat nilai belum tersedia',
              detail: (holdings?.isEmpty ?? true)
                  ? 'Tambahkan kartu ke koleksi untuk mulai melacak nilainya.'
                  : 'Grafik akan terisi setelah ada riwayat harga harian '
                        'untuk kartu-kartu ini.',
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
    final rising = series.last.value >= series.first.value;
    final line = rising ? context.appSemantic.success : colors.error;

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
    if (series.length < 2 || size.width <= 0 || size.height <= 0) return;

    var min = series.first.value;
    var max = series.first.value;
    for (final point in series) {
      if (point.value < min) min = point.value;
      if (point.value > max) max = point.value;
    }
    // A dead-flat series would divide by zero; give it a band so the line
    // lands in the middle instead of at the top edge.
    final span = (max - min) == 0 ? 1 : max - min;

    // Points are spaced by index: `price_history` only has rows for days a
    // card traded, so spacing by date would leave gaps that imply the
    // portfolio didn't exist on the quiet days.
    final stepX = size.width / (series.length - 1);
    // Inset so the stroke isn't clipped at the top and bottom.
    const padY = 3.0;
    final usableHeight = size.height - padY * 2;

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final x = stepX * i;
      final y =
          padY + usableHeight - ((series[i].value - min) / span) * usableHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
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

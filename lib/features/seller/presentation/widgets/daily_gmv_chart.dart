import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/seller_dashboard.dart';

/// Ports the dashboard's daily net-revenue `BarChart`.
///
/// Bars are laid out by index rather than by date: the RPC only returns days
/// that had revenue, so spacing them by calendar position would leave a
/// mostly-empty chart on a quiet week. Tapping a bar reveals its day and
/// amount, which stands in for the web's hover tooltip.
class DailyGmvChart extends StatefulWidget {
  const DailyGmvChart({super.key, required this.data, this.height = 132});

  final List<DailyGmv> data;
  final double height;

  @override
  State<DailyGmvChart> createState() => _DailyGmvChartState();
}

class _DailyGmvChartState extends State<DailyGmvChart> {
  int? _selected;

  @override
  void didUpdateWidget(DailyGmvChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The window switcher swaps the whole series; an index into the old one
    // means nothing against the new.
    if (oldWidget.data.length != widget.data.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final data = widget.data;

    if (data.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Belum ada penjualan di periode ini.',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      );
    }

    final max = data.fold<int>(0, (m, d) => d.gmv > m ? d.gmv : m);
    final selected = _selected != null && _selected! < data.length
        ? data[_selected!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Bars share the width evenly, with a quarter of each slot
              // given over to the gap.
              final slot = constraints.maxWidth / data.length;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final index = (details.localPosition.dx / slot).floor();
                  if (index < 0 || index >= data.length) return;
                  setState(() => _selected = _selected == index ? null : index);
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < data.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: slot * 0.12,
                          ),
                          child: _Bar(
                            // A day with revenue always gets a visible sliver,
                            // so "some" never renders as "none".
                            fraction: max == 0
                                ? 0
                                : (data[i].gmv / max).clamp(
                                    data[i].gmv > 0 ? 0.04 : 0.0,
                                    1.0,
                                  ),
                            highlighted: _selected == null || _selected == i,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // The readout keeps its line whether or not a bar is selected, so
        // tapping doesn't shift the card's height.
        SizedBox(
          height: 18,
          child: selected == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _shortDay(data.first.day),
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    Text(
                      'Tertinggi ${formatRupiahCompact(max)}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    Text(
                      _shortDay(data.last.day),
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text(
                      _shortDay(selected.day),
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const Spacer(),
                    Text(
                      formatRupiah(selected.gmv),
                      style: AppTypography.captionSemibold(colors.onSurface),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// `2026-08-20` → `20 Agu`.
  static String _shortDay(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${parsed.day} ${months[parsed.month - 1]}';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.highlighted});

  final double fraction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FractionallySizedBox(
      alignment: Alignment.bottomCenter,
      heightFactor: fraction == 0 ? 0.02 : fraction,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fraction == 0
              ? colors.secondary
              : colors.primary.withValues(alpha: highlighted ? 1 : 0.35),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ),
    );
  }
}

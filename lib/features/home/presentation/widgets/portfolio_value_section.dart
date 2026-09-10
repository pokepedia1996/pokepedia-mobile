import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../portfolio/presentation/widgets/portfolio_picker_sheet.dart';
import '../../repository/models/portfolio_value.dart';
import '../../usecase/portfolio_value_notifier.dart';
import 'portfolio_value_chart.dart';

/// The top of Beranda: which portfolio is being valued, what it's worth, how
/// that has moved, and the timeline filter over the history chart.
class PortfolioValueSection extends ConsumerWidget {
  const PortfolioValueSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(authProvider).valueOrNull;

    if (user == null) return const _SignedOutPreview();

    final target = ref.watch(selectedPortfolioProvider);
    final value = ref.watch(portfolioValueProvider);
    final counts = ref.watch(portfolioCardCountProvider);
    final delta = ref.watch(portfolioDeltaProvider);
    final range = ref.watch(portfolioRangeProvider);
    final loading = ref.watch(portfolioHoldingsProvider).isLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PortfolioPicker(selected: target),
          const SizedBox(height: 2),

          // The headline. Held at one line so switching portfolios doesn't
          // reflow the chart below it.
          Text(
            loading ? 'Rp–' : formatRupiah(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.h1(colors.onSurface),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (delta != null) ...[
                Icon(
                  delta.isUp ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: delta.isUp
                      ? context.appSemantic.success
                      : colors.error,
                ),
                Text(
                  '${formatRupiah(delta.amount.abs())} '
                  '(${delta.percent.abs().toStringAsFixed(2)}%)',
                  style: AppTypography.caption(
                    delta.isUp ? context.appSemantic.success : colors.error,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '${counts.unique} kartu unik · ${counts.total} total',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const PortfolioValueChart(),
          const SizedBox(height: 12),
          _RangeChips(
            selected: range,
            onSelect: (next) =>
                ref.read(portfolioRangeProvider.notifier).state = next,
          ),
        ],
      ),
    );
  }
}

/// "Portofolio Utama ⌄" — tapping opens the picker, as sketched.
class _PortfolioPicker extends ConsumerWidget {
  const _PortfolioPicker({required this.selected});

  final PortfolioTarget selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      // Always the sheet, even with only the main portfolio in it — its
      // "Buat list baru" row is what a buyer with one list needs, and it
      // keeps them on Beranda instead of navigating away.
      onTap: () => showPortfolioPicker(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(context.mutedForeground),
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.selected, required this.onSelect});

  final PortfolioRange selected;
  final ValueChanged<PortfolioRange> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        for (final range in PortfolioRange.values)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(range),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: range == selected
                      ? colors.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  range.label,
                  style: range == selected
                      ? AppTypography.captionSemibold(colors.primary)
                      : AppTypography.caption(context.mutedForeground),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Signed out, the section still shows the shape of what's behind it —
/// blurred, inert, and captioned with a way in.
///
/// Ports how the web gates `app/portfolio/list/page.tsx`: it renders a
/// skeleton at `opacity-40 blur-[2px] select-none pointer-events-none` under
/// its auth gate. Following that, the preview is a *skeleton* rather than
/// invented figures — a blurred "Rp 1.798.925.030" would be a number the
/// reader could mistake for their own.
class _SignedOutPreview extends StatelessWidget {
  const _SignedOutPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // `IgnorePointer` matches `pointer-events-none`: nothing back here
          // is real, so nothing back here should be tappable.
          IgnorePointer(
            child: Opacity(
              opacity: 0.55,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: const _PreviewSkeleton(),
              ),
            ),
          ),
          const _SignInCallout(),
        ],
      ),
    );
  }
}

/// The section's own layout, with blocks where the numbers go and a
/// representative curve where the history goes.
class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  /// Shape only — this is drawn blurred and is never read as data.
  static final _shape = <PortfolioValuePoint>[
    for (var i = 0; i < _curve.length; i++)
      PortfolioValuePoint(
        day: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        value: _curve[i],
      ),
  ];

  static const _curve = [
    52,
    58,
    55,
    63,
    61,
    70,
    68,
    74,
    71,
    79,
    84,
    81,
    88,
    95,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Block(width: 96, height: 13),
        const SizedBox(height: 8),
        const _Block(width: 210, height: 30),
        const SizedBox(height: 8),
        const _Block(width: 150, height: 12),
        const SizedBox(height: 12),
        SizedBox(height: 140, child: PortfolioSparkline(series: _shape)),
        const SizedBox(height: 12),
        Row(
          children: [
            // One block per real chip, so the row lines up with what
            // replaces it once signed in.
            for (var i = 0; i < PortfolioRange.values.length; i++)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: _Block(height: 26),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

/// The call to action sitting on top of the blur.
class _SignInCallout extends StatelessWidget {
  const _SignInCallout();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.chartLine, size: 22, color: colors.primary),
          const SizedBox(height: 6),
          Text(
            'Lacak nilai koleksimu',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.push(Routes.login),
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../portfolio/presentation/widgets/portfolio_picker_sheet.dart';
import '../../repository/models/portfolio_value.dart';
import '../../usecase/home_preferences.dart';
import '../../usecase/portfolio_value_notifier.dart';
import 'portfolio_value_chart.dart';

/// Holdings listed under "Nilai tertinggi" when the card is open.
const _topHoldingCount = 3;

/// What a hidden rupiah figure reads as.
const _masked = 'Rp•••••••';

/// A move as the card writes it: one decimal, an Indonesian comma.
String _percent(double value) =>
    '${value.abs().toStringAsFixed(1).replaceAll('.', ',')}%';

/// The move pill's text: "−Rp322.874 (11,0%)", or just "−11,0%" while the
/// figures are hidden.
String _moveText(PortfolioDelta delta, bool hidden) {
  final sign = delta.isUp ? '+' : '−';
  if (hidden) return '$sign${_percent(delta.percent)}';
  return '$sign${formatRupiah(delta.amount.abs())} (${_percent(delta.percent)})';
}

TextStyle _amountStyle(Color color) => TextStyle(
  fontFamily: 'CalSans',
  fontSize: 24,
  letterSpacing: -0.5,
  color: color,
);

/// The top of Beranda: the selected portfolio's worth and how it has moved,
/// opening onto its history chart and the holdings carrying most of it.
///
/// Shut, it is one row — the portfolio, its value, the move over the chosen
/// range and the toggle. Open, the chart with its range switch and the top
/// three holdings follow. The eye hides every rupiah figure on the card.
class PortfolioValueSection extends ConsumerWidget {
  const PortfolioValueSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const _SignedOutPreview();

    final palette = DesignPalette.of(context);
    final expanded = ref.watch(portfolioCardExpandedProvider);
    final hidden = ref.watch(hidePortfolioValuesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border, width: 1.5),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Summary(expanded: expanded, hidden: hidden),
              if (expanded) ...[
                const SizedBox(height: 14),
                PortfolioValueChart(height: 110, hideValues: hidden),
                const SizedBox(height: 12),
                _RangeTabs(
                  selected: ref.watch(portfolioRangeProvider),
                  onSelect: (next) =>
                      ref.read(portfolioRangeProvider.notifier).state = next,
                ),
                _TopHoldings(hidden: hidden),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's own row: name, value and move on the left, the toggle on the
/// right.
class _Summary extends ConsumerWidget {
  const _Summary({required this.expanded, required this.hidden});

  final bool expanded;
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final target = ref.watch(selectedPortfolioProvider);
    final value = ref.watch(portfolioValueProvider);
    final delta = ref.watch(portfolioDeltaProvider);
    // A pull-to-refresh keeps the current figure up; only a first load or a
    // portfolio switch blanks it.
    final summary = ref.watch(collectionSummaryProvider);
    final loading = summary.isLoading && !summary.isRefreshing;

    final title = target.isPrimary ? 'Portofolio Utama' : target.name;
    final figure = loading
        ? 'Rp–'
        : hidden
        ? _masked
        : formatRupiah(value);
    final moveText = delta == null || loading ? null : _moveText(delta, hidden);

    final name = Row(
      children: [
        Flexible(child: _PortfolioPicker(name: title)),
        const SizedBox(width: 8),
        _IconTap(
          icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
          color: palette.muted,
          tooltip: hidden ? 'Tampilkan nilai' : 'Sembunyikan nilai',
          onTap: () => ref.read(hidePortfolioValuesProvider.notifier).toggle(),
        ),
      ],
    );
    // Shrinks rather than cuts off: a figure missing its last digits reads
    // as a different figure.
    final amount = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(figure, maxLines: 1, style: _amountStyle(palette.ink)),
    );
    final trailing = [
      if (delta != null && moveText != null) ...[
        const SizedBox(width: 10),
        _MovePill(up: delta.isUp, text: moveText),
      ],
      const SizedBox(width: 10),
      _ExpandToggle(
        expanded: expanded,
        onTap: () =>
            ref.read(portfolioCardExpandedProvider.notifier).state = !expanded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // The design's row — name over figure, then the move and the toggle
        // — when all of it fits. Where it wouldn't (a narrower phone, a
        // long list name, a larger text size) the name takes a line of its
        // own instead of being cut short.
        double measure(String text, TextStyle style) => (TextPainter(
          // As `Text` draws it: merged into the inherited default, whose
          // letter spacing is part of the width.
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout()).width;
        // Chevron and its gap, then the eye's gap and hit area.
        final nameWidth =
            measure(title, _PortfolioPicker.style(palette.ink)) +
            4 +
            16 +
            8 +
            24;
        final figureWidth = measure(figure, _amountStyle(palette.ink));
        // Pill padding and icon, then the gaps and the toggle.
        final pillWidth = moveText == null
            ? 0
            : 10 + 8 + 13 + 4 + measure(moveText, _MovePill.style) + 8;
        final needed =
            (nameWidth > figureWidth ? nameWidth : figureWidth) +
            pillWidth +
            10 +
            32;
        if (needed <= constraints.maxWidth) {
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, const SizedBox(height: 4), amount],
                ),
              ),
              ...trailing,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            name,
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: amount),
                ...trailing,
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Portofolio Utama ⌄" — opens the picker.
class _PortfolioPicker extends ConsumerWidget {
  const _PortfolioPicker({required this.name});

  final String name;

  static TextStyle style(Color color) => GoogleFonts.urbanist(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: color,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
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
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(palette.ink),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: palette.ink),
          ],
        ),
      ),
    );
  }
}

/// The move over the chosen range: "−Rp322.874 (11,0%)", red falling and
/// green rising.
class _MovePill extends StatelessWidget {
  const _MovePill({required this.up, required this.text});

  final bool up;
  final String text;

  /// Its text's style, less the colour: [_Summary] measures with it.
  static final style = GoogleFonts.urbanist(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final foreground = up ? palette.successText : palette.errorText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: up ? palette.successSoft : palette.errorSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
            size: 13,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(text, style: style.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Semantics(
      button: true,
      label: expanded ? 'Tutup grafik portofolio' : 'Buka grafik portofolio',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: palette.chip,
            shape: BoxShape.circle,
          ),
          child: Icon(
            expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 16,
            color: palette.ink,
          ),
        ),
      ),
    );
  }
}

/// A bare icon with a comfortable hit area around it.
class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// The chart's timeline switch — `1H 7H 1B 3B 6B MAX` — as one segmented
/// track.
class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.selected, required this.onSelect});

  final PortfolioRange selected;
  final ValueChanged<PortfolioRange> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final range in PortfolioRange.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(range),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: range == selected
                        ? palette.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: range == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x1F1C1413),
                              offset: Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    range.label,
                    style: GoogleFonts.urbanist(
                      fontSize: 12,
                      fontWeight: range == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: range == selected ? palette.brand : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Nilai tertinggi": the three holdings worth the most, then a way to the
/// rest. Read only while the card is open — it is a full read of the
/// portfolio, which the shut card has no use for.
class _TopHoldings extends ConsumerWidget {
  const _TopHoldings({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final holdings = ref.watch(topHoldingsProvider);
    if (holdings.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nilai tertinggi',
            style: GoogleFonts.urbanist(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: 2),
          for (final (i, holding) in holdings.take(_topHoldingCount).indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: palette.border)),
              ),
              child: HoldingRow(holding: holding, hidden: hidden),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: InkWell(
              onTap: () => context.go(Routes.portfolio),
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(
                  'Lihat semua',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.brand,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One holding: name, then its print (flag, number, set, rarity); its price
/// a copy and the week's move on the right.
@visibleForTesting
class HoldingRow extends StatelessWidget {
  const HoldingRow({super.key, required this.holding, this.hidden = false});

  final PortfolioHolding holding;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final meta = [
      holding.collectorNumber,
      holding.expansionCode.toUpperCase(),
      if (holding.rarity case final rarity? when rarity.isNotEmpty) rarity,
    ].join(' · ');
    final change = holding.priceChangePct;

    return InkWell(
      onTap: () =>
          context.push(Routes.cardDetail(holding.packSlug, holding.cardId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holding.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.urbanist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      CardLanguageBadge(language: holding.language, size: 14),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            color: palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hidden ? 'Rp•••' : formatRupiah(holding.unitPrice),
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${change < 0 ? '−' : '+'}${_percent(change)}',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: change < 0
                          ? palette.errorText
                          : palette.successText,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
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

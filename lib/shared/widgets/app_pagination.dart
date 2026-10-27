import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// The page numbers [AppPagination] draws, 1-based, with null for a gap.
///
/// Web's `getPageNumbers` keeps the first and last three pages around the
/// current one — thirteen 40px buttons, wider than a phone. This keeps one
/// at each end instead, so the row fits at 360dp: `1 … 4 5 6 … 12`. A gap
/// of a single page is filled with that page rather than an ellipsis, as
/// web does.
List<int?> pageNumbers(int current, int total) {
  if (total <= 5) return [for (var i = 1; i <= total; i++) i];

  final shown = <int>{1, total};
  for (var i = current - 1; i <= current + 1; i++) {
    if (i >= 1 && i <= total) shown.add(i);
  }
  final sorted = shown.toList()..sort();

  final result = <int?>[];
  for (var i = 0; i < sorted.length; i++) {
    if (i > 0) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap == 2) {
        result.add(sorted[i] - 1);
      } else if (gap > 2) {
        result.add(null);
      }
    }
    result.add(sorted[i]);
  }
  return result;
}

/// Ports `components/ui/pagination.tsx`: previous, the page numbers with
/// the current one filled, and next. [page] is 1-based like web's. Draws
/// nothing for a single page.
class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        _PageButton(
          tooltip: 'Halaman sebelumnya',
          onTap: page > 1 ? () => onPage(page - 1) : null,
          child: const Icon(LucideIcons.chevronLeft, size: 16),
        ),
        for (final n in pageNumbers(page, pageCount))
          if (n == null)
            SizedBox(
              width: 20,
              child: Icon(
                LucideIcons.ellipsis,
                size: 14,
                color: context.mutedForeground,
              ),
            )
          else
            _PageButton(
              active: n == page,
              onTap: n == page ? null : () => onPage(n),
              child: Text('$n'),
            ),
        _PageButton(
          tooltip: 'Halaman berikutnya',
          onTap: page < pageCount ? () => onPage(page + 1) : null,
          child: const Icon(LucideIcons.chevronRight, size: 16),
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.onTap,
    required this.child,
    this.active = false,
    this.tooltip,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // The current page is drawn filled but takes no tap; any other button
    // without one is a bound that has been reached, and dims.
    final disabled = onTap == null && !active;
    final fg = active
        ? colors.onPrimary
        : disabled
        ? context.mutedForeground.withValues(alpha: 0.5)
        : context.mutedForeground;
    final radius = BorderRadius.circular(AppRadius.md);

    final button = Material(
      color: active
          ? colors.primary
          : disabled
          ? colors.secondary.withValues(alpha: 0.6)
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: active ? colors.primary : context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IconTheme.merge(
                data: IconThemeData(color: fg),
                child: DefaultTextStyle.merge(
                  style: AppTypography.captionSemibold(fg),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Ports `components/ui/page-size-selector.tsx`: "Tampilkan [15 ▾] per
/// halaman".
class PageSizeSelector extends StatelessWidget {
  const PageSizeSelector({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.bodySm(context.mutedForeground);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text('Tampilkan', style: muted),
        PopupMenuButton<int>(
          tooltip: 'Jumlah per halaman',
          initialValue: value,
          position: PopupMenuPosition.under,
          onSelected: onChanged,
          itemBuilder: (_) => [
            for (final option in options)
              PopupMenuItem(value: option, child: Text('$option')),
          ],
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  '$value',
                  style: AppTypography.bodySmSemibold(
                    context.appColors.onSurface,
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: context.mutedForeground,
                ),
              ],
            ),
          ),
        ),
        Text('per halaman', style: muted),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `components/ui/empty-state.tsx`.
///
/// Centred in whatever room it is given, both ways — a page body, a tab, an
/// `Expanded` — so every empty screen reads the same. Where the height is
/// unbounded (inside a list or a `Column` in a scroll view) `Center` shrinks
/// to the content, so those spots keep their layout; a scrolling page that
/// wants it centred puts it in a `SliverFillRemaining` instead.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: context.mutedForeground),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// An [EmptyState] on a page that scrolls — under pull-to-refresh, or below
/// the page's own header — centred in the room left under [header] rather
/// than sat at the top of it, as it is everywhere else.
///
/// Still a scroll view, always scrollable, so a pull to refresh works from
/// an empty screen too. A [header] taller than the screen just scrolls, with
/// the empty state after it.
class ScrollableEmptyState extends StatelessWidget {
  const ScrollableEmptyState({
    super.key,
    required this.child,
    this.header = const [],
    this.padding = EdgeInsets.zero,
  });

  /// The empty state itself — usually an [EmptyState].
  final Widget child;

  /// What the page shows above it: a title, filters.
  final List<Widget> header;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            0,
          ),
          sliver: SliverList(delegate: SliverChildListDelegate(header)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            padding.bottom,
          ),
          sliver: SliverFillRemaining(hasScrollBody: false, child: child),
        ),
      ],
    );
  }
}

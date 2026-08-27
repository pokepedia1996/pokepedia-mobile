import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/app_bottom_nav.dart';
import '../shared/widgets/app_top_bar.dart';
import 'router/routes.dart';

/// Wraps the six buyer tab branches with the floating bottom nav, mirroring
/// `MobileBottomNav` + the `<main>` shell in `app/layout.tsx`.
///
/// The nav bar is only shown on the 6 tab roots themselves; once the user
/// drills into a child route nested under a branch (e.g. a pack/card detail
/// under Ekspansi), it's hidden since that page is already a child screen.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.state,
  });

  final StatefulNavigationShell navigationShell;
  final GoRouterState state;

  static const _tabRootPaths = {
    Routes.home,
    Routes.expansions,
    Routes.search,
    Routes.portfolio,
    Routes.market,
    Routes.account,
  };

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Below this offset the nav always stays at full size, so short pages and
  /// the first flick of a long one don't shrink it. Mirrors the `y > 80`
  /// check in `mobile-bottom-nav.tsx`.
  static const _compactThreshold = 80.0;

  /// Ignores sub-pixel jitter from the scroll physics settling.
  static const _minDelta = 1.0;

  bool _compact = false;

  bool _onScroll(ScrollNotification notification) {
    // Horizontal carousels (set rows, market shelves) also bubble up here.
    if (notification.metrics.axis != Axis.vertical) return false;

    // The top bar's logo row keys off absolute offset, like the web's
    // `scrollY > 100`, so it's read from every notification rather than
    // only the direction-sensitive updates the nav pill needs below.
    _syncTopBar(notification.metrics.pixels > AppTopBar.morphThreshold);

    if (notification is! ScrollUpdateNotification) return false;

    final delta = notification.scrollDelta ?? 0;
    if (delta.abs() < _minDelta) return false;

    // Down past the threshold shrinks it; any upward scroll restores it.
    final compact =
        delta > 0 && notification.metrics.pixels > _compactThreshold;
    if (compact != _compact) setState(() => _compact = compact);
    return false;
  }

  void _syncTopBar(bool scrolled) {
    final notifier = ref.read(topBarScrolledProvider.notifier);
    if (notifier.state != scrolled) notifier.state = scrolled;
  }

  @override
  Widget build(BuildContext context) {
    final isTabRoot = AppShell._tabRootPaths.contains(widget.state.uri.path);
    final navigationShell = widget.navigationShell;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: navigationShell,
      ),
      extendBody: isTabRoot,
      bottomNavigationBar: isTabRoot
          ? AppBottomNav(
              currentIndex: navigationShell.currentIndex,
              compact: _compact,
              onTap: (index) {
                // The incoming tab starts at its own scroll offset, so drop
                // back to the full-size pill and bring the logo row back.
                if (_compact) setState(() => _compact = false);
                _syncTopBar(false);
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            )
          : null,
    );
  }
}

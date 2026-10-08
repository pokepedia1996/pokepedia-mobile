import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router/routes.dart';
import '../features/account/usecase/account_nav_indicator.dart';
import '../shared/widgets/app_bottom_nav.dart';
import 'tab_reselect.dart';
import '../shared/widgets/app_top_bar.dart';

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

  /// The nav's own list, so the paths the pill navigates to and the ones the
  /// shell treats as tab roots can't drift apart.
  static final _tabRootPaths = AppBottomNav.tabPaths.toSet();

  static final _accountTabIndex = AppBottomNav.tabPaths.indexOf(Routes.account);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Below this offset the nav always stays put, so short pages and the
  /// first flick of a long one don't send it away. Mirrors the `y > 80`
  /// check in `mobile-bottom-nav.tsx`.
  static const _hideThreshold = 80.0;

  /// Ignores sub-pixel jitter from the scroll physics settling.
  static const _minDelta = 1.0;

  /// Whether the nav is currently off-screen.
  bool _navHidden = false;

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

    // Down past the threshold sends it away; any upward scroll brings it
    // back — the behaviour of every feed the reader already knows.
    final hidden = delta > 0 && notification.metrics.pixels > _hideThreshold;
    if (hidden != _navHidden) setState(() => _navHidden = hidden);
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
    final accountDot = ref.watch(accountNavIndicatorProvider);

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: navigationShell,
      ),
      extendBody: isTabRoot,
      bottomNavigationBar: isTabRoot
          ? AppBottomNav(
              currentIndex: navigationShell.currentIndex,
              hidden: _navHidden,
              dotted: accountDot ? {AppShell._accountTabIndex} : const {},
              onTap: (index) {
                // The incoming tab starts at its own scroll offset, so bring
                // the pill and the logo row back.
                if (_navHidden) setState(() => _navHidden = false);
                _syncTopBar(false);

                // Tapping the tab already open is not navigation — the
                // branch pops to its root either way, and a page sitting at
                // its root would answer with nothing at all. The page hears
                // about it instead and decides what "again" means for it.
                if (index == navigationShell.currentIndex) {
                  ref.read(tabReselectProvider.notifier).tapped(index);
                }

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

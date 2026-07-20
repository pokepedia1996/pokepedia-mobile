import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/app_bottom_nav.dart';
import 'router/routes.dart';

/// Wraps the six buyer tab branches with the floating bottom nav, mirroring
/// `MobileBottomNav` + the `<main>` shell in `app/layout.tsx`.
///
/// The nav bar is only shown on the 6 tab roots themselves; once the user
/// drills into a child route nested under a branch (e.g. a pack/card detail
/// under Ekspansi), it's hidden since that page is already a child screen.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell, required this.state});

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
  Widget build(BuildContext context) {
    final isTabRoot = _tabRootPaths.contains(state.uri.path);

    return Scaffold(
      body: navigationShell,
      extendBody: isTabRoot,
      bottomNavigationBar: isTabRoot
          ? AppBottomNav(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            )
          : null,
    );
  }
}

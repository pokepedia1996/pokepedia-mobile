import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/app_bottom_nav.dart';

/// Wraps the six buyer tab branches with the floating bottom nav, mirroring
/// `MobileBottomNav` + the `<main>` shell in `app/layout.tsx`.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      extendBody: true,
      bottomNavigationBar: AppBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

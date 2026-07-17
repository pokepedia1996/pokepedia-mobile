import 'package:flutter/material.dart';

import '../../../shared/widgets/app_top_bar.dart';
import 'widgets/explore_expansions_section.dart';
import 'widgets/hero_section.dart';
import 'widgets/promo_sections.dart';
import 'widgets/recently_viewed_section.dart';

/// Ports `app/page.tsx` — the buyer home tab.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: const [
            AppTopBar(),
            HeroSection(),
            RecentlyViewedSection(),
            ExploreExpansionsSection(),
            SearchPromoSection(),
            DeckbuilderPromoSection(),
            CollectionPromoSection(),
            SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}

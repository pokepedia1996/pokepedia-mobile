import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../usecase/home_feed_notifier.dart';
import '../usecase/portfolio_value_notifier.dart';
import 'widgets/home_loading_gate.dart';
import 'widgets/marketplace_feed_section.dart';
import 'widgets/portfolio_value_section.dart';
import 'widgets/top_holdings_section.dart';

/// The buyer home tab, built around what the collection is worth: the
/// selected portfolio's market value and its history over a chosen
/// timeline, the holdings carrying most of that value, and the marketplace
/// feed underneath.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: HomeLoadingGate(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(portfolioHoldingsProvider);
              ref.invalidate(portfolioValueSeriesProvider);
              ref.invalidate(homeFeedProvider);
              await ref.read(portfolioHoldingsProvider.future);
            },
            child: ListView(
              // Bottom padding rather than a fixed spacer: the last feed
              // card has to clear the floating nav pill it scrolls under.
              padding: EdgeInsets.only(
                bottom: AppBottomNav.reservedSpace(context) + 12,
              ),
              children: const [
                AppTopBar(),
                PortfolioValueSection(),
                TopHoldingsSection(),
                MarketplaceFeedSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../promos/presentation/promo_popup_gate.dart';
import '../usecase/home_notifier.dart';
import '../usecase/portfolio_value_notifier.dart';
import '../usecase/store_shelves_notifier.dart';
import 'widgets/home_banner_carousel.dart';
import 'widgets/home_loading_gate.dart';
import 'widgets/home_tasks_section.dart';
import 'widgets/latest_releases_section.dart';
import 'widgets/onboarding_shortcuts_section.dart';
import 'widgets/portfolio_value_section.dart';
import 'widgets/store_shelves_section.dart';
import 'widgets/tcg_picker_section.dart';

/// The buyer home tab: what the collection is worth, the banners and the
/// catalogs to browse, the newest sets, then the stores that listed most
/// recently — loading more of them as the reader scrolls.
///
/// Also where the interstitial campaign appears — web mounts its
/// `PromoPopupGate` app-wide, but the app has one front door.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  /// How close to the end of the page the next stores start loading, so
  /// they are usually in before the reader gets there.
  static const _loadMoreWithin = 600.0;

  /// The space between two of the page's sections.
  static const _sectionGap = SizedBox(height: 32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PromoPopupGate(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Pinned above the feed rather than scrolled as its first row —
              // the web's navbar is `fixed inset-x-0 top-0`, and a search
              // field that scrolls away isn't much of a search field.
              const AppTopBar(),
              Expanded(
                child: HomeLoadingGate(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(ref),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // The page's own scroll only: the banner and release
                        // rows scroll sideways inside it.
                        if (notification.depth == 0 &&
                            notification.metrics.axis == Axis.vertical &&
                            notification.metrics.extentAfter <
                                _loadMoreWithin) {
                          ref.read(storeShelvesProvider.notifier).loadMore();
                        }
                        return false;
                      },
                      child: ListView(
                        // Bottom padding rather than a fixed spacer: the last
                        // shelf has to clear the floating nav pill it
                        // scrolls under.
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: AppBottomNav.reservedSpace(context) + 12,
                        ),
                        children: const [
                          // A new account's own picks from onboarding come
                          // first: it has no value or holdings to show yet.
                          OnboardingShortcutsSection(),
                          PortfolioValueSection(),
                          // What needs answering, before anything to browse.
                          // Absent when nothing does.
                          HomeTasksSection(),
                          _sectionGap,
                          // Banners booked in `ads`; nothing when none are,
                          // gap below included.
                          HomeBannerCarousel(),
                          TcgPickerSection(),
                          _sectionGap,
                          LatestReleasesSection(),
                          _sectionGap,
                          StoreShelvesSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    // Sections keep what they show until the new data lands, rather than
    // dropping back to spinners.
    final refreshing = ref.read(homeRefreshingProvider.notifier);
    refreshing.state = true;
    ref.invalidate(portfolioHoldingsProvider);
    ref.invalidate(collectionSummaryProvider);
    ref.invalidate(portfolioValueSeriesProvider);
    ref.invalidate(latestReleaseOwnedProvider);
    ref.invalidate(storeShelvesProvider);
    try {
      await Future.wait<void>([
        ref.read(collectionSummaryProvider.future),
        ref.read(portfolioValueSeriesProvider.future),
        ref.read(storeShelvesProvider.future),
      ]);
    } catch (_) {
      // Each section shows its own error; the spinner just needs to stop.
    } finally {
      refreshing.state = false;
    }
  }
}

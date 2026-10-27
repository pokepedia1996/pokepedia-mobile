import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_search_field.dart';
import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/store_model.dart';
import '../../../shared/widgets/cart_app_bar_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/reputation_star.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/simple_markdown.dart';
import '../../../shared/widgets/store_card.dart'
    show TopSellerBadge, VerifiedBadge;
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../chat/repository/models/chat_models.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../repository/models/store_feedback.dart';
import '../usecase/market_notifier.dart';
import 'widgets/listing_filter_sheet.dart';
import 'widgets/store_share_sheet.dart';
import '../../moderation/presentation/blocked_user_notice.dart';
import '../../moderation/presentation/user_safety_menu.dart';
import '../../moderation/usecase/moderation_notifier.dart';
import '../../../shared/widgets/app_network_image.dart';

/// Ports `features/market/store/components/storefront/storefront-view.tsx` —
/// a seller's storefront: banner and identity with follow and chat beside
/// it, the stat chips, and the WTS / WTB / Tentang / Penilaian tabs over
/// their listings.
class StoreDetailPage extends ConsumerStatefulWidget {
  const StoreDetailPage({super.key, required this.handle});

  final String handle;

  @override
  ConsumerState<StoreDetailPage> createState() => _StoreDetailPageState();
}

/// Web's `StorefrontTab`, in the same order.
enum _StoreTab { shop, buylist, about, feedback }

extension _StoreTabX on _StoreTab {
  String get label => switch (this) {
    // The trade shorthand the design uses: want to sell, want to buy.
    _StoreTab.shop => 'WTS',
    _StoreTab.buylist => 'WTB',
    _StoreTab.about => 'Tentang',
    _StoreTab.feedback => 'Penilaian',
  };
}

class _StoreDetailPageState extends ConsumerState<StoreDetailPage> {
  final _searchController = TextEditingController();

  _StoreTab _tab = _StoreTab.shop;
  String _query = '';

  /// [_query] once typing has paused — what is actually sent. Each search is
  /// a server round trip now, so it waits for the word rather than firing on
  /// every letter of it.
  String _search = '';
  Timer? _searchDebounce;

  /// Everything web's storefront rail filters by — type, language, rarity,
  /// condition, city and price — sent to the server with the search.
  MarketFilters _filters = const MarketFilters();
  MarketSort _sort = MarketSort.createdDesc;
  bool _following = false;
  bool _followingInitialised = false;
  bool _followBusy = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim());
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _search != _query) setState(() => _search = _query);
    });
  }

  StoreFeedKey _feedKey(String sellerUserId) => (
    sellerUserId: sellerUserId,
    side: _tab == _StoreTab.buylist ? 'bid' : 'ask',
    search: _search,
    filters: _filters,
    sort: _sort.raw,
  );

  /// Asks for the next page while there is still a screenful to go, so the
  /// grid keeps running rather than stopping to wait at its foot.
  bool _onScroll(ScrollNotification notification, StoreFeedKey? key) {
    if (key == null || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification.metrics.extentAfter < 600) {
      ref.read(storeFeedProvider(key).notifier).loadMore();
    }
    return false;
  }

  /// Follows or unfollows, flipping the button first and putting it back if
  /// the write fails — the round trip is long enough that waiting for it
  /// makes the button feel broken.
  Future<void> _toggleFollow(StoreModel store) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final shopUserId = store.userId;
    if (shopUserId == null || _followBusy) return;

    final next = !_following;
    setState(() {
      _following = next;
      _followBusy = true;
    });

    final error = await ref
        .read(followControllerProvider)
        .setFollowing(shopUserId: shopUserId, following: next);
    if (!mounted) return;

    setState(() {
      _followBusy = false;
      if (error != null) _following = !next;
    });

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (next
                  ? 'Mengikuti ${store.storeName}'
                  : 'Berhenti mengikuti ${store.storeName}'),
        ),
        persist: false,
      ),
    );
    // The header's follower count is part of the storefront row.
    ref.invalidate(storeDetailProvider(widget.handle));
  }

  Future<void> _contact(StoreModel store) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final sellerId = store.userId;
    if (sellerId == null) return;

    final arg = await ref
        .read(chatOpenerProvider)
        .withUser(otherUserId: sellerId, title: store.storeName);
    if (!mounted) return;

    final slug = arg.slug;
    if (slug != null) {
      context.push(Routes.chatThread(slug), extra: store.storeName);
    } else {
      context.push(
        Routes.chatNew,
        extra: ChatTarget(otherUserId: sellerId, title: store.storeName),
      );
    }
  }

  /// How many filters are on, for the badge on the toggle.
  int get _activeFilters =>
      _filters.activeCount + (_sort == MarketSort.createdDesc ? 0 : 1);

  /// The sorts web offers on a storefront.
  static const _storeSorts = [
    MarketSort.createdDesc,
    MarketSort.priceAsc,
    MarketSort.priceDesc,
  ];

  /// The market's filter sheet, pointed at this store: its own counts for
  /// the side on show, and only the sections web's storefront rail has —
  /// no wishlist, bulk or verified switch, which narrow nothing within one
  /// seller's shop. Sorting rides along, since this page has no sort button.
  Future<void> _openFilters() async {
    final sellerId = ref
        .read(storeDetailProvider(widget.handle))
        .valueOrNull
        ?.userId;
    if (sellerId == null) return;
    final side = _tab == _StoreTab.buylist ? 'bid' : 'ask';
    await showListingSheet(
      context,
      ListingFilterSheet(
        initial: _filters,
        initialSort: _sort,
        sortOptions: _storeSorts,
        facets: storeFacetsProvider((sellerUserId: sellerId, side: side)),
        onApply: (filters, sort) => setState(() {
          _filters = filters;
          _sort = sort;
        }),
      ),
    );
  }

  List<Widget> _listingSlivers(StoreFeedKey? key) {
    final empty = EmptyState(
      icon: LucideIcons.store,
      title: _search.isNotEmpty || _filters.activeCount > 0
          ? 'Tidak ada kartu yang cocok'
          : _tab == _StoreTab.buylist
          ? 'Toko ini belum mencari kartu'
          : 'Belum ada listing',
    );
    if (key == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.only(top: 32), child: empty),
        ),
      ];
    }

    final feed = ref.watch(storeFeedProvider(key));
    if (feed.loading) {
      return const [SliverToBoxAdapter(child: PikachuLoader())];
    }
    if (feed.failed) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: LucideIcons.circleAlert,
            title: 'Gagal memuat listing',
            action: OutlinedButton(
              onPressed: () =>
                  ref.read(storeFeedProvider(key).notifier).retry(),
              child: const Text('Coba lagi'),
            ),
          ),
        ),
      ];
    }
    if (feed.listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.only(top: 32), child: empty),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, feed.hasNext ? 8 : 24),
        sliver: SliverGrid(
          gridDelegate: listingGridDelegate(context, showSeller: false),
          delegate: SliverChildBuilderDelegate(
            (context, i) =>
                ListingCard(listing: feed.listings[i], showSeller: false),
            childCount: feed.listings.length,
          ),
        ),
      ),
      if (feed.hasNext)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeDetailProvider(widget.handle));
    final viewerId = ref.watch(authProvider).valueOrNull?.id;
    final shown = storeAsync.valueOrNull;
    // Web's storefront safety menu: not your own shop. A signed-out tap
    // goes to login from inside the menu.
    final safetyUserId = shown?.userId == null || shown!.userId == viewerId
        ? null
        : shown.userId;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(
        actions: [
          if (shown != null)
            _BarButton(
              icon: LucideIcons.share2,
              tooltip: 'Bagikan toko',
              onPressed: () => showStoreShareSheet(context, store: shown),
            ),
          // A storefront is where a basket fills up, so the way to it
          // belongs in reach.
          const CartAppBarButton(),
          if (safetyUserId != null)
            _BarButton(
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'Opsi pengguna',
              onPressed: () => openUserSafetyMenu(
                context,
                ref,
                userId: safetyUserId,
                username: shown!.handle,
                reportContext: UserReportContext.store,
                // Blocking hides the store from both sides; reloading lands
                // on the unblock notice below.
                onBlockChanged: (_) =>
                    ref.invalidate(storeDetailProvider(widget.handle)),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return _MissingStore(
              handle: widget.handle,
              onUnblocked: () =>
                  ref.invalidate(storeDetailProvider(widget.handle)),
            );
          }
          // Seeded from the server once, then owned locally so the button
          // responds before the refetch lands.
          if (!_followingInitialised) {
            _following = store.isFollowing;
            _followingInitialised = true;
          }

          final sellerId = store.userId;
          final feedKey = sellerId == null ? null : _feedKey(sellerId);

          // Following yourself is refused by `follow_shop`, and
          // `ensure_direct_room` has nobody to open a room with — so on your
          // own storefront neither button is offered.
          final isOwnStore = sellerId != null && sellerId == viewerId;

          return AppBarOverlayBody(
            reserveToolbar: true,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => _onScroll(n, feedKey),
              child: CustomScrollView(
                // Only what is on screen is built, so only what is on screen
                // fetches and decodes its art. The default builds 250pt
                // ahead in both directions, which on a store of large
                // catalog images meant a screenful of downloads and decodes
                // the reader had not scrolled to.
                cacheExtent: 0,
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      store: store,
                      actions: isOwnStore
                          ? null
                          : _IdentityActions(
                              following: _following,
                              busy: _followBusy,
                              onToggleFollow: () => _toggleFollow(store),
                              onContact: () => _contact(store),
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _TabBar(
                      active: _tab,
                      onSelect: (tab) => setState(() => _tab = tab),
                    ),
                  ),
                  if (_tab == _StoreTab.about)
                    SliverToBoxAdapter(child: _About(store: store))
                  else if (_tab == _StoreTab.feedback)
                    SliverToBoxAdapter(child: _Feedback(store: store))
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: AppSearchField(
                                hintText: _tab == _StoreTab.shop
                                    ? 'Cari dari '
                                          '${formatCountId(store.activeListingCount)}'
                                          ' listing'
                                    : 'Cari di WTB toko ini',
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                              ),
                            ),
                            _FilterToggle(
                              count: _activeFilters,
                              onPressed: _openFilters,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ..._listingSlivers(feedKey),
                  ],
                ],
              ),
            ),
          );
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat toko',
        ),
      ),
    );
  }
}

/// Banner, then the identity row — avatar, name and rating, with follow and
/// chat beside it — the vacation notice, and the stat chips.
class _Header extends StatelessWidget {
  const _Header({required this.store, this.actions});

  final StoreModel store;

  /// Follow and chat; null on the viewer's own store.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final banner = store.bannerUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inset and rounded rather than bled under the bar: the buttons
          // up there no longer sit on whatever the banner is doing. A store
          // without one goes straight to its name, as on web.
          if (banner != null && banner.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: SizedBox(
                height: 112,
                width: double.infinity,
                child: cachedNetworkImage(
                  banner,
                  fit: BoxFit.cover,
                  // Decoded at the width it is drawn at. Banners are uploaded
                  // straight from phone cameras, and one decoded at full size
                  // — a 4000px photo is ~48MB of bitmap, more for larger ones
                  // — was enough to have the OS kill the app on opening that
                  // store, while stores with small banners opened fine.
                  cacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: colors.secondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.borderColor),
                ),
                child: SellerAvatar(
                  name: store.storeName,
                  imageUrl: store.logoUrl,
                  size: 56,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            store.storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.h2(colors.onSurface),
                          ),
                        ),
                        if (store.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 17),
                        ],
                        if (store.topRated) ...[
                          const SizedBox(width: 4),
                          const TopSellerBadge(),
                        ],
                        const SizedBox(width: 6),
                        ReputationStar(
                          score: store.feedbackScore ?? 0,
                          size: 15,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    _Rates(store: store),
                  ],
                ),
              ),
              if (actions != null) ...[const SizedBox(width: 8), actions!],
            ],
          ),
          if (store.tagline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              store.tagline,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
          if (store.onVacation) ...[
            const SizedBox(height: 10),
            _VacationPill(store: store),
          ],
          const SizedBox(height: 14),
          _StatChips(store: store),
        ],
      ),
    );
  }
}

/// "100% positif · 80% selesai" — the two rates a shop is judged on, the
/// figures in the foreground. A store nobody has rated, or one with too few
/// orders for a completion rate, says so instead of showing a 0.
class _Rates extends StatelessWidget {
  const _Rates({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final strong = AppTypography.bodySmSemibold(context.appColors.onSurface);
    final muted = AppTypography.bodySm(context.mutedForeground);
    final positive = store.positivePct;
    final completion = store.completionPct;

    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          if (positive == null)
            const TextSpan(text: 'Belum dinilai')
          else ...[
            TextSpan(
              text: '${positive.toStringAsFixed(positive % 1 == 0 ? 0 : 1)}%',
              style: strong,
            ),
            const TextSpan(text: ' positif'),
          ],
          const TextSpan(text: ' · '),
          if (completion == null)
            const TextSpan(text: 'Penjual baru')
          else ...[
            TextSpan(text: '$completion%', style: strong),
            const TextSpan(text: ' selesai'),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Follow over chat, as two round buttons beside the name — follow filled
/// so it reads as the one being asked for.
class _IdentityActions extends StatelessWidget {
  const _IdentityActions({
    required this.following,
    required this.busy,
    required this.onToggleFollow,
    required this.onContact,
  });

  final bool following;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final filled = !following;
    final followFg = filled ? colors.surface : colors.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        _RoundButton(
          tooltip: following ? 'Berhenti mengikuti' : 'Ikuti',
          background: filled ? colors.onSurface : Theme.of(context).cardColor,
          bordered: !filled,
          onPressed: busy ? null : onToggleFollow,
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: followFg,
                  ),
                )
              : Icon(
                  following ? LucideIcons.userCheck : LucideIcons.userPlus,
                  size: 17,
                  color: followFg,
                ),
        ),
        _RoundButton(
          tooltip: 'Chat',
          background: Theme.of(context).cardColor,
          bordered: true,
          onPressed: onContact,
          child: Icon(
            LucideIcons.messageCircle,
            size: 17,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.background,
    required this.bordered,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final Color background;
  final bool bordered;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: CircleBorder(
          side: bordered
              ? BorderSide(color: context.borderColor)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 38, height: 38, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// The circular, bordered treatment of `CircularBackButton`, for the bar's
/// share and options buttons.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: Theme.of(context).cardColor.withValues(alpha: 0.9),
            shape: CircleBorder(side: BorderSide(color: context.borderColor)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 19, color: context.appColors.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VacationPill extends StatelessWidget {
  const _VacationPill({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.palmtree, size: 14, color: colors.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              store.vacationMessage?.isNotEmpty == true
                  ? store.vacationMessage!
                  : 'Toko sedang libur',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionSemibold(colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sold, followers and how fast it ships, as outlined chips — the facts a
/// buyer weighs after the two rates beside the name.
class _StatChips extends StatelessWidget {
  const _StatChips({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final shipTime = store.shipTimeLabel;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(value: formatCountId(store.itemsSoldCount), label: 'terjual'),
        _Chip(value: formatCountId(store.followersCount), label: 'pengikut'),
        if (shipTime != null) _Chip(icon: LucideIcons.truck, label: shipTime),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.value, this.icon});

  final String label;
  final String? value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: muted),
            const SizedBox(width: 5),
          ],
          if (value != null) ...[
            Text(
              value!,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTypography.caption(muted)),
        ],
      ),
    );
  }
}

/// Ports `storefront-tab-nav.tsx` — the underlined pair the web uses, not a
/// Material TabBar, so it sits inside the scroll view with the header.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.onSelect});

  final _StoreTab active;
  final ValueChanged<_StoreTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          for (final tab in _StoreTab.values)
            InkWell(
              onTap: () => onSelect(tab),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                margin: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == active
                          ? colors.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab.label,
                  style: tab == active
                      ? AppTypography.bodySmSemibold(colors.onSurface)
                      : AppTypography.bodySm(context.mutedForeground),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ports `storefront-about-tab.tsx` — the seller's description, over the
/// facts a buyer checks before trusting a shop.
class _About extends StatelessWidget {
  const _About({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final about = store.aboutMarkdown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tentang toko',
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          if (about == null || about.trim().isEmpty)
            Text(
              'Penjual ini belum menulis deskripsi toko.',
              style: AppTypography.bodySm(context.mutedForeground),
            )
          else
            SimpleMarkdown(data: about),

          const SizedBox(height: 20),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 14),
          Text('Info', style: AppTypography.bodySemibold(colors.onSurface)),
          const SizedBox(height: 8),
          _AboutRow(
            icon: LucideIcons.idCard,
            label: 'Status',
            value: store.isVerified ? 'Terverifikasi' : 'Belum terverifikasi',
          ),
          if (store.cityName.isNotEmpty)
            _AboutRow(
              icon: LucideIcons.mapPin,
              label: 'Lokasi',
              value: store.cityName,
            ),
          if (store.memberSince != null)
            _AboutRow(
              icon: LucideIcons.calendar,
              label: 'Bergabung',
              value: formatJoinedId(store.memberSince!),
            ),
          _AboutRow(
            icon: LucideIcons.tag,
            label: 'Terjual',
            value: '${store.itemsSoldCount} kartu',
          ),
          _AboutRow(
            icon: LucideIcons.users,
            label: 'Pengikut',
            value: '${store.followersCount}',
          ),
          if (store.onVacation)
            _AboutRow(
              icon: LucideIcons.palmtree,
              label: 'Libur',
              value: store.vacationUntil == null
                  ? 'Sedang libur'
                  : 'Sampai ${formatShortDateId(store.vacationUntil!)}',
            ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: context.mutedForeground),
          const SizedBox(width: 8),
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filter button, carrying how many filters are on — otherwise a
/// filtered grid and an empty one look the same.
class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Material(
        color: Theme.of(context).cardColor.withValues(alpha: 0.92),
        shape: CircleBorder(side: BorderSide(color: context.borderColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: onPressed == null
                      ? context.mutedForeground
                      : colors.onSurface,
                ),
                if (count > 0)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: AppTypography.badge(
                          colors.onPrimary,
                        ).copyWith(fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ports `storefront-feedback-tab.tsx` — the positive-rate headline, the
/// three-way breakdown, and the reviews themselves.
class _Feedback extends ConsumerWidget {
  const _Feedback({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final userId = store.userId;
    if (userId == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: EmptyState(
          icon: LucideIcons.star,
          title: 'Penilaian belum tersedia',
        ),
      );
    }

    final summaryAsync = ref.watch(storeFeedbackSummaryProvider(userId));
    final listAsync = ref.watch(storeFeedbackProvider(userId));
    final summary = summaryAsync.valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      // A store nobody has rated shows a dash, not 100%.
                      summary?.positivePercent == null
                          ? '–'
                          : '${summary!.positivePercent!.round()}%',
                      style: AppTypography.h1(colors.onSurface),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'positif',
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${summary?.total ?? 0} penilaian',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Tally(
                      label: 'Positif',
                      count: summary?.positive ?? 0,
                      color: context.appSemantic.success,
                    ),
                    _Tally(
                      label: 'Netral',
                      count: summary?.neutral ?? 0,
                      color: context.mutedForeground,
                    ),
                    _Tally(
                      label: 'Negatif',
                      count: summary?.negative ?? 0,
                      color: colors.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          listAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Belum ada penilaian untuk toko ini.',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                );
              }
              return Column(
                children: [for (final item in items) _FeedbackTile(item: item)],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Text(
              'Gagal memuat penilaian.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count', style: AppTypography.bodySemibold(color)),
          Text(label, style: AppTypography.caption(context.mutedForeground)),
        ],
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.item});

  final StoreFeedback item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tone = switch (item.kind) {
      FeedbackKind.positive => context.appSemantic.success,
      FeedbackKind.neutral => context.mutedForeground,
      FeedbackKind.negative => colors.error,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.kind == FeedbackKind.positive
                    ? LucideIcons.thumbsUp
                    : item.kind == FeedbackKind.negative
                    ? LucideIcons.thumbsDown
                    : LucideIcons.minus,
                size: 14,
                color: tone,
              ),
              const SizedBox(width: 6),
              Text(item.kind.label, style: AppTypography.captionSemibold(tone)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.raterUsername ?? 'Pengguna',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              Text(
                formatRelativeId(item.createdAt, now: DateTime.now()),
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
          if (item.comment != null && item.comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.comment!, style: AppTypography.bodySm(colors.onSurface)),
          ] else if (item.isAuto) ...[
            const SizedBox(height: 6),
            Text(
              'Penilaian otomatis setelah transaksi selesai.',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
          if (item.reply != null && item.reply!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balasan penjual',
                    style: AppTypography.captionSemibold(
                      context.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.reply!,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A storefront the RPCs returned nothing for. Either it doesn't exist, the
/// viewer blocked its owner, or its owner blocked the viewer — web shows the
/// blocker the unblock notice and everyone else "not found"
/// (`app/market/[slug]/page.tsx`).
class _MissingStore extends ConsumerWidget {
  const _MissingStore({required this.handle, required this.onUnblocked});

  final String handle;
  final VoidCallback onUnblocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(blockStatusProvider(handle)).valueOrNull;
    if (status != null && status.blockedByMe && status.userId != null) {
      return AppBarOverlayBody(
        child: Center(
          child: BlockedUserNotice(
            userId: status.userId!,
            username: status.username,
            onUnblocked: onUnblocked,
          ),
        ),
      );
    }
    return const EmptyState(
      icon: LucideIcons.store,
      title: 'Toko tidak ditemukan',
    );
  }
}

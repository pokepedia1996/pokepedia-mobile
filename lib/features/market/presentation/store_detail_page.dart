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
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../../../shared/widgets/condition_grade_picker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/simple_markdown.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../chat/repository/models/chat_models.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../repository/models/store_feedback.dart';
import '../usecase/market_notifier.dart';
import 'widgets/store_share_sheet.dart';

/// Ports `features/market/store/components/storefront/storefront-view.tsx` —
/// a seller's storefront: banner and identity, the stats strip, the actions,
/// and the Listing / Buylist / Tentang tabs over their listings.
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
    _StoreTab.shop => 'Listing',
    _StoreTab.buylist => 'Buylist',
    _StoreTab.about => 'Tentang',
    _StoreTab.feedback => 'Penilaian',
  };

  /// The two that list cards; the others take the whole width instead.
  bool get isListing => this == _StoreTab.shop || this == _StoreTab.buylist;
}

class _StoreDetailPageState extends ConsumerState<StoreDetailPage> {
  final _searchController = TextEditingController();

  _StoreTab _tab = _StoreTab.shop;
  String _query = '';
  CardCondition? _condition;
  _StoreSort _sort = _StoreSort.newest;
  bool _following = false;
  bool _followingInitialised = false;
  bool _followBusy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  List<ListingModel> _visible(List<ListingModel> listings) {
    final side = _tab == _StoreTab.buylist ? ListingSide.bid : ListingSide.ask;
    final needle = _query.toLowerCase();

    final visible = listings.where((listing) {
      if (listing.side != side) return false;
      if (_condition != null && listing.condition != _condition) return false;
      if (needle.isEmpty) return true;
      return listing.card.name.toLowerCase().contains(needle) ||
          listing.card.collectorNumber.toLowerCase().contains(needle) ||
          listing.card.expansionCode.toLowerCase().contains(needle);
    }).toList();

    visible.sort(switch (_sort) {
      _StoreSort.newest => (a, b) => b.createdAt.compareTo(a.createdAt),
      _StoreSort.priceAsc => (a, b) => a.price.compareTo(b.price),
      _StoreSort.priceDesc => (a, b) => b.price.compareTo(a.price),
    });
    return visible;
  }

  /// How many filters are on, for the badge on the toggle.
  int get _activeFilters =>
      (_condition == null ? 0 : 1) + (_sort == _StoreSort.newest ? 0 : 1);

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      // A Consumer-free StatefulBuilder: the sheet edits this page's state
      // directly, so both it and the grid behind it update as you tap.
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter',
                        style: AppTypography.h3(context.appColors.onSurface),
                      ),
                    ),
                    if (_activeFilters > 0)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _condition = null;
                            _sort = _StoreSort.newest;
                          });
                          setSheetState(() {});
                        },
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Urutkan',
                  style: AppTypography.captionSemibold(context.mutedForeground),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final sort in _StoreSort.values)
                      ChoiceChip(
                        label: Text(sort.label),
                        selected: _sort == sort,
                        onSelected: (_) {
                          setState(() => _sort = sort);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Kondisi',
                  style: AppTypography.captionSemibold(context.mutedForeground),
                ),
                const SizedBox(height: 6),
                ConditionGradePicker(
                  value: _condition,
                  onChanged: (value) {
                    setState(() => _condition = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Terapkan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeDetailProvider(widget.handle));
    final listingsAsync = ref.watch(storeListingsProvider(widget.handle));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(
        // Beside the back button rather than above the grid: it's the
        // control people reach for first on a storefront, and this keeps it
        // reachable while the listings scroll.
        title: _StoreSearchField(
          controller: _searchController,
          enabled: _tab.isListing,
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        actions: [
          _FilterToggle(
            count: _activeFilters,
            onPressed: _tab.isListing ? _openFilters : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return const EmptyState(
              icon: LucideIcons.store,
              title: 'Toko tidak ditemukan',
            );
          }
          // Seeded from the server once, then owned locally so the button
          // responds before the refetch lands.
          if (!_followingInitialised) {
            _following = store.isFollowing;
            _followingInitialised = true;
          }

          return AppBarOverlayBody(
            reserveToolbar: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(store: store)),
                SliverToBoxAdapter(
                  child: _Actions(
                    // Following yourself is refused by `follow_shop`, and
                    // `ensure_direct_room` has nobody to open a room with —
                    // so on your own storefront neither button is offered.
                    isOwnStore:
                        store.userId != null &&
                        store.userId == ref.watch(authProvider).valueOrNull?.id,
                    following: _following,
                    busy: _followBusy,
                    onToggleFollow: () => _toggleFollow(store),
                    onContact: () => _contact(store),
                    onShare: () => showStoreShareSheet(context, store: store),
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
                  listingsAsync.when(
                    data: (listings) {
                      final visible = _visible(listings);
                      if (visible.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: EmptyState(
                              icon: LucideIcons.store,
                              title: _query.isNotEmpty
                                  ? 'Tidak ada kartu yang cocok'
                                  : _tab == _StoreTab.buylist
                                  ? 'Toko ini belum mencari kartu'
                                  : 'Belum ada listing',
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        sliver: SliverGrid(
                          gridDelegate: listingGridDelegate(
                            context,
                            showSeller: false,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => ListingCard(
                              listing: visible[i],
                              showSeller: false,
                            ),
                            childCount: visible.length,
                          ),
                        ),
                      );
                    },
                    loading: () =>
                        const SliverToBoxAdapter(child: PikachuLoader()),
                    error: (_, __) => SliverToBoxAdapter(
                      child: EmptyState(
                        icon: LucideIcons.circleAlert,
                        title: 'Gagal memuat listing',
                        action: OutlinedButton(
                          onPressed: () => ref.invalidate(
                            storeListingsProvider(widget.handle),
                          ),
                          child: const Text('Coba lagi'),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
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

/// Banner, avatar, name and the stats strip — web's storefront header.
class _Header extends StatelessWidget {
  const _Header({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final banner = store.bannerUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The banner runs under the transparent app bar, like the artwork on
        // a card page; stores without one get a plain band so the avatar
        // below still has something to sit against.
        SizedBox(
          height: 132,
          width: double.infinity,
          child: banner == null || banner.isEmpty
              ? ColoredBox(color: colors.secondary)
              : Image.network(
                  banner,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: colors.secondary),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, -28),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    shape: BoxShape.circle,
                  ),
                  child: SellerAvatar(
                    name: store.storeName,
                    imageUrl: store.logoUrl,
                    size: 64,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -16),
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
                          Icon(
                            LucideIcons.badgeCheck,
                            size: 18,
                            color: colors.primary,
                          ),
                        ],
                      ],
                    ),
                    if (store.tagline.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        store.tagline,
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    ],
                    if (store.onVacation) ...[
                      const SizedBox(height: 8),
                      _VacationPill(store: store),
                    ],
                    const SizedBox(height: 10),
                    _Stats(store: store),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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

/// Ports `storefront-stats-strip.tsx`.
class _Stats extends StatelessWidget {
  const _Stats({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _Stat(
          icon: LucideIcons.shoppingBag,
          label: '${store.activeListingCount} listing',
        ),
        _Stat(icon: LucideIcons.tag, label: '${store.itemsSoldCount} terjual'),
        _Stat(
          icon: LucideIcons.users,
          label: '${store.followersCount} pengikut',
        ),
        if (store.cityName.isNotEmpty)
          _Stat(icon: LucideIcons.mapPin, label: store.cityName),
        if (store.memberSince != null)
          _Stat(
            icon: LucideIcons.calendar,
            label: formatJoinedId(store.memberSince!),
          ),
        if (store.topRated) _Stat(icon: LucideIcons.star, label: 'Top Rated'),
      ],
    );
  }
}

/// Ports `storefront-action-buttons.tsx`.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.isOwnStore,
    required this.following,
    required this.busy,
    required this.onToggleFollow,
    required this.onContact,
    required this.onShare,
  });

  /// The viewer is the seller. Follow and Chat are both about reaching
  /// someone else, so they aren't drawn — sharing your own shop is the one
  /// action that still means something.
  final bool isOwnStore;

  final bool following;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    if (isOwnStore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: SizedBox(
          width: double.infinity,
          // Full width and labelled, rather than the bare icon left behind
          // when the two buttons beside it go.
          child: OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(LucideIcons.share, size: 16),
            label: const Text('Bagikan toko'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(38),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: following
                ? OutlinedButton.icon(
                    onPressed: busy ? null : onToggleFollow,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.check, size: 15),
                    label: const Text('Diikuti'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: busy ? null : onToggleFollow,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.plus, size: 15),
                    label: const Text('Ikuti'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                    ),
                  ),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onContact,
              icon: const Icon(LucideIcons.messageCircle, size: 15),
              label: const Text('Chat'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(38),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onShare,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 38),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(LucideIcons.share, size: 16),
          ),
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
      margin: const EdgeInsets.only(top: 8),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.mutedForeground),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}

/// The orders web offers on a storefront's listings.
enum _StoreSort { newest, priceAsc, priceDesc }

extension _StoreSortX on _StoreSort {
  String get label => switch (this) {
    _StoreSort.newest => 'Terbaru',
    _StoreSort.priceAsc => 'Termurah',
    _StoreSort.priceDesc => 'Termahal',
  };
}

/// The search field as it sits in the app bar: short, rounded, and on its
/// own surface so it reads against whatever the banner is doing behind it.
class _StoreSearchField extends StatelessWidget {
  const _StoreSearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSearchField(
      hintText: 'Cari di toko ini',
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
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

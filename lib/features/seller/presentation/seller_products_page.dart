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
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import 'widgets/add_listing_sheet.dart';
import 'widgets/draft_bulk_menu.dart';
import 'widgets/draft_selection_bar.dart';
import 'widgets/listing_card_tile.dart';
import 'widgets/seller_header.dart';
import 'widgets/draft_card.dart';
import '../repository/models/seller_listing.dart';
import '../repository/seller_listings_repository.dart';
import '../usecase/offers_notifier.dart';
import '../usecase/seller_listings_notifier.dart';

/// Ports `app/seller/products` — the seller's listings, bucketed, with the
/// per-listing actions their product table offers.
class SellerProductsPage extends ConsumerStatefulWidget {
  const SellerProductsPage({
    super.key,
    this.initialBucket,
    this.initialOffersFilter = false,
  });

  /// Which tab to open on, from `?tab=`.
  ///
  /// Applied once on the first frame rather than watched: after that the
  /// chips own the selection, and a link that kept forcing its tab back
  /// would make them unusable.
  final SellerListingBucket? initialBucket;

  /// Whether to arrive with "Dengan penawaran" already on.
  final bool initialOffersFilter;

  @override
  ConsumerState<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends ConsumerState<SellerProductsPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    final bucket = widget.initialBucket;
    if (bucket == null && !widget.initialOffersFilter) return;
    // After the frame: these are providers, and the tree is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (bucket != null) {
        ref.read(sellerBucketProvider.notifier).state = bucket;
      }
      if (widget.initialOffersFilter) {
        ref.read(sellerOfferFilterProvider.notifier).state = true;
      }
    });
  }

  final _draftSearch = TextEditingController();
  final _workspaceSearch = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _draftSearch.dispose();
    _workspaceSearch.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _run(Future<String?> Function() action, String success) async {
    final error = await action();
    _toast(error ?? success);
  }

  Future<void> _confirmArchive(SellerListing listing) {
    return showConfirmDialog(
      context,
      title: 'Arsipkan listing?',
      description:
          '${listing.card.name} tidak akan muncul di market sampai kamu '
          'mengembalikannya dari arsip.',
      confirmLabel: 'Arsipkan',
      loadingLabel: 'Mengarsipkan...',
      onConfirm: () => _run(
        () => ref.read(sellerListingActionsProvider).archive(listing.slug),
        'Listing diarsipkan',
      ),
    );
  }

  /// `delete_listing` is a soft delete, but nothing in the app brings a row
  /// back from it — so it asks first, and says so plainly.
  Future<void> _confirmDelete(SellerListing listing) {
    return showConfirmDialog(
      context,
      title: 'Hapus listing ini?',
      description:
          '${listing.card.name} akan dihapus permanen dan tidak bisa '
          'dikembalikan dari aplikasi. Untuk menyimpannya, arsipkan saja.',
      confirmLabel: 'Hapus permanen',
      onConfirm: () => _run(
        () => ref
            .read(sellerListingActionsProvider)
            .deletePermanent(listing.slug),
        'Listing dihapus',
      ),
    );
  }

  Future<void> _restock(SellerListing listing) async {
    final controller = TextEditingController(text: '1');
    final quantity = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tambah stok',
              style: AppTypography.h3(context.appColors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              listing.card.name,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim()) ?? 0;
                if (value > 0) Navigator.of(sheetContext).pop(value);
              },
              child: const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (quantity == null) return;

    await _run(
      () => ref
          .read(sellerListingActionsProvider)
          .restock(listing.slug, quantity),
      'Stok ditambahkan',
    );
  }

  /// Re-reads the drafts after a card or the bulk menu writes one. Posting a
  /// draft makes a listing, so the list and the tab counts are re-read too.
  Future<void> _refreshDrafts() async {
    ref.invalidate(sellerDraftsProvider);
    refreshSellerListingsFromWidget(ref);
    await ref.read(sellerDraftsProvider.future);
  }

  /// Turns the seller's collection into drafts in one go, through the
  /// database function built for it. Nothing is posted — the seller still
  /// prices each draft and presses Pasang.
  Future<void> _importFromPortfolio() async {
    final result = await ref
        .read(sellerListingsRepositoryProvider)
        .importDraftsFromCollection();
    if (!mounted) return;

    if (result.error == null) {
      ref.read(sellerBucketProvider.notifier).state = SellerListingBucket.draft;
      await _refreshDrafts();
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.error ??
                (result.inserted == 0
                    ? 'Tidak ada kartu baru untuk diimpor'
                    : '${result.inserted} draft dibuat dari koleksimu'),
          ),
          persist: false,
        ),
      );
  }

  /// Web's "Tambah listing": pick a card, then post the ask through the
  /// same form the catalog page uses.
  Future<void> _addListing() async {
    final added = await showAddListingSheet(context);
    if (added != true || !mounted) return;
    // The sheet makes drafts, not listings, so the Draft tab is where the
    // cards the seller just picked actually are.
    ref.read(sellerBucketProvider.notifier).state = SellerListingBucket.draft;
    await _refreshDrafts();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = ref.watch(authProvider).valueOrNull;
    final bucket = ref.watch(sellerBucketProvider);
    final feed = ref.watch(sellerListingsFeedProvider);
    final tabCounts =
        ref.watch(sellerListingTabCountsProvider).valueOrNull ?? const {};

    if (user == null) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const TransparentAppBar(),
        body: AppBarOverlayBody(
          child: EmptyState(
            icon: LucideIcons.package,
            title: 'Masuk untuk mengelola listing',
            action: ElevatedButton(
              onPressed: () => context.push(Routes.login),
              child: const Text('Masuk'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // One scroll for the whole page, not a fixed head over a scrolling
      // list. The chrome above the cards is five rows deep — header, search,
      // tabs, heading, two buttons — and pinning it left a phone showing
      // barely two listings through a slot. Everything scrolls away
      // together; the selection bar is the only thing that stays, because it
      // is about what is already chosen rather than what is on screen.
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (bucket.isListingBucket &&
                    notification.metrics.extentAfter < 600) {
                  ref.read(sellerListingsFeedProvider.notifier).loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SellerHeader(controller: _workspaceSearch),
                        const SizedBox(height: 12),
                        // Web's order: the tabs come first, then the heading and the
                        // line that explains the tab you're on, then the one primary
                        // action.
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              for (final b in SellerListingBucket.values) ...[
                                _BucketChip(
                                  bucket: b,
                                  count: tabCounts[b],
                                  selected: b == bucket,
                                  onTap: () =>
                                      ref
                                              .read(
                                                sellerBucketProvider.notifier,
                                              )
                                              .state =
                                          b,
                                ),
                                const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kelola Listing',
                                style: AppTypography.h3(colors.onSurface),
                              ),
                              if (bucket !=
                                  SellerListingBucket.preferences) ...[
                                const SizedBox(height: 12),
                                // Full width and stacked rather than a lone button on
                                // the left: these are the two ways a listing starts, and
                                // the page is otherwise a list of listings that already
                                // exist. Importing comes first because it is the one
                                // that turns a collection into a shop in one go.
                                OutlinedButton.icon(
                                  onPressed: _importFromPortfolio,
                                  icon: const Icon(
                                    LucideIcons.folderOpen,
                                    size: 15,
                                  ),
                                  label: const Text('Impor dari Portofolio'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.onSurface,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).cardColor,
                                    side: BorderSide(
                                      color: context.borderColor,
                                    ),
                                    minimumSize: const Size.fromHeight(40),
                                    textStyle: AppTypography.bodySmSemibold(
                                      colors.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _addListing,
                                  icon: const Icon(LucideIcons.plus, size: 15),
                                  label: const Text('Tambahkan Listing'),
                                  // Black, not the brand red the theme gives an
                                  // ElevatedButton. Red is the app's "careful" colour,
                                  // and it sits directly under a red-dotted bell and a
                                  // row of white chips — the one filled control on this
                                  // screen should read as the primary action, not as an
                                  // alert.
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colors.onSurface,
                                    foregroundColor: Theme.of(
                                      context,
                                    ).cardColor,
                                    minimumSize: const Size.fromHeight(40),
                                    textStyle: AppTypography.bodySmSemibold(
                                      Theme.of(context).cardColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (bucket == SellerListingBucket.draft) ...[
                          const SizedBox(height: 12),
                          _DraftFilterChips(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: AppSearchField(
                                    hintText: 'Cari nama kartu...',
                                    controller: _draftSearch,
                                    onChanged: (v) =>
                                        ref
                                                .read(
                                                  draftQueryProvider.notifier,
                                                )
                                                .state =
                                            v,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                DraftBulkMenu(onChanged: _refreshDrafts),
                              ],
                            ),
                          ),
                        ],
                        if (bucket.isListingBucket) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: AppSearchField(
                                    hintText:
                                        'Cari nama, ekspansi, nomor, kondisi...',
                                    controller: _search,
                                    onChanged: (v) =>
                                        ref
                                                .read(
                                                  sellerListingQueryProvider
                                                      .notifier,
                                                )
                                                .state =
                                            v,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _SortMenuButton(
                                  sort: ref.watch(sellerSortProvider),
                                  onChanged: (col) => ref
                                      .read(sellerSortProvider.notifier)
                                      .update((s) => s.toggled(col)),
                                ),
                              ],
                            ),
                          ),
                          // How much is being shown, and the one filter worth a chip.
                          // The count used to live nowhere: a seller filtering a hundred
                          // listings down to four had no way to tell that was the whole
                          // answer rather than the top of a longer one.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            // Both ends give way rather than a `Spacer` holding
                            // them apart: "1-24 dari 24 listing" beside
                            // "Dengan penawaran 12" is wider than a narrow
                            // phone, and the row had nowhere to overflow to.
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _rangeLabel(feed),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySm(
                                      context.mutedForeground,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _OfferFilterChip(
                                  active: ref.watch(sellerOfferFilterProvider),
                                  count:
                                      feed.offersCount ??
                                      ref.watch(offerCountsProvider).length,
                                  onTap: () => ref
                                      .read(sellerOfferFilterProvider.notifier)
                                      .update((on) => !on),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  ..._bodySlivers(bucket, feed),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: AppBottomNav.reservedSpace(context) + 16,
                    ),
                  ),
                ],
              ),
            ),
            if (bucket == SellerListingBucket.draft)
              Positioned(
                left: 0,
                right: 0,
                // Sat on the full nav reserve, which includes the gap above
                // the pill — so the bar floated a pill-gap clear of it and
                // read as a third layer. It belongs on top of the nav.
                bottom: (AppBottomNav.reservedSpace(context) - 40),
                child: DraftSelectionBar(onDone: _refreshDrafts),
              ),
          ],
        ),
      ),
    );
  }

  /// The part of the page that changes with the tab, as slivers so it shares
  /// the page's one scroll.
  List<Widget> _bodySlivers(
    SellerListingBucket bucket,
    SellerListingsFeedState feed,
  ) {
    return switch (bucket) {
      SellerListingBucket.preferences => const [
        SliverToBoxAdapter(child: _PreferencesPanel()),
      ],
      SellerListingBucket.draft => _draftSlivers(),
      _ => _listingSlivers(bucket, feed),
    };
  }

  /// "1-30 dari 120 listing" — what is loaded out of what matched.
  String _rangeLabel(SellerListingsFeedState feed) {
    if (feed.loading) return 'Memuat...';
    if (feed.rows.isEmpty) return 'Tidak ada listing';
    return '1-${feed.rows.length} dari ${feed.totalCount} listing';
  }

  /// A message where the cards would be, sized so it sits in the page's
  /// scroll rather than fighting it for height.
  Widget _messageSliver(Widget child) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Center(child: child),
    ),
  );

  List<Widget> _listingSlivers(
    SellerListingBucket bucket,
    SellerListingsFeedState feed,
  ) {
    if (feed.loading) return [_messageSliver(const PikachuLoader())];
    if (feed.error) {
      return [
        _messageSliver(
          Text(
            'Gagal memuat listing',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      ];
    }
    final listings = feed.rows;
    if (listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _EmptyCard(
            title: _emptyTitle(bucket),
            description: _emptyDescription(bucket),
          ),
        ),
      ];
    }
    final offers = ref.watch(offerCountsProvider);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverList.builder(
          itemCount: listings.length,
          itemBuilder: (context, i) {
            final listing = listings[i];
            return ListingCardTile(
              key: ValueKey(listing.slug),
              listing: listing,
              offerCount: offers[listing.slug]?.needsResponse ?? 0,
              onToggleAutoRelist: (v) => _run(
                () => ref
                    .read(sellerListingActionsProvider)
                    .setAutoRelist(listing.slug, v),
                v ? 'Auto-relist aktif' : 'Auto-relist mati',
              ),
              onToggleOffers: (v) => _run(
                () => ref
                    .read(sellerListingActionsProvider)
                    .setAcceptsOffers(listing.slug, v),
                v ? 'Tawaran diaktifkan' : 'Tawaran dimatikan',
              ),
              onMenu: () => _showListingMenu(listing),
            );
          },
        ),
      ),
      if (feed.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: PikachuLoader()),
          ),
        ),
    ];
  }

  List<Widget> _draftSlivers() {
    final async = ref.watch(sellerDraftsProvider);

    return async.when(
      loading: () => [_messageSliver(const PikachuLoader())],
      error: (_, __) => [
        _messageSliver(
          Text(
            'Gagal memuat draft',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      ],
      data: (all) {
        if (all.isEmpty) {
          return const [
            SliverToBoxAdapter(
              child: _EmptyCard(
                title: 'Belum ada draft',
                description:
                    'Draft yang kamu simpan tapi belum dipasang akan muncul '
                    'di sini.',
              ),
            ),
          ];
        }

        // The chip and the search box have already had their say.
        final drafts = ref.watch(visibleDraftsProvider);
        if (drafts.isEmpty) {
          return const [
            SliverToBoxAdapter(
              child: _EmptyCard(
                title: 'Tidak ada draft yang cocok',
                description: 'Coba ganti filter atau kata kuncinya.',
              ),
            ),
          ];
        }

        final selection = ref.watch(draftSelectionProvider);

        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.builder(
              itemCount: drafts.length,
              itemBuilder: (context, i) {
                final draft = drafts[i];
                return DraftCard(
                  // Keyed by draft: the cards hold what is being typed into
                  // them, and without this a filter change would hand one
                  // card's half-finished price to a different draft.
                  key: ValueKey(draft.id),
                  draft: draft,
                  selected: selection.contains(draft.id),
                  onToggleSelect: () {
                    final next = {...selection};
                    if (!next.remove(draft.id)) next.add(draft.id);
                    ref.read(draftSelectionProvider.notifier).state = next;
                  },
                  onDelete: () => _deleteDraft(draft),
                  onChanged: _refreshDrafts,
                );
              },
            ),
          ),
        ];
      },
    );
  }

  Future<void> _deleteDraft(SellerDraft draft) async {
    await showConfirmDialog(
      context,
      title: 'Hapus draft?',
      description: '${draft.card.name} akan dihapus dari daftar draft.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        final error = await ref
            .read(sellerListingsRepositoryProvider)
            .deleteDraft(draft.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(error ?? 'Draft dihapus'), persist: false),
          );
        if (error == null) await _refreshDrafts();
      },
    );
  }

  /// The `⋮` on a listing card. The same actions the table's row menu had —
  /// they are the listing's, not the table's.
  Future<void> _showListingMenu(SellerListing listing) async {
    final offers =
        ref.read(offerCountsProvider)[listing.slug]?.needsResponse ?? 0;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.handCoins, size: 20),
              title: const Text('Lihat penawaran'),
              trailing: offers == 0 ? null : Text('$offers'),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push(Routes.sellerListingOffers(listing.slug));
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.packagePlus, size: 20),
              title: const Text('Ubah stok'),
              onTap: () {
                Navigator.of(sheet).pop();
                _restock(listing);
              },
            ),
            if (listing.isArchived)
              ListTile(
                leading: const Icon(LucideIcons.archiveRestore, size: 20),
                title: const Text('Kembalikan dari arsip'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _run(
                    () => ref
                        .read(sellerListingActionsProvider)
                        .unarchive(listing.slug),
                    'Listing dikembalikan',
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(LucideIcons.archive, size: 20),
                title: const Text('Arsipkan'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _confirmArchive(listing);
                },
              ),
            ListTile(
              leading: Icon(
                LucideIcons.trash2,
                size: 20,
                color: context.appColors.error,
              ),
              title: Text(
                'Hapus listing',
                style: TextStyle(color: context.appColors.error),
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _confirmDelete(listing);
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _emptyTitle(SellerListingBucket bucket) => switch (bucket) {
    SellerListingBucket.active => 'Belum ada listing aktif',
    SellerListingBucket.inactive => 'Tidak ada listing inaktif',
    SellerListingBucket.archived => 'Arsip kosong',
    SellerListingBucket.draft => 'Belum ada draft',
    SellerListingBucket.preferences => 'Preferensi',
  };

  static String? _emptyDescription(SellerListingBucket bucket) =>
      switch (bucket) {
        SellerListingBucket.active =>
          'Buat draft baru di tab Draft untuk mulai memasang listing.',
        SellerListingBucket.inactive =>
          'Listing yang terjual atau kedaluwarsa akan muncul di sini.',
        SellerListingBucket.archived =>
          'Listing yang kamu arsipkan akan muncul di sini.',
        _ => null,
      };
}

/// Web's empty state is a bordered card, not bare centred text.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final description = this.description;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.package, size: 32, color: context.mutedForeground),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Semua / Perlu dilengkapi / Siap dipasang, with how many are in each.
///
/// A draft is only ever missing a price, so this splits the pile into the
/// ones that can be posted now and the ones that still need a decision —
/// which is the only question worth asking of a list of drafts.
class _DraftFilterChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(draftFilterProvider);
    final counts = ref.watch(draftCountsProvider);

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final filter in DraftFilter.values) ...[
            _DraftChip(
              label: '${filter.label} · ${counts[filter] ?? 0}',
              selected: filter == selected,
              onTap: () =>
                  ref.read(draftFilterProvider.notifier).state = filter,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _DraftChip extends StatelessWidget {
  const _DraftChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final success = context.appSemantic.success;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? success : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? success : context.borderColor),
        ),
        child: Text(
          label,
          style: AppTypography.captionSemibold(
            selected ? Colors.white : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The `⋮` beside the listing search: the sort that used to live in the
/// table's column headers.
///
/// Sorting had nowhere to go once the rows became cards — there are no
/// headers to tap. It is a menu rather than a row of chips because it is a
/// choice of one from several, and the seller makes it rarely.
class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({required this.sort, required this.onChanged});

  final ListingSort sort;
  final ValueChanged<ListingSortCol> onChanged;

  static const _labels = {
    ListingSortCol.name: 'Nama kartu',
    ListingSortCol.expansion: 'Ekspansi',
    ListingSortCol.number: 'Nomor',
    ListingSortCol.condition: 'Kondisi',
    ListingSortCol.price: 'Harga',
    ListingSortCol.quantity: 'Jumlah',
    ListingSortCol.views: 'Dilihat',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ListingSortCol>(
      tooltip: 'Urutkan listing',
      initialValue: sort.col,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final entry in _labels.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                Expanded(child: Text(entry.value)),
                if (entry.key == sort.col)
                  Icon(
                    sort.ascending
                        ? LucideIcons.arrowUp
                        : LucideIcons.arrowDown,
                    size: 15,
                    color: context.mutedForeground,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(
          LucideIcons.ellipsisVertical,
          size: 20,
          color: context.appColors.onSurface,
        ),
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.bucket,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final SellerListingBucket bucket;

  /// From `get_seller_listing_tab_counts`; null while loading and for
  /// Preferensi, which has nothing to count.
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  static IconData _icon(SellerListingBucket bucket) => switch (bucket) {
    SellerListingBucket.active => LucideIcons.tag,
    SellerListingBucket.inactive => LucideIcons.archive,
    SellerListingBucket.archived => LucideIcons.packageX,
    SellerListingBucket.draft => LucideIcons.fileText,
    SellerListingBucket.preferences => LucideIcons.slidersHorizontal,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = Theme.of(context).cardColor;
    // Inverted rather than tinted. These are the page's top-level switch and
    // they sit directly under a search box of the same shape — a tint left
    // the selected one reading as one more field in the row rather than as
    // the tab you are on.
    final foreground = selected ? card : colors.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : card,
          border: Border.all(
            color: selected ? colors.onSurface : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(bucket), size: 13, color: foreground),
            const SizedBox(width: 6),
            Text(bucket.label, style: AppTypography.bodySmSemibold(foreground)),
            if (count case final n?) ...[
              const SizedBox(width: 5),
              Text('$n', style: AppTypography.bodySm(foreground)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Draft tab. `listing_drafts` is own-row CRUD under RLS, so this reads
/// and deletes straight from the table.
/// The Preferensi tab — defaults stamped onto new listings. Saved on toggle
/// rather than behind a Simpan button, matching the rest of the app's
/// switches.
class _PreferencesPanel extends ConsumerStatefulWidget {
  const _PreferencesPanel();

  @override
  ConsumerState<_PreferencesPanel> createState() => _PreferencesPanelState();
}

class _PreferencesPanelState extends ConsumerState<_PreferencesPanel> {
  bool _saving = false;

  Future<void> _save(ListingDefaults next) async {
    setState(() => _saving = true);
    final error = await ref
        .read(sellerListingsRepositoryProvider)
        .saveListingDefaults(next);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Preferensi disimpan'), persist: false),
      );
    if (error == null) ref.invalidate(listingDefaultsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(listingDefaultsProvider);

    return async.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => Center(
        child: Text(
          'Gagal memuat preferensi',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ),
      data: (defaults) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: defaults.autoRelist,
                  onChanged: _saving
                      ? null
                      : (v) => _save(defaults.copyWith(autoRelist: v)),
                  title: Text(
                    'Otomatis Perpanjang',
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                  subtitle: Text(
                    'Pasang ulang otomatis saat listing kedaluwarsa.',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ),
                Divider(height: 1, color: context.borderColor),
                SwitchListTile.adaptive(
                  value: defaults.acceptsOffers,
                  onChanged: _saving
                      ? null
                      : (v) => _save(defaults.copyWith(acceptsOffers: v)),
                  title: Text(
                    'Terima tawaran',
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                  subtitle: Text(
                    'Pembeli bisa mengajukan harga di listing barumu.',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Berlaku untuk listing yang kamu buat setelah ini. Listing yang '
            'sudah ada bisa diubah satu per satu di tab Aktif.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Ports the "Dengan penawaran" pill from `active-table.tsx`.
///
/// The count is listings holding a live offer, not offers — it is the number
/// of rows the filter would leave, which is what the seller is deciding
/// about when they tap it.
class _OfferFilterChip extends StatelessWidget {
  const _OfferFilterChip({
    required this.active,
    required this.count,
    required this.onTap,
  });

  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = active ? colors.onPrimary : colors.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? colors.primary : context.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.handshake, size: 14, color: foreground),
            const SizedBox(width: 6),
            // Shrinks before it clips: the chip shares its row with a count
            // that grows as the list does.
            Flexible(
              child: Text(
                'Dengan penawaran',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionSemibold(foreground),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: active
                    ? colors.onPrimary.withValues(alpha: 0.22)
                    : colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              alignment: Alignment.center,
              child: Text('$count', style: AppTypography.badge(foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

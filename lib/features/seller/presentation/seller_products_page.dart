import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import 'widgets/add_listing_sheet.dart';
import 'widgets/listing_table.dart';
import '../repository/models/seller_listing.dart';
import '../repository/seller_listings_repository.dart';
import '../usecase/offers_notifier.dart';
import '../usecase/seller_listings_notifier.dart';

/// Ports `app/seller/products` — the seller's listings, bucketed, with the
/// per-listing actions their product table offers.
class SellerProductsPage extends ConsumerStatefulWidget {
  const SellerProductsPage({super.key});

  @override
  ConsumerState<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends ConsumerState<SellerProductsPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
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

  /// Web's "Tambah listing": pick a card, then post the ask through the
  /// same form the catalog page uses.
  Future<void> _addListing() async {
    final posted = await showAddListingSheet(context);
    if (posted == true) ref.invalidate(sellerListingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = ref.watch(authProvider).valueOrNull;
    final bucket = ref.watch(sellerBucketProvider);
    final async = ref.watch(sellerListingsProvider);

    if (user == null) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const TransparentAppBar(),
        body: AppBarOverlayBody(
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
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
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Web's order: the tabs come first, then the heading and the
            // line that explains the tab you're on, then the one primary
            // action.
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final b in SellerListingBucket.values) ...[
                    _BucketChip(
                      bucket: b,
                      selected: b == bucket,
                      onTap: () =>
                          ref.read(sellerBucketProvider.notifier).state = b,
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
                    style: AppTypography.h1(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bucket.description,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  if (bucket != SellerListingBucket.preferences) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: _addListing,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Tambahkan Listing'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (bucket.isListingBucket)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (v) =>
                      ref.read(sellerListingQueryProvider.notifier).state = v,
                  style: AppTypography.bodySm(colors.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    hintText: 'Cari nama, ekspansi, nomor, kondisi...',
                    hintStyle: AppTypography.bodySm(context.mutedForeground),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    // Without this the icon claims a 48dp box and sets the
                    // field's height on its own.
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 0,
                    ),
                  ),
                ),
              ),
            if (bucket.isListingBucket)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _OfferFilterChip(
                    active: ref.watch(sellerOfferFilterProvider),
                    count: ref.watch(offerCountsProvider).length,
                    onTap: () => ref
                        .read(sellerOfferFilterProvider.notifier)
                        .update((on) => !on),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (bucket) {
                SellerListingBucket.preferences => const _PreferencesPanel(),
                SellerListingBucket.draft => _DraftList(onChanged: _refresh),
                _ => _listingBody(bucket, async),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _refresh() {
    ref.invalidate(sellerListingsProvider);
    ref.invalidate(sellerDraftsProvider);
  }

  Widget _listingBody(
    SellerListingBucket bucket,
    AsyncValue<List<SellerListing>> async,
  ) {
    return async.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => Center(
        child: Text(
          'Gagal memuat listing',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ),
      data: (listings) {
        if (listings.isEmpty) {
          return _EmptyCard(
            title: _emptyTitle(bucket),
            description: _emptyDescription(bucket),
          );
        }
        return ListingTable(
          listings: listings,
          sort: ref.watch(sellerSortProvider),
          onSort: (col) => ref
              .read(sellerSortProvider.notifier)
              .update((s) => s.toggled(col)),
          onArchive: _confirmArchive,
          onUnarchive: (l) => _run(
            () => ref.read(sellerListingActionsProvider).unarchive(l.slug),
            'Listing dikembalikan',
          ),
          onRestock: _restock,
          onDelete: _confirmDelete,
          onToggleOffers: (l, v) => _run(
            () => ref
                .read(sellerListingActionsProvider)
                .setAcceptsOffers(l.slug, v),
            v ? 'Tawaran diaktifkan' : 'Tawaran dimatikan',
          ),
          offerCounts: ref.watch(offerCountsProvider),
          onViewOffers: (l) => context.push(Routes.sellerListingOffers(l.slug)),
          onToggleAutoRelist: (l, v) => _run(
            () =>
                ref.read(sellerListingActionsProvider).setAutoRelist(l.slug, v),
            v ? 'Auto-relist aktif' : 'Auto-relist mati',
          ),
          onRefresh: () async {
            ref.invalidate(sellerListingsProvider);
            await ref.read(sellerListingsProvider.future);
          },
        );
      },
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
            Icon(
              Icons.inventory_2_outlined,
              size: 32,
              color: context.mutedForeground,
            ),
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

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.bucket,
    required this.selected,
    required this.onTap,
  });

  final SellerListingBucket bucket;
  final bool selected;
  final VoidCallback onTap;

  static IconData _icon(SellerListingBucket bucket) => switch (bucket) {
    SellerListingBucket.active => Icons.check_circle_outline,
    SellerListingBucket.inactive => Icons.pause_circle_outline,
    SellerListingBucket.archived => Icons.archive_outlined,
    SellerListingBucket.draft => Icons.edit_note,
    SellerListingBucket.preferences => Icons.tune,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.primary : context.mutedForeground;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // Web tints the selected tab rather than inverting it, so the
          // label stays the same colour family across the row.
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(bucket), size: 13, color: foreground),
            const SizedBox(width: 4),
            Text(
              bucket.label,
              // `badge` is already bold; the unselected tab just carries
              // the muted colour, the way web separates them.
              style: AppTypography.badge(foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Draft tab. `listing_drafts` is own-row CRUD under RLS, so this reads
/// and deletes straight from the table.
class _DraftList extends ConsumerWidget {
  const _DraftList({required this.onChanged});

  final VoidCallback onChanged;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SellerDraft draft,
  ) async {
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(error ?? 'Draft dihapus'), persist: false),
          );
        if (error == null) onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sellerDraftsProvider);

    return async.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => Center(
        child: Text(
          'Gagal memuat draft',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ),
      data: (drafts) {
        if (drafts.isEmpty) {
          return const _EmptyCard(
            title: 'Belum ada draft',
            description:
                'Draft yang kamu simpan tapi belum dipasang akan muncul di '
                'sini.',
          );
        }
        return DraftTable(
          drafts: drafts,
          onDelete: (draft) => _delete(context, ref, draft),
          onRefresh: () async {
            ref.invalidate(sellerDraftsProvider);
            await ref.read(sellerDraftsProvider.future);
          },
        );
      },
    );
  }
}

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
            Icon(Icons.handshake_outlined, size: 14, color: foreground),
            const SizedBox(width: 6),
            Text(
              'Dengan penawaran',
              style: AppTypography.captionSemibold(foreground),
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

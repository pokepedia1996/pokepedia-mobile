import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/seller_listing.dart';
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
      () => ref.read(sellerListingActionsProvider).restock(listing.slug, quantity),
      'Stok ditambahkan',
    );
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Produk', style: AppTypography.h2(colors.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    ref.read(sellerListingQueryProvider.notifier).state = v,
                decoration: const InputDecoration(
                  hintText: 'Cari nama, nomor, atau ekspansi...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            SizedBox(
              height: 38,
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
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: async.when(
                loading: () => const PikachuLoader(),
                error: (_, __) => Center(
                  child: Text(
                    'Gagal memuat listing',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ),
                data: (listings) {
                  if (listings.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: _emptyTitle(bucket),
                      description: bucket == SellerListingBucket.active
                          ? 'Listing baru dibuat lewat pokepedia.id untuk '
                                'sekarang.'
                          : null,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(sellerListingsProvider);
                      await ref.read(sellerListingsProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: listings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ListingCard(
                        listing: listings[i],
                        onArchive: () => _confirmArchive(listings[i]),
                        onUnarchive: () => _run(
                          () => ref
                              .read(sellerListingActionsProvider)
                              .unarchive(listings[i].slug),
                          'Listing dikembalikan',
                        ),
                        onRestock: () => _restock(listings[i]),
                        onToggleOffers: (v) => _run(
                          () => ref
                              .read(sellerListingActionsProvider)
                              .setAcceptsOffers(listings[i].slug, v),
                          v ? 'Tawaran diaktifkan' : 'Tawaran dimatikan',
                        ),
                        onToggleAutoRelist: (v) => _run(
                          () => ref
                              .read(sellerListingActionsProvider)
                              .setAutoRelist(listings[i].slug, v),
                          v ? 'Auto-relist aktif' : 'Auto-relist mati',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _emptyTitle(SellerListingBucket bucket) => switch (bucket) {
    SellerListingBucket.active => 'Belum ada listing aktif',
    SellerListingBucket.sold => 'Belum ada yang terjual',
    SellerListingBucket.expired => 'Tidak ada listing kedaluwarsa',
    SellerListingBucket.archived => 'Arsip kosong',
  };
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.secondary,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          bucket.label,
          style: selected
              ? AppTypography.captionSemibold(colors.onPrimary)
              : AppTypography.caption(context.mutedForeground),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.onArchive,
    required this.onUnarchive,
    required this.onRestock,
    required this.onToggleOffers,
    required this.onToggleAutoRelist,
  });

  final SellerListing listing;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onRestock;
  final ValueChanged<bool> onToggleOffers;
  final ValueChanged<bool> onToggleAutoRelist;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 46,
                  child: CardArt(
                    imageUrl: listing.card.imageUrl,
                    borderRadius: AppRadius.sm,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      Text(
                        '${listing.card.collectorNumber} · '
                        '${listing.card.expansionCode.toUpperCase()}',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ConditionBadge(
                            condition: listing.condition,
                            dense: true,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            listing.isOutOfStock
                                ? 'Stok habis'
                                : 'Stok ${listing.available}',
                            style: AppTypography.caption(
                              listing.isOutOfStock
                                  ? colors.error
                                  : context.mutedForeground,
                            ),
                          ),
                          if (listing.qtyLocked > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· ${listing.qtyLocked} dikunci',
                              style: AppTypography.caption(
                                context.appSemantic.gold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRupiah(listing.price),
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      '${listing.viewCount} dilihat',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          // Toggles only make sense on a live listing; an archived or sold
          // one gets the action that applies to it instead.
          if (listing.isArchived)
            _ActionRow(
              children: [
                _Action(
                  icon: Icons.unarchive_outlined,
                  label: 'Kembalikan',
                  onTap: onUnarchive,
                ),
              ],
            )
          else ...[
            _ToggleRow(
              label: 'Terima tawaran',
              value: listing.acceptsOffers,
              onChanged: onToggleOffers,
            ),
            Divider(height: 1, color: context.borderColor),
            _ToggleRow(
              label: 'Auto-relist saat kedaluwarsa',
              value: listing.autoRelist,
              onChanged: onToggleAutoRelist,
            ),
            Divider(height: 1, color: context.borderColor),
            _ActionRow(
              children: [
                if (listing.isOutOfStock)
                  _Action(
                    icon: Icons.add_box_outlined,
                    label: 'Tambah stok',
                    onTap: onRestock,
                  ),
                _Action(
                  icon: Icons.archive_outlined,
                  label: 'Arsipkan',
                  onTap: onArchive,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm(context.appColors.onSurface),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(children: children),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: context.mutedForeground),
    );
  }
}

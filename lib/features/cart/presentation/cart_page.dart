import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/models/listing_model.dart';
import '../repository/models/cart_item.dart';
import '../usecase/cart_notifier.dart';
import '../usecase/cart_selection.dart';

/// Ports `features/cart/components/cart-client.tsx` — the cart grouped per
/// seller, with per-line selection driving what actually gets checked out.
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: items.isEmpty
            ? EmptyState(
                icon: Icons.shopping_cart_outlined,
                title: 'Keranjang kosong',
                description: 'Yuk cari kartu incaranmu di Market.',
                action: ElevatedButton(
                  onPressed: () => context.go(Routes.market),
                  child: const Text('Jelajahi Market'),
                ),
              )
            : const _CartBody(),
      ),
    );
  }
}

class _CartBody extends ConsumerWidget {
  const _CartBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final selected = ref.watch(cartSelectionProvider);
    final selectedItems = ref.watch(selectedCartItemsProvider);
    final subtotal = ref.watch(selectedSubtotalProvider);

    final selectable = items.where((i) => i.isAvailable).toList();
    final allSelected =
        selectable.isNotEmpty && selectable.every((i) => selected.contains(i.cartItemId));

    // Grouped by seller, as the web does — an order is placed per seller, so
    // the cart shows the shape the order will take.
    final groups = <String, List<CartItem>>{};
    for (final item in items) {
      (groups[item.listing.sellerId] ??= []).add(item);
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(
                'Keranjang',
                style: AppTypography.h2(context.appColors.onSurface),
              ),
              const SizedBox(height: 12),
              _SelectAllBar(
                total: selectable.length,
                allSelected: allSelected,
                anySelected: selected.isNotEmpty,
                onToggleAll: (value) => ref
                    .read(cartSelectionProvider.notifier)
                    .toggleAll(selected: value),
                onBulkRemove: () => _confirmBulkRemove(context, ref),
              ),
              const SizedBox(height: 12),
              for (final entry in groups.entries) ...[
                _SellerGroup(sellerId: entry.key, items: entry.value),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        _CheckoutBar(
          itemCount: selectedItems.length,
          subtotal: subtotal,
          // Ports the web's `hasSoldOutSelected` guard. Selection excludes
          // unavailable lines, so this only trips if one went out of stock
          // while it sat selected.
          hasSoldOut: selectedItems.any((i) => !i.isAvailable),
        ),
      ],
    );
  }

  Future<void> _confirmBulkRemove(BuildContext context, WidgetRef ref) {
    final selected = ref.read(selectedCartItemsProvider);
    return showConfirmDialog(
      context,
      title: 'Hapus item terpilih?',
      description:
          'Akan menghapus ${selected.length} item dari keranjang.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        final notifier = ref.read(cartProvider.notifier);
        for (final item in selected) {
          await notifier.remove(item.cartItemId);
        }
      },
    );
  }
}

/// "Pilih Semua (N)" with the bulk-delete action beside it.
class _SelectAllBar extends StatelessWidget {
  const _SelectAllBar({
    required this.total,
    required this.allSelected,
    required this.anySelected,
    required this.onToggleAll,
    required this.onBulkRemove,
  });

  final int total;
  final bool allSelected;
  final bool anySelected;
  final ValueChanged<bool> onToggleAll;
  final VoidCallback onBulkRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: total == 0 ? null : (v) => onToggleAll(v ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              'Pilih Semua ($total)',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ),
          if (anySelected)
            TextButton(
              onPressed: onBulkRemove,
              child: Text(
                'Hapus',
                style: AppTypography.bodySmSemibold(colors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One seller's lines under a header carrying their store.
class _SellerGroup extends ConsumerWidget {
  const _SellerGroup({required this.sellerId, required this.items});

  final String sellerId;
  final List<CartItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(cartSelectionProvider);
    final first = items.first.listing;

    final selectable = items.where((i) => i.isAvailable).toList();
    final allSelected = selectable.isNotEmpty &&
        selectable.every((i) => selected.contains(i.cartItemId));

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(Routes.storeDetail(first.storeSlug)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    onChanged: selectable.isEmpty
                        ? null
                        : (v) => ref
                              .read(cartSelectionProvider.notifier)
                              .toggleSeller(sellerId, selected: v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  SellerAvatar(
                    imageUrl: first.storeLogoUrl ?? first.sellerAvatarUrl,
                    name: first.storeName,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      first.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(
                        context.appColors.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: context.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          for (final item in items) ...[
            Divider(height: 1, color: context.borderColor),
            _CartLine(item: item),
          ],
        ],
      ),
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final listing = item.listing;
    final card = listing.card;
    final available = item.isAvailable;
    final selected = ref.watch(cartSelectionProvider).contains(item.cartItemId);

    // Sold-out lines stay visible but read as unavailable — the buyer needs
    // to see what they're being asked to remove.
    return Opacity(
      opacity: available ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: available
                  ? (_) => ref
                        .read(cartSelectionProvider.notifier)
                        .toggle(item.cartItemId)
                  : null,
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(
              width: 52,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${card.collectorNumber} · ${card.expansionCode.toUpperCase()}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ConditionBadge(condition: listing.condition, dense: true),
                      if (!available) ...[
                        const SizedBox(width: 6),
                        Text(
                          listing.status == ListingStatus.open
                              ? 'Stok habis'
                              : 'Tidak tersedia',
                          style: AppTypography.caption(colors.error),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (available)
                        QuantitySelector(
                          value: item.quantity,
                          min: 1,
                          max: listing.available,
                          onChanged: (q) => ref
                              .read(cartProvider.notifier)
                              .updateQuantity(item, q),
                        ),
                      const Spacer(),
                      Text(
                        formatRupiah(item.subtotal),
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 19),
                        color: context.mutedForeground,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(cartProvider.notifier)
                            .remove(item.cartItemId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The summary that the web keeps in a sticky sidebar; on a phone it's a
/// bottom bar.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.itemCount,
    required this.subtotal,
    required this.hasSoldOut,
  });

  final int itemCount;
  final int subtotal;
  final bool hasSoldOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final blocked = itemCount == 0 || hasSoldOut;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Subtotal ($itemCount item)',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const Spacer(),
                Text(
                  formatRupiah(subtotal),
                  style: AppTypography.h3(colors.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: blocked ? null : () => context.push(Routes.checkout),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Lanjut ke Checkout'),
            ),
            if (hasSoldOut) ...[
              const SizedBox(height: 6),
              Text(
                'Hapus item habis stok untuk lanjut',
                textAlign: TextAlign.center,
                style: AppTypography.caption(context.appSemantic.gold),
              ),
            ] else if (itemCount == 0) ...[
              const SizedBox(height: 6),
              Text(
                'Pilih kartu dulu untuk lanjut',
                textAlign: TextAlign.center,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

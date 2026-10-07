import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/seller_avatar.dart';
import 'checkout_page.dart';
import 'widgets/empty_cart_card.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/models/listing_model.dart';
import '../../orders/usecase/orders_notifier.dart';
import '../repository/models/cart_item.dart';
import '../repository/models/checkout_deal.dart';
import '../usecase/cart_deals.dart';
import '../usecase/cart_notifier.dart';
import '../usecase/cart_selection.dart';

/// Ports `features/cart/components/cart-client.tsx` — the cart grouped per
/// seller, with per-line selection driving what actually gets checked out,
/// and the buyer's accepted bid proposals waiting beside the lines.
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final deals = ref.watch(cartDealsProvider).valueOrNull ?? const [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: items.isEmpty && deals.isEmpty
            ? const EmptyCartCard()
            : const _CartBody(),
      ),
    );
  }
}

/// Where the cart's checkout button goes: the plain cart checkout, or — once
/// a deal is ticked — `dealCheckoutRoute`, carrying the ticked lines along
/// when there are any (`handleProceedToCheckout`'s `?s=&d=`).
void openCartCheckout(
  BuildContext context, {
  required List<String> dealExternalIds,
  required bool hasCartItems,
}) {
  if (dealExternalIds.isEmpty) {
    context.push(Routes.checkout);
    return;
  }
  Navigator.of(
    context,
  ).push(dealCheckoutRoute(dealExternalIds, withCartSelection: hasCartItems));
}

class _CartBody extends ConsumerWidget {
  const _CartBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final selected = ref.watch(cartSelectionProvider);
    final selectedItems = ref.watch(selectedCartItemsProvider);
    final subtotal = ref.watch(selectedSubtotalProvider);
    final deals = ref.watch(cartDealsProvider).valueOrNull ?? const [];
    final selectedDealIds = ref.watch(cartDealSelectionProvider);
    final selectedDeals = ref.watch(selectedCartDealsProvider);

    final selectable = items.where((i) => i.isAvailable).toList();
    final selectableCount = selectable.length + deals.length;
    final allSelected =
        selectableCount > 0 &&
        selectable.every((i) => selected.contains(i.cartItemId)) &&
        deals.every((d) => selectedDealIds.contains(d.externalId));

    // Grouped by seller, as the web does — an order is placed per seller, so
    // the cart shows the shape the order will take. A seller with only a
    // deal still gets a group, after the ones with cart lines.
    final groups = <String, List<CartItem>>{};
    for (final item in items) {
      (groups[item.listing.sellerId] ??= []).add(item);
    }
    final dealsBySeller = <String, List<CheckoutDeal>>{};
    for (final deal in deals) {
      (dealsBySeller[deal.sellerId] ??= []).add(deal);
      groups.putIfAbsent(deal.sellerId, () => []);
    }

    final dealLineCount = selectedDeals.fold(
      0,
      (sum, deal) => sum + deal.lines.length,
    );
    final dealSubtotal = selectedDeals.fold(
      0,
      (sum, deal) => sum + deal.subtotal,
    );

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
                total: selectableCount,
                allSelected: allSelected,
                anySelected: selected.isNotEmpty,
                onToggleAll: (value) {
                  ref
                      .read(cartSelectionProvider.notifier)
                      .toggleAll(selected: value);
                  ref
                      .read(cartDealSelectionProvider.notifier)
                      .setAll(selected: value);
                },
                onBulkRemove: () => _confirmBulkRemove(context, ref),
              ),
              const SizedBox(height: 12),
              for (final entry in groups.entries) ...[
                _SellerGroup(
                  sellerId: entry.key,
                  items: entry.value,
                  deals: dealsBySeller[entry.key] ?? const [],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        _CheckoutBar(
          itemCount: selectedItems.length + dealLineCount,
          subtotal: subtotal + dealSubtotal,
          // Ports the web's `hasSoldOutSelected` guard. Selection excludes
          // unavailable lines, so this only trips if one went out of stock
          // while it sat selected.
          hasSoldOut: selectedItems.any((i) => !i.isAvailable),
          onCheckout: () => openCartCheckout(
            context,
            dealExternalIds: [
              for (final deal in selectedDeals) deal.externalId,
            ],
            hasCartItems: selectedItems.isNotEmpty,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmBulkRemove(BuildContext context, WidgetRef ref) {
    final selected = ref.read(selectedCartItemsProvider);
    return showConfirmDialog(
      context,
      title: 'Hapus item terpilih?',
      description: 'Akan menghapus ${selected.length} item dari keranjang.',
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

/// One seller's lines and deals under a header carrying their store.
class _SellerGroup extends ConsumerWidget {
  const _SellerGroup({
    required this.sellerId,
    required this.items,
    this.deals = const [],
  });

  final String sellerId;
  final List<CartItem> items;
  final List<CheckoutDeal> deals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(cartSelectionProvider);
    final first = items.firstOrNull?.listing;
    final deal = deals.firstOrNull;
    final storeName =
        first?.storeName ??
        (deal?.storeName?.isNotEmpty == true ? deal!.storeName! : 'Penjual');
    final storeImageUrl =
        first?.storeLogoUrl ?? first?.sellerAvatarUrl ?? deal?.storeLogoUrl;

    final selectable = items.where((i) => i.isAvailable).toList();
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((i) => selected.contains(i.cartItemId));

    final header = Padding(
      padding: EdgeInsets.fromLTRB(items.isEmpty ? 14 : 8, 8, 12, 8),
      child: Row(
        children: [
          // Web's seller checkbox covers cart lines only; a deal is ticked
          // on its own row.
          if (items.isNotEmpty)
            Checkbox(
              value: allSelected,
              onChanged: selectable.isEmpty
                  ? null
                  : (v) => ref
                        .read(cartSelectionProvider.notifier)
                        .toggleSeller(sellerId, selected: v ?? false),
              visualDensity: VisualDensity.compact,
            ),
          SellerAvatar(imageUrl: storeImageUrl, name: storeName, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ),
          if (first != null)
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          if (first != null)
            InkWell(
              onTap: () => context.push(Routes.storeDetail(first.storeSlug)),
              child: header,
            )
          else
            header,
          for (final item in items) ...[
            Divider(height: 1, color: context.borderColor),
            _CartLine(item: item),
          ],
          for (final deal in deals) ...[
            Divider(height: 1, color: context.borderColor),
            _DealGroup(deal: deal),
          ],
        ],
      ),
    );
  }
}

/// One accepted proposal in the cart — `DealItemGroup` as `SellerGroupCard`
/// renders it there: a "Bid Proposal" tag with the time left to pay, then
/// each line at the price the deal fixed, ticked as one and cancelled as one.
class _DealGroup extends ConsumerWidget {
  const _DealGroup({required this.deal});

  final CheckoutDeal deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final selected = ref
        .watch(cartDealSelectionProvider)
        .contains(deal.externalId);
    final expiresAt = deal.expiresAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appSemantic.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'Bid Proposal',
                  style: AppTypography.captionSemibold(
                    context.appSemantic.success,
                  ),
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.clock,
                  size: 12,
                  color: context.mutedForeground,
                ),
                const SizedBox(width: 4),
                Text(
                  dealExpiryLabel(expiresAt, DateTime.now()),
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ],
          ),
        ),
        for (final line in deal.lines)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (_) => ref
                      .read(cartDealSelectionProvider.notifier)
                      .toggle(deal.externalId),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 52,
                  child: CardArt(
                    imageUrl: line.imageUrl,
                    borderRadius: AppRadius.sm,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.cardName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (line.condition case final condition?
                              when !line.isSealed) ...[
                            ConditionBadge(condition: condition, dense: true),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            'Qty: ${line.quantity}',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            formatRupiah(line.subtotal),
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 19),
                            color: context.mutedForeground,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Batalkan penawaran',
                            onPressed: () => _confirmCancel(context, ref),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    return showConfirmDialog(
      context,
      title: 'Batalkan penawaran?',
      description:
          'Menghapus penawaran ini akan membatalkan kesepakatan dan melepas '
          'stok. Tindakan ini tidak bisa dibatalkan.',
      confirmLabel: 'Batalkan Penawaran',
      loadingLabel: 'Membatalkan...',
      onConfirm: () async {
        final error = await ref
            .read(ordersRepositoryProvider)
            .cancelPendingCheckout(deal.externalId);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(error ?? 'Penawaran dibatalkan'),
              persist: false,
            ),
          );
        if (error != null) return;
        ref.invalidate(cartDealsProvider);
        ref.invalidate(myPendingCheckoutsProvider);
      },
    );
  }
}

/// Ports `formatExpiry` in `deal-item-group.tsx`: "5j 12m", "40m", or
/// "Kedaluwarsa" once the 24 hours are up.
String dealExpiryLabel(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return 'Kedaluwarsa';
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  return hours > 0 ? '${hours}j ${minutes}m' : '${minutes}m';
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
                      if (!card.isSealed)
                        ConditionBadge(
                          condition: listing.condition,
                          dense: true,
                        ),
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
                        icon: const Icon(LucideIcons.trash2, size: 19),
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
    required this.onCheckout,
  });

  final int itemCount;
  final int subtotal;
  final bool hasSoldOut;
  final VoidCallback onCheckout;

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
                Expanded(
                  child: Text(
                    'Subtotal ($itemCount item)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ),
                Text(
                  formatRupiah(subtotal),
                  style: AppTypography.h3(colors.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: blocked ? null : onCheckout,
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

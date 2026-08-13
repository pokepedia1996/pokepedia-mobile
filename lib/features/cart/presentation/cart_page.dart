import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/cart_notifier.dart';

/// Ports `app/cart/page.tsx` / `components/cart/cart-client.tsx`.
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: items.isEmpty
            ? const EmptyState(
                icon: Icons.shopping_cart_outlined,
                title: 'Keranjang kosong',
                description: 'Yuk cari kartu incaranmu di Market.',
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 56,
                                child: CardArt(borderRadius: AppRadius.sm),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.listing.card.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.bodySmSemibold(
                                        colors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.listing.storeName,
                                      style: AppTypography.caption(
                                        context.mutedForeground,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formatRupiah(item.listing.price),
                                      style: AppTypography.bodySmSemibold(
                                        colors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        QuantitySelector(
                                          value: item.quantity,
                                          min: 1,
                                          max: item.listing.available,
                                          onChanged: (v) =>
                                              notifier.updateQuantity(item, v),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                          color: colors.error,
                                          onPressed: () =>
                                              notifier.remove(item.cartItemId),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(
                        top: BorderSide(color: context.borderColor),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SummaryRow(
                          label: 'Subtotal',
                          value: formatRupiah(notifier.subtotal),
                        ),
                        _SummaryRow(
                          label: 'Ongkir',
                          value: formatRupiah(flatShippingCost),
                        ),
                        const SizedBox(height: 4),
                        _SummaryRow(
                          label: 'Total',
                          value: formatRupiah(notifier.total),
                          emphasize: true,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context.push(Routes.checkout),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Checkout'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Alamat, ongkir, dan pembayaran dilanjutkan di pokepedia.id',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption(context.mutedForeground),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? AppTypography.bodySemibold(context.appColors.onSurface)
        : AppTypography.bodySm(context.mutedForeground);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

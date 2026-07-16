import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../usecase/cart_notifier.dart';

/// Ports `app/cart/checkout/page.tsx`.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  String _courier = 'jne_reg';
  String _payment = 'qris';

  static const _couriers = [
    ('jne_reg', 'JNE Reguler', 'Rp15.000 · 2-3 hari'),
    ('jnt_express', 'J&T Express', 'Rp18.000 · 1-2 hari'),
    ('sicepat_best', 'SiCepat BEST', 'Rp22.000 · 1 hari'),
  ];

  static const _payments = [
    ('qris', 'QRIS'),
    ('va_bca', 'Virtual Account BCA'),
    ('saldo', 'Saldo pokepedia.id'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    title: 'Alamat Pengiriman',
                    icon: Icons.place_outlined,
                    child: Text(
                      'Ash Ketchum\n0812-3456-7890\nJl. Pallet Town No. 1, Kecamatan Pallet, Jakarta Selatan, 12345',
                      style: AppTypography.bodySm(colors.onSurface),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Kurir',
                    icon: Icons.local_shipping_outlined,
                    child: Column(
                      children: [
                        for (final (value, label, hint) in _couriers)
                          _SelectableTile(
                            selected: _courier == value,
                            title: label,
                            subtitle: hint,
                            onTap: () => setState(() => _courier = value),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Metode Pembayaran',
                    icon: Icons.payments_outlined,
                    child: Column(
                      children: [
                        for (final (value, label) in _payments)
                          _SelectableTile(
                            selected: _payment == value,
                            title: label,
                            onTap: () => setState(() => _payment = value),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Ringkasan',
                    icon: Icons.receipt_long_outlined,
                    child: Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.listing.card.name} ×${item.quantity}',
                                    style: AppTypography.bodySm(
                                      colors.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatRupiah(item.subtotal),
                                  style: AppTypography.bodySm(colors.onSurface),
                                ),
                              ],
                            ),
                          ),
                        Divider(color: context.borderColor),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: AppTypography.bodySemibold(
                                colors.onSurface,
                              ),
                            ),
                            Text(
                              formatRupiah(notifier.total),
                              style: AppTypography.bodySemibold(
                                colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: ElevatedButton(
                onPressed: () {
                  notifier.clear();
                  context.push(Routes.checkoutSuccess);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: context.appSemantic.success,
                ),
                child: Text('Bayar ${formatRupiah(notifier.total)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(title, style: AppTypography.bodySmSemibold(colors.onSurface)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? colors.primary : context.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
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

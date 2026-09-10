import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';

/// Ports the "paid" state of `components/checkout/checkout-success-client.tsx`
/// — the web polls the order for its live status after redirect, but since
/// this pass is dummy-data-only there's nothing to poll, so the page always
/// renders straight to the success state with the summary handed off by
/// [CheckoutPage] before it cleared the cart.
class CheckoutSuccessPage extends StatelessWidget {
  const CheckoutSuccessPage({super.key, this.itemCount, this.total});

  final int? itemCount;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.circleCheckBig,
                    size: 48,
                    color: context.appSemantic.success,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pembayaran Berhasil!',
                    textAlign: TextAlign.center,
                    style: AppTypography.h3(colors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  if (itemCount != null)
                    Text(
                      '$itemCount kartu berhasil dibeli.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  if (total != null) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: 'Total: ',
                        style: AppTypography.bodySm(context.mutedForeground),
                        children: [
                          TextSpan(
                            text: formatRupiah(total!),
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.goHomeThen(Routes.orders),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: const Text('Lihat Pesanan'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go(Routes.home),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: const Text('Belanja Lagi'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// The screen that closes a saldo checkout.
///
/// Ports the `status === "paid"` branch of web's `checkout-success-client.tsx`.
/// A card payment reaches its equivalent inside the Xendit WebView and then
/// lands on [CheckoutStatusPage], which polls because the webhook decides
/// whether it was really paid. Saldo has nothing to poll:
/// `pay_checkout_with_wallet` has already debited the wallet and written the
/// order rows by the time the request returns, so this states the outcome
/// rather than waiting for it.
///
/// Reached through `goHomeThen`, so Beranda sits underneath it — the cart and
/// checkout it came from are gone, and backing out of a finished order lands
/// somewhere that still makes sense.
class CheckoutThankYouPage extends StatelessWidget {
  const CheckoutThankYouPage({
    super.key,
    required this.cardCount,
    required this.totalAmount,
  });

  /// Copies bought, not cart lines — "3 kartu" reads as three cards even when
  /// they came from one line at quantity three.
  final int cardCount;

  /// What the wallet was actually charged: the discounted total, with no
  /// gateway fee, matching `carts.invoice_amount`.
  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
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
                  Text(
                    '$cardCount kartu berhasil dibeli.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dibayar dari saldo: ${formatRupiah(totalAmount)}',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => context.push(Routes.orders),
                      child: const Text('Lihat Pesanan'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      // `go` rather than `pop`: Beranda is already the one
                      // route underneath, so this returns to it instead of
                      // stacking a second copy.
                      onPressed: () => context.go(Routes.home),
                      child: const Text('Belanja Lagi'),
                    ),
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

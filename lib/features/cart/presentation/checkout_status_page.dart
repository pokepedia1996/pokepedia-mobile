import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/checkout_gateway.dart';
import '../usecase/cart_notifier.dart';

/// Confirms an order after the payment page closes.
///
/// The redirect back from Xendit is UX only — the webhook is what settles
/// the order, and it can land before or after the buyer returns. Someone who
/// pays by VA transfer and closes the page never redirects at all, and
/// someone who returns immediately may arrive before the webhook does. So
/// coming back is never treated as payment; this asks our own backend
/// instead, and keeps asking for a while.
class CheckoutStatusPage extends ConsumerStatefulWidget {
  const CheckoutStatusPage({
    super.key,
    required this.externalId,
    this.droppedItems = const [],
  });

  final String externalId;

  /// Lines the server refused at lock time, surfaced here because this is
  /// the first screen after the order was placed.
  final List<String> droppedItems;

  @override
  ConsumerState<CheckoutStatusPage> createState() => _CheckoutStatusPageState();
}

class _CheckoutStatusPageState extends ConsumerState<CheckoutStatusPage> {
  /// Every two seconds for a minute. Long enough for a webhook that's merely
  /// slow, short enough that nobody watches a spinner forever — after that
  /// the order is still fine, it just isn't confirmed *here*.
  static const _interval = Duration(seconds: 2);
  static const _attempts = 30;

  Timer? _timer;
  int _tries = 0;
  CheckoutProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted) return;
    _tries++;

    try {
      final progress = await ref
          .read(checkoutGatewayProvider)
          .fetchProgress(widget.externalId);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _error = null;
      });
      if (progress.isSettled) {
        _timer?.cancel();
        // The cart is emptied server-side at lock time; pull that through so
        // the badge doesn't keep showing items that are now an order.
        await ref.read(cartProvider.notifier).refresh();
      }
    } catch (e) {
      if (!mounted) return;
      // A failed poll is not a failed payment. Keep trying, and only say so
      // if every attempt fails.
      setState(() => _error = 'Belum bisa memastikan status pembayaran.');
    }

    if (_tries >= _attempts) _timer?.cancel();
  }

  bool get _timedOut => _tries >= _attempts && !(_progress?.isSettled ?? false);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = _progress?.status;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (status == CheckoutStatus.paid) ...[
                  Icon(
                    Icons.check_circle,
                    size: 56,
                    color: context.appSemantic.success,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pembayaran diterima',
                    style: AppTypography.h2(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pesanan kamu sedang disiapkan penjual.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ] else if (status == CheckoutStatus.cancelled) ...[
                  Icon(Icons.cancel_outlined, size: 56, color: colors.error),
                  const SizedBox(height: 12),
                  Text(
                    _cancelledTitle(_progress!.raw),
                    style: AppTypography.h2(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kartu di keranjang sudah dilepas kembali.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ] else if (_timedOut) ...[
                  Icon(
                    Icons.hourglass_empty,
                    size: 56,
                    color: context.mutedForeground,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Masih menunggu konfirmasi',
                    style: AppTypography.h2(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kalau kamu sudah membayar, pesanan tetap diproses '
                    'begitu pembayaran masuk. Cek halaman Pesanan sebentar '
                    'lagi.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ] else ...[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mengonfirmasi pembayaran...',
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Jangan tutup halaman ini dulu ya.',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],

                if (_error != null && status == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],

                if (widget.droppedItems.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _DroppedItemsNotice(items: widget.droppedItems),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(Routes.orders),
                    child: const Text('Lihat Pesanan'),
                  ),
                ),
                if (status != CheckoutStatus.paid) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.go(Routes.home),
                      child: const Text('Kembali ke Beranda'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _cancelledTitle(String raw) => switch (raw) {
    'expired' => 'Waktu pembayaran habis',
    'refunded' => 'Pembayaran dikembalikan',
    'refund_required' => 'Menunggu pengembalian dana',
    'failed' => 'Pembayaran gagal',
    _ => 'Pesanan dibatalkan',
  };
}

/// The server drops lines it can no longer honour when it locks the cart.
/// The buyer paid for what remained, so this has to be said out loud.
class _DroppedItemsNotice extends StatelessWidget {
  const _DroppedItemsNotice({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSemantic.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.appSemantic.gold.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${items.length} kartu tidak jadi dibeli',
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Stok habis atau harga berubah sebelum pembayaran selesai. '
            'Kartu ini tidak ditagihkan.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

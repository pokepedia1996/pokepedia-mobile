import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../repository/checkout_gateway.dart';
import 'payment_webview_page.dart';

/// The QRIS payment screen, drawn natively instead of opening Xendit's
/// hosted invoice in a WebView.
///
/// The QR payload comes from the invoice the checkout already opened, so the
/// payment settles through the same webhook the web flow uses. Only QRIS is
/// handled here; a virtual-account checkout still goes to the hosted page,
/// which knows how to display an account number and its instructions.
class QrisPaymentPage extends ConsumerStatefulWidget {
  const QrisPaymentPage({
    super.key,
    required this.externalId,
    required this.amount,
    this.invoiceUrl,
  });

  final String externalId;

  /// What the checkout said was owed, shown until the gateway confirms it.
  final int amount;

  /// Where to finish if the QR can't be produced.
  final String? invoiceUrl;

  @override
  ConsumerState<QrisPaymentPage> createState() => _QrisPaymentPageState();
}

class _QrisPaymentPageState extends ConsumerState<QrisPaymentPage> {
  /// Polled rather than pushed: a QRIS transfer is confirmed by Xendit
  /// calling our webhook, so the app can only find out by asking.
  static const _pollInterval = Duration(seconds: 4);

  Timer? _poll;
  Timer? _tick;

  QrisCharge? _charge;
  String? _error;
  String? _diagnostic;
  String? _fallbackUrl;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Drives the countdown; the poll below is what actually checks payment.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _fallbackUrl = null;
      _diagnostic = null;
    });
    try {
      final charge = await ref
          .read(checkoutGatewayProvider)
          .fetchQris(widget.externalId);
      if (!mounted) return;
      setState(() {
        _charge = charge;
        _paid = charge.isPaid;
      });
      if (!_paid) _startPolling();
    } on QrisUnavailableException catch (e) {
      if (!mounted) return;
      final invoiceUrl = e.invoiceUrl ?? widget.invoiceUrl;

      // No QR to draw, but the hosted invoice can still take the payment —
      // and that page is the documented flow (§5 of the bearer-auth
      // handoff: mobile opens a WebView on `invoiceUrl` and nothing else).
      // Showing a dead end with a link the buyer has to notice would strand
      // a checkout that is otherwise perfectly payable.
      if (invoiceUrl != null) {
        await _payOnXendit(invoiceUrl);
        return;
      }

      setState(() {
        _error = e.message;
        _fallbackUrl = invoiceUrl;
        _diagnostic = e.diagnostic;
      });
    } catch (_) {
      if (!mounted) return;
      // Same reasoning as above, for the failures that aren't a considered
      // "no QR here" answer — the function being unreachable, a shape we
      // can't parse. If there's an invoice, it can still be paid.
      final invoiceUrl = widget.invoiceUrl;
      if (invoiceUrl != null) {
        await _payOnXendit(invoiceUrl);
        return;
      }
      setState(() => _error = 'Gagal memuat QRIS.');
    }
  }

  /// The lines under the error headline: where to finish paying, and what
  /// the invoice actually held when no QR could be read off it.
  String? _errorDetail() {
    final lines = [
      if (_fallbackUrl != null) 'Selesaikan pembayaran di halaman Xendit.',
      if (_diagnostic != null) _diagnostic!,
    ];
    return lines.isEmpty ? null : lines.join('\n\n');
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _checkPaid());
  }

  Future<void> _checkPaid() async {
    try {
      final progress = await ref
          .read(checkoutGatewayProvider)
          .fetchProgress(widget.externalId);
      if (!mounted || !progress.isSettled) return;
      _poll?.cancel();
      setState(() => _paid = progress.status == CheckoutStatus.paid);
      if (mounted) Navigator.of(context).pop(_paid);
    } catch (_) {
      // A failed poll is not a failed payment; the next tick tries again.
    }
  }

  /// Hands the buyer to Xendit's hosted invoice, in place of this page.
  ///
  /// `pushReplacement`, not `push`: there is no QR here to come back to, and
  /// leaving a dead page under the WebView means the back gesture lands on
  /// an error screen instead of returning to checkout.
  ///
  /// The outcome is deliberately not trusted — the webhook settles the
  /// order, so the caller polls status either way. Returning normally is
  /// what lets it.
  Future<void> _payOnXendit(String invoiceUrl) async {
    if (!mounted) return;
    _poll?.cancel();
    _tick?.cancel();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<PaymentOutcome>(
        builder: (_) => PaymentWebViewPage(invoiceUrl: invoiceUrl),
      ),
    );
  }

  Future<void> _openInvoice(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Duration? get _remaining {
    final expiry = _charge?.expiresAt;
    if (expiry == null) return null;
    final left = expiry.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final charge = _charge;

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan QRIS')),
      body: SafeArea(
        child: _error != null
            ? EmptyState(
                icon: LucideIcons.qrCode,
                title: _error!,
                description: _errorDetail(),
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Coba lagi'),
                    ),
                    if (_fallbackUrl != null) ...[
                      const SizedBox(height: 8),
                      // A last resort, and deliberately the system browser
                      // rather than an in-app WebView: this flow is native
                      // now, and leaving the app makes that explicit.
                      TextButton(
                        onPressed: () => _openInvoice(_fallbackUrl!),
                        child: const Text('Bayar lewat browser'),
                      ),
                    ],
                  ],
                ),
              )
            : charge == null
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    'Total tagihan',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRupiah(
                      charge.amount > 0 ? charge.amount : widget.amount,
                    ),
                    style: AppTypography.h1(colors.onSurface),
                  ),
                  const SizedBox(height: 16),
                  _QrPanel(qrString: charge.qrString),
                  const SizedBox(height: 14),
                  if (_remaining != null) _Countdown(remaining: _remaining!),
                  const SizedBox(height: 14),
                  if (charge.qrString != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: charge.qrString!),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Kode QRIS disalin'),
                              persist: false,
                            ),
                          );
                      },
                      icon: const Icon(LucideIcons.copy, size: 15),
                      label: const Text('Salin kode QRIS'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const _Instructions(),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Menunggu pembayaran...',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.qrString});

  final String? qrString;

  @override
  Widget build(BuildContext context) {
    final code = qrString;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // White regardless of theme: a scanner reads dark-on-light, and a
        // QR inverted for dark mode is a QR that doesn't scan.
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Center(
        child: code == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'Pembayaran sudah diterima.',
                  style: AppTypography.bodySm(Colors.black),
                ),
              )
            : QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                // A QRIS payload is long; the lowest correction level keeps
                // the modules big enough to scan on a phone screen.
                errorCorrectionLevel: QrErrorCorrectLevel.L,
              ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final expired = remaining == Duration.zero;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Center(
      child: Text(
        expired
            ? 'Waktu pembayaran habis'
            : 'Selesaikan dalam $minutes:$seconds',
        style: AppTypography.bodySmSemibold(
          expired ? context.appColors.error : context.appColors.onSurface,
        ),
      ),
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions();

  static const _steps = [
    'Buka aplikasi bank atau e-wallet yang mendukung QRIS.',
    'Pilih menu Scan / Bayar, lalu arahkan ke kode di atas.',
    'Periksa nominal dan nama penerima sebelum menyelesaikan pembayaran.',
    'Halaman ini otomatis lanjut begitu pembayaran diterima.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cara membayar',
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}.',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

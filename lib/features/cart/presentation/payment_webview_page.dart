import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Why the payment page closed.
enum PaymentOutcome {
  /// The gateway redirected to our success URL. This is *not* proof of payment —
  /// it only means the gateway sent the buyer back. The order is settled by
  /// the webhook, so the caller still has to poll.
  returned,

  /// The buyer backed out. Also not proof of anything: they may have paid by
  /// VA transfer and closed the page before the redirect.
  dismissed,
}

/// Hosts the gateway's payment page — Xendit's invoice or DOKU Checkout —
/// the one checkout screen that is deliberately not native, because it is
/// the gateway's own surface.
///
/// Everything here is about not letting the WebView do more than that:
/// only a gateway's own hosts may load, the return URLs are intercepted
/// rather than followed, and payment-app deep links are handed to the OS.
class PaymentWebViewPage extends StatefulWidget {
  const PaymentWebViewPage({super.key, required this.invoiceUrl});

  final String invoiceUrl;

  /// Pages the payment page may move to once open: its own hosts, and DOKU's
  /// other hosts, which its page can step through while the buyer pays.
  @visibleForTesting
  static bool isGatewayNavigation(Uri uri) =>
      uri.scheme == 'https' &&
      (_PaymentWebViewPageState._allowedHosts.contains(uri.host) ||
          uri.host.endsWith('.doku.com'));

  @override
  State<PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<PaymentWebViewPage> {
  late final WebViewController _controller;
  double _progress = 0;

  /// The only hosts a payment page may be opened at. Mirrors the server's
  /// `isSafePaymentUrl`; anything else is either a mistake or an attempt to
  /// dress something up as our payment page. DOKU's sandbox serves
  /// `staging.doku.com`; production is `jokul.doku.com`.
  static const _allowedHosts = {
    'checkout.xendit.co',
    'checkout-staging.xendit.co',
    'staging.doku.com',
    'sandbox.doku.com',
    'jokul.doku.com',
  };

  /// Our own return URLs. They need a session cookie the app doesn't have,
  /// so loading one would bounce to /login and look like a failed payment.
  static const _successPath = '/cart/checkout/success';

  /// Where a gateway sends a buyer who backs out of its page (DOKU's
  /// `callback_url_cancel`).
  static const _cancelPath = '/orders';

  static bool _isTrustedInvoice(Uri? uri) =>
      uri != null && uri.scheme == 'https' && _allowedHosts.contains(uri.host);

  @override
  void initState() {
    super.initState();
    final invoiceUri = Uri.tryParse(widget.invoiceUrl);
    if (!_isTrustedInvoice(invoiceUri)) {
      _controller = WebViewController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(PaymentOutcome.dismissed);
      });
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(invoiceUri!);
  }

  Future<NavigationDecision> _handleNavigation(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    // The return leg. Close instead of loading it, and let the caller decide
    // what actually happened by asking our own backend.
    if (uri.path.startsWith(_successPath)) {
      if (mounted) Navigator.of(context).pop(PaymentOutcome.returned);
      return NavigationDecision.prevent;
    }

    // The buyer backed out on the gateway's page: back to checkout, which
    // asks our backend what happened, rather than our orders page in a browser.
    if (!PaymentWebViewPage.isGatewayNavigation(uri) &&
        uri.path.startsWith(_cancelPath)) {
      if (mounted) Navigator.of(context).pop(PaymentOutcome.dismissed);
      return NavigationDecision.prevent;
    }

    // QRIS and VA pages hand off to bank and e-wallet apps via `gojek://`,
    // `shopeeid://`, `intent://` and friends. Without this the buyer
    // dead-ends on a page the WebView can't render.
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      if (await launcher.canLaunchUrl(uri)) {
        await launcher.launchUrl(
          uri,
          mode: launcher.LaunchMode.externalApplication,
        );
      }
      return NavigationDecision.prevent;
    }

    if (PaymentWebViewPage.isGatewayNavigation(uri)) {
      return NavigationDecision.navigate;
    }

    // Anything else — including our own domain — opens outside rather than
    // inside the frame the buyer is trusting with their payment.
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
    }
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          Navigator.of(context).pop(PaymentOutcome.dismissed);
        }
      },
      child: Scaffold(
        appBar: TransparentAppBar(
          onBack: () => Navigator.of(context).pop(PaymentOutcome.dismissed),
        ),
        body: Column(
          children: [
            if (_progress < 1)
              LinearProgressIndicator(value: _progress, minHeight: 2),
            // The host the buyer is actually on. A payment page should say
            // whose page it is.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(LucideIcons.lock, size: 13, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    Uri.tryParse(widget.invoiceUrl)?.host ?? '',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

/// Address, shipping, coupon, and payment only exist as a real, working
/// flow on pokepedia-web — those routes authenticate via browser cookies
/// the mobile app has no way to share, so the buyer finishes checkout
/// there instead of in a native (would-be dummy) flow. Embeds it in-app via
/// a WebView (rather than handing off to an external browser) so the buyer
/// never leaves pokepedia.id mobile.
class CheckoutWebViewPage extends StatefulWidget {
  const CheckoutWebViewPage({super.key, this.path = '/cart/checkout'});

  /// Path under [AppConfig.appUrl] to load — overridable so this same page
  /// can host other cookie-authenticated flows later (order actions,
  /// disputes) without a new widget per page.
  final String path;

  @override
  State<CheckoutWebViewPage> createState() => _CheckoutWebViewPageState();
}

class _CheckoutWebViewPageState extends State<CheckoutWebViewPage> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
          onPageFinished: (_) async {
            final canGoBack = await _controller.canGoBack();
            if (mounted) setState(() => _canGoBack = canGoBack);
          },
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(Uri.parse('${AppConfig.appUrl}${widget.path}'));
  }

  /// Keeps ordinary http(s) navigation (our own domain, and Xendit's hosted
  /// invoice page once checkout redirects there) inside the WebView; hands
  /// off anything else — bank/e-wallet app deep links, `intent:`/`market:`
  /// URIs some payment channels use, `mailto:`, etc. — to the OS so those
  /// apps open natively instead of failing to load in-WebView.
  Future<NavigationDecision> _handleNavigation(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NavigationDecision.navigate;
    }
    if (uri != null && await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  Future<void> _openInBrowser() async {
    final url = await _controller.currentUrl();
    if (url == null) return;
    await launcher.launchUrl(Uri.parse(url), mode: launcher.LaunchMode.externalApplication);
  }

  Future<bool> _handleBack() async {
    if (_canGoBack) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang',
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Buka di browser',
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 1)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2,
                color: context.appColors.primary,
                backgroundColor: Colors.transparent,
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

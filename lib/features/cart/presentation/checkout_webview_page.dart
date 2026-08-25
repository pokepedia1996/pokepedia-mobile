import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Hosts the one checkout screen that is deliberately not native: the
/// payment gateway's own page.
///
/// Passing [url] loads it directly — that's the Xendit hosted invoice the
/// native flow gets back from `/api/cart/checkout`, and it has to be the
/// gateway's page because that is where the card and VA details are
/// entered. Passing [path] instead loads a pokepedia.id route, which is the
/// fallback used when the app can't reach the API and the buyer has to
/// finish on the web.
class CheckoutWebViewPage extends StatefulWidget {
  const CheckoutWebViewPage({super.key, this.path = '/cart/checkout', this.url});

  /// Path under [AppConfig.appUrl] to load. Ignored when [url] is set.
  final String path;

  /// Absolute URL to load instead of [path].
  final String? url;

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
      ..loadRequest(
        Uri.parse(widget.url ?? '${AppConfig.appUrl}${widget.path}'),
      );
  }

  /// Keeps ordinary http(s) navigation (our own domain, and Xendit's hosted
  /// invoice page once checkout redirects there) inside the WebView; hands
  /// off anything else — bank/e-wallet app deep links, `intent:`/`market:`
  /// URIs some payment channels use, `mailto:`, etc. — to the OS so those
  /// apps open natively instead of failing to load in-WebView.
  Future<NavigationDecision> _handleNavigation(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NavigationDecision.navigate;
    }
    if (uri != null && await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
    }
    return NavigationDecision.prevent;
  }

  Future<void> _openInBrowser() async {
    final url = await _controller.currentUrl();
    if (url == null) return;
    await launcher.launchUrl(
      Uri.parse(url),
      mode: launcher.LaunchMode.externalApplication,
    );
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
        appBar: TransparentAppBar(
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

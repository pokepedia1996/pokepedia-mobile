import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards a policy rather than a calculation: payment happens on Xendit's
/// hosted invoice in a WebView, and nowhere else.
///
/// Asserted against the source because the alternative is mounting the whole
/// checkout page with a stubbed Supabase session, network and navigator just
/// to prove a route is never pushed. The failure this prevents is someone
/// re-adding the fallback in a hurry, and an import is exactly where that
/// shows up.
void main() {
  final checkout = File(
    'lib/features/cart/presentation/checkout_page.dart',
  ).readAsStringSync();

  test('checkout never hands payment off to the web version', () {
    // The web checkout would re-run pricing and address selection against a
    // session the app can't see the state of, with two checkouts racing over
    // one cart. An unreachable API is reported here instead.
    expect(checkout, isNot(contains('CheckoutWebViewPage')));
    expect(checkout, isNot(contains('checkout_webview_page.dart')));
  });

  test('an unreachable API is a toast, not a navigation', () {
    final handler = checkout.substring(
      checkout.indexOf('on ApiUnreachableException'),
      checkout.indexOf('on ApiSessionExpiredException'),
    );
    expect(handler, contains('_toast('));
    expect(handler, isNot(contains('Navigator')));
    expect(handler, isNot(contains('context.go')));
    expect(handler, isNot(contains('context.push')));
  });

  test('the hosted invoice is still the payment surface', () {
    // The other half of the rule: removing the fallback must not have
    // removed the thing it was falling back from.
    expect(checkout, contains('PaymentWebViewPage(invoiceUrl: invoiceUrl)'));
  });
}

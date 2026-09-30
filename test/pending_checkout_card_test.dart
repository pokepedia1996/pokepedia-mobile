import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/presentation/orders_page.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/pending_checkout.dart';

PendingCheckout _checkout({String? storeName, String? username}) =>
    PendingCheckout(
      cartId: 1,
      externalId: 'INV-1',
      buyerUsername: null,
      createdAt: DateTime(2026, 9, 15),
      expiresAt: DateTime(2026, 9, 15, 2),
      items: const [],
      hasInvoice: true,
      storeName: storeName,
      sellerUsername: username,
    );

void main() {
  group('formatRemaining ports web PendingCountdown', () {
    test('hours carry their minutes', () {
      // "1 jam" was the old wording for anything over an hour, which told a
      // buyer with 34 minutes left they had more room than they did.
      expect(formatRemaining(const Duration(hours: 1, minutes: 34)), '1j 34m');
      expect(formatRemaining(const Duration(hours: 2)), '2j 0m');
    });

    test('under an hour drops the hour part', () {
      expect(formatRemaining(const Duration(minutes: 45)), '45m');
    });

    test('the last minute says so rather than rounding to zero', () {
      expect(formatRemaining(const Duration(seconds: 30)), '<1m');
      expect(formatRemaining(Duration.zero), '<1m');
    });
  });

  group('seller display', () {
    test('storefront name wins, handle sits under it', () {
      final checkout = _checkout(storeName: 'Toko User3', username: 'user3');
      expect(checkout.displayName, 'Toko User3');
      expect(checkout.sellerSecondaryName, '@user3');
    });

    test('a handle that just repeats the name is not shown twice', () {
      final checkout = _checkout(storeName: 'user3', username: 'user3');
      expect(checkout.sellerSecondaryName, isNull);
    });

    test('no storefront falls back to the handle', () {
      final checkout = _checkout(username: 'user3');
      expect(checkout.displayName, 'user3');
      // Already the headline, so not repeated beneath it.
      expect(checkout.sellerSecondaryName, isNull);
    });

    test('neither still names something', () {
      expect(_checkout().displayName, 'Penjual');
    });
  });
}

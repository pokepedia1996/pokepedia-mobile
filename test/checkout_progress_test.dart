import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';

/// Xendit's redirect back to the app is UX only — the webhook is what
/// settles an order, and it can land before or after the buyer returns. So
/// the app decides from `carts`, and these pin how that row is read.
void main() {
  group('CheckoutProgress', () {
    test('pending is not settled', () {
      const progress = CheckoutProgress(
        status: CheckoutStatus.pending,
        raw: 'pending',
      );
      expect(progress.isSettled, isFalse);
    });

    test('paid and cancelled both end the poll', () {
      expect(
        const CheckoutProgress(
          status: CheckoutStatus.paid,
          raw: 'pending',
        ).isSettled,
        isTrue,
      );
      expect(
        const CheckoutProgress(
          status: CheckoutStatus.cancelled,
          raw: 'expired',
        ).isSettled,
        isTrue,
      );
    });
  });

  group('CheckoutResult', () {
    test('carries the id the poll needs and the lines that were dropped', () {
      const result = CheckoutResult(
        invoiceUrl: 'https://checkout.xendit.co/web/abc',
        externalId: 'INV-260810-A7K3P',
        totalAmount: 208162,
        droppedItems: ['Pikachu 025/165'],
      );

      expect(result.externalId, 'INV-260810-A7K3P');
      expect(result.totalAmount, 208162);
      expect(result.droppedItems, hasLength(1));
    });

    test('defaults to nothing dropped rather than null', () {
      const result = CheckoutResult(invoiceUrl: 'https://x');
      expect(result.droppedItems, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/errors/user_message.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';

/// What `/api/cart/checkout` and the other routes answer on failure, and
/// how the buyer ends up reading it.
void main() {
  group('parseDroppedItems', () {
    test('maps each {reason, available} to Indonesian', () {
      final messages = parseDroppedItems([
        {'reason': 'listing_matched', 'available': null},
        {'reason': 'insufficient_quantity', 'available': 2},
        {'reason': 'seller_on_vacation'},
      ]);
      expect(messages, [
        'Satu listing sudah terjual.',
        'Stok satu listing tinggal 2.',
        'Penjual sedang libur, satu item tidak bisa diproses.',
      ]);
    });

    test('an unknown reason still yields a sentence, never the code', () {
      final messages = parseDroppedItems([
        {'reason': 'something_new'},
      ]);
      expect(messages.single, isNot(contains('something_new')));
    });

    test('anything but a list is nothing dropped', () {
      expect(parseDroppedItems(null), isEmpty);
      expect(parseDroppedItems({'reason': 'listing_matched'}), isEmpty);
    });
  });

  group('CheckoutGateway.progressFromRow', () {
    test('paid_at settles a pending row as paid', () {
      final progress = CheckoutGateway.progressFromRow(
        status: 'paid',
        paidAt: '2026-10-07T10:00:00Z',
      );
      expect(progress.status, CheckoutStatus.paid);
    });

    for (final status in [
      'failed_unavailable',
      'failed_buyer_ineligible',
      'refund_failed',
      'refund_required',
      'refunded',
    ]) {
      test('$status ends the poll even though it was paid', () {
        final progress = CheckoutGateway.progressFromRow(
          status: status,
          paidAt: '2026-10-07T10:00:00Z',
        );
        expect(progress.status, CheckoutStatus.cancelled);
        expect(progress.raw, status);
      });
    }

    test('an open invoice keeps polling', () {
      final progress = CheckoutGateway.progressFromRow(
        status: 'pending',
        paidAt: null,
      );
      expect(progress.isSettled, isFalse);
    });
  });

  group('userFacingError for ApiException', () {
    test("shows the route's Indonesian sentence", () {
      const e = ApiException(
        'Saldo tidak cukup untuk penarikan ini',
        statusCode: 400,
        code: 'insufficient_balance',
      );
      expect(userFacingError(e), 'Saldo tidak cukup untuk penarikan ini');
    });

    test('maps a bare code through the token table', () {
      const e = ApiException(
        ApiException.genericMessage,
        statusCode: 409,
        code: 'listing_reserved_by_deal',
      );
      expect(userFacingError(e), contains('sedang dipakai di checkout'));
    });

    test('never shows a raw code', () {
      const e = ApiException('rpc_error', statusCode: 500);
      expect(userFacingError(e), isNot(contains('rpc_error')));
    });
  });

  test('isErrorCode tells codes from sentences', () {
    expect(isErrorCode('coupon_invalid'), isTrue);
    expect(isErrorCode('Kuota promo sudah habis.'), isFalse);
  });
}

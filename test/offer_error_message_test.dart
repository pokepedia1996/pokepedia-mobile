import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/offers_repository.dart';

void main() {
  group('offerErrorMessage', () {
    test('translates the RPC refusal codes web already words', () {
      // The RPCs report refusals as `{error: '<code>'}` data rather than
      // throwing, so an untranslated code would surface to the seller raw.
      expect(
        offerErrorMessage('counter_limit_reached', 'x'),
        'Batas 5 penawaran balik tercapai. Terima atau tolak.',
      );
      expect(
        offerErrorMessage('insufficient_quantity', 'x'),
        'Stok tidak mencukupi',
      );
      expect(
        offerErrorMessage('offer_expired', 'x'),
        'Penawaran sudah kadaluwarsa',
      );
    });

    test('an unknown code falls back to the caller\'s wording', () {
      // New codes ship server-side ahead of the app; the action the seller
      // was taking is more useful than the code they cannot read.
      expect(
        offerErrorMessage('some_new_code', 'Gagal menolak penawaran'),
        'Gagal menolak penawaran',
      );
    });

    test('every message is written for a seller, not a log', () {
      const codes = [
        'unauthorized',
        'offer_not_found',
        'offer_not_pending',
        'offer_expired',
        'not_participant',
        'not_your_turn',
        'order_not_available',
        'insufficient_quantity',
        'note_too_long',
        'message_too_long',
        'invalid_price',
        'price_above_listing',
        'counter_must_raise',
        'counter_limit_reached',
      ];
      for (final code in codes) {
        final message = offerErrorMessage(code, 'FALLBACK');
        expect(message, isNot('FALLBACK'), reason: code);
        expect(message, isNot(contains('_')), reason: code);
      }
    });
  });
}

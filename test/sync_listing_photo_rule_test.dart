import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/trading_models.dart';
import 'package:pokepedia_mobile/features/expansions/repository/trading_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Web's `20260917111012_photo_required_only_for_graded` moved the listing
/// photo rule from "price >= Rp100.000" to "graded slab, any price". The
/// gates and copy here must agree with `isGradedCondition` or a raw NM ask
/// gets blocked client-side for a photo the server no longer wants.
void main() {
  group('isGraded mirrors isGradedCondition', () {
    test('the four raw conditions are not graded', () {
      for (final raw in ['NM', 'LP', 'MP', 'HP']) {
        expect(CardConditionX.fromRaw(raw).isGraded, isFalse, reason: raw);
      }
    });

    test('every slab grade is graded', () {
      final graded = CardCondition.values.where(
        (c) => !rawConditions.contains(c),
      );
      expect(graded, isNotEmpty);
      for (final condition in graded) {
        expect(condition.isGraded, isTrue, reason: condition.raw);
      }
    });
  });

  group('listing photo gate', () {
    test('only graded conditions require a photo', () {
      expect(CardCondition.nm.requiresListingPhoto, isFalse);
      expect(CardCondition.hp.requiresListingPhoto, isFalse);
      expect(CardCondition.psa10.requiresListingPhoto, isTrue);
      expect(CardCondition.bgsBl10.requiresListingPhoto, isTrue);
      expect(CardCondition.cgcLow.requiresListingPhoto, isTrue);
      expect(CardCondition.egs95.requiresListingPhoto, isTrue);
    });

    test('photo_required reads as web GRADED_PHOTO_REQUIRED_MESSAGE', () {
      const result = PlaceOrderResult.failed('photo_required', side: 'ask');
      expect(result.messageId, 'Foto wajib untuk kartu graded (slab).');
      expect(result.messageId, isNot(contains('100')));
    });
  });

  group('new place_order / proposal codes', () {
    test('listing_reserved_by_deal reads per side, like the web route', () {
      expect(
        const PlaceOrderResult.failed(
          'listing_reserved_by_deal',
          side: 'bid',
        ).messageId,
        startsWith('Bid ini sedang dipakai di checkout'),
      );
      expect(
        const PlaceOrderResult.failed(
          'listing_reserved_by_deal',
          side: 'ask',
        ).messageId,
        startsWith('Listing ini sedang dipakai di checkout pembeli'),
      );
    });

    test('broadcast refusals carry web copy', () {
      final repository = TradingRepository(
        SupabaseClient('http://localhost:54321', 'anon-key'),
      );
      expect(
        repository.debugMessageFor('no_open_bids'),
        'Tidak ada bid aktif di harga ini untuk dikirimi proposal.',
      );
      expect(
        repository.debugMessageFor('already_proposed'),
        'Kamu sudah mengirim proposal ke semua pembeli di harga ini. '
        'Cek di halaman Proposal.',
      );
      expect(
        repository.debugMessageFor('invalid_photos'),
        'Foto wajib untuk kartu graded (slab), maksimal 4 foto.',
      );
    });
  });
}
